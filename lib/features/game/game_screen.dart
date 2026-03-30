// project_folder/lib/features/game/game_screen.dart

/// GameScreen — the root gameplay screen.
///
/// Architecture note:
///   This is a pure phase router. It owns exactly one
///   ValueListenableBuilder and switches child widgets based on
///   GameState.phase. No game logic lives here — it is a display
///   coordinator only.
///
///   Each child widget receives only the data it needs from GameState.
///   None of them read the controller or the provider directly —
///   data flows down as plain Dart objects, actions flow up as callbacks.

import 'package:flutter/material.dart';

import '../../core/models/game_phase.dart';
import '../../main.dart';
import '../../state/game_controller.dart';
import '../../state/game_state.dart';
import 'countdown_widget.dart';
import 'question_view.dart';
import 'result_banner.dart';
import 'leaderboard_widget.dart';
import '../lobby/lobby_screen.dart';
import '../lobby/lobby_entry_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final controller = GameControllerProvider.of(context).controller;

    return ValueListenableBuilder<GameState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        if (state.phase == GamePhase.lobby) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted || _navigating) return;
            _navigating = true;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LobbyScreen()),
            );
          });
        } else if (state.phase == GamePhase.initial) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted || _navigating) return;
            _navigating = true;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LobbyEntryScreen()),
              (route) => false,
            );
          });
        }
        return PopScope(
          canPop: false, // back button disabled during active game
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: const Color(0xFF1A1A2E),
            body: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _buildPhaseView(context, state, controller),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Maps the current GamePhase to the correct child widget.
  /// Every case is explicit — no default fallthrough that could hide bugs.
  Widget _buildPhaseView(
    BuildContext context,
    GameState state,
    GameController controller,
  ) {
    switch (state.phase) {
      case GamePhase.countdown:
        return const CountdownWidget(key: ValueKey('countdown'));

      case GamePhase.questionActive:
      case GamePhase.questionClosed:
        // QuestionView handles both phases — it locks the UI internally
        // when phase == questionClosed.
        final question = state.currentQuestion;
        if (question == null) return _loadingView(key: const ValueKey('q-loading'));

        return QuestionView(
          // key: const ValueKey('question'),
          // state: state,
          key: const ValueKey('question'),
          state: state,
          stateNotifier: controller.state,
          onAnswerSelected: (answer) {
            controller.submitAnswer(
              questionId: question.id,
              answer:     answer,
            );
          },
        );

      case GamePhase.roundResult:
        return ResultBanner(
          key: const ValueKey('result'),
          correctAnswer:  state.correctAnswer  ?? '',
          scoreDelta:     state.lastScoreDelta  ?? 0,
          speedBonus:     state.lastSpeedBonus  ?? 0,
          streakBonus:    state.lastStreakBonus  ?? 0,
        );

      case GamePhase.leaderboard:
        return LeaderboardWidget(
          key: const ValueKey('leaderboard'),
          players: state.topPlayers,
          roundNumber: state.session?.currentRound ?? 0,
          totalRounds: state.session?.totalRounds ?? 0,
          isFinal: false,
          isHost: state.isHost,
        );

      case GamePhase.gameEnd:
        return LeaderboardWidget(
          key: const ValueKey('game-end'),
          players:         state.topPlayers,
          roundNumber:     state.session?.totalRounds ?? 0,
          totalRounds:     state.session?.totalRounds ?? 0,
          isFinal:         true,
          winnerPlayerId:  state.winnerPlayerId,
          isHost:          state.isHost,
          onGoToLobby:     state.isHost ? () => controller.goToLobby() : null,
        );

      case GamePhase.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: state.errorMessage ?? 'Connection lost.',
          onRetry: () => controller.leaveSession(),
        );

      // initial and lobby phases navigate away via addPostFrameCallback.
      // Show a blank scaffold — NOT a spinner — so there's no visual buffering
      // between the "Leave Game" tap and the navigation completing.
      case GamePhase.initial:
      case GamePhase.lobby:
        return const SizedBox.shrink();
    }
  }

  Widget _loadingView({Key? key}) {
    return Center(
      key: key,
      child: const CircularProgressIndicator(color: Color(0xFFE94560)),
    );
  }
}

/// Shown when SSE enters an unrecoverable error state.
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.white24),
            const SizedBox(height: 20),
            const Text(
              'Connection Lost',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Leave Game'),
            ),
          ],
        ),
      ),
    );
  }
}