// project_folder/trivia-server/game.js

// Game engine — controls the entire game loop.
//
// Responsibilities:
//   1. Select and shuffle questions for the session.
//   2. Drive the phase sequence with server-controlled timers.
//   3. Collect and validate answers.
//   4. Calculate scores (server-authoritative).
//   5. Broadcast the correct SSE event at each phase.
//   6. Debounce ANSWER_COUNT broadcasts (every 500ms max).
//
// Phase sequence (mirrors Flutter GamePhase exactly):
//   lobby → [GAME_START] → countdown(3s)
//   → [QUESTION] → questionActive(timer_seconds)
//   → [Q_RESULT per player] → questionClosed(1.2s)
//   → [LEADERBOARD] → leaderboard(5s)
//   → next question countdown OR [GAME_END]
//
// Timer ownership:
//   All setTimeout/setInterval handles are stored in session.timers
//   so they can be cancelled cleanly on session end or server shutdown.

'use strict';

const { getSession, serializePlayer, deleteSession } = require('./store');
const { broadcast, sendToPlayer }                    = require('./broadcast');
const { QUESTIONS }                                  = require('./questions');
const { SCORING_RULES, calculateScore }              = require('./scoring');

// ---------------------------------------------------------------------------
// Timing constants (milliseconds)
// All durations are server-controlled — clients just react to events.
// ---------------------------------------------------------------------------
const COUNTDOWN_MS       = 3_000;   // "Get Ready" before each question
const RESULT_REVEAL_MS   = 2_000;   // show correct answer before leaderboard
const LEADERBOARD_MS     = 5_000;   // leaderboard display between rounds
const QUESTIONS_PER_GAME = 5;       // how many questions per session

// ---------------------------------------------------------------------------
// Public API — called by routes/game.js
// ---------------------------------------------------------------------------

/**
 * Starts the game for a session.
 * Selects questions, broadcasts GAME_START, begins first countdown.
 *
 * @param {string} sessionId
 * @returns {{ ok: boolean, error?: string }}
 */
function startGame(sessionId) {
  const session = getSession(sessionId);
  if (!session) return { ok: false, error: 'Session not found.' };
  if (session.phase !== 'lobby') return { ok: false, error: 'Game already started.' };
  if (session.players.size < 1) return { ok: false, error: 'No players in session.' };

  // Select a random subset of questions for this session.
  // session.questions = _selectQuestions(QUESTIONS_PER_GAME);
  session.questions = _selectQuestions(session.totalRounds);
  session.phase     = 'countdown';

  console.log(
    `[Game] Starting ${session.roomCode} with ` +
    `${session.players.size} player(s), ${session.questions.length} questions`
  );

  // Broadcast GAME_START to all players simultaneously.
  // Flutter transitions: lobby → countdown on receiving this.
  // broadcast(session, 'GAME_START', {
  //   total_rounds:   session.questions.length,
  //   question_count: session.questions.length,
  //   scoring_rules:  SCORING_RULES,
  // });
  broadcast(session, 'GAME_START', {
    total_rounds:   session.totalRounds,
    question_count: session.questions.length,
    scoring_rules:  SCORING_RULES,
  });

  // Begin the first question after the countdown delay.
  _scheduleQuestion(session, 0);

  return { ok: true };
}

/**
 * Records a player's answer for the current question.
 * Ignores duplicate or late answers.
 *
 * @param {string} sessionId
 * @param {string} questionId
 * @param {string} playerId
 * @param {string} answer
 * @returns {{ ok: boolean, error?: string }}
 */
