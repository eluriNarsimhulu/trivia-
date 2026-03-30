// project_folder/trivia-server/routes/sessions.js

// REST routes for session lifecycle.
//   POST /sessions      — host creates a new session
//   POST /sessions/join — player joins by room code

const {
  createSession,
  getSession,
  getSessionByRoomCode,
  serializeSession,
  serializePlayer,
  deleteSession,
} = require('../store');

const { broadcast, getCurrentEventId } = require('../broadcast');
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();



// DELETE /sessions/:id?host_id=...
// Host cancels the session from lobby. Notifies all players then cleans up.
router.delete('/:id', (req, res) => {
  const { id: sessionId } = req.params;
  const { host_id } = req.query;  // sent as query param: ?host_id=...

  if (!host_id) {
    return res.status(400).json({ error: 'host_id is required.' });
  }

  const session = getSession(sessionId);
  if (!session) {
    return res.status(404).json({ error: 'Session not found.' });
  }

  if (session.hostId !== host_id) {
    return res.status(403).json({ error: 'Only the host can cancel the session.' });
  }

  if (session.phase !== 'lobby') {
    return res.status(409).json({ error: 'Can only cancel from lobby.' });
  }

  // Notify ALL connected players before closing.
  broadcast(session, 'SESSION_CANCELLED', {
    reason: 'Host left the room.',
  });

  // Give clients ~500ms to receive the event before closing connections.
  setTimeout(() => {
    for (const res of session.connections.values()) {
      try { res.end(); } catch (_) { }
    }
    deleteSession(sessionId);
    console.log(`[Sessions] Session ${session.roomCode} cancelled by host.`);
  }, 500);

  return res.status(200).json({ status: 'cancelled' });
});


// ---------------------------------------------------------------------------
// POST /sessions
// Host creates a new session.
//
// Body:  { host_id, display_name, total_rounds }
// Response: { session_id, room_code }
// ---------------------------------------------------------------------------
router.post('/', (req, res) => {
  const { host_id, display_name, total_rounds = 3 } = req.body;

  if (!host_id || !display_name) {
    return res.status(400).json({ error: 'host_id and display_name are required.' });
  }

  const sessionId = uuidv4();
  const session = createSession(sessionId, host_id, total_rounds);

  // Add the host as the first player.
  session.players.set(host_id, {
    id: host_id,
    displayName: display_name,
    isHost: true,
    isConnected: true,
  });

  // Initialise host score record.
  session.scores.set(host_id, { total: 0, streak: 0, lastRank: null });

  console.log(`[Sessions] Created session ${session.roomCode} by ${display_name}`);

  return res.status(201).json({
    session_id: sessionId,
    room_code: session.roomCode,
    current_event_id: getCurrentEventId(),
    phase: 'lobby',
  });
});

// ---------------------------------------------------------------------------
// POST /sessions/join
// Player joins an existing session using a room code.
//
// Body:  { room_code, player_id, display_name }
// Response: { session_id, session: { full snapshot } }
// ---------------------------------------------------------------------------
router.post('/join', (req, res) => {
  const { room_code, player_id, display_name } = req.body;

  if (!room_code || !player_id || !display_name) {
    return res.status(400).json({
      error: 'room_code, player_id, and display_name are required.',
    });
  }

  const session = getSessionByRoomCode(room_code);
  if (!session) {
    return res.status(404).json({ error: 'Room not found. Check the code.' });
  }

  if (session.phase !== 'lobby') {
    return res.status(409).json({ error: 'Game already started.' });
  }

  // Upsert player — handles reconnect where same player_id rejoins.
  const isRejoining = session.players.has(player_id);

  session.players.set(player_id, {
    id: player_id,
    displayName: display_name,
    isHost: false,
    isConnected: true,
  });

  if (!isRejoining) {
    session.scores.set(player_id, { total: 0, streak: 0, lastRank: null });
  }

  console.log(`[Sessions] ${display_name} joined ${session.roomCode}${isRejoining ? ' (rejoin)' : ''}`);

  // Create the snapshot AFTER all state changes (including player list update).
  const sessionSnapshot = serializeSession(session);

  return res.status(200).json({
    session_id: session.sessionId,
    session: sessionSnapshot,
    current_event_id: getCurrentEventId(),
  });
});

// ---------------------------------------------------------------------------
// GET /sessions/:id/sync
// Returns a full session snapshot for state-based synchronization.
// ---------------------------------------------------------------------------
router.get('/:id/sync', (req, res) => {
  const { id: sessionId } = req.params;
  const session = getSession(sessionId);

  if (!session) {
    return res.status(404).json({ error: 'Session not found.' });
  }

  return res.status(200).json({
    session: serializeSession(session),
    current_event_id: getCurrentEventId(),
  });
});

module.exports = router;