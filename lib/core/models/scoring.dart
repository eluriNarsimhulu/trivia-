/// ScoringRules: delivered once in GAME_START, constant for the session.
/// PlayerScore: recreated on every LEADERBOARD and Q_RESULT event.
///
/// Architecture note:
///   Scoring math is SERVER-AUTHORITATIVE.
///   The client never calculates scores — it only displays what the server sends.
///   These models are pure display data.

class ScoringRules {
  final int basePoints;
  final int maxSpeedBonus;
  final int streakBonusPerStep;

  const ScoringRules({
    required this.basePoints,
    required this.maxSpeedBonus,
    required this.streakBonusPerStep,
  });

  factory ScoringRules.fromJson(Map<String, dynamic> json) {
    return ScoringRules(
      basePoints:         json['base_points'] as int,
      maxSpeedBonus:      json['max_speed_bonus'] as int,
      streakBonusPerStep: json['streak_bonus_per_step'] as int,
    );
  }
}

/// One player's standing snapshot — rebuilt on every leaderboard update.
class PlayerScore {
  final String playerId;
  final String displayName;
  final int totalScore;
  final int rank;
  final int rankDelta;   // +N = moved up N spots, -N = dropped
  final int streak;      // consecutive correct answers

  const PlayerScore({
    required this.playerId,
    required this.displayName,
    required this.totalScore,
    required this.rank,
    required this.rankDelta,
    required this.streak,
  });

  factory PlayerScore.fromJson(Map<String, dynamic> json) {
    return PlayerScore(
      playerId:    json['player_id'] as String,
      displayName: json['display_name'] as String,
      totalScore:  json['total_score'] as int,
      rank:        json['rank'] as int,
      rankDelta:   json['rank_delta'] as int? ?? 0,
      streak:      json['streak'] as int? ?? 0,
    );
  }
}