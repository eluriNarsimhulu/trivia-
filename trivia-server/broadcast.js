// Broadcast engine — the single place that writes SSE events to clients.
//
// Architecture note:
//   All game logic (game.js, routes/game.js) calls broadcast() or sendToPlayer()
//   from this module. No other file writes directly to SSE response objects.
//   This keeps the write logic centralized and ensures consistent SSE framing.
//
// SSE frame format (RFC 8895):
//   event: EVENT_NAME\n
//   data: {...json}\n
//   \n
//
// The blank line at the end is mandatory — it signals end of frame to the client.

'use strict';

/**
 * Broadcasts an SSE event to ALL connected players in a session.
 *
 * @param {object} session   - the session object from store.js
 * @param {string} eventName - SSE event name (must match Flutter SseService._parseEvent)
 * @param {object} payload   - JSON-serializable payload
 */
function broadcast(session, eventName, payload) {
  const frame = buildFrame(eventName, payload);
  let sent = 0;

  for (const [playerId, res] of session.connections) {
    if (res.writableEnded) {
      // Connection is already closed — remove stale entry.
      session.connections.delete(playerId);
      continue;
    }
    try {
      res.write(frame);
      sent++;
    } catch (err) {
      console.error(`[Broadcast] Failed to write to ${playerId}: ${err.message}`);
      session.connections.delete(playerId);
    }
  }

  console.log(`[Broadcast] ${eventName} → ${sent} player(s) in ${session.roomCode}`);
}

/**
 * Sends an SSE event to ONE specific player.
 * Used for personalised events like Q_RESULT (score delta is per-player).
 *
 * @param {object} session   - the session object
 * @param {string} playerId  - target player's ID
 * @param {string} eventName - SSE event name
 * @param {object} payload   - JSON-serializable payload
 */
function sendToPlayer(session, playerId, eventName, payload) {
  const res = session.connections.get(playerId);

  if (!res || res.writableEnded) {
    console.warn(`[Broadcast] sendToPlayer: no live connection for ${playerId}`);
    return;
  }

  try {
    res.write(buildFrame(eventName, payload));
  } catch (err) {
    console.error(`[Broadcast] sendToPlayer failed for ${playerId}: ${err.message}`);
    session.connections.delete(playerId);
  }
}

/**
 * Builds a complete SSE frame string.
 * Centralising this ensures every event is framed identically.
 *
 * @param {string} eventName
 * @param {object} payload
 * @returns {string} complete SSE frame ready to write to response
 */
function buildFrame(eventName, payload) {
  // JSON.stringify is safe here — payload is always a plain object.
  return `event: ${eventName}\ndata: ${JSON.stringify(payload)}\n\n`;
}

module.exports = { broadcast, sendToPlayer, buildFrame };