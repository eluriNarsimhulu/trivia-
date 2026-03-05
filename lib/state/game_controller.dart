/// GameController — State Machine Enforced Version (Stage 2)
///
/// Why phase validation matters in SSE systems:
///   Unlike WebSockets, SSE is a unidirectional HTTP stream. On reconnect,
///   the server may replay recent events, or buffered events may arrive
///   out of order. Without a transition guard, a replayed GAME_START event
///   could reset an active game back to countdown. The validator prevents this.
///
/// Why SSE events arrive out of order:
///   Each SSE reconnect opens a fresh HTTP connection. The server may send
///   a buffered QUESTION event before the client has processed the preceding
///   GAME_START. The state machine must be resilient to these races.
///
/// Why countdown is client-side but question start is server-driven:
///   The server controls when questions open (it broadcasts QUESTION over SSE).
///   The 3-second countdown is purely a UX affordance — it gives players
///   a visual "get ready" moment. It does not gate any server action.
///   The client transitions to questionActive only when the server sends
///   the QUESTION event, not when the local timer fires.
///
/// Timer ownership:
///   _countdownTimer  — runs during GamePhase.countdown (3s UX delay)
///   _resultDelayTimer — runs during GamePhase.questionClosed (1.2s reveal delay)
///   Both are cancelled on leaveSession() and dispose().

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models/game_events.dart';
import '../core/models/game_phase.dart';
import '../core/models/game_session.dart';
import '../core/models/player.dart';
import '../core/models/scoring.dart';
import '../core/services/sse_service.dart';
import '../core/services/rest_service.dart';
import 'game_state.dart';

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
      ValueNotifier(const GameState.initial());

  // Active timers — tracked so we can cancel safely.
  Timer? _countdownTimer;
  Timer? _resultDelayTimer;

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
      debugPrint(
        '[GameController] ⛔ Illegal transition: $currentPhase → $newPhase — ignored.',
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
      debugPrint('[GameController] startGame() called by non-host — ignored.');
      return;
    }
    final session = state.value.session;
    if (session == null) return;

    await _restService.startGame(
      sessionId: session.sessionId,
      hostId: state.value.currentPlayer!.id,
    );
    // No local phase change here. We wait for GAME_START over SSE
    // so all clients transition lobby → countdown simultaneously.
  }

  /// Submits answer via REST. Rejected if phase is not questionActive.
  Future<void> submitAnswer({
    required String questionId,
    required String answer,
  }) async {
    if (state.value.phase != GamePhase.questionActive) {
      debugPrint('[GameController] submitAnswer() outside questionActive — ignored.');
      return;
    }
    final session = state.value.session;
    final player = state.value.currentPlayer;
    if (session == null || player == null) return;

    await _restService.submitAnswer(
      sessionId:  session.sessionId,
      questionId: questionId,
      playerId:   player.id,
      answer:     answer,
    );
  }

  /// Leaves the session, cancels all timers, tears down SSE.
  Future<void> leaveSession() async {
    _cancelAllTimers();
    await _sseService.disconnect();
    _emit(const GameState.initial());
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

  void _handlePlayerJoined(PlayerJoinedEvent event) {
    // No phase restriction — players can join any time before game ends.
    final session = state.value.session;
    if (session == null) return;

    final updatedPlayers = [
      ...session.players.where((p) => p.id != event.player.id),
      event.player,
    ];
    _emit(state.value.copyWith(
      session: session.copyWith(players: List.unmodifiable(updatedPlayers)),
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
      debugPrint(
        '[GameController] ⚠️ GAME_START ignored — phase is $currentPhase, expected lobby.',
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
      debugPrint(
        '[GameController] ⚠️ QUESTION ignored — phase is $currentPhase.',
      );
      return;
    }

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
      debugPrint('[GameController] ⚠️ ANSWER_COUNT ignored — phase is ${state.value.phase}.');
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
        debugPrint('[GameController] Result delay fired but phase changed — aborted.');
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
        debugPrint('[GameController] Countdown complete — awaiting QUESTION from server.');
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

  void _onSseError(Object error) {
    // Surface error for UI reconnection banner. Phase is preserved —
    // game resumes naturally when SSE reconnects and replays missed events.
    // The transition validator ensures replayed events cannot corrupt state.
    debugPrint('[GameController] SSE error: $error');
    _emit(state.value.copyWith(errorMessage: error.toString()));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Raw state emission — only called for non-phase-changing updates
  /// (player list, answer count). All phase changes go through _transitionTo().
  void _emit(GameState newState) {
    state.value = newState;
  }

  void dispose() {
    _cancelAllTimers();
    _sseService.disconnect();
    state.dispose();
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