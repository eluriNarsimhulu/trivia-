// project_folder/trivia-server/routes/game.js

// REST routes that trigger game actions.
//   POST /sessions/:id/start   — host starts the game
//   POST /sessions/:id/answers — player submits an answer

'use strict';

const express              = require('express');
const router               = express.Router();
const { getSession }       = require('../store');
const { startGame, submitAnswer, restartGame } = require('../game');

// ---------------------------------------------------------------------------
// POST /sessions/:id/restart
// Host restarts the game with the same players.
//
// Body:    { host_id }
// Returns: 200 OK | 400/403/404/409
// ---------------------------------------------------------------------------
router.post('/:id/restart', (req, res) => {
  const { id: sessionId } = req.params;
  const { host_id }       = req.body;

  if (!host_id) {
    return res.status(400).json({ error: 'host_id is required.' });
  }

  const session = getSession(sessionId);
  if (!session) {
    return res.status(404).json({ error: 'Session not found.' });
  }

  if (session.hostId !== host_id) {
    return res.status(403).json({ error: 'Only the host can restart the game.' });
  }

  const result = restartGame(sessionId);
  if (!result.ok) {
    return res.status(409).json({ error: result.error });
  }

  return res.status(200).json({ status: 'restarted' });
});
// ---------------------------------------------------------------------------
// POST /sessions/:id/start
// Host triggers game start.
//
// Body:    { host_id }
// Returns: 200 OK  |  400/403/404/409
// ---------------------------------------------------------------------------
router.post('/:id/start', (req, res) => {
  const { id: sessionId } = req.params;
  const { host_id }       = req.body;

  if (!host_id) {
    return res.status(400).json({ error: 'host_id is required.' });
  }

  const session = getSession(sessionId);
  if (!session) {
    return res.status(404).json({ error: 'Session not found.' });
  }

  // Only the host may start the game.
  if (session.hostId !== host_id) {
    return res.status(403).json({ error: 'Only the host can start the game.' });
  }

  const result = startGame(sessionId);

  if (!result.ok) {
    return res.status(409).json({ error: result.error });
  }

  return res.status(200).json({ status: 'started' });
});

// ---------------------------------------------------------------------------
// POST /sessions/:id/answers
// Player submits an answer.
//
// Body:    { question_id, player_id, answer }
// Returns: 200 OK  |  400/404/409
//
// Flutter's GameController already guards against:
//   - submitting outside questionActive phase (client-side guard)
//   - duplicate submissions (client-side guard)
// The server adds a second layer of both checks.
// ---------------------------------------------------------------------------
router.post('/:id/answers', (req, res) => {
  const { id: sessionId }               = req.params;
  const { question_id, player_id, answer } = req.body;

  if (!question_id || !player_id || !answer) {
    return res.status(400).json({
      error: 'question_id, player_id, and answer are required.',
    });
  }

  const result = submitAnswer(sessionId, question_id, player_id, answer);

  if (!result.ok) {
    // 409 for "already answered" or "wrong question" — client treats these
    // as ignorable (RestException.isIgnorable in Flutter RestService).
    const status = result.error === 'Session not found.' ? 404 : 409;
    return res.status(status).json({ error: result.error });
  }

  return res.status(200).json({ status: 'recorded' });
});

module.exports = router;


// ```

// ---

// ## Game loop timeline
// ```
// broadcast GAME_START
//          │
//          └── wait COUNTDOWN_MS (3s)
//                    │
//                    ▼
//          broadcast QUESTION (Q1)
//                    │
//                    ├── players submit answers
//                    │       │
//                    │       ├── record answer + timestamp
//                    │       ├── debounce ANSWER_COUNT (500ms)
//                    │       └── if all answered → close early
//                    │
//                    └── wait timer_seconds (10-20s)
//                              │
//                              ▼
//                    sendToPlayer Q_RESULT  ← personalised per player
//                              │
//                              └── wait RESULT_REVEAL_MS (1.2s)
//                                        │
//                                        ▼
//                              broadcast LEADERBOARD
//                                        │
//                                        └── wait LEADERBOARD_MS (5s)
//                                                  │
//                                     ┌────────────┴──────────────┐
//                                more questions              last question
//                                     │                          │
//                              wait COUNTDOWN_MS          broadcast GAME_END
//                                     │                          │
//                              broadcast QUESTION (Q2)    clean up session