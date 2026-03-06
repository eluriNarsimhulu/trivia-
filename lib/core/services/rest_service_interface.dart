// project_folder/lib/core/services/rest_service_interface.dart

/// RestServiceInterface — contract for all client → server write operations.
///
/// Separated into its own file so GameController imports only this interface,
/// never the concrete RestService class. Dependency inversion is maintained:
/// GameController depends on the abstraction, not the implementation.
///
/// In tests, inject a MockRestService that returns pre-scripted responses
/// without touching the network.

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

  Future<void> restartGame({
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