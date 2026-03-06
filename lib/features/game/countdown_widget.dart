// project_folder/lib/features/game/countdown_widget.dart

/// CountdownWidget — displayed during GamePhase.countdown.
///
/// Architecture note:
///   The visual countdown is driven by a local AnimationController,
///   not by GameState. GameState does not store a countdown integer —
///   it only stores the phase. The animation is pure UX cosmetics.
///
///   When the server sends the QUESTION event, GameScreen's
///   ValueListenableBuilder rebuilds and replaces this widget with
///   QuestionView. The local animation is discarded at that point.
///   The server — not this timer — is the authoritative signal to advance.

import 'package:flutter/material.dart';

class CountdownWidget extends StatefulWidget {
  const CountdownWidget({super.key});

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  // Local display counter — purely cosmetic.
  int _displayCount = 3;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.4, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_animController);

    _startCycle();
  }

  void _startCycle() {
    _animController.forward(from: 0);

    // Tick every second — display only. Server controls real transition.
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_displayCount > 1) {
        setState(() => _displayCount--);
        _startCycle();
      }
      // When display reaches 1, we stay there until the server's
      // QUESTION event arrives and GameScreen swaps the widget.
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'GET READY',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 32),
          ScaleTransition(
            scale: _scaleAnim,
            child: Text(
              '$_displayCount',
              style: const TextStyle(
                color: Color(0xFFE94560),
                fontSize: 120,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Question coming up…',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}