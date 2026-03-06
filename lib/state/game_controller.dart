/// The sole authority on game state transitions.
///
/// ## Responsibilities
///   - Subscribe to [SseServiceInterface.events] and dispatch typed [GameEvent]s.
///   - Validate every phase transition via [_canTransition] before applying it.
///   - Produce a new [GameState] on every valid event via [GameState.copyWith].
///   - Guard against duplicate answers, late submissions, and illegal transitions.
///   - Manage client-side timers (countdown, result reveal delay).
///   - Expose [state] as a [ValueNotifier] for zero-package reactive UI.
///
/// ## What this class does NOT do
///   - Render any UI.
///   - Calculate scores (server-authoritative).
///   - Know HTTP endpoint URLs (delegated to [RestServiceInterface]).
///   - Know SSE connection details (delegated to [SseServiceInterface]).
///
/// ## Dependency contract
///   Both service dependencies are injected as interfaces.
///   The concrete [SseService] and [RestService] are never imported here.
///   This keeps the controller fully unit-testable with mock services.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/game_events.dart';
import '../core/models/game_phase.dart';
import '../core/models/game_session.dart';
import '../core/models/player.dart';
import '../core/services/rest_service.dart';
import 'game_state.dart';
import '../core/utils/logger.dart';

import '../core/services/sse_service_interface.dart';
import '../core/services/rest_service_interface.dart';
// import '../core/services/rest_service_interface.dart';

/// How long the "get ready" countdown runs before we expect the QUESTION event.
const _kCountdownDuration = Duration(seconds: 3);

/// How long questionClosed stays visible before transitioning to roundResult.
/// Gives UI time to animate the correct answer reveal.
const _kResultRevealDelay = Duration(milliseconds: 1200);

class GameController {
  final SseServiceInterface _sseService;
  final RestServiceInterface _restService;

  /// Single reactive state atom. UI subscribes via ValueListenableBuilder.
  final ValueNotifier<GameState> state =
      ValueNotifier(GameState.initial());

  // Active timers — tracked so we can cancel safely.
  Timer? _countdownTimer;
  Timer? _resultDelayTimer;

  // ---------------------------------------------------------------------------
  // Edge case tracking fields
  // ---------------------------------------------------------------------------

  /// Tracks the question ID already answered by this client.
  /// Prevents duplicate answer submissions.
  String? _lastAnsweredQuestionId;

  /// Tracks if a permanent SSE error was already emitted.
  bool _permanentErrorEmitted = false;

  GameController({
    required SseServiceInterface sseService,
    required RestServiceInterface restService,
  })  : _sseService = sseService,
        _restService = restService;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE MACHINE — Transition Validation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Defines every legal phase transition as a whitelist.
  ///
  /// Any transition not listed here is illegal and will be rejected.
  /// This is the single place to update when the game flow changes.
  bool _canTransition(GamePhase from, GamePhase to) {
    const allowedTransitions = <GamePhase, Set<GamePhase>>{
      GamePhase.initial:        {GamePhase.lobby},
      GamePhase.lobby:          {GamePhase.countdown},
      GamePhase.countdown:      {GamePhase.questionActive},
      GamePhase.questionActive: {GamePhase.questionClosed},
      GamePhase.questionClosed: {GamePhase.roundResult},
      GamePhase.roundResult:    {GamePhase.leaderboard},
      GamePhase.leaderboard:    {GamePhase.countdown, GamePhase.gameEnd},
      // error and gameEnd are terminal — no outbound transitions.
    };
    return allowedTransitions[from]?.contains(to) ?? false;
  }

