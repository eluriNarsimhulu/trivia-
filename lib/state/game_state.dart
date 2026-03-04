/// The single source of truth for the entire client-side game view.
///
/// Architecture notes:
///   1. IMMUTABLE — every update produces a new instance via copyWith().
///      No field is ever changed in place. This makes state diffs trivial
///      and eliminates entire classes of subtle bugs.
///
///   2. SEPARATION OF CONCERNS:
///      - `session`      → who is in the room (server-authoritative)
///      - `currentPlayer`→ this client's own identity
///      - `phase`        → where in the game flow we are
///      - question/score fields → transient per-question data
///
///   3. NULLABLE FIELDS signal "not applicable in current phase."
///      e.g. currentQuestion is null in lobby. The controller
///      guarantees these contracts — the UI checks before reading.
///
///   4. No methods that change state. GameController owns all mutations.

import '../core/models/game_phase.dart';
import '../core/models/game_session.dart';
import '../core/models/player.dart';
import '../core/models/question.dart';
import '../core/models/scoring.dart';

class GameState {
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

  const GameState({
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
    this.topPlayers = const [],
    this.winnerPlayerId,
    this.rewardPointsGranted,
    this.errorMessage,
  });

  /// The guaranteed-safe starting state on app launch.
  const GameState.initial() : this();

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
    String? errorMessage,
  }) {
    return GameState(
      currentPlayer:       currentPlayer ?? this.currentPlayer,
      session:             session ?? this.session,
      phase:               phase ?? this.phase,
      scoringRules:        scoringRules ?? this.scoringRules,
      currentQuestion:     currentQuestion ?? this.currentQuestion,
      questionIndex:       questionIndex ?? this.questionIndex,
      answeredCount:       answeredCount ?? this.answeredCount,
      totalPlayers:        totalPlayers ?? this.totalPlayers,
      correctAnswer:       correctAnswer ?? this.correctAnswer,
      lastScoreDelta:      lastScoreDelta ?? this.lastScoreDelta,
      lastSpeedBonus:      lastSpeedBonus ?? this.lastSpeedBonus,
      lastStreakBonus:      lastStreakBonus ?? this.lastStreakBonus,
      topPlayers:          topPlayers ?? this.topPlayers,
      winnerPlayerId:      winnerPlayerId ?? this.winnerPlayerId,
      rewardPointsGranted: rewardPointsGranted ?? this.rewardPointsGranted,
      errorMessage:        errorMessage ?? this.errorMessage,
    );
  }
}