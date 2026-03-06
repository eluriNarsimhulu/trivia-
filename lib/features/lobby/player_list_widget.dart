// project_folder/lib/features/lobby/player_list_widget.dart
/// PlayerListWidget — displays the current roster of players in the lobby.
///
/// Architecture note:
///   This widget is purely presentational. It receives a List<Player>
///   and renders it — no controller calls, no state reads.
///   It is intentionally stateless: the parent (LobbyScreen) owns the
///   ValueListenableBuilder and passes the already-resolved list down.
///
///   Keeping this widget data-driven (not controller-aware) means it
///   can be reused on any screen that needs to show a player list —
///   e.g. a mid-game player panel in a future stage.

import 'package:flutter/material.dart';
import '../../core/models/player.dart';

class PlayerListWidget extends StatelessWidget {
  final List<Player> players;

  const PlayerListWidget({
    super.key,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Center(
        child: Text(
          'No players yet…',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _PlayerTile(player: players[index]);
      },
    );
  }
}

/// Single player row — avatar, name, host badge, connection indicator.
class _PlayerTile extends StatelessWidget {
  final Player player;
  const _PlayerTile({required this.player});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: player.isConnected
            ? const Color(0xFF16213E)
            : const Color(0xFF16213E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: player.isHost
              ? const Color(0xFFE94560).withOpacity(0.6)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          _PlayerAvatar(player: player),
          const SizedBox(width: 14),
          Expanded(child: _PlayerInfo(player: player)),
          _ConnectionDot(isConnected: player.isConnected),
        ],
      ),
    );
  }
}

/// Circular avatar using the first letter of the player's display name.
class _PlayerAvatar extends StatelessWidget {
  final Player player;
  const _PlayerAvatar({required this.player});

  @override
  Widget build(BuildContext context) {
    // Deterministic color from player id so avatar color is stable
    // across SSE-driven list refreshes.
    final color = _colorFromId(player.id);

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withOpacity(player.isConnected ? 1 : 0.3),
      child: Text(
        player.displayName.isNotEmpty
            ? player.displayName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Generates a stable color from the player's UUID without dart:math.
  Color _colorFromId(String id) {
    const palette = [
      Color(0xFF6C63FF),
      Color(0xFFFF6584),
      Color(0xFF43BCCD),
      Color(0xFFF7B731),
      Color(0xFF26DE81),
      Color(0xFFFC5C65),
      Color(0xFF45AAF2),
      Color(0xFFA55EEA),
    ];
    final index = id.codeUnits.fold(0, (sum, c) => sum + c) % palette.length;
    return palette[index];
  }
}

/// Player name + host / disconnected labels.
class _PlayerInfo extends StatelessWidget {
  final Player player;
  const _PlayerInfo({required this.player});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                player.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: player.isConnected ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            if (player.isHost) ...[
              const SizedBox(width: 8),
              _Badge(label: 'HOST', color: const Color(0xFFE94560)),
            ],
          ],
        ),
        if (!player.isConnected) ...[
          const SizedBox(height: 2),
          const Text(
            'Disconnected',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Small coloured label badge (HOST, etc.).
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Green/grey dot indicating live connection status.
class _ConnectionDot extends StatelessWidget {
  final bool isConnected;
  const _ConnectionDot({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isConnected ? const Color(0xFF26DE81) : Colors.white24,
        boxShadow: isConnected
            ? [
                BoxShadow(
                  color: const Color(0xFF26DE81).withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}