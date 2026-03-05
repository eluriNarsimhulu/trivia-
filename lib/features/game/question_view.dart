/// QuestionView — displayed during questionActive and questionClosed phases.
///
/// Architecture note:
///   QuestionView is responsible for displaying the question and routing
///   to the correct answer input widget based on QuestionType.
///   It does NOT submit answers itself — it receives an [onAnswerSelected]
///   callback and fires it upward to GameScreen, which calls the controller.
///
///   Answer locking is derived from GameState.phase:
///     questionActive  → answers enabled
///     questionClosed  → answers locked (no callback fires)
///   No local "hasAnswered" bool is needed for locking — the phase is
///   the single source of truth. Local state only tracks the selected
///   answer for visual highlighting.

import 'package:flutter/material.dart';

import '../../core/models/game_phase.dart';
import '../../core/models/question.dart';
import '../../state/game_state.dart';
import 'answer_options_widget.dart';

class QuestionView extends StatefulWidget {
  final GameState state;
  final ValueNotifier<GameState> stateNotifier;
  final void Function(String answer) onAnswerSelected;

  const QuestionView({
    super.key,
    required this.state,
    required this.stateNotifier,
    required this.onAnswerSelected,
  });

  @override
  State<QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<QuestionView> {
  /// The answer this player has selected, or null if not yet answered.
  /// Used only for local visual highlighting — the controller owns submission.
  String? _selectedAnswer;

  bool get _isLocked =>
      _selectedAnswer != null ||
      widget.state.phase == GamePhase.questionClosed;

  void _onAnswer(String answer) {
    if (_isLocked) return;
    setState(() => _selectedAnswer = answer);
    widget.onAnswerSelected(answer);
  }

  @override
  Widget build(BuildContext context) {
    final state    = widget.state;
    final question = state.currentQuestion!;
    final total    = state.totalPlayers;
    final answered = state.answeredCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionHeader(
            questionIndex: state.questionIndex,
            roundNumber:   state.session?.currentRound ?? 0,
            totalRounds:   state.session?.totalRounds ?? 0,
          ),
          const SizedBox(height: 16),
          // _AnswerProgressBar(answered: answered, total: total),
          _LiveAnswerProgress(stateNotifier: widget.stateNotifier),
          const SizedBox(height: 20),
          _QuestionCard(question: question),
          const SizedBox(height: 24),
          Expanded(
            child: AnswerOptionsWidget(
              question:       question,
              selectedAnswer: _selectedAnswer,
              isLocked:       _isLocked,
              onAnswerSelected: _onAnswer,
            ),
          ),
          if (_isLocked && state.phase == GamePhase.questionActive) ...[
            const SizedBox(height: 16),
            _AnswerLockedChip(),
          ],
        ],
      ),
    );
  }
}

class _QuestionHeader extends StatelessWidget {
  final int questionIndex;
  final int roundNumber;
  final int totalRounds;

  const _QuestionHeader({
    required this.questionIndex,
    required this.roundNumber,
    required this.totalRounds,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Round $roundNumber / $totalRounds',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE94560).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE94560).withOpacity(0.4),
            ),
          ),
          child: Text(
            'Q${questionIndex + 1}',
            style: const TextStyle(
              color: Color(0xFFE94560),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// Before: QuestionView receives the full state and passes raw ints down.
// Every ANSWER_COUNT event rebuilds the entire QuestionView tree.

// After: isolate the progress bar behind its own listener.
// The rest of QuestionView only rebuilds on phase/question changes.

/// Add this to QuestionView — accepts the notifier directly
/// so only this widget subtree rebuilds on answer count changes.
class _LiveAnswerProgress extends StatelessWidget {
  final ValueNotifier<GameState> stateNotifier;

  const _LiveAnswerProgress({required this.stateNotifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        return _AnswerProgressBar(
          answered: state.answeredCount,
          total:    state.totalPlayers,
        );
      },
    );
  }
}

/// Live "X / Y answered" progress bar — updates on every ANSWER_COUNT event.
class _AnswerProgressBar extends StatelessWidget {
  final int answered;
  final int total;

  const _AnswerProgressBar({required this.answered, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (answered / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$answered / $total answered',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            Text(
              '${(fraction * 100).round()}%',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF26DE81)),
          ),
        ),
      ],
    );
  }
}

/// Question text card — includes optional image for imageBased type.
class _QuestionCard extends StatelessWidget {
  final Question question;
  const _QuestionCard({required this.question});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          if (question.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                question.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: Colors.white10,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.white24, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            question.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small chip shown after the player has locked in their answer.
class _AnswerLockedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF26DE81).withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF26DE81).withOpacity(0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                color: Color(0xFF26DE81), size: 16),
            SizedBox(width: 8),
            Text(
              'Answer locked in!',
              style: TextStyle(
                color: Color(0xFF26DE81),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}