function submitAnswer(sessionId, questionId, playerId, answer) {
  const session = getSession(sessionId);
  if (!session) return { ok: false, error: 'Session not found.' };

  // Guard: only accept answers during questionActive phase.
  if (session.phase !== 'questionActive') {
    return { ok: false, error: 'Question is not active.' };
  }

  // Guard: answer must be for the current question.
  const currentQ = session.questions[session.currentQuestionIndex];
  if (!currentQ || currentQ.id !== questionId) {
    return { ok: false, error: 'Answer is for wrong question.' };
  }

  // Guard: duplicate answer — player already answered this question.
  if (session.answers.has(playerId)) {
    return { ok: false, error: 'Already answered.' };
  }

  // Guard: player must be in this session.
  if (!session.players.has(playerId)) {
    return { ok: false, error: 'Player not in session.' };
  }

  // Record answer with timestamp for speed bonus calculation.
  session.answers.set(playerId, {
    answer:      answer.trim(),
    submittedAt: Date.now(),
  });

  console.log(
    `[Game] ${session.players.get(playerId).displayName} answered ` +
    `Q${session.currentQuestionIndex + 1} in ${session.roomCode}`
  );

  // Debounced ANSWER_COUNT broadcast — at most once per 500ms.
  _scheduleAnswerCountBroadcast(session);

  // If all connected players have answered, close the question early.
  const connectedCount = _connectedPlayerCount(session);
  const answeredCount  = session.answers.size;

  if (answeredCount >= connectedCount) {
    console.log(`[Game] All ${connectedCount} players answered — closing early`);
    _closeQuestionEarly(session);
  }

  return { ok: true };
}

// ---------------------------------------------------------------------------
// Game loop — private
// ---------------------------------------------------------------------------

/**
 * Schedules the next question after a countdown delay.
 * Called after GAME_START and after each LEADERBOARD display.
 *
 * @param {object} session
 * @param {number} questionIndex - 0-based index into session.questions
 */
function _scheduleQuestion(session, questionIndex) {

  _clearTimer(session, 'question');

  session.phase = 'countdown';

  console.log(
    `[Game] Broadcasting ROUND_COUNTDOWN before Q${questionIndex + 1} ` +
    `in ${session.roomCode}`
  );
  // Notify all clients to enter countdown phase before next question.
  // Flutter GameController handles 'ROUND_COUNTDOWN' → GamePhase.countdown.
  broadcast(session, 'ROUND_COUNTDOWN', {
    duration_seconds: COUNTDOWN_MS / 1000,
    next_question_index: questionIndex,
  });

  session.timers.question = setTimeout(() => {
    _openQuestion(session, questionIndex);
  }, COUNTDOWN_MS);
}

/**
 * Opens a question — broadcasts QUESTION event and starts the answer timer.
 *
 * @param {object} session
 * @param {number} questionIndex
 */
function _openQuestion(session, questionIndex) {
  const question = session.questions[questionIndex];
  if (!question) {
    // Should never happen — guard against off-by-one bugs.
    console.error(`[Game] No question at index ${questionIndex}`);
    return;
  }

  session.currentQuestionIndex = questionIndex;
  session.questionStartTime    = Date.now();
  session.answers              = new Map(); // clear previous answers
  session.phase                = 'questionActive';

  console.log(
    `[Game] Q${questionIndex + 1}/${session.questions.length}: ` +
    `"${question.text}" (${question.timer_seconds}s) in ${session.roomCode}`
  );

  // Broadcast QUESTION to all players.
  // Flutter transitions: countdown → questionActive on receiving this.
  broadcast(session, 'QUESTION', {
    round_number:   questionIndex + 1,
    question_index: questionIndex,
    question: {
      id:            question.id,
      type:          question.type,
      text:          question.text,
      options:       question.options,
      timer_seconds: question.timer_seconds,
      image_url:     question.image_url ?? null,
    },
  });

  // Schedule automatic question close when timer expires.
  _clearTimer(session, 'question');
  session.timers.question = setTimeout(() => {
    // Only close if still active — early close may have already fired.
    if (session.phase === 'questionActive') {
      _closeQuestion(session);
    }
  }, question.timer_seconds * 1_000);
}

/**
 * Called when the question timer expires naturally.
 * Cleans up debounce interval then closes the question.
 */
// _closeQuestion — called when timer expires naturally
function _closeQuestion(session) {
  _clearTimer(session, 'answerCount');
  // 'question' timer already fired naturally — no need to clear it
  _processQuestionEnd(session);
}

// _closeQuestionEarly — called when all players answered
function _closeQuestionEarly(session) {
  _clearTimer(session, 'question');    // cancel the expiry timer
  _clearTimer(session, 'answerCount'); // cancel debounce
  _processQuestionEnd(session);
}

