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

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GameControllerProvider.of(context).controller;

    return ValueListenableBuilder<GameState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        return PopScope(
          canPop: false, // back button disabled during active game
          child: Scaffold(
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
          players:     state.topPlayers,
          roundNumber: state.session?.currentRound ?? 0,
          isFinal:     false,
        );

      case GamePhase.gameEnd:
        return LeaderboardWidget(
          key: const ValueKey('game-end'),
          players:         state.topPlayers,
          roundNumber:     state.session?.totalRounds ?? 0,
          isFinal:         true,
          winnerPlayerId:  state.winnerPlayerId,
        );

      case GamePhase.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: state.errorMessage ?? 'Connection lost.',
          onRetry: () => controller.leaveSession(),
        );

      // Lobby and initial phases should never reach GameScreen.
      // If they do, show a safe fallback.
      case GamePhase.initial:
      case GamePhase.lobby:
        return _loadingView(key: const ValueKey('fallback'));
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