// project_folder/trivia-server/scoring.js


// Server-authoritative scoring.
// Flutter client displays whatever the server sends — no client calculation.
//
// Formula:
//   base:         100 points for a correct answer
//   speed bonus:  up to 50 points — linear decay over question timer
//   streak bonus: 10 points per consecutive correct answer (capped at 50)

const BASE_POINTS         = 100;
const MAX_SPEED_BONUS     = 50;
const STREAK_BONUS_STEP   = 10;
const MAX_STREAK_BONUS    = 50;

// Rules object sent to Flutter in GAME_START — must match ScoringRules.fromJson
const SCORING_RULES = {
  base_points:          BASE_POINTS,
  max_speed_bonus:      MAX_SPEED_BONUS,
  streak_bonus_per_step: STREAK_BONUS_STEP,
};

/**
 * Calculate points for a correct answer.
 *
 * @param {number} elapsedMs    - how long the player took to answer (ms)
 * @param {number} timerSeconds - total time allowed for the question
 * @param {number} streak       - player's current consecutive correct count
 * @returns {{ scoreDelta, speedBonus, streakBonus }}
 */
function calculateScore(elapsedMs, timerSeconds, streak) {
  const timerMs   = timerSeconds * 1000;
  const remaining = Math.max(0, timerMs - elapsedMs);

  // Speed bonus: full bonus if answered instantly, 0 if answered at the last ms.
  const speedBonus = Math.round((remaining / timerMs) * MAX_SPEED_BONUS);

  // Streak bonus: 10 per streak level, capped at 50.
  const streakBonus = Math.min(streak * STREAK_BONUS_STEP, MAX_STREAK_BONUS);

  const scoreDelta = BASE_POINTS + speedBonus + streakBonus;

  return { scoreDelta, speedBonus, streakBonus };
}

module.exports = { SCORING_RULES, calculateScore };