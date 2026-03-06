// project_folder/lib/core/models/player.dart

/// Represents a single participant in a game session.
///
/// Architecture note:
///   Player is immutable. When a player's connection status changes,
///   GameController replaces the Player instance inside GameSession —
///   it never mutates the existing object.
///
///   isHost is set once at session creation and never changes.
///   isConnected is updated on PLAYER_JOINED / PLAYER_LEFT events.

class Player {
  final String id;
  final String displayName;
  final bool isHost;
  final bool isConnected;

  const Player({
    required this.id,
    required this.displayName,
    required this.isHost,
    required this.isConnected,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id:          json['id'] as String,
      displayName: json['display_name'] as String,
      isHost:      json['is_host'] as bool,
      isConnected: json['is_connected'] as bool? ?? true,
    );
  }

  /// Returns a new Player with only the specified fields changed.
  /// Used by GameController when updating connection status.
  Player copyWith({
    String? id,
    String? displayName,
    bool? isHost,
    bool? isConnected,
  }) {
    return Player(
      id:          id ?? this.id,
      displayName: displayName ?? this.displayName,
      isHost:      isHost ?? this.isHost,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Player && other.id == id;

  @override
  int get hashCode => id.hashCode;
}