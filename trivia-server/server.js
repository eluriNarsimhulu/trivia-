// project_folder/trivia-server/server.js

// Trivia Game Backend — entry point.
//
// Starts an Express server that:
//   • serves REST endpoints for session management and answer submission
//   • serves GET /sessions/:id/events as a persistent SSE stream
//   • broadcasts game events to all players in a session in real time
//
// Designed for local WiFi demo: run on host machine, phones connect by IP.

'use strict';

const express = require('express');
const cors    = require('cors');

const sessionRoutes = require('./routes/sessions');
const gameRoutes    = require('./routes/game');
const eventRoutes   = require('./routes/events');

const app  = express();
const PORT = process.env.PORT || 3000;

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

// Allow all origins — required so Flutter app on a phone can reach the server.
app.use(cors());

// Parse JSON bodies for all POST requests.
app.use(express.json());

// Request logger — helpful during demo.
app.use((req, _res, next) => {
  console.log(`→ ${req.method} ${req.path}`);
  next();
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

app.use('/sessions', sessionRoutes);
app.use('/sessions', gameRoutes);
app.use('/sessions', eventRoutes);

// Health check — useful to confirm server is reachable from phone.
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------
// On CTRL+C, close all open SSE connections before exiting.
// Prevents Flutter clients from hanging on a half-closed stream.

const { sessions } = require('./store');   // expose sessions Map for shutdown

process.on('SIGINT', () => {
  console.log('\n[Server] Shutting down — closing SSE connections...');

  for (const session of sessions.values()) {
    for (const res of session.connections.values()) {
      try {
        res.end();
      } catch (_) {}
    }

    // Cancel any running game timers.
    if (session.timers.question)    clearTimeout(session.timers.question);
    if (session.timers.answerCount) clearTimeout(session.timers.answerCount);
    if (session.timers.result)      clearTimeout(session.timers.result);
    if (session.timers.leaderboard) clearTimeout(session.timers.leaderboard);
    if (session.timers.cleanup)     clearTimeout(session.timers.cleanup);
  }

  console.log('[Server] Done. Goodbye.');
  process.exit(0);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('┌─────────────────────────────────────────┐');
  console.log('│        Trivia Game Server Running        │');
  console.log(`│  Local:   http://localhost:${PORT}           │`);
  console.log(`│  Network: http://<YOUR-IP>:${PORT}           │`);
  console.log('│                                          │');
  console.log('│  Find your IP:                           │');
  console.log('│    macOS/Linux: ifconfig | grep inet     │');
  console.log('│    Windows:     ipconfig                 │');
  console.log('└─────────────────────────────────────────┘');
  console.log('');
});