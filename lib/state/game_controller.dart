// project_folder/lib/state/game_controller.dart

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

import 'game_state.dart';
import '../core/utils/logger.dart';

import '../core/services/sse_service_interface.dart';
import '../core/services/rest_service_interface.dart';

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
  Timer? _sessionCancelledTimer;
  Timer? _syncTimer;
  StreamSubscription<GameEvent>? _eventSubscription;

  // ---------------------------------------------------------------------------
  // Edge case tracking fields
  // ---------------------------------------------------------------------------

  /// Tracks the question ID already answered by this client.
  /// Prevents duplicate answer submissions.
  String? _lastAnsweredQuestionId;

  /// Tracks if a permanent SSE error was already emitted.
  bool _permanentErrorEmitted = false;

  /// Tracks if the controller has been disposed or left the session intentionally.
  bool _disconnected = false;

  GameController({
    required SseServiceInterface sseService,
    required RestServiceInterface restService,
  })  : _sseService = sseService,
        _restService = restService;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE MACHINE — Transition Validation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Defines every legal phase transition as a whitelist.
  bool _canTransition(GamePhase from, GamePhase to) {
    const allPhases = {
      GamePhase.lobby,
      GamePhase.countdown,
      GamePhase.questionActive,
      GamePhase.questionClosed,
      GamePhase.roundResult,
      GamePhase.leaderboard,
      GamePhase.gameEnd,
      GamePhase.error,
    };

    const allowedTransitions = <GamePhase, Set<GamePhase>>{
      GamePhase.initial:        allPhases, // Allow hydration jump from initial to any phase
      GamePhase.lobby:          allPhases, // Allow jump from lobby (late-join race)
      GamePhase.countdown:      {GamePhase.questionActive, GamePhase.error},
      GamePhase.questionActive: {GamePhase.questionClosed, GamePhase.error},
      GamePhase.questionClosed: {GamePhase.roundResult, GamePhase.leaderboard, GamePhase.error},
      GamePhase.roundResult:    {GamePhase.leaderboard, GamePhase.error},
      GamePhase.leaderboard:    {GamePhase.countdown, GamePhase.gameEnd, GamePhase.error},
      GamePhase.gameEnd:        {GamePhase.lobby, GamePhase.countdown, GamePhase.error},
    };
    return allowedTransitions[from]?.contains(to) ?? (to == GamePhase.error);
  }

  void _transitionTo(GamePhase newPhase, {GameState Function(GameState)? updater}) {
    final currentPhase = state.value.phase;

    if (!_canTransition(currentPhase, newPhase)) {
      gameWarn(
        'GameController',
        'Illegal transition: $currentPhase → $newPhase — ignored.',
      );
      return;
    }

    final baseState = state.value.copyWith(phase: newPhase);
    _emit(updater != null ? updater(baseState) : baseState);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

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
      phase:        'lobby',
    );

    final initialPhase = _mapServerPhase(session.phase);

    _transitionTo(
      initialPhase,
      updater: (s) => s.copyWith(
        currentPlayer: host,
        session: session,
        scoringRules: session.scoringRules,
        currentQuestion: session.currentQuestion,
        questionIndex: session.currentRound > 0 ? session.currentRound - 1 : 0,
        totalPlayers: session.players.length,
      ),
    );

    if (initialPhase == GamePhase.countdown) {
      _startCountdownTimer();
    }

    final initialEventId = response['current_event_id']?.toString();
    await _connectSse(
      sessionId: session.sessionId,
      playerId: hostId,
      lastEventId: initialEventId,
    );
  }

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

    final session = GameSession.fromJson(
      response['session'] as Map<String, dynamic>,
    );

    final initialPhase = _mapServerPhase(session.phase);

    _transitionTo(
      initialPhase,
      updater: (s) => s.copyWith(
        currentPlayer: self,
        session: session,
        scoringRules: session.scoringRules,
        currentQuestion: session.currentQuestion,
        questionIndex: session.currentRound > 0 ? session.currentRound - 1 : 0,
        totalPlayers: session.players.length,
      ),
    );

    if (initialPhase == GamePhase.countdown) {
      _startCountdownTimer();
    }

    final initialEventId = response['current_event_id']?.toString();
    await _connectSse(
      sessionId: session.sessionId,
      playerId: playerId,
      lastEventId: initialEventId,
    );
  }

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
  }

  Future<void> restartGame() async {
    if (!state.value.isHost) {
      gameWarn('GameController', 'restartGame() called by non-host — ignored.');
      return;
    }

    if (!_guardSession()) return;
    final session = state.value.session!;

    try {
      await _restService.restartGame(
        sessionId: session.sessionId,
        hostId: state.value.currentPlayer!.id,
      );
    } catch (e) {
      gameError('GameController', 'restartGame() failed: $e');
      _emit(state.value.copyWith(
        errorMessage: 'Restart failed. Please try again.',
      ));
    }
  }

  Future<void> goToLobby() async {
    if (!state.value.isHost) {
      gameWarn('GameController', 'goToLobby() called by non-host — ignored.');
      return;
    }

    if (!_guardSession()) return;
    final session = state.value.session!;

    try {
      await _restService.goToLobby(
        sessionId: session.sessionId,
        hostId: state.value.currentPlayer!.id,
      );
    } catch (e) {
      gameError('GameController', 'goToLobby() failed: $e');
    }
  }

  Future<void> submitAnswer({
    required String questionId,
    required String answer,
  }) async {
    if (state.value.phase != GamePhase.questionActive) {
      gameWarn('GameController', 'submitAnswer() ignored — phase is not questionActive');
      return;
    }

    if (_lastAnsweredQuestionId == questionId) {
      gameWarn('GameController', 'submitAnswer() duplicate ignored for question $questionId');
      return;
    }

    if (!_guardSession() || !_guardPlayer()) return;

    final session = state.value.session!;
    final player  = state.value.currentPlayer!;

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
        gameLog('GameController', 'submitAnswer() ignorable REST error: $e');
      } else {
        gameError('GameController', 'submitAnswer() REST error: $e');
        _emit(state.value.copyWith(errorMessage: e.message));
      }
    } catch (e) {
      gameError('GameController', 'submitAnswer() network error: $e');
      _emit(state.value.copyWith(errorMessage: 'Answer submission failed. Check your connection.'));
    }
  }

  Future<void> leaveSession() async {
    _permanentErrorEmitted = false;
    _cancelAllTimers();
    _stopSyncTimer();
    _lastAnsweredQuestionId = null;

    _emit(GameState.initial());

    _eventSubscription?.cancel().then((_) => _eventSubscription = null);
    _sseService.disconnect();
  }

  Future<void> cancelSession() async {
    if (!state.value.isHost) {
      gameWarn('GameController', 'cancelSession() called by non-host — ignored.');
      return;
    }

    if (!_guardSession() || !_guardPlayer()) return;

    final session = state.value.session!;
    final hostId  = state.value.currentPlayer!.id;

    _cancelAllTimers();
    _stopSyncTimer();

    try {
      await _restService.cancelSession(
        sessionId: session.sessionId,
        hostId: hostId,
      );
    } catch (e) {
      gameError('GameController', 'cancelSession() REST error: $e');
    }

    await _sseService.disconnect();
    _emit(GameState.initial());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SSE SETUP
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _connectSse({
    required String sessionId,
    required String playerId,
    String? lastEventId,
  }) async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _sseService.connect(
      sessionId: sessionId,
      playerId: playerId,
      lastEventId: lastEventId,
    );
    _eventSubscription = _sseService.events.listen(
      _onEvent,
      onError: _onSseError,
      cancelOnError: false,
    );

    _startSyncTimer();
  }

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
      case GameRestartedEvent():
        _handleGameRestarted(event);
      case HostChangedEvent():
        _handleHostChanged(event);
      case SessionCancelledEvent():
        _handleSessionCancelled(event);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _handlePlayerJoined(PlayerJoinedEvent event) {
    final session = state.value.session;
    if (session == null) return;

    final alreadyExists = session.players.any((p) => p.id == event.player.id);

    final updatedPlayers = alreadyExists
        ? session.players.map((p) {
            return p.id == event.player.id
                ? p.copyWith(isConnected: true)
                : p;
          }).toList()
        : [...session.players, event.player];

    _emit(state.value.copyWith(
      session: session.copyWith(
        players: List.unmodifiable(updatedPlayers),
      ),
    ));
  }

  void _handlePlayerLeft(PlayerLeftEvent event) {
    final session = state.value.session;
    if (session == null) return;

    final updatedPlayers = session.players
        .where((p) => p.id != event.playerId)
        .toList();

    _emit(state.value.copyWith(
      session: session.copyWith(players: List.unmodifiable(updatedPlayers)),
    ));
  }

  void _handleGameStart(GameStartEvent event) {
    final currentPhase = state.value.phase;
    final validPriorPhases = {GamePhase.initial, GamePhase.lobby};

    if (!validPriorPhases.contains(currentPhase)) {
      gameWarn('GameController', 'GAME_START ignored — phase is $currentPhase');
      return;
    }

    final session = state.value.session;

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

    _startCountdownTimer();
  }

  void _handleQuestion(QuestionEvent event) {
    final currentPhase = state.value.phase;
    final validPriorPhases = {GamePhase.countdown, GamePhase.leaderboard};

    if (!validPriorPhases.contains(currentPhase)) {
      gameWarn('GameController', 'QUESTION ignored — phase is $currentPhase');
      return;
    }

    _lastAnsweredQuestionId = null;
    _cancelCountdownTimer();

    final session = state.value.session;

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

  void _handleAnswerCount(AnswerCountEvent event) {
    if (state.value.phase != GamePhase.questionActive) {
      gameWarn('GameController', 'ANSWER_COUNT ignored — phase is ${state.value.phase}');
      return;
    }
    _emit(state.value.copyWith(
      answeredCount: event.answeredCount,
      totalPlayers:  event.totalPlayers,
    ));
  }

  void _handleQuestionResult(QuestionResultEvent event) {
    _transitionTo(
      GamePhase.questionClosed,
      updater: (s) => s.copyWith(correctAnswer: event.correctAnswer),
    );

    if (state.value.phase != GamePhase.questionClosed) return;

    _cancelResultDelayTimer();

    _resultDelayTimer = Timer(_kResultRevealDelay, () {
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
    final phase = state.value.phase;

    if (phase != GamePhase.leaderboard && phase != GamePhase.countdown) {
      gameWarn('GameController', 'ROUND_COUNTDOWN ignored — phase is $phase');
      return;
    }

    if (phase == GamePhase.leaderboard) {
      _transitionTo(GamePhase.countdown);
    }

    _startCountdownTimer();
  }

  void _handleLeaderboard(LeaderboardEvent event) {
    final session = state.value.session;
    _cancelResultDelayTimer();

    final currentPhase = state.value.phase;

    if (currentPhase == GamePhase.questionClosed) {
      _transitionTo(GamePhase.roundResult);
      if (state.value.phase != GamePhase.roundResult) return;
    }

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
    _transitionTo(
      GamePhase.gameEnd,
      updater: (s) => s.copyWith(
        topPlayers:          event.finalLeaderboard,
        winnerPlayerId:      event.winnerPlayerId,
        rewardPointsGranted: event.rewardPointsGranted,
      ),
    );
  }

  void _handleGameRestarted(GameRestartedEvent event) {
    if (state.value.phase != GamePhase.gameEnd) {
      gameWarn('GameController', 'GAME_RESTARTED ignored — phase is ${state.value.phase}');
      return;
    }

    _cancelAllTimers();
    _permanentErrorEmitted = false;
    _lastAnsweredQuestionId = null;

    final session = state.value.session;
    if (session == null) return;

    final updatedSession = session.copyWith(
      players: event.players,
      currentRound: 0,
    );

    _transitionTo(
      GamePhase.lobby,
      updater: (s) => GameState(
        currentPlayer:       s.currentPlayer,
        session:             updatedSession,
        phase:               GamePhase.lobby,
        errorMessage:        null,
        scoringRules:        null,
        currentQuestion:     null,
        questionIndex:       0,
        answeredCount:       0,
        totalPlayers:        0,
        correctAnswer:       null,
        lastScoreDelta:      null,
        lastSpeedBonus:      null,
        lastStreakBonus:      null,
        topPlayers:          const [],
        winnerPlayerId:      null,
        rewardPointsGranted: null,
      ),
    );
  }

  void _handleHostChanged(HostChangedEvent event) {
    final session = state.value.session;
    if (session == null) return;

    final updatedSession = session.copyWith(hostId: event.newHostId);

    final updatedPlayers = updatedSession.players.map((p) {
      if (p.id == event.newHostId) return p.copyWith(isHost: true);
      if (p.isHost) return p.copyWith(isHost: false);
      return p;
    }).toList();

    _emit(state.value.copyWith(
      session: updatedSession.copyWith(
        players: List.unmodifiable(updatedPlayers),
      ),
    ));

    gameLog('GameController', 'Host changed to ${event.newHostName}');
  }

  void _handleSessionCancelled(SessionCancelledEvent event) {
    final phase = state.value.phase;
    if (phase == GamePhase.initial ||
        phase == GamePhase.error   ||
        phase == GamePhase.gameEnd) return;

    _cancelAllTimers();
    _permanentErrorEmitted = false;
    _lastAnsweredQuestionId = null;

    _emit(state.value.copyWith(errorMessage: event.reason));

    _sessionCancelledTimer?.cancel();
    _sessionCancelledTimer = Timer(const Duration(seconds: 2), () async {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      await _sseService.disconnect();
      _emit(GameState.initial());
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMER HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _startCountdownTimer() {
    _cancelCountdownTimer();
    _countdownTimer = Timer(_kCountdownDuration, () {
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
    _stopSyncTimer();
    _sessionCancelledTimer?.cancel();
    _sessionCancelledTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WATCHDOG (POLLING FALLBACK)
  // ═══════════════════════════════════════════════════════════════════════════

  void _startSyncTimer() {
    _stopSyncTimer();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => _performSync());
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> _performSync() async {
    final session = state.value.session;
    if (session == null || _disconnected) return;

    try {
      final response = await _restService.syncSession(sessionId: session.sessionId);
      final serverSession = GameSession.fromJson(response['session'] as Map<String, dynamic>);
      final serverPhase = _mapServerPhase(serverSession.phase);

      _handleSyncState(serverSession, serverPhase);
    } catch (e) {
      debugPrint('[GameController] Sync watchdog failed: $e');
    }
  }

  void _handleSyncState(GameSession serverSession, GamePhase serverPhase) {
    if (state.value.phase == serverPhase) {
      _emit(state.value.copyWith(
        session: serverSession,
        totalPlayers: serverSession.players.length,
      ));
      return;
    }

    gameWarn('GameController', 'SYNC: Phase mismatch! Local=${state.value.phase}, Server=$serverPhase. Forcing hydration jump.');

    _transitionTo(
      serverPhase,
      updater: (s) => s.copyWith(
        session: serverSession,
        scoringRules: serverSession.scoringRules,
        currentQuestion: serverSession.currentQuestion,
        questionIndex: serverSession.currentRound > 0 ? serverSession.currentRound - 1 : 0,
        totalPlayers: serverSession.players.length,
      ),
    );

    if (serverPhase == GamePhase.countdown) {
      _startCountdownTimer();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERROR HANDLING
  // ═══════════════════════════════════════════════════════════════════════════

  void _onSseError(Object error) {
    gameError('GameController', 'SSE error: $error');

    final isTerminal = error is SocketException &&
        error.message.contains('permanently disconnected');

    if (isTerminal && !_permanentErrorEmitted) {
      _permanentErrorEmitted = true;
      _cancelAllTimers();
      _emit(state.value.copyWith(
        phase:        GamePhase.error,
        errorMessage: 'Connection permanently lost. Please rejoin.',
      ));
      return;
    }

    if (!_permanentErrorEmitted) {
      _emit(state.value.copyWith(errorMessage: 'Reconnecting…'));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool _guardSession() {
    assert(state.value.session != null, 'Expected an active session');
    return state.value.session != null;
  }

  bool _guardPlayer() {
    assert(state.value.currentPlayer != null, 'Expected currentPlayer');
    return state.value.currentPlayer != null;
  }

  void _emit(GameState newState) {
    state.value = newState;
  }

  Future<void> dispose() async {
    _disconnected = true;
    _permanentErrorEmitted = false;
    _cancelAllTimers();
    _stopSyncTimer();
    
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _sseService.disconnect();

    state.dispose();
  }

  GamePhase _mapServerPhase(String serverPhase) {
    switch (serverPhase) {
      case 'lobby':           return GamePhase.lobby;
      case 'countdown':       return GamePhase.countdown;
      case 'questionActive':  return GamePhase.questionActive;
      case 'questionClosed':  return GamePhase.questionClosed;
      case 'leaderboard':     return GamePhase.leaderboard;
      case 'gameEnd':         return GamePhase.gameEnd;
      default:                return GamePhase.lobby;
    }
  }
}