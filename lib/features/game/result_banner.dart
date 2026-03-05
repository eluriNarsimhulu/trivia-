/// ResultBanner — displayed during GamePhase.roundResult.
///
/// Architecture note:
///   All values are passed in as plain ints/strings from GameScreen,
///   which reads them from GameState. This widget has no knowledge of
///   GameState, the controller, or SSE events — it only renders numbers.
///   Score calculation is server-authoritative; this widget just displays.

import 'package:flutter/material.dart';

class ResultBanner extends StatefulWidget {
  final String correctAnswer;
  final int scoreDelta;
  final int speedBonus;
  final int streakBonus;

  const ResultBanner({
    super.key,
    required this.correctAnswer,
    required this.scoreDelta,
    required this.speedBonus,
    required this.streakBonus,
  });

  @override
  State<ResultBanner> createState() => _ResultBannerState();
}

class _ResultBannerState extends State<ResultBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _wasCorrect => widget.scoreDelta > 0;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideIn,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ResultIcon(correct: _wasCorrect),
              const SizedBox(height: 20),
              _ResultHeadline(correct: _wasCorrect),
              const SizedBox(height: 24),
              _CorrectAnswerCard(answer: widget.correctAnswer),
              const SizedBox(height: 24),
              if (_wasCorrect) ...[
                _ScoreBreakdownCard(
                  scoreDelta:  widget.scoreDelta,
                  speedBonus:  widget.speedBonus,
                  streakBonus: widget.streakBonus,
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Leaderboard coming up…',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultIcon extends StatelessWidget {
  final bool correct;
  const _ResultIcon({required this.correct});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (correct ? const Color(0xFF26DE81) : const Color(0xFFE94560))
            .withOpacity(0.15),
      ),
      child: Icon(
        correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size:  52,
        color: correct ? const Color(0xFF26DE81) : const Color(0xFFE94560),
      ),
    );
  }
}

class _ResultHeadline extends StatelessWidget {
  final bool correct;
  const _ResultHeadline({required this.correct});

  @override
  Widget build(BuildContext context) {
    return Text(
      correct ? 'Correct! 🎉' : 'Not quite…',
      style: TextStyle(
        color:      correct ? const Color(0xFF26DE81) : Colors.white60,
        fontSize:   28,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _CorrectAnswerCard extends StatelessWidget {
  final String answer;
  const _CorrectAnswerCard({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          const Text(
            'CORRECT ANSWER',
            style: TextStyle(
              color:       Colors.white38,
              fontSize:    11,
              letterSpacing: 1.8,
              fontWeight:  FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color:      Colors.white,
              fontSize:   20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBreakdownCard extends StatelessWidget {
  final int scoreDelta;
  final int speedBonus;
  final int streakBonus;

  const _ScoreBreakdownCard({
    required this.scoreDelta,
    required this.speedBonus,
    required this.streakBonus,
  });

  int get _basePoints => scoreDelta - speedBonus - streakBonus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF26DE81).withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          _ScoreRow(label: 'Base points',  value: _basePoints, icon: Icons.star_outline),
          if (speedBonus > 0) ...[
            const Divider(color: Colors.white12, height: 20),
            _ScoreRow(label: 'Speed bonus',  value: speedBonus,  icon: Icons.bolt),
          ],
          if (streakBonus > 0) ...[
            const Divider(color: Colors.white12, height: 20),
            _ScoreRow(label: 'Streak bonus', value: streakBonus, icon: Icons.local_fire_department),
          ],
          const Divider(color: Colors.white24, height: 24),
          _ScoreRow(
            label:   'Total earned',
            value:   scoreDelta,
            icon:    Icons.emoji_events_rounded,
            isTotal: true,
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool isTotal;

  const _ScoreRow({
    required this.label,
    required this.value,
    required this.icon,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isTotal ? const Color(0xFFF7B731) : Colors.white70;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color:      color,
                fontSize:   isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        Text(
          '+$value',
          style: TextStyle(
            color:      color,
            fontSize:   isTotal ? 18 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}