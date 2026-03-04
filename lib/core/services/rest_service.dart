/// REST Service interface — skeleton only.
/// Full implementation in Stage 6.
///
/// Architecture note:
///   All client → server actions go through REST.
///   SSE is strictly server → client only.
///   This boundary is enforced here: SseService has no write methods,
///   RestService has no read/stream methods.

abstract class RestServiceInterface {
  /// Host creates a new game session. Returns sessionId + roomCode.
  Future<Map<String, dynamic>> createSession({
    required String hostId,
    required String displayName,
    required int totalRounds,
  });

  /// Player joins an existing session using a room code.
  Future<Map<String, dynamic>> joinSession({
    required String roomCode,
    required String playerId,
    required String displayName,
  });

  /// Host-only: triggers GAME_START SSE event for all clients.
  Future<void> startGame({
    required String sessionId,
    required String hostId,
  });

  /// Player submits an answer for the active question.
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required String playerId,
    required String answer,
  });
}