  /// The ONLY method allowed to change game phase.
  ///
  /// Validates the transition, rejects illegal ones with a log,
  /// and emits the new state. All handlers call this instead of
  /// calling _emit() with a phase change directly.
  void _transitionTo(GamePhase newPhase, {GameState Function(GameState)? updater}) {
    final currentPhase = state.value.phase;

    if (!_canTransition(currentPhase, newPhase)) {
      // debugPrint(
      //   '[GameController] ⛔ Illegal transition: $currentPhase → $newPhase — ignored.',
      // );
      gameWarn(
        'GameController',
        'Illegal transition: $currentPhase → $newPhase — ignored.',
      );
      return;
    }

    // Apply optional extra state fields alongside the phase change.
    final baseState = state.value.copyWith(phase: newPhase);
    _emit(updater != null ? updater(baseState) : baseState);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// HOST flow: creates session via REST, builds GameSession from response,
  /// then opens the SSE connection.
  Future<void> createAndJoinSession({
    required String hostId,
    required String displayName,
    required int totalRounds,
  }) async {
    final response = await _restService.createSession(
      hostId: hostId,
      displayName: displayName,
      totalRounds: totalRounds,
    );

    final host = Player(
      id: hostId,
      displayName: displayName,
      isHost: true,
      isConnected: true,
    );

    final session = GameSession(
      sessionId:    response['session_id'] as String,
      roomCode:     response['room_code'] as String,
      hostId:       hostId,
      players:      List.unmodifiable([host]),
      totalRounds:  totalRounds,
      currentRound: 0,
    );

    // initial → lobby
    _transitionTo(
      GamePhase.lobby,
      updater: (s) => s.copyWith(currentPlayer: host, session: session),
    );

    await _connectSse(sessionId: session.sessionId, playerId: hostId);
  }

  /// PLAYER flow: joins via REST (receives full session snapshot), opens SSE.
  Future<void> joinSession({
    required String roomCode,
    required String playerId,
    required String displayName,
  }) async {
    final response = await _restService.joinSession(
      roomCode: roomCode,
      playerId: playerId,
      displayName: displayName,
    );

    final self = Player(
      id: playerId,
      displayName: displayName,
      isHost: false,
      isConnected: true,
    );

    // REST join response includes current full session — handles late-join.
    final session = GameSession.fromJson(
      response['session'] as Map<String, dynamic>,
    );

    // initial → lobby
    _transitionTo(
      GamePhase.lobby,
      updater: (s) => s.copyWith(currentPlayer: self, session: session),
    );

    await _connectSse(sessionId: session.sessionId, playerId: playerId);
  }

  /// HOST-ONLY: fires POST /sessions/{id}/start.
  /// Server broadcasts GAME_START over SSE to all clients (host included).
  Future<void> startGame() async {
    if (!state.value.isHost) {
      gameWarn('GameController', 'startGame() called by non-host — ignored.');
      return;
    }

    if (!_guardSession()) return;
    final session = state.value.session!;

    await _restService.startGame(
      sessionId: session.sessionId,
      hostId: state.value.currentPlayer!.id,
    );
    // No local phase change here. We wait for GAME_START over SSE
    // so all clients transition lobby → countdown simultaneously.
  }

  /// Submits answer via REST. Rejected if phase is not questionActive.
  // Future<void> submitAnswer({
  //   required String questionId,
  //   required String answer,
  // }) async {
  //   if (state.value.phase != GamePhase.questionActive) {
  //     debugPrint('[GameController] submitAnswer() outside questionActive — ignored.');
  //     return;
  //   }
  //   final session = state.value.session;
  //   final player = state.value.currentPlayer;
  //   if (session == null || player == null) return;

  //   await _restService.submitAnswer(
  //     sessionId:  session.sessionId,
  //     questionId: questionId,
  //     playerId:   player.id,
  //     answer:     answer,
  //   );
  // }

  Future<void> submitAnswer({
    required String questionId,
    required String answer,
  }) async {
    // Guard 1 — late submission.
    // Phase may have moved to questionClosed between the user tapping
    // and this method executing (especially on slow devices).
    // The controller is authoritative; the UI phase-check is a UX hint only.
    if (state.value.phase != GamePhase.questionActive) {
      gameWarn('GameController', 'submitAnswer() ignored — phase is not questionActive');
      return;
    }

    // Guard 2 — duplicate submission.
    // In real-time games the user may tap an answer button twice quickly
    // before the state update from the first submission re-renders the UI
    // with locked buttons. We track the last answered question ID here
    // so the second call is dropped at the controller layer regardless
    // of UI state.
    if (_lastAnsweredQuestionId == questionId) {
      gameWarn('GameController', 'submitAnswer() duplicate ignored for question $questionId');
      return;
    }

    if (!_guardSession() || !_guardPlayer()) return;

    final session = state.value.session!;
    final player  = state.value.currentPlayer!;

    // Mark as answered immediately — before the async REST call.
    // This ensures a second tap that arrives before the HTTP round-trip
    // completes is still caught by Guard 2 above.
    _lastAnsweredQuestionId = questionId;

    try {
      await _restService.submitAnswer(
        sessionId:  session.sessionId,
        questionId: questionId,
        playerId:   player.id,
        answer:     answer,
      );
    } on RestException catch (e) {
      if (e.isIgnorable) {
        // 409 Conflict = server already has our answer (duplicate at HTTP level).
        // 400 Bad Request = question already closed server-side.
        // Both are safe to swallow — state is already correct.
        gameLog('GameController', 'submitAnswer() ignorable REST error: $e');
      } else {
        // Unexpected server error (5xx, auth failure, etc.).
        // Surface it non-destructively — phase stays intact, user sees a banner.
        gameError('GameController', 'submitAnswer() REST error: $e');
        _emit(state.value.copyWith(errorMessage: e.message));
      }
    } catch (e) {
      // Network-level failure (socket timeout, no connectivity).
      gameError('GameController', 'submitAnswer() network error: $e');
      _emit(state.value.copyWith(errorMessage: 'Answer submission failed. Check your connection.'));
    }
  }

  /// Leaves the session, cancels all timers, tears down SSE.
  Future<void> leaveSession() async {
    // Reset the terminal error flag so a fresh session started after
    // leaving is not incorrectly treated as already permanently failed.
    _permanentErrorEmitted = false;

    _cancelAllTimers();
    await _sseService.disconnect();
    _emit(GameState.initial());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SSE SETUP
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _connectSse({
    required String sessionId,
    required String playerId,
  }) async {
    await _sseService.connect(sessionId: sessionId, playerId: playerId);
    _sseService.events.listen(
      _onEvent,
      onError: _onSseError,
      cancelOnError: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT DISPATCH — sealed switch is exhaustive at compile time
  // ═══════════════════════════════════════════════════════════════════════════

  void _onEvent(GameEvent event) {
    switch (event) {
      case RoundCountdownEvent():
        _handleRoundCountdown(event);
      case PlayerJoinedEvent():
        _handlePlayerJoined(event);
      case PlayerLeftEvent():
        _handlePlayerLeft(event);
      case GameStartEvent():
        _handleGameStart(event);
      case QuestionEvent():
        _handleQuestion(event);
      case AnswerCountEvent():
        _handleAnswerCount(event);
      case QuestionResultEvent():
        _handleQuestionResult(event);
      case LeaderboardEvent():
        _handleLeaderboard(event);
      case GameEndEvent():
        _handleGameEnd(event);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  // void _handlePlayerJoined(PlayerJoinedEvent event) {
  //   // No phase restriction — players can join any time before game ends.
  //   final session = state.value.session;
  //   if (session == null) return;

  //   final updatedPlayers = [
  //     ...session.players.where((p) => p.id != event.player.id),
  //     event.player,
  //   ];
  //   _emit(state.value.copyWith(
  //     session: session.copyWith(players: List.unmodifiable(updatedPlayers)),
  //   ));
  // }
  void _handlePlayerJoined(PlayerJoinedEvent event) {
    // No phase restriction — players can reconnect at any point.
    final session = state.value.session;
    if (session == null) return;

    // If the player already exists in the list (reconnect scenario),
    // update only their connection flag rather than appending a duplicate.
    // If they are genuinely new (fresh join), they are appended.
    // Either way, question/score state is completely untouched.
    final alreadyExists = session.players.any((p) => p.id == event.player.id);

    final updatedPlayers = alreadyExists
        ? session.players.map((p) {
            return p.id == event.player.id
                ? p.copyWith(isConnected: true)   // restore connection flag
                : p;
          }).toList()
        : [...session.players, event.player];     // genuine new join

    _emit(state.value.copyWith(
      session: session.copyWith(
        players: List.unmodifiable(updatedPlayers),
      ),
    ));
  }

  void _handlePlayerLeft(PlayerLeftEvent event) {
    // No phase restriction — disconnects can happen at any time.
    final session = state.value.session;
    if (session == null) return;

    final updatedPlayers = session.players.map((p) {
      return p.id == event.playerId ? p.copyWith(isConnected: false) : p;
    }).toList();

    _emit(state.value.copyWith(
      session: session.copyWith(players: List.unmodifiable(updatedPlayers)),
    ));
  }

  /// Guard: only valid from lobby.
  /// On reconnect, a replayed GAME_START must not reset an active game.
  void _handleGameStart(GameStartEvent event) {
    final currentPhase = state.value.phase;
    if (currentPhase != GamePhase.lobby) {
      gameWarn(
        'GameController',
        'GAME_START ignored — phase is $currentPhase, expected lobby',
      );
      return;
    }

    final session = state.value.session;

    // lobby → countdown
    _transitionTo(
      GamePhase.countdown,
      updater: (s) => s.copyWith(
        scoringRules: event.scoringRules,
        session: session?.copyWith(
          totalRounds:  event.totalRounds,
          currentRound: 1,
        ),
      ),
    );

    // Start the client-side countdown UX timer.
    // This does NOT gate the QUESTION event — it is purely cosmetic.
    // The real questionActive transition happens when QUESTION arrives from server.
    _startCountdownTimer();
  }

  /// Guard: only valid from countdown or leaderboard (between rounds).
  /// A replayed QUESTION during roundResult must be ignored.
  void _handleQuestion(QuestionEvent event) {
    final currentPhase = state.value.phase;
    final validPriorPhases = {GamePhase.countdown, GamePhase.leaderboard};

    if (!validPriorPhases.contains(currentPhase)) {
      gameWarn('GameController', 'QUESTION ignored — phase is $currentPhase');
      return;
    }

    // Reset the duplicate-answer guard for the incoming question.
    // Each new question gets a clean slate — the previous question's ID
    // must not block submission for the next one.
    _lastAnsweredQuestionId = null;

    // Cancel the countdown timer — the server has taken over.
    _cancelCountdownTimer();

    final session = state.value.session;

    // countdown → questionActive  (or leaderboard → countdown → questionActive,
    // but QUESTION event skips the countdown on subsequent rounds if server
    // sends it immediately — _canTransition handles this via leaderboard → countdown
    // only; if we are in leaderboard we first need countdown. In practice the
    // server sends a new GAME_START-style countdown signal. This guard means
    // if QUESTION arrives while in leaderboard it is rejected, and a new
    // countdown event from server will move us first. This is intentional:
    // the server controls the pacing.)
    _transitionTo(
      GamePhase.questionActive,
      updater: (s) => s.copyWith(
        currentQuestion: event.question,
        questionIndex:   event.questionIndex,
        answeredCount:   0,
        correctAnswer:   null,
        lastScoreDelta:  null,
        lastSpeedBonus:  null,
        lastStreakBonus:  null,
        session:         session?.copyWith(currentRound: event.roundNumber),
      ),
    );
  }

  /// Guard: only meaningful during questionActive.
  /// Debounced server push — stale counts after close must be dropped.
  void _handleAnswerCount(AnswerCountEvent event) {
    if (state.value.phase != GamePhase.questionActive) {
      gameWarn('GameController', 'ANSWER_COUNT ignored — phase is ${state.value.phase}');
      return;
    }
    // No phase change — purely informational update.
    _emit(state.value.copyWith(
      answeredCount: event.answeredCount,
      totalPlayers:  event.totalPlayers,
    ));
  }

  /// Two-step timed transition on Q_RESULT:
  ///
  ///   Step 1 (immediate): questionActive → questionClosed
  ///     Locks the question. UI animates correct answer reveal.
  ///
  ///   Step 2 (after 1200ms): questionClosed → roundResult
  ///     Score delta appears. UI animates points gained.
  ///
  /// The delay is intentional UX — it lets players register whether
  /// they were right before the score hits them.
  void _handleQuestionResult(QuestionResultEvent event) {
    // Step 1 — lock the question immediately.
    _transitionTo(
      GamePhase.questionClosed,
      updater: (s) => s.copyWith(correctAnswer: event.correctAnswer),
    );

    // Guard: if transition was rejected (wrong prior phase), do not start timer.
    if (state.value.phase != GamePhase.questionClosed) return;

    // Cancel any stale result timer before starting a new one.
    _cancelResultDelayTimer();

    // Step 2 — delayed score reveal.
    _resultDelayTimer = Timer(_kResultRevealDelay, () {
      // Re-check phase: a leaveSession() during the delay must abort this.
      if (state.value.phase != GamePhase.questionClosed) {
        gameWarn('GameController', 'Result delay fired but phase changed — aborted');
        return;
      }
      _transitionTo(
        GamePhase.roundResult,
        updater: (s) => s.copyWith(
          lastScoreDelta:  event.scoreDelta,
          lastSpeedBonus:  event.speedBonus,
          lastStreakBonus:  event.streakBonus,
        ),
      );
    });
  }

  void _handleRoundCountdown(RoundCountdownEvent event) {
    // Valid from leaderboard phase only — between rounds.
    if (state.value.phase != GamePhase.leaderboard) {
      gameWarn('GameController', 'ROUND_COUNTDOWN ignored — phase is ${state.value.phase}');
      return;
    }
    _transitionTo(GamePhase.countdown);
    _startCountdownTimer();
  }

  void _handleLeaderboard(LeaderboardEvent event) {
    final session = state.value.session;
    _transitionTo(
      GamePhase.leaderboard,
      updater: (s) => s.copyWith(
        topPlayers: event.topPlayers,
        session:    session?.copyWith(currentRound: event.roundNumber),
      ),
    );
  }

  void _handleGameEnd(GameEndEvent event) {
    _cancelAllTimers();
    // leaderboard → gameEnd
    _transitionTo(
      GamePhase.gameEnd,
      updater: (s) => s.copyWith(
        topPlayers:          event.finalLeaderboard,
        winnerPlayerId:      event.winnerPlayerId,
        rewardPointsGranted: event.rewardPointsGranted,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COUNTDOWN TIMER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Starts the 3-second client-side "get ready" countdown.
  ///
  /// This timer is purely cosmetic UX. The actual questionActive transition
  /// is driven by the server's QUESTION event arriving over SSE.
  /// The timer fires only to advance the UI countdown display — it does NOT
  /// self-transition to questionActive. That transition requires a QUESTION event.
  ///
  /// Why? Because in a multiplayer game, the server is the clock.
  /// If we self-transitioned on timer fire, clock drift across clients
  /// would cause them to show "active" at slightly different times,
  /// creating unfair speed-bonus windows.
  void _startCountdownTimer() {
    // Prevent duplicate timers (e.g. reconnect replaying GAME_START).
    _cancelCountdownTimer();

    _countdownTimer = Timer(_kCountdownDuration, () {
      // Timer fires only as a UX signal. The QUESTION event from server
      // will trigger the real questionActive transition.
      // If QUESTION has already arrived and phase moved on, this is a no-op.
      if (state.value.phase == GamePhase.countdown) {
        gameLog('GameController', 'Countdown complete — awaiting QUESTION from server');
      }
    });
  }

  void _cancelCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _cancelResultDelayTimer() {
    _resultDelayTimer?.cancel();
    _resultDelayTimer = null;
  }

  void _cancelAllTimers() {
    _cancelCountdownTimer();
    _cancelResultDelayTimer();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  // void _onSseError(Object error) {
  //   // Surface error for UI reconnection banner. Phase is preserved —
  //   // game resumes naturally when SSE reconnects and replays missed events.
  //   // The transition validator ensures replayed events cannot corrupt state.
  //   debugPrint('[GameController] SSE error: $error');
  //   _emit(state.value.copyWith(errorMessage: error.toString()));
  // }

  void _onSseError(Object error) {

    gameError('GameController', 'SSE error: $error');

    final isTerminal = error is SocketException &&
        error.message.contains('permanently disconnected');

    if (isTerminal && !_permanentErrorEmitted) {
      // SseService has exhausted all reconnect attempts.
      // Transition to error phase so GameScreen shows the error UI.
      // The flag prevents this block from firing multiple times if the
      // stream emits several terminal errors before the UI reacts.
      _permanentErrorEmitted = true;
      _cancelAllTimers();
      _emit(state.value.copyWith(
        phase:        GamePhase.error,
        errorMessage: 'Connection permanently lost. Please rejoin.',
      ));
      return;
    }

    // Non-terminal error (transient drop — SseService is reconnecting).
    // Preserve the current phase so the game can resume seamlessly.
    // The UI shows a non-blocking reconnecting banner via errorMessage.
    if (!_permanentErrorEmitted) {
      _emit(state.value.copyWith(
        errorMessage: 'Reconnecting…',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool _guardSession() {
    assert(
      state.value.session != null,
      '[GameController] Expected an active session but session is null.',
    );
    return state.value.session != null;
  }

  bool _guardPlayer() {
    assert(
      state.value.currentPlayer != null,
      '[GameController] Expected currentPlayer but it is null.',
    );
    return state.value.currentPlayer != null;
  }
  /// Raw state emission — only called for non-phase-changing updates
  /// (player list, answer count). All phase changes go through _transitionTo().
  void _emit(GameState newState) {
    state.value = newState;
  }

  Future<void> dispose() async {
    _permanentErrorEmitted = false;
    _cancelAllTimers();
    await _sseService.disconnect();   // wait for SSE teardown
    state.dispose();                  // dispose notifier last
  }
  
}
// ```

// ---

// ## How The State Machine Now Works
// ```
// SSE Event arrives
//        │
//        ▼
//   _onEvent() dispatch
//        │
//        ▼
//   Handler runs
//        │
//        ├─ Non-phase updates (player list, answer count)
//        │    └─ _emit() directly — no validator needed
//        │
//        └─ Phase-changing updates
//             └─ _transitionTo(newPhase)
//                      │
//                      ├─ _canTransition(current, new)?
//                      │        │
//                      │      false ──► debugPrint + return  (state unchanged)
//                      │        │
//                      │       true
//                      │        │
//                      │        ▼
//                      └─ _emit(updater(state.copyWith(phase: newPhase)))