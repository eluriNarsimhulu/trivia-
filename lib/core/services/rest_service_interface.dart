abstract class RestServiceInterface {
  Future<Map<String, dynamic>> createSession({
    required String hostId,
    required String displayName,
    required int totalRounds,
  });

  Future<Map<String, dynamic>> joinSession({
    required String roomCode,
    required String playerId,
    required String displayName,
  });

  Future<void> startGame({
    required String sessionId,
    required String hostId,
  });

  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required String playerId,
    required String answer,
  });
}