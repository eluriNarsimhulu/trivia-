// project_folder/trivia-server/routes/events.js

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
const router = express.Router();

const { getSession, serializePlayer, deleteSession } = require('../store');
const { broadcast, sendToPlayer } = require('../broadcast');

// _clearAllTimers is imported from game.js to avoid duplicating logic.
// We use a local inline version here to avoid circular require.
function _clearAllTimers(session) {
  const names = ['question', 'answerCount', 'result', 'leaderboard', 'cleanup'];
  for (const name of names) {
    if (session.timers[name]) {
      clearTimeout(session.timers[name]);
      session.timers[name] = null;
    }
  }
}

// ---------------------------------------------------------------------------
// GET /sessions/:id/events?playerId=...
// ---------------------------------------------------------------------------
router.get('/:id/events', (req, res) => {
  const { id: sessionId } = req.params;
  const { playerId, lastEventId } = req.query;

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
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  // Flush headers immediately so the client knows the stream is open.
  // Without this, some HTTP clients buffer until the first write.
  res.flushHeaders();

  //// -- Handle duplicate connection (reconnect) --
  // If an existing live connection is found, close it before registering
  // the new one. This prevents the momentary race where both are active.
  const existingConnection = session.connections.get(playerId);
  if (existingConnection && !existingConnection.writableEnded) {
    console.log(`[SSE] ${player.displayName} replacing live connection`);
    try {
      // Flush a comment before ending so the client's onDone fires cleanly.
      existingConnection.write(': replaced\n\n');
      existingConnection.end();
    } catch (_) { }
    // Small synchronous pause is not possible in Node, but end() is immediate.
    // The new registration below is safe because end() marks writableEnded=true
    // synchronously, so the old close handler's identity check will fail.
  }

  // -- Register connection --
  session.connections.set(playerId, res);
  player.isConnected = true;

  console.log(
    `[SSE] ${player.displayName} connected to ${session.roomCode} ` +
    `(${session.connections.size} total)`
  );

  // -- Bug #1 Fix: Cancel Grace Period on Reconnect --
  // If this player was in the middle of a 10s disconnect countdown,
  // stop the countdown now. They are back!
  const disconnectTimerName = `disconnect_${playerId}`;
  if (session.timers[disconnectTimerName]) {
    console.log(`[SSE] ${player.displayName} reconnected — cancelling disconnect timer.`);
    clearTimeout(session.timers[disconnectTimerName]);
    session.timers[disconnectTimerName] = null;
  }

  // -- Send initial heartbeat --
  // Confirms to the client that the stream is alive immediately.
  // Flutter SseService ignores comment lines (starts with ':') per RFC 8895.
  res.write(': connected\n\n');

  // -- Replay missed events if client sent a lastEventId --
  // This fires when a player reconnects after a network drop.
  // We replay any buffered events with id > lastEventId so they
  // don't get stuck in a stale phase.
  if (lastEventId !== undefined) {
    const sinceId = parseInt(lastEventId, 10);
    if (!isNaN(sinceId)) {
      const missed = (session.eventLog || []).filter(e => e.id > sinceId);
      for (const entry of missed) {
        res.write(entry.frame);
      }
      console.log(`[SSE] Replayed ${missed.length} missed event(s) to ${player.displayName}`);
    }
  }

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
  }, 12_000);

  // -- Disconnect handler --
  // Fires when the client closes the connection (app backgrounded,
  // network lost, or explicit disconnect() call from Flutter).
  req.on('close', () => {
    clearInterval(heartbeatInterval);

    // Only process if this is still the active connection for this player.
    if (session.connections.get(playerId) !== res) return;

    // Remove the player's connection and mark as disconnected.
    session.connections.delete(playerId);
    player.isConnected = false;

    console.log(`[SSE] ${player.displayName} signal lost. Starting 10s grace period.`);

    // -- Bug #1 Fix: 10-second Grace Period --
    // Instead of deleting the player immediately, we wait 10 seconds.
    // If they reconnect before then, this timer is cleared above.
    const disconnectTimerName = `disconnect_${playerId}`;
    session.timers[disconnectTimerName] = setTimeout(() => {

      session.timers[disconnectTimerName] = null;

      // Grace period expired — now we remove them for real.
      console.log(`[SSE] Grace period expired for ${player.displayName} — removing from session.`);

      session.players.delete(playerId);
      session.scores.delete(playerId);

      // --- Empty room: delete the session so the room code is freed ---
      if (session.players.size === 0) {
        console.log(`[SSE] All players left ${session.roomCode} — deleting session`);
        _clearAllTimers(session);
        deleteSession(session.sessionId);
        return;
      }

      // Notify remaining players this person left.
      broadcast(session, 'PLAYER_LEFT', {
        player_id: playerId,
      });

      // --- Host left: transfer host to another connected player ---
      if (player.isHost && session.phase !== 'ended') {
        let newHostId = null;
        for (const [pid, p] of session.players) {
          if (p.isConnected) {
            newHostId = pid;
            break;
          }
        }

        if (newHostId) {
          session.hostId = newHostId;
          session.players.get(newHostId).isHost = true;
          console.log(`[SSE] Host left for good — transferring to ${session.players.get(newHostId).displayName}`);
          broadcast(session, 'HOST_CHANGED', {
            new_host_id: newHostId,
            new_host_name: session.players.get(newHostId).displayName,
          });
        } else {
          console.log(`[SSE] Host left and no players remain — deleting session`);
          _clearAllTimers(session);
          deleteSession(session.sessionId);
        }
      }

    }, 10_000); // 10 second grace period
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