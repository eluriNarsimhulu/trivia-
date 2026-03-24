// project_folder/lib/core/services/rest_service_interface.dart

/// RestServiceInterface — contract for all client → server write operations.
///
/// Separated into its own file so GameController imports only this interface,
/// never the concrete RestService class. Dependency inversion is maintained:
/// GameController depends on the abstraction, not the implementation.
///
/// In tests, inject a MockRestService that returns pre-scripted responses
/// without touching the network.
///
/// Note on RestException:
///   RestException is defined in rest_service.dart (the concrete layer).
///   It is imported here indirectly via rest_service.dart's export — callers
///   that only import this interface file still catch RestException because
///   GameController imports both this file and rest_service_interface.dart
///   is the only file imported by GameController, and RestException is
///   thrown by the concrete RestService which GameController never imports.
///
///   The single canonical definition lives in rest_service.dart:
///     { required int statusCode, required String message }
///     bool get isIgnorable => statusCode == 409 || statusCode == 400;

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

  Future<void> cancelSession({
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
