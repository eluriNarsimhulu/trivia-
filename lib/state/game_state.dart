// project_folder/lib/state/game_state.dart

/// Immutable snapshot of the entire client-side game view at a point in time.
///
/// This is the single source of truth that all UI widgets read from.
/// No widget ever writes to this directly — all mutations flow through
/// [GameController.state] via [GameState.copyWith].
///
/// Field groupings:
///   Identity   — who this client is ([currentPlayer])
///   Session    — who else is in the room ([session])
///   Phase      — where in the game flow we are ([phase])
///   Question   — the active question and answer progress
///   Result     — score breakdown after each question
///   Leaderboard— top-5 standings
///   Error      — non-null when a recoverable or terminal error has occurred
///
/// Null contract:
///   Fields are null when they are not meaningful in the current phase.
///   For example, [currentQuestion] is null in [GamePhase.lobby].
///   [GameController] enforces these contracts — UI should always null-check
///   before reading phase-specific fields.

import '../core/models/game_phase.dart';
import '../core/models/game_session.dart';
import '../core/models/player.dart';
import '../core/models/question.dart';
import '../core/models/scoring.dart';

class GameState {
  static const Object _clear = Object();
  // -- Identity --
  /// This client's own player record.
  final Player? currentPlayer;

  // -- Session --
  /// The shared session visible to all participants.
  final GameSession? session;

  // -- Phase --
  final GamePhase phase;

  // -- Scoring config (set once on GAME_START) --
  final ScoringRules? scoringRules;

  // -- Active question --
  final Question? currentQuestion;
  final int questionIndex;       // 0-based within current round
  final int answeredCount;       // players who answered so far
  final int totalPlayers;        // total active players

  // -- Round result (populated after Q_RESULT) --
  final String? correctAnswer;
  final int? lastScoreDelta;
  final int? lastSpeedBonus;
  final int? lastStreakBonus;

  // -- Leaderboard --
  final List<PlayerScore> topPlayers;

  // -- Game end --
  final String? winnerPlayerId;
  final int? rewardPointsGranted;

  // -- Error --
  final String? errorMessage;

  GameState({
    this.currentPlayer,
    this.session,
    this.phase = GamePhase.initial,
    this.scoringRules,
    this.currentQuestion,
    this.questionIndex = 0,
    this.answeredCount = 0,
    this.totalPlayers = 0,
    this.correctAnswer,
    this.lastScoreDelta,
    this.lastSpeedBonus,
    this.lastStreakBonus,
    List<PlayerScore> topPlayers = const [],
    this.winnerPlayerId,
    this.rewardPointsGranted,
    this.errorMessage,
  }) : topPlayers = List.unmodifiable(topPlayers);

  /// The guaranteed-safe starting state on app launch.
  GameState.initial() : this();

  /// Convenience: true if this client is the host of the current session.
  bool get isHost =>
      currentPlayer != null &&
      session != null &&
      currentPlayer!.id == session!.hostId;

  /// copyWith — the ONLY way GameController should update state.
  GameState copyWith({
    Player? currentPlayer,
    GameSession? session,
    GamePhase? phase,
    ScoringRules? scoringRules,
    Question? currentQuestion,
    int? questionIndex,
    int? answeredCount,
    int? totalPlayers,
    String? correctAnswer,
    int? lastScoreDelta,
    int? lastSpeedBonus,
    int? lastStreakBonus,
    List<PlayerScore>? topPlayers,
    String? winnerPlayerId,
    int? rewardPointsGranted,
    Object? errorMessage = _clear,
  }) {
    return GameState(
      currentPlayer: currentPlayer ?? this.currentPlayer,
      session: session ?? this.session,
      phase: phase ?? this.phase,
      scoringRules: scoringRules ?? this.scoringRules,
      currentQuestion: currentQuestion ?? this.currentQuestion,
      questionIndex: questionIndex ?? this.questionIndex,
      answeredCount: answeredCount ?? this.answeredCount,
      totalPlayers: totalPlayers ?? this.totalPlayers,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      lastScoreDelta: lastScoreDelta ?? this.lastScoreDelta,
      lastSpeedBonus: lastSpeedBonus ?? this.lastSpeedBonus,
      lastStreakBonus: lastStreakBonus ?? this.lastStreakBonus,
      topPlayers: topPlayers != null
          ? List.unmodifiable(topPlayers)
          : this.topPlayers,
      winnerPlayerId: winnerPlayerId ?? this.winnerPlayerId,
      rewardPointsGranted:
          rewardPointsGranted ?? this.rewardPointsGranted,
      errorMessage: errorMessage == _clear
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
  // GameState copyWith({
  //   Player? currentPlayer,
  //   GameSession? session,
  //   GamePhase? phase,
  //   ScoringRules? scoringRules,
  //   Question? currentQuestion,
  //   int? questionIndex,
  //   int? answeredCount,
  //   int? totalPlayers,
  //   String? correctAnswer,
  //   int? lastScoreDelta,
  //   int? lastSpeedBonus,
  //   int? lastStreakBonus,
  //   List<PlayerScore>? topPlayers,
  //   String? winnerPlayerId,
  //   int? rewardPointsGranted,
  //   String? errorMessage,
  // }) {
  //   return GameState(
  //     currentPlayer:       currentPlayer ?? this.currentPlayer,
  //     session:             session ?? this.session,
  //     phase:               phase ?? this.phase,
  //     scoringRules:        scoringRules ?? this.scoringRules,
  //     currentQuestion:     currentQuestion ?? this.currentQuestion,
  //     questionIndex:       questionIndex ?? this.questionIndex,
  //     answeredCount:       answeredCount ?? this.answeredCount,
  //     totalPlayers:        totalPlayers ?? this.totalPlayers,
  //     correctAnswer:       correctAnswer ?? this.correctAnswer,
  //     lastScoreDelta:      lastScoreDelta ?? this.lastScoreDelta,
  //     lastSpeedBonus:      lastSpeedBonus ?? this.lastSpeedBonus,
  //     lastStreakBonus:      lastStreakBonus ?? this.lastStreakBonus,
  //     // topPlayers:          topPlayers ?? this.topPlayers,
  //     topPlayers: topPlayers != null ? List.unmodifiable(topPlayers) : this.topPlayers,
  //     winnerPlayerId:      winnerPlayerId ?? this.winnerPlayerId,
  //     rewardPointsGranted: rewardPointsGranted ?? this.rewardPointsGranted,
  //     errorMessage:        errorMessage ?? this.errorMessage,
  //   );
  // }
}