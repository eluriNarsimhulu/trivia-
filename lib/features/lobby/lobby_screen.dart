// project_folder/lib/features/lobby/lobby_screen.dart

/// LobbyScreen — the waiting room after joining a session.
///
/// Responsibilities (UI only):
///   • Display room code for players to share.
///   • Show the live player list (updates via SSE PLAYER_JOINED events).
///   • Show "Start Game" button to host only.
///   • Transition to game screen when phase changes to countdown.
///
/// Architecture note:
///   This screen is entirely reactive. It wraps its body in a single
///   ValueListenableBuilder and reads everything from GameState.
///   It calls exactly two controller methods: startGame() and leaveSession().
///   No local state drives any game logic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart';
import '../../state/game_controller.dart';
import '../../state/game_state.dart';
import '../../core/models/game_phase.dart';
import 'player_list_widget.dart';
import '../game/game_screen.dart';
import '../lobby/lobby_entry_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  /// Guards against double-navigation when state rebuilds rapidly.
  /// Set to true the moment a navigation is triggered — all subsequent
  /// addPostFrameCallback firings for the same transition are no-ops.
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final provider   = GameControllerProvider.of(context);
    final controller = provider.controller;

    return ValueListenableBuilder<GameState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        // React to phase changes — navigate away when game starts or session ends.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted || _navigating) return;

          // Reset flag if state returns to lobby (e.g. after a restart cycle
          // that briefly passed through initial before settling on lobby).
          if (state.phase == GamePhase.lobby) {
            _navigating = false;
            return;
          }

          // Navigate back to entry screen if session ended or was left.
          // Checked first — initial takes priority over countdown.
          if (state.phase == GamePhase.initial) {
            _navigating = true;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LobbyEntryScreen()),
              (route) => false,
            );
            return;
          }

          // Navigate to GameScreen when countdown starts.
          if (state.phase == GamePhase.countdown) {
            _navigating = true;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const GameScreen()),
            );
          }
        });

        final session = state.session;
        if (session == null) {
          // Session not yet hydrated — should resolve within one frame.
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A2E),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope(
          // Intercept back button — cleanly leave session before popping.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) {
              await _handleLeavePressed(context, controller, state);
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            appBar: AppBar(
              backgroundColor: const Color(0xFF16213E),
              foregroundColor: Colors.white,
              title: const Text('Lobby'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  tooltip: state.isHost ? 'Cancel room' : 'Leave room',
                  onPressed: () => _handleLeavePressed(context, controller, state),
                ),
              ],

            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoomCodeCard(roomCode: session.roomCode),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: 'Players',
                      trailing: '${session.players.length} joined',
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: PlayerListWidget(players: session.players),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: state.errorMessage!),
                    ],
                    const SizedBox(height: 16),
                    _BottomBar(state: state, controller: controller),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // void _handlePhaseTransition(BuildContext context, GamePhase phase) {
  //   if (!context.mounted) return;
  //   // Navigate to game screen when countdown starts.
  //   // Actual game screen is built in Stage 5 extension / Stage 6.
  //   // Placeholder navigation guard is here so the lobby correctly
  //   // hands off when phase leaves lobby.
  //   if (phase == GamePhase.countdown || phase == GamePhase.questionActive) {
  //     // TODO(Stage 6): replace with named route or GameScreen push.
  //     debugPrint('[LobbyScreen] Game started — navigate to GameScreen.');
  //   }
  // // }
  // void _handlePhaseTransition(BuildContext context, GamePhase phase) {
  //   if (!context.mounted) return;

  //   if (phase == GamePhase.countdown) {
  //     Navigator.of(context).pushReplacement(
  //       MaterialPageRoute(builder: (_) => const GameScreen()),
  //     );
  //   }
  // }

  // Future<void> _confirmLeave(
  //   BuildContext context,
  //   GameController controller,
  // ) async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (ctx) => AlertDialog(
  //       backgroundColor: const Color(0xFF16213E),
  //       title: const Text('Leave session?',
  //           style: TextStyle(color: Colors.white)),
  //       content: const Text(
  //         'You will be removed from the game.',
  //         style: TextStyle(color: Colors.white70),
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(ctx, false),
  //           child: const Text('Stay', style: TextStyle(color: Colors.white54)),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.pop(ctx, true),
  //           child: const Text('Leave',
  //               style: TextStyle(color: Color(0xFFE94560))),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true && context.mounted) {
  //     await controller.leaveSession();
  //     if (context.mounted) Navigator.of(context).pop();
  //   }
  // }
  Future<void> _handleLeavePressed(
    BuildContext context,
    GameController controller,
    GameState state,
  ) async {
    if (state.isHost) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          title: const Text('Cancel Room?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'This will remove the room for all players.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Room',
                  style: TextStyle(color: Color(0xFFE94560))),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;
      await controller.cancelSession();
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          title: const Text('Leave Room?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You will be removed from the game.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave',
                  style: TextStyle(color: Color(0xFFE94560))),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;
      await controller.leaveSession();
    }
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets — decomposed to keep LobbyScreen.build() readable.
// Each sub-widget is private (_) because it has no value outside this file.
// ---------------------------------------------------------------------------

/// Displays the room code with a copy-to-clipboard action.
class _RoomCodeCard extends StatelessWidget {
  final String roomCode;
  const _RoomCodeCard({required this.roomCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE94560).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Room Code',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white54,
                  letterSpacing: 1.4,
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
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white54),
                tooltip: 'Copy code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: roomCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Room code copied!'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Share this code with friends',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                ),
          ),
        ],
      ),
    );
  }
}

/// Section header with an optional trailing count label.
class _SectionLabel extends StatelessWidget {
  final String label;
  final String? trailing;
  const _SectionLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
      ],
    );
  }
}

/// Non-blocking error banner shown when SSE has a reconnection issue.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reconnecting… $message',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar — shows host Start Game button or a waiting message.
class _BottomBar extends StatelessWidget {
  final GameState state;
  final GameController controller;

  const _BottomBar({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (state.isHost) {
      final canStart = (state.session?.players.length ?? 0) >= 2;

      return Column(
        children: [
          if (!canStart)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Waiting for at least one more player…',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: canStart ? () => controller.startGame() : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'Start Game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Non-host players see a waiting indicator.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Waiting for host to start…',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white38,
              ),
        ),
      ],
    );
  }
}