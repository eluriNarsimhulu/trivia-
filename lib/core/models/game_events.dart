
// project_folder/lib/core/models/game_events.dart
/// Typed SSE event hierarchy.
///
/// Architecture note:
///   SseService parses raw SSE text → emits a GameEvent subclass.
///   GameController receives the event → drives a state transition.
///   UI never touches events — it only reads GameState.
///
///   `sealed` enforces exhaustive switch in GameController.
///   Adding a new event type without a handler = compile error.
///
/// Protocol boundary (important):
///   SSE  = server → client ONLY   (events below)
///   REST = client → server ONLY   (createSession, joinSession, startGame, submitAnswer)
///
///   Session creation is a REST concern. The host calls POST /sessions,
///   receives sessionId + roomCode in the HTTP response body, then opens
///   the SSE stream. There is no SESSION_CREATED SSE event — that would
///   be redundant and would blur the REST/SSE boundary.

import 'player.dart';
import 'question.dart';
import 'scoring.dart';

sealed class GameEvent {
  const GameEvent();
}

// ---------------------------------------------------------------------------
// GAME_RESTARTED
// Broadcast when host restarts. All clients return to lobby.
// SSE connection stays open — no reconnect needed.
// ---------------------------------------------------------------------------
class GameRestartedEvent extends GameEvent {
  final List<Player> players;

  const GameRestartedEvent({required this.players});

