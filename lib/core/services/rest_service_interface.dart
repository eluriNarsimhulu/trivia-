// project_folder/lib/core/services/rest_service_interface.dart

import 'dart:async';

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

  Future<void> goToLobby({
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

  Future<Map<String, dynamic>> syncSession({
    required String sessionId,
  });
}

/// Typed exception for REST failures.
///
/// Using a typed exception rather than a raw Exception lets callers
/// inspect the status code and decide whether to retry, show an error,
/// or silently ignore (e.g. 409 Conflict on duplicate answer submission).
class RestException implements Exception {
  final int statusCode;
  final String message;

  const RestException({required this.statusCode, required this.message});

  /// Returns true if this is a known "safe to ignore" server rejection.
  /// e.g. 409 = duplicate answer, 400 = answer after question closed.
  bool get isIgnorable => statusCode == 409 || statusCode == 400;

  @override
  String toString() => 'RestException($statusCode): $message';
}