// project_folder/lib/features/lobby/lobby_screen.dart

/// LobbyScreen — waiting room for players before the game starts.
///
/// Responsibilities:
///   - Display the room code for the current session.
///   - List all players currently in the session using [PlayerListWidget].
///   - Provide a "Start Game" button (HOST ONLY).
///   - Provide a "Leave" button.
///   - Observe [GameState] and navigate to [GameScreen] when phase → [GamePhase.countdown].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart';
import '../../state/game_controller.dart';
import '../../state/game_state.dart';
import '../../core/models/game_phase.dart';
import '../game/game_screen.dart';
import 'player_list_widget.dart';
import 'lobby_entry_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final controller = GameControllerProvider.of(context).controller;

    return ValueListenableBuilder<GameState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final session = state.session;

        // --- NAVIGATION HANDLER ---
        // If the server signals game start (phase moves to countdown),
        // we transition to the GameScreen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _navigating) return;

          if (state.phase == GamePhase.countdown) {
            _navigating = true;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const GameScreen()),
            );
          } else if (state.phase == GamePhase.initial) {
             _navigating = true;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LobbyEntryScreen()),
              (route) => false,
            );
          }
        });

        if (session == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A2E),
            body: Center(child: CircularProgressIndicator(color: Color(0xFFE94560))),
          );
        }

        return PopScope(
          canPop: false, // Force use of 'Leave' button
          child: Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: const Text(
                'GAME LOBBY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => controller.leaveSession(),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RoomCodeCard(roomCode: session.roomCode),
                    const SizedBox(height: 32),
                    const Text(
                      'PLAYERS',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: PlayerListWidget(players: session.players),
                    ),
                    const SizedBox(height: 24),
                    _buildFooter(context, state, controller),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, GameState state, GameController controller) {
    if (state.isHost) {
      final canStart = state.session != null && state.session!.players.isNotEmpty;
      return Column(
        children: [
          const Text(
            'You are the host. Tap start when everyone is ready!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: canStart ? () => controller.startGame() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
                shadowColor: const Color(0xFFE94560).withOpacity(0.4),
              ),
              child: const Text(
                'START GAME',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFE94560),
            ),
          ),
          SizedBox(width: 16),
          Text(
            'Waiting for host to start…',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeCard extends StatelessWidget {
  final String roomCode;
  const _RoomCodeCard({required this.roomCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ROOM CODE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                roomCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Color(0xFFE94560), size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: roomCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Room code copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}