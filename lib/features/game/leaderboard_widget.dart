// project_folder/lib/features/game/leaderboard_widget.dart

/// LeaderboardWidget — displayed during GamePhase.leaderboard and gameEnd.
///
/// Architecture note:
///   Receives a plain List<PlayerScore> from GameScreen.
///   No controller or provider access needed — pure display widget.
///   [isFinal] switches between mid-game and end-of-game presentation.
///   [winnerPlayerId] is only meaningful when isFinal == true.

import 'package:flutter/material.dart';

import '../../core/models/scoring.dart';

class LeaderboardWidget extends StatefulWidget {
  final List<PlayerScore> players;
  final int roundNumber;
  final bool isFinal;
  final String? winnerPlayerId;

  final bool isHost;              // ADD
  final VoidCallback? onPlayAgain; // ADD

  const LeaderboardWidget({
    super.key,
    required this.players,
    required this.roundNumber,
    required this.isFinal,
    this.winnerPlayerId,
    this.isHost = false,          // ADD
    this.onPlayAgain,             // ADD
  });

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LeaderboardHeader(
            roundNumber: widget.roundNumber,
            isFinal:     widget.isFinal,
          ),
          const SizedBox(height: 8),
          if (widget.isFinal && widget.winnerPlayerId != null) ...[
            _WinnerBanner(
              winner: widget.players.firstWhere(
                (p) => p.playerId == widget.winnerPlayerId,
                orElse: () => widget.players.first,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: ListView.separated(
              itemCount:       widget.players.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final delay = index * 0.08;
                final slideAnim = Tween<Offset>(
                  begin: const Offset(0.3, 0),
                  end:   Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _anim,
                  curve:  Interval(delay, (delay + 0.4).clamp(0, 1),
                      curve: Curves.easeOut),
                ));
                final fadeAnim = Tween<double>(begin: 0, end: 1).animate(
                  CurvedAnimation(
                    parent: _anim,
                    curve:  Interval(delay, (delay + 0.4).clamp(0, 1),
                        curve: Curves.easeOut),
                  ),
                );

                return FadeTransition(
                  opacity: fadeAnim,
                  child: SlideTransition(
                    position: slideAnim,
                    child: _PlayerRankTile(
                      score:    widget.players[index],
                      isWinner: widget.isFinal &&
                          widget.players[index].playerId ==
                              widget.winnerPlayerId,
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.isFinal) ...[
            const SizedBox(height: 20),

            if (widget.isHost)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: widget.onPlayAgain,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text(
                    'Play Again',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else
              const Text(
                'Waiting for host to restart…',
                style: TextStyle(color: Colors.white38, fontSize: 13),
                textAlign: TextAlign.center,
              ),

          ] else ...[
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Next round starting soon…',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardHeader extends StatelessWidget {
  final int roundNumber;
  final bool isFinal;

  const _LeaderboardHeader({
    required this.roundNumber,
    required this.isFinal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isFinal ? '🏆 Final Results' : '📊 Leaderboard',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color:      Colors.white,
            fontSize:   26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isFinal ? 'Game over!' : 'After Round $roundNumber',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ],
    );
  }
}

/// Highlighted winner card shown only on final leaderboard.
class _WinnerBanner extends StatelessWidget {
  final PlayerScore winner;
  const _WinnerBanner({required this.winner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7B731), Color(0xFFFC5C65)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:       const Color(0xFFF7B731).withOpacity(0.3),
            blurRadius:  16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('👑', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WINNER',
                  style: TextStyle(
                    color:       Colors.white70,
                    fontSize:    11,
                    letterSpacing: 2,
                    fontWeight:  FontWeight.bold,
                  ),
                ),
                Text(
                  winner.displayName,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${winner.totalScore}',
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'pts',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single player row with rank, name, score, and rank change indicator.
class _PlayerRankTile extends StatelessWidget {
  final PlayerScore score;
  final bool isWinner;

  const _PlayerRankTile({required this.score, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isWinner
            ? const Color(0xFFF7B731).withOpacity(0.12)
            : const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner
              ? const Color(0xFFF7B731).withOpacity(0.5)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          _RankBadge(rank: score.rank),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              score.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (score.streak > 1) ...[
            const SizedBox(width: 8),
            _StreakBadge(streak: score.streak),
          ],
          const SizedBox(width: 12),
          _RankDelta(delta: score.rankDelta),
          const SizedBox(width: 12),
          Text(
            '${score.totalScore}',
            style: const TextStyle(
              color:      Colors.white,
              fontSize:   16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  static const _medals = {1: '🥇', 2: '🥈', 3: '🥉'};

  @override
  Widget build(BuildContext context) {
    final medal = _medals[rank];
    if (medal != null) {
      return SizedBox(
        width: 32,
        child: Text(medal, style: const TextStyle(fontSize: 22),
            textAlign: TextAlign.center),
      );
    }
    return SizedBox(
      width: 32,
      child: Text(
        '#$rank',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Small flame badge for active streaks.
class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color:        const Color(0xFFFC5C65).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFC5C65).withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department,
              color: Color(0xFFFC5C65), size: 13),
          const SizedBox(width: 3),
          Text(
            '$streak',
            style: const TextStyle(
              color: Color(0xFFFC5C65), fontSize: 12, fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Up/down arrow showing rank change from last round.
class _RankDelta extends StatelessWidget {
  final int delta;
  const _RankDelta({required this.delta});

  @override
  Widget build(BuildContext context) {
    if (delta == 0) {
      return const Icon(Icons.remove, color: Colors.white24, size: 16);
    }
    final up    = delta > 0;
    final color = up ? const Color(0xFF26DE81) : const Color(0xFFE94560);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: color,
          size:  16,
        ),
        Text(
          '${delta.abs()}',
          style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
// ```

// ---

// ## Data Flow Summary
// ```
// SSE event arrives → GameController updates GameState
//                               │
//                               ▼
//                ValueListenableBuilder<GameState> rebuilds GameScreen
//                               │
//                     _buildPhaseView(state)
//                               │
//          ┌────────────────────┼─────────────────────────┐
//          │                    │                         │
//    countdown          questionActive/Closed        roundResult
//          │                    │                         │
// CountdownWidget         QuestionView             ResultBanner
//   (local anim)               │                  (plain data in)
//   server drives         AnswerOptionsWidget
//   real transition            │
//                       onAnswerSelected(answer)
//                              │
//                     GameScreen.onAnswerSelected
//                              │
//                     controller.submitAnswer()     ← only call to controller
//                              │
//                     REST POST /sessions/{id}/answers