  factory GameRestartedEvent.fromJson(Map<String, dynamic> json) {
    final list = json['players'] as List? ?? [];
    return GameRestartedEvent(
      players: List.unmodifiable(
        list.map((p) => Player.fromJson(p as Map<String, dynamic>)),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// GAME_RESTARTED
// Broadcast by server when host restarts with same players.
// All clients transition back to lobby — SSE stays connected.
// ---------------------------------------------------------------------------
// class GameRestartedEvent extends GameEvent {
//   final String roomCode;
//   final List<Player> players;

//   const GameRestartedEvent({
//     required this.roomCode,
//     required this.players,
//   });

//   factory GameRestartedEvent.fromJson(Map<String, dynamic> json) {
//     final playerList = json['players'] as List;
//     return GameRestartedEvent(
//       roomCode: json['room_code'] as String,
//       players: List.unmodifiable(
//         playerList.map((p) => Player.fromJson(p as Map<String, dynamic>)),
//       ),
//     );
//   }
// }

// ---------------------------------------------------------------------------
// PLAYER_JOINED
// Broadcast to all connected clients when a new player joins the lobby.
// ---------------------------------------------------------------------------
class PlayerJoinedEvent extends GameEvent {
  final Player player;

  const PlayerJoinedEvent({required this.player});

  factory PlayerJoinedEvent.fromJson(Map<String, dynamic> json) {
    return PlayerJoinedEvent(
      player: Player.fromJson(json['player'] as Map<String, dynamic>),
    );
  }
}

// ---------------------------------------------------------------------------
// PLAYER_LEFT
// Broadcast when a player disconnects or leaves.
// Controller marks them isConnected: false — never removes from list.
// Preserves leaderboard rank for reconnecting players.
// ---------------------------------------------------------------------------
class PlayerLeftEvent extends GameEvent {
  final String playerId;

  const PlayerLeftEvent({required this.playerId});

  factory PlayerLeftEvent.fromJson(Map<String, dynamic> json) {
    return PlayerLeftEvent(
      playerId: json['player_id'] as String,
    );
  }
}

// ---------------------------------------------------------------------------
// GAME_START
// Broadcast to ALL clients when host calls POST /sessions/{id}/start.
// This is what transitions every client from lobby → countdown simultaneously.
// The host does NOT get a special event — host is just another subscriber.
// ---------------------------------------------------------------------------
class GameStartEvent extends GameEvent {
  final int totalRounds;
  final int questionCount;
  final ScoringRules scoringRules;

  const GameStartEvent({
    required this.totalRounds,
    required this.questionCount,
    required this.scoringRules,
  });

  factory GameStartEvent.fromJson(Map<String, dynamic> json) {
    return GameStartEvent(
      totalRounds:   json['total_rounds'] as int,
      questionCount: json['question_count'] as int,
      scoringRules:  ScoringRules.fromJson(
        json['scoring_rules'] as Map<String, dynamic>,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QUESTION
// Emitted to all clients at the start of each question phase.
// Server controls timing — all players see this simultaneously.
// ---------------------------------------------------------------------------
class QuestionEvent extends GameEvent {
  final int roundNumber;
  final int questionIndex;
  final Question question;

  const QuestionEvent({
    required this.roundNumber,
    required this.questionIndex,
    required this.question,
  });

  factory QuestionEvent.fromJson(Map<String, dynamic> json) {
    return QuestionEvent(
      roundNumber:   json['round_number'] as int,
      questionIndex: json['question_index'] as int,
      question:      Question.fromJson(
                       json['question'] as Map<String, dynamic>,
                     ),
    );
  }
}

// ---------------------------------------------------------------------------
// ANSWER_COUNT
// Debounced every 500ms. Live "X / Y answered" progress indicator.
// Does NOT trigger a phase transition — purely informational.
// ---------------------------------------------------------------------------
class AnswerCountEvent extends GameEvent {
  final int answeredCount;
  final int totalPlayers;

  const AnswerCountEvent({
    required this.answeredCount,
    required this.totalPlayers,
  });

  factory AnswerCountEvent.fromJson(Map<String, dynamic> json) {
    return AnswerCountEvent(
      answeredCount: json['answered_count'] as int,
      totalPlayers:  json['total_players'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// Q_RESULT
// Server emits this when the question closes (timer expired or all answered).
// Drives a two-step transition: questionActive → questionClosed → roundResult
// The split is intentional: questionClosed animates the correct answer reveal,
// roundResult shows the score delta. Stage 2 enforces this formally.
// ---------------------------------------------------------------------------
class QuestionResultEvent extends GameEvent {
  final String correctAnswer;
  final int scoreDelta;
  final int speedBonus;
  final int streakBonus;

  const QuestionResultEvent({
    required this.correctAnswer,
    required this.scoreDelta,
    required this.speedBonus,
    required this.streakBonus,
  });

  factory QuestionResultEvent.fromJson(Map<String, dynamic> json) {
    return QuestionResultEvent(
      correctAnswer: json['correct_answer'] as String,
      scoreDelta:    json['score_delta'] as int,
      speedBonus:    json['speed_bonus'] as int,
      streakBonus:   json['streak_bonus'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// LEADERBOARD
// Top-5 standings after each round, with rank change deltas.
// ---------------------------------------------------------------------------
class LeaderboardEvent extends GameEvent {
  final int roundNumber;
  final List<PlayerScore> topPlayers;

  const LeaderboardEvent({
    required this.roundNumber,
    required this.topPlayers,
  });

  factory LeaderboardEvent.fromJson(Map<String, dynamic> json) {
    final entries = json['top_players'] as List;
    return LeaderboardEvent(
      roundNumber: json['round_number'] as int,
      topPlayers:  List.unmodifiable(
        entries.map((e) => PlayerScore.fromJson(e as Map<String, dynamic>)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GAME_END
// Final leaderboard + winner + reward points. Terminal event.
// ---------------------------------------------------------------------------
class GameEndEvent extends GameEvent {
  final List<PlayerScore> finalLeaderboard;
  final String winnerPlayerId;
  final int rewardPointsGranted;

  const GameEndEvent({
    required this.finalLeaderboard,
    required this.winnerPlayerId,
    required this.rewardPointsGranted,
  });

  factory GameEndEvent.fromJson(Map<String, dynamic> json) {
    final entries = json['final_leaderboard'] as List;
    return GameEndEvent(
      finalLeaderboard:    List.unmodifiable(
        entries.map((e) => PlayerScore.fromJson(e as Map<String, dynamic>)),
      ),
      winnerPlayerId:      json['winner_player_id'] as String,
      rewardPointsGranted: json['reward_points_granted'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// ROUND_COUNTDOWN
// Emitted before each question (including Q1 after GAME_START).
// Tells all clients to enter countdown phase between rounds.
// ---------------------------------------------------------------------------
class RoundCountdownEvent extends GameEvent {
  final int durationSeconds;
  final int nextQuestionIndex;

  const RoundCountdownEvent({
    required this.durationSeconds,
    required this.nextQuestionIndex,
  });

  factory RoundCountdownEvent.fromJson(Map<String, dynamic> json) {
    return RoundCountdownEvent(
      durationSeconds:    json['duration_seconds'] as int,
      nextQuestionIndex:  json['next_question_index'] as int,
    );
  }
}