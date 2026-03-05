// SSE endpoint — GET /sessions/:id/events?playerId=...
//
// This is the heart of the real-time system.
//
// How SSE works here:
//   1. Flutter client opens a GET request to this endpoint.
//   2. Server sets headers to keep the connection alive indefinitely.
//   3. Server stores the response object in session.connections.
//   4. Any time a game event occurs, broadcast.js writes to all stored responses.
//   5. If the client disconnects, we clean up and notify other players.
//
// One SSE connection per player per session.
// Duplicate connections from the same player replace the old one.

'use strict';

const express = require('express');
const router  = express.Router();

const { getSession, serializePlayer } = require('../store');
const { broadcast, sendToPlayer }     = require('../broadcast');

// ---------------------------------------------------------------------------
// GET /sessions/:id/events?playerId=...
// ---------------------------------------------------------------------------
router.get('/:id/events', (req, res) => {
  const { id: sessionId } = req.params;
  const { playerId }      = req.query;

  // -- Validate inputs --
  if (!playerId) {
    return res.status(400).json({ error: 'playerId query param is required.' });
  }

  const session = getSession(sessionId);
  if (!session) {
    return res.status(404).json({ error: 'Session not found.' });
  }

  const player = session.players.get(playerId);
  if (!player) {
    // Player must have joined via REST before opening SSE.
    return res.status(403).json({
      error: 'Player not in session. Call POST /sessions/join first.',
    });
  }

  // -- SSE headers --
  // These three headers are mandatory for a valid SSE stream.
  // no-cache prevents proxies from buffering events.
  // keep-alive tells the TCP layer to hold the connection open.
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');

  // Flush headers immediately so the client knows the stream is open.
  // Without this, some HTTP clients buffer until the first write.
  res.flushHeaders();

  // -- Handle duplicate connection (reconnect) --
  // If this player already has an open SSE connection, close the old one
  // before registering the new one. This happens on mobile network switches
  // or when the Flutter app reconnects after a drop.
  const existingConnection = session.connections.get(playerId);
  if (existingConnection) {
    console.log(`[SSE] ${player.displayName} replacing existing connection`);
    try {
      existingConnection.end();
    } catch (_) {
      // Old connection may already be dead — safe to ignore.
    }
  }

  // -- Register connection --
  session.connections.set(playerId, res);
  player.isConnected = true;

  console.log(
    `[SSE] ${player.displayName} connected to ${session.roomCode} ` +
    `(${session.connections.size} total)`
  );

  // -- Send initial heartbeat --
  // Confirms to the client that the stream is alive immediately.
  // Flutter SseService ignores comment lines (starts with ':') per RFC 8895.
  res.write(': connected\n\n');

  // -- Notify other players this player joined/reconnected --
  // Broadcast PLAYER_JOINED to everyone EXCEPT the joining player themselves.
  // The joining player already has their own identity from the REST response.
  broadcastPlayerJoined(session, player, playerId);

  // -- Heartbeat interval --
  // Sends a comment line every 25 seconds.
  // Prevents NAT gateways and mobile networks from killing idle connections.
  // Flutter SseService discards comment lines silently.
  const heartbeatInterval = setInterval(() => {
    if (!res.writableEnded) {
      res.write(': heartbeat\n\n');
    } else {
      clearInterval(heartbeatInterval);
    }
  }, 25_000);

  // -- Disconnect handler --
  // Fires when the client closes the connection (app backgrounded,
  // network lost, or explicit disconnect() call from Flutter).
  req.on('close', () => {
    clearInterval(heartbeatInterval);

    // Only process if this is still the active connection for this player.
    // (Not a stale handler from a replaced connection.)
    if (session.connections.get(playerId) === res) {
      session.connections.delete(playerId);
      player.isConnected = false;

      console.log(
        `[SSE] ${player.displayName} disconnected from ${session.roomCode} ` +
        `(${session.connections.size} remaining)`
      );

      // Notify remaining players.
      broadcast(session, 'PLAYER_LEFT', {
        player_id: playerId,
      });
    }
  });
});

// ---------------------------------------------------------------------------
// Helper — broadcast PLAYER_JOINED to everyone except the joining player
// ---------------------------------------------------------------------------
function broadcastPlayerJoined(session, player, joiningPlayerId) {
  const payload = {
    player: serializePlayer(player),
  };

  // Send to all connected players except the one who just joined.
  for (const [pid, connection] of session.connections) {
    if (pid !== joiningPlayerId && !connection.writableEnded) {
      writeEvent(connection, 'PLAYER_JOINED', payload);
    }
  }
}

// Exposed for internal use by broadcast.js (avoids circular require).
function writeEvent(res, eventName, data) {
  if (res.writableEnded) return;
  res.write(`event: ${eventName}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

module.exports = router;