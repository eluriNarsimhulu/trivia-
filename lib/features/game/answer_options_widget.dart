// project_folder/lib/features/game/answer_options_widget.dart


/// AnswerOptionsWidget — renders the correct input UI per QuestionType.
///
/// Architecture note:
///   This widget is purely presentational. It receives:
///     • the question (to know type + options)
///     • selectedAnswer (for visual state)
///     • isLocked (disables all interaction)
///     • onAnswerSelected callback (fires once, upward to QuestionView)
///
///   It never calls the controller. It never reads GameState.
///   QuestionView owns the "has this player answered?" logic —
///   this widget just renders buttons and fires the callback.

import 'package:flutter/material.dart';

import '../../core/models/question.dart';

class AnswerOptionsWidget extends StatelessWidget {
  final Question question;
  final String? selectedAnswer;
  final bool isLocked;
  final void Function(String answer) onAnswerSelected;

  const AnswerOptionsWidget({
    super.key,
    required this.question,
    required this.selectedAnswer,
    required this.isLocked,
    required this.onAnswerSelected,
  });

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.multipleChoice:
      case QuestionType.imageBased:
        return _McqOptions(
          options:        question.options,
          selectedAnswer: selectedAnswer,
          isLocked:       isLocked,
          onSelected:     onAnswerSelected,
        );
      case QuestionType.trueFalse:
        return _TrueFalseOptions(
          selectedAnswer: selectedAnswer,
          isLocked:       isLocked,
          onSelected:     onAnswerSelected,
        );
      case QuestionType.typeIn:
        return _TypeInOption(
          isLocked:   isLocked,
          onSubmitted: onAnswerSelected,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// MCQ — grid of coloured option buttons
// ---------------------------------------------------------------------------

class _McqOptions extends StatelessWidget {
  final List<String> options;
  final String? selectedAnswer;
  final bool isLocked;
  final void Function(String) onSelected;

  const _McqOptions({
    required this.options,
    required this.selectedAnswer,
    required this.isLocked,
    required this.onSelected,
  });

  // Distinct colours per option index — Kahoot-style visual identity.
  static const _optionColors = [
    Color(0xFFE94560),
    Color(0xFF6C63FF),
    Color(0xFF26DE81),
    Color(0xFFF7B731),
  ];

  @override
  // Widget build(BuildContext context) {
  //   return GridView.builder(
  //     physics: const NeverScrollableScrollPhysics(),
  //     shrinkWrap: true,
  //     gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
  //       crossAxisCount:   2,
  //       childAspectRatio: 2.2,
  //       crossAxisSpacing: 12,
  //       mainAxisSpacing:  12,
  //     ),
  //     itemCount: options.length,
  //     itemBuilder: (_, index) {
  //       final option    = options[index];
  //       final color     = _optionColors[index % _optionColors.length];
  //       final isChosen  = selectedAnswer == option;

  //       return _OptionButton(
  //         label:    option,
  //         color:    color,
  //         isChosen: isChosen,
  //         isLocked: isLocked,
  //         onTap:    () => onSelected(option),
  //       );
  //     },
  //   );
  // }
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: options.length,
      itemBuilder: (_, index) {
        final option = options[index];
        final color = _optionColors[index % _optionColors.length];
        final isChosen = selectedAnswer == option;

        return _OptionButton(
          label: option,
          color: color,
          isChosen: isChosen,
          isLocked: isLocked,
          onTap: () => onSelected(option),
        );
      },
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isChosen;
  final bool isLocked;
  final VoidCallback onTap;

  const _OptionButton({
    required this.label,
    required this.color,
    required this.isChosen,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isChosen
            ? color
            : color.withOpacity(isLocked ? 0.1 : 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isLocked ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isChosen ? color : color.withOpacity(0.35),
                width: isChosen ? 2.5 : 1.5,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isChosen ? Colors.white : Colors.white70,
                fontWeight:
                    isChosen ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// True / False — two large buttons
// ---------------------------------------------------------------------------

class _TrueFalseOptions extends StatelessWidget {
  final String? selectedAnswer;
  final bool isLocked;
  final void Function(String) onSelected;

  const _TrueFalseOptions({
    required this.selectedAnswer,
    required this.isLocked,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _TrueFalseButton(
            label:    'True',
            icon:     Icons.check_circle_outline,
            color:    const Color(0xFF26DE81),
            isChosen: selectedAnswer == 'true',
            isLocked: isLocked,
            onTap:    () => onSelected('true'),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _TrueFalseButton(
            label:    'False',
            icon:     Icons.cancel_outlined,
            color:    const Color(0xFFE94560),
            isChosen: selectedAnswer == 'false',
            isLocked: isLocked,
            onTap:    () => onSelected('false'),
          ),
        ),
      ],
    );
  }
}

class _TrueFalseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isChosen;
  final bool isLocked;
  final VoidCallback onTap;

  const _TrueFalseButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isChosen,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      child: Material(
        color: isChosen ? color : color.withOpacity(isLocked ? 0.08 : 0.15),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: isLocked ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isChosen ? color : color.withOpacity(0.4),
                width: isChosen ? 2.5 : 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color: isChosen ? Colors.white : color, size: 28),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    color:      isChosen ? Colors.white : Colors.white70,
                    fontSize:   22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type-in — text field + submit button
// ---------------------------------------------------------------------------

class _TypeInOption extends StatefulWidget {
  final bool isLocked;
  final void Function(String) onSubmitted;

  const _TypeInOption({required this.isLocked, required this.onSubmitted});

  @override
  State<_TypeInOption> createState() => _TypeInOptionState();
}

class _TypeInOptionState extends State<_TypeInOption> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _submitted = false;
  void _submit() {
    if (_submitted) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _submitted = true;
    widget.onSubmitted(text);
  }

  // void _submit() {
  //   final text = _controller.text.trim();
  //   if (text.isEmpty) return;
  //   widget.onSubmitted(text);
  // }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          enabled: !widget.isLocked,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText:    widget.isLocked ? 'Answer submitted' : 'Type your answer…',
            hintStyle:   const TextStyle(color: Colors.white38),
            filled:      true,
            fillColor:   const Color(0xFF16213E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFE94560), width: 2,
              ),
            ),
          ),
          onSubmitted: widget.isLocked ? null : (_) => _submit(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: widget.isLocked ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor:         const Color(0xFFE94560),
              foregroundColor:         Colors.white,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white24,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              widget.isLocked ? 'Submitted ✓' : 'Submit Answer',
              style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}