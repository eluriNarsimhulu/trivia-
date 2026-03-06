// project_folder/lib/core/models/game_phase.dart

/// Represents every distinct phase the game can occupy.
///
/// Architecture note:
///   GameController is the ONLY class that drives phase transitions.
///   UI reads phase from GameState and renders accordingly.
///   Illegal transitions are silently ignored — enforced in Stage 2.
///
/// Transition graph:
///   initial → lobby
///   lobby → countdown             (on GAME_START, host triggered via REST)
///   countdown → questionActive    (on QUESTION event)
///   questionActive → questionClosed   (on Q_RESULT — timer expired / all answered)
///   questionClosed → roundResult  (immediate, after brief UI reveal delay)
///   roundResult → leaderboard
///   leaderboard → countdown       (next round)
///   leaderboard → gameEnd         (all rounds complete)
///   any → error                   (unrecoverable SSE failure)
///
/// NOTE on questionClosed:
///   This phase is intentionally distinct from roundResult.
///   questionClosed = "no more answers accepted, revealing answer now"
///   roundResult    = "answer revealed, score delta shown"
///   The two-step split gives the UI a clean hook to animate the
///   correct answer reveal before showing score changes.
///   GameController enters questionClosed first on Q_RESULT,
///   then transitions to roundResult — formally enforced in Stage 2.

enum GamePhase {
  /// App launched. No session established.
  initial,

  /// Session created. Players joining via room code. Host waiting.
  lobby,

  /// Host started game. Brief countdown before first question.
  countdown,

  /// Question visible to all players. Timer running. Answers accepted.
  questionActive,

  /// Timer expired or all players answered. Answers no longer accepted.
  /// UI shows the correct answer reveal animation.
  /// Transitions immediately to roundResult after reveal.
  questionClosed,

  /// Correct answer shown. Per-player score delta displayed.
  roundResult,

  /// Top-5 leaderboard displayed between rounds.
  leaderboard,

  /// All rounds complete. Final standings and winner announced.
  gameEnd,

  /// Unrecoverable failure (e.g. SSE permanently disconnected).
  error,
}