// project_folder/lib/core/models/game_session.dart

/// Represents the shared game session — the same data structure
/// all clients see after joining via a room code.
///
/// Architecture note:
///   GameSession is the "room" metadata. It is separate from GameState
///   because GameState is the local client view (phase, current question,
///   scores), while GameSession is the server-authoritative session record.
///
///   players is an unmodifiable list — GameController replaces the entire
///   list on every PLAYER_JOINED / PLAYER_LEFT event rather than mutating.

import 'player.dart';

class GameSession {
  final String sessionId;
  final String roomCode;
  final String hostId;
  final List<Player> players;
  final int totalRounds;
  final int currentRound;

  const GameSession({
    required this.sessionId,
    required this.roomCode,
    required this.hostId,
    required this.players,
    required this.totalRounds,
    required this.currentRound,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final playerList = json['players'] as List? ?? [];
    return GameSession(
      sessionId:    json['session_id'] as String,
      roomCode:     json['room_code'] as String,
      hostId:       json['host_id'] as String,
      players:      List.unmodifiable(
        playerList.map((p) => Player.fromJson(p as Map<String, dynamic>)),
      ),
      totalRounds:  json['total_rounds'] as int,
      currentRound: json['current_round'] as int? ?? 0,
    );
  }

  /// Convenience: find a single player by id. Returns null if not found.
  Player? playerById(String id) {
    try {
      return players.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  GameSession copyWith({
    String? sessionId,
    String? roomCode,
    String? hostId,
    List<Player>? players,
    int? totalRounds,
    int? currentRound,
  }) {
    return GameSession(
      sessionId:    sessionId ?? this.sessionId,
      roomCode:     roomCode ?? this.roomCode,
      hostId:       hostId ?? this.hostId,
      players:      players ?? this.players,
      totalRounds:  totalRounds ?? this.totalRounds,
      currentRound: currentRound ?? this.currentRound,
    );
  }
}