/**
 * Core question-end logic:
 *   1. Set phase to questionClosed.
 *   2. Calculate per-player scores.
 *   3. Send personalised Q_RESULT to each player.
 *   4. After reveal delay, broadcast LEADERBOARD.
 *   5. Schedule next question or broadcast GAME_END.
 */
function _processQuestionEnd(session) {
  session.phase = 'questionClosed';

  const currentQ    = session.questions[session.currentQuestionIndex];
  const correctAns  = currentQ.correct;
  const leaderboard = _calculateAndApplyScores(session, currentQ);

  // Diagnostic — confirms question count is correct.
  console.log(
    `[Game] _processQuestionEnd: index=${session.currentQuestionIndex} ` +
    `total=${session.questions.length} ` +
    `isLast=${session.currentQuestionIndex >= session.questions.length - 1}`
  );

  for (const [playerId] of session.players) {
    const submission = session.answers.get(playerId);
    sendToPlayer(session, playerId, 'Q_RESULT', {
      correct_answer: correctAns,
      score_delta:    submission?._scoreDelta  ?? 0,
      speed_bonus:    submission?._speedBonus  ?? 0,
      streak_bonus:   submission?._streakBonus ?? 0,
    });
  }

  session.timers.result = setTimeout(() => {
    _broadcastLeaderboard(session, leaderboard);

    const isLastQuestion =
      session.currentQuestionIndex >= session.questions.length - 1;

    session.timers.leaderboard = setTimeout(() => {
      if (isLastQuestion) {
        _endGame(session, leaderboard);
      } else {
        const nextIndex = session.currentQuestionIndex + 1;
        console.log(`[Game] Advancing to question ${nextIndex + 1} of ${session.questions.length}`);
        _scheduleQuestion(session, nextIndex);
      }
    }, LEADERBOARD_MS);

  }, RESULT_REVEAL_MS);
}

/**
 * Calculates scores for all players and applies them to session.scores.
 * Also stamps each answer record with score breakdown for Q_RESULT.
 *
 * @returns {PlayerScore[]} sorted leaderboard array
 */
function _calculateAndApplyScores(session, question) {
  const questionStart = session.questionStartTime;

  for (const [playerId, submission] of session.answers) {
    const playerScore = session.scores.get(playerId);
    if (!playerScore) continue;

    const isCorrect = _isCorrectAnswer(submission.answer, question.correct);

    if (isCorrect) {
      const elapsedMs = submission.submittedAt - questionStart;
      const { scoreDelta, speedBonus, streakBonus } = calculateScore(
        elapsedMs,
        question.timer_seconds,
        playerScore.streak,
      );

      // Apply score.
      playerScore.total  += scoreDelta;
      playerScore.streak += 1;

      // Stamp breakdown onto the answer record for Q_RESULT lookup above.
      submission._scoreDelta  = scoreDelta;
      submission._speedBonus  = speedBonus;
      submission._streakBonus = streakBonus;
    } else {
      // Wrong answer resets streak.
      playerScore.streak     = 0;
      submission._scoreDelta  = 0;
      submission._speedBonus  = 0;
      submission._streakBonus = 0;
    }
  }

  // Players who did not answer also lose their streak.
  for (const [playerId] of session.players) {
    if (!session.answers.has(playerId)) {
      const playerScore = session.scores.get(playerId);
      if (playerScore) playerScore.streak = 0;
    }
  }

  return _buildLeaderboard(session);
}

/**
 * Compares a player's answer to the correct answer.
 * Case-insensitive, whitespace-trimmed.
 * Handles true/false normalisation (e.g. 'True' → 'true').
 */
function _isCorrectAnswer(playerAnswer, correctAnswer) {
  return playerAnswer.toLowerCase().trim() ===
         correctAnswer.toLowerCase().trim();
}

/**
 * Builds a sorted leaderboard array from session.scores.
 * Calculates rank and rankDelta compared to last round.
 *
 * @returns {PlayerScorePayload[]} top-5 entries, server-sorted
 */
