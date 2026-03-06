// project_folder/trivia-server/store.dart

// In-memory session store.
//
// All game state lives here for the lifetime of the server process.
// No database — designed for local demo use.
//
// Structure:
//   sessions: Map<sessionId, Session>
//
// Session shape:
//   {
//     sessionId:            string
//     roomCode:             string        (6-char uppercase)
//     hostId:               string
//     players:              Map<playerId, Player>
//     connections:          Map<playerId, SseConnection>
//     questions:            Question[]    (shuffled subset for this session)
//     currentQuestionIndex: number
//     questionStartTime:    number|null   (Date.now() when question opened)
//     scores:               Map<playerId, { total, streak, rankDelta }>
//     answers:              Map<playerId, string>  (for current question)
//     phase:                string
//     timers:               { question: Timeout|null, answerCount: Timeout|null }
//     totalRounds:          number
//   }

const sessions = new Map();

// Reverse-lookup: roomCode → sessionId (for fast join-by-code)
const roomCodeIndex = new Map();

/**
 * Generates a 6-character uppercase alphanumeric room code.
 * Retries on collision (astronomically rare but handled).
 */
function generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0, I/1 confusion
  let code;
  do {
    code = Array.from(
      { length: 6 },
      () => chars[Math.floor(Math.random() * chars.length)]
    ).join('');
  } while (roomCodeIndex.has(code));
  return code;
}

/**
 * Creates and stores a new game session.
 * @returns {Session} the created session object
 */
function createSession(sessionId, hostId, totalRounds) {
  const roomCode = generateRoomCode();

  const session = {
    sessionId,
    roomCode,
    hostId,
    players:              new Map(),
    connections:          new Map(),
    questions:            [],
    currentQuestionIndex: -1,
    questionStartTime:    null,
    scores:               new Map(),
    answers:              new Map(),
    phase:                'lobby',
    timers: {
      question:    null,
      answerCount: null,
      result:      null,
      leaderboard: null,
      cleanup:     null,
    },
    totalRounds,
  };

  sessions.set(sessionId, session);
  roomCodeIndex.set(roomCode, sessionId);

  return session;
}

/**
 * Returns a session by ID, or null if not found.
 */
function getSession(sessionId) {
  return sessions.get(sessionId) ?? null;
}

/**
 * Returns a session by room code, or null if not found.
 */
function getSessionByRoomCode(roomCode) {
  const sessionId = roomCodeIndex.get(roomCode.toUpperCase());
  if (!sessionId) return null;
  return sessions.get(sessionId) ?? null;
}

/**
 * Removes a session and its room code from the store.
 * Called after GAME_END to free memory.
 */
function deleteSession(sessionId) {
  const session = sessions.get(sessionId);
  if (session) {
    roomCodeIndex.delete(session.roomCode);
    sessions.delete(sessionId);
  }
}

/**
 * Serializes a session into the shape Flutter's GameSession.fromJson expects.
 *
 * Flutter expects:
 *   session_id, room_code, host_id, players (array), total_rounds, current_round
 */
function serializeSession(session) {
  return {
    session_id:    session.sessionId,
    room_code:     session.roomCode,
    host_id:       session.hostId,
    players:       Array.from(session.players.values()).map(serializePlayer),
    total_rounds:  session.totalRounds,
    current_round: session.currentQuestionIndex + 1,
  };
}

/**
 * Serializes a player into the shape Flutter's Player.fromJson expects.
 *
 * Flutter expects:
 *   id, display_name, is_host, is_connected
 */
function serializePlayer(player) {
  return {
    id:           player.id,
    display_name: player.displayName,
    is_host:      player.isHost,
    is_connected: player.isConnected,
  };
}

module.exports = {
  sessions,
  createSession,
  getSession,
  getSessionByRoomCode,
  deleteSession,
  serializeSession,
  serializePlayer,
};


// ```

// ---

// ## How the SSE layer works end to end
// ```
// Flutter SseService.connect(sessionId, playerId)
//           │
//           ▼
// GET /sessions/:id/events?playerId=xxx
//           │
//           ├── validate session + player exists
//           ├── set SSE headers + flushHeaders()
//           ├── store res in session.connections
//           ├── write ': connected\n\n'  (heartbeat comment)
//           ├── broadcast PLAYER_JOINED to others
//           └── start 25s heartbeat interval
//                     │
//           ┌─────────┴──────────────────────────┐
//           │   Connection stays open forever    │
//           │   broadcast() writes frames here   │
//           └─────────────────────────────────────┘
//                     │
//           req.on('close')
//           ├── clear heartbeat interval
//           ├── remove from session.connections
//           ├── mark player.isConnected = false
//           └── broadcast PLAYER_LEFT to others
// ```
// ```
// broadcast(session, 'GAME_START', payload)
//           │
//           └── loops session.connections
//                     │
//                     ├── player A  →  res.write(frame)
//                     ├── player B  →  res.write(frame)
//                     └── player C  →  res.write(frame)

// sendToPlayer(session, playerId, 'Q_RESULT', payload)
//           │
//           └── session.connections.get(playerId)
//                     │
//                     └── res.write(frame)   ← only this player