function _buildLeaderboard(session) {
  const entries = [];

  for (const [playerId, score] of session.scores) {
    const player = session.players.get(playerId);
    if (!player) continue;

    entries.push({
      playerId,
      displayName: player.displayName,
      totalScore:  score.total,
      streak:      score.streak,
      // Use null to signal "no previous rank" for first round.
      lastRank:    score.lastRank ?? null,
    });
  }

  entries.sort((a, b) => b.totalScore - a.totalScore);

  const result = entries.map((entry, index) => {
    const newRank = index + 1;

    // First round: lastRank is null → delta is 0.
    // Subsequent rounds: positive = moved up, negative = dropped.
    const rankDelta = entry.lastRank === null
      ? 0
      : entry.lastRank - newRank;

    const score = session.scores.get(entry.playerId);
    if (score) score.lastRank = newRank;

    return {
      player_id:    entry.playerId,
      display_name: entry.displayName,
      total_score:  entry.totalScore,
      rank:         newRank,
      rank_delta:   rankDelta,
      streak:       entry.streak,
    };
  });

  return result.slice(0, 5);
}

/**
 * Broadcasts the LEADERBOARD event to all players.
 */
function _broadcastLeaderboard(session, leaderboard) {
  session.phase = 'leaderboard';

  broadcast(session, 'LEADERBOARD', {
    round_number: session.currentQuestionIndex + 1,
    top_players:  leaderboard,
  });

  console.log(`[Game] Leaderboard sent for round ${session.currentQuestionIndex + 1}`);
}

/**
 * Broadcasts GAME_END and cleans up the session after a delay.
 */
function _endGame(session, finalLeaderboard) {
  session.phase = 'ended';

  const winner = finalLeaderboard[0];

  console.log(
    `[Game] GAME_END in ${session.roomCode}. ` +
    `Winner: ${winner?.display_name ?? 'nobody'}. ` +
    `Total questions asked: ${session.currentQuestionIndex + 1}`
  );

  broadcast(session, 'GAME_END', {
    final_leaderboard:     finalLeaderboard,
    winner_player_id:      winner?.player_id ?? '',
    reward_points_granted: winner ? 500 : 0,
  });

  // Increased from 10s to 60s — gives mobile clients time to receive
  // GAME_END and gracefully disconnect before server cleanup.
  // SSE reconnects on mobile can take 15-30s on poor networks.
  session.timers.cleanup = setTimeout(() => {

    session.timers.cleanup = null;

    _clearAllTimers(session);

    for (const res of session.connections.values()) {
      try { res.end(); } catch (_) {}
    }

    deleteSession(session.sessionId);

    console.log(`[Game] Session ${session.roomCode} removed from memory.`);

  }, 60_000);
}

// ---------------------------------------------------------------------------
// ANSWER_COUNT debounce
// ---------------------------------------------------------------------------

/**
 * Schedules an ANSWER_COUNT broadcast, debounced to fire at most once per 500ms.
 *
 * Why debounce?
 *   In a room of 20 players all answering at once, without debounce we would
 *   broadcast 20 individual ANSWER_COUNT events per second. With debounce,
 *   we send at most 2 per second regardless of room size.
 */
function _scheduleAnswerCountBroadcast(session) {
  // If a broadcast is already scheduled, let it fire — don't reset the timer.
  if (session.timers.answerCount) return;

  session.timers.answerCount = setTimeout(() => {
    session.timers.answerCount = null; // allow next debounce cycle

    // Only broadcast if question is still active.
    if (session.phase !== 'questionActive') return;

    const total    = session.players.size;
    const answered = session.answers.size;

    broadcast(session, 'ANSWER_COUNT', {
      answered_count: answered,
      total_players:  total,
    });
  }, 500);
}

// ---------------------------------------------------------------------------
// Question selection
// ---------------------------------------------------------------------------

/**
 * Returns a randomly shuffled subset of questions.
 * Uses Fisher-Yates shuffle for uniform distribution.
 *
 * @param {number} count - how many questions to select
 * @returns {Question[]}
 */
function _selectQuestions(count) {
  const pool    = [...QUESTIONS]; // shallow copy — do not mutate the original
  const capped  = Math.min(count, pool.length);

  // Fisher-Yates shuffle.
  for (let i = pool.length - 1; i > 0; i--) {
    const j      = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }

  return pool.slice(0, capped);
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

/**
 * Safely cancels a named timer stored in session.timers.
 */
function _clearTimer(session, name) {
  if (session.timers[name]) {
    clearTimeout(session.timers[name]);
    session.timers[name] = null;
  }
}


function _clearAllTimers(session) {
  _clearTimer(session, 'question');
  _clearTimer(session, 'answerCount');
  _clearTimer(session, 'result');
  _clearTimer(session, 'leaderboard');
  _clearTimer(session, 'cleanup');
}

/**
 * Returns the number of players with active SSE connections.
 * Used to determine "all answered" threshold.
 * Disconnected players cannot answer, so we exclude them from the count.
 */
function _connectedPlayerCount(session) {
  let count = 0;
  for (const player of session.players.values()) {
    if (player.isConnected) count++;
  }
  return count;
}


/**
 * Resets a completed session so the same players can play again.
 * Keeps all players and SSE connections intact.
 * Resets scores, answers, question state, and phase back to lobby.
 *
 * @param {string} sessionId
 * @returns {{ ok: boolean, error?: string }}
 */
function restartGame(sessionId) {
  const session = getSession(sessionId);
  if (!session) return { ok: false, error: 'Session not found.' };

  // Only allow restart from ended state.
  if (session.phase !== 'ended') {
    return { ok: false, error: 'Game has not ended yet.' };
  }

  // Reset all timers.
  _clearAllTimers(session);

  // Reset all game state — keep players and connections untouched.
  session.questions            = [];
  session.currentQuestionIndex = -1;
  session.questionStartTime    = null;
  session.answers              = new Map();
  session.phase                = 'lobby';


  // Reset scores for all players — fresh game.
  for (const [playerId] of session.players) {
    session.scores.set(playerId, { total: 0, streak: 0, lastRank: null });
  }

  console.log(
    `[Game] Session ${session.roomCode} restarted with ` +
    `${session.players.size} player(s)`
  );

  // Broadcast GAME_RESTARTED to all connected clients.
  // Flutter transitions all clients back to lobby phase on receiving this.
  broadcast(session, 'GAME_RESTARTED', {
    room_code: session.roomCode,
    players:   Array.from(session.players.values()).map(p => ({
      id:           p.id,
      display_name: p.displayName,
      is_host:      p.isHost,
      is_connected: p.isConnected,
    })),
  });

  return { ok: true };
}

/**
 * Resets the session back to lobby phase with the same players.
 * Broadcasts GAME_RESTARTED so all Flutter clients return to lobby.
 * SSE connections are kept alive — no reconnect needed.
 */
function restartGame(sessionId) {
  const session = getSession(sessionId);
  if (!session) return { ok: false, error: 'Session not found.' };

  // Allow restart only from ended state.
  if (session.phase !== 'ended') {
    return { ok: false, error: 'Game has not ended yet.' };
  }

  // Clear all timers defensively.
  _clearAllTimers(session);

  // Reset session state back to lobby.
  session.phase                = 'lobby';
  session.questions            = [];
  session.currentQuestionIndex = -1;
  session.questionStartTime    = null;
  session.answers              = new Map();

  // Reset all player scores but keep the players in the session.
  for (const [playerId] of session.scores) {
    session.scores.set(playerId, { total: 0, streak: 0, lastRank: null });
  }

  console.log(`[Game] Restarting ${session.roomCode} back to lobby`);

  // Serialize current player list for the event payload.
  const players = Array.from(session.players.values()).map(p => ({
    id:           p.id,
    display_name: p.displayName,
    is_host:      p.isHost,
    is_connected: p.isConnected,
  }));

  // Broadcast to ALL clients — Flutter transitions gameEnd → lobby.
  broadcast(session, 'GAME_RESTARTED', {
    players,
  });

  return { ok: true };
}

// Add _clearAllTimers as a standalone helper (used by restartGame above):

// Update exports:
module.exports = { startGame, submitAnswer, restartGame };