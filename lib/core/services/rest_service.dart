// project_folder/lib/core/services/rest_service.dart


/// RestService — concrete implementation of RestServiceInterface.
///
/// Architecture note:
///   All client → server writes go through this class.
///   SSE is strictly server → client. This class has no streaming methods.
///   The boundary is enforced structurally: RestService and SseService
///   have completely disjoint method sets.
///
///   Full request/response handling (auth headers, error codes, retries)
///   will be hardened in Stage 6. For now we establish the correct
///   structure and wire real HTTP calls so the flow compiles end-to-end.
///
/// Base URL:
///   Injected at construction time so staging vs production endpoints
///   can be swapped without touching business logic.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'rest_service_interface.dart';
// import 'rest_service_interface.dart';

class RestService implements RestServiceInterface {
  final String _baseUrl;
  final HttpClient _client;

  RestService({
    required String baseUrl,
  })  : _baseUrl = baseUrl,
        _client = HttpClient();

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  /// Creates a new game session.
  ///
  /// Returns a map containing at minimum:
  ///   { "session_id": String, "room_code": String }
  @override
  Future<Map<String, dynamic>> createSession({
    required String hostId,
    required String displayName,
    required int totalRounds,
  }) async {
    final body = jsonEncode({
      'host_id':      hostId,
      'display_name': displayName,
      'total_rounds': totalRounds,
    });
    return await _post('/sessions', body);
  }

  /// Joins an existing session by room code.
  ///
  /// Returns a map containing at minimum:
  ///   { "session_id": String, "session": { full GameSession json } }
  ///
  /// The full session snapshot in the response is used by GameController
  /// to hydrate the player list for late-joining players.
  @override
  Future<Map<String, dynamic>> joinSession({
    required String roomCode,
    required String playerId,
    required String displayName,
  }) async {
    final body = jsonEncode({
      'room_code':    roomCode,
      'player_id':   playerId,
      'display_name': displayName,
    });
    return await _post('/sessions/join', body);
  }

  /// Signals the server to start the game.
  ///
  /// Server validates that the caller is the host, then broadcasts
  /// GAME_START over SSE to all connected clients.
  @override
  Future<void> startGame({
    required String sessionId,
    required String hostId,
  }) async {
    final body = jsonEncode({'host_id': hostId});
    await _post('/sessions/$sessionId/start', body);
  }

  @override
  Future<void> restartGame({
    required String sessionId,
    required String hostId,
  }) async {
    final body = jsonEncode({'host_id': hostId});
    await _post('/sessions/$sessionId/restart', body);
  }

  /// Submits a player's answer for the current question.
  ///
  /// Server validates:
  ///   • question is still open
  ///   • player has not already answered
  ///   • answer format matches question type
  ///
  /// Duplicate or late submissions receive a 409/400 from the server —
  /// logged here, not surfaced as an error (GameController already guards
  /// against submitting outside questionActive phase).
  @override
  Future<void> submitAnswer({
    required String sessionId,
    required String questionId,
    required String playerId,
    required String answer,
  }) async {
    final body = jsonEncode({
      'question_id': questionId,
      'player_id':   playerId,
      'answer':      answer,
    });
    await _post('/sessions/$sessionId/answers', body);
  }

  // ---------------------------------------------------------------------------
  // HTTP primitives
  // ---------------------------------------------------------------------------

  /// Sends a POST request and returns the decoded JSON response body.
  ///
  /// Throws a [RestException] on non-2xx responses so callers can
  /// decide how to handle failures without parsing raw HTTP status codes.
  Future<Map<String, dynamic>> _post(String path, String body) async {
    final uri = Uri.parse('$_baseUrl$path');
    debugPrint('[RestService] POST $uri');

    try {
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(body);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('[RestService] ${response.statusCode} $uri');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseBody.isEmpty) return const {};
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      // Non-2xx — wrap in a typed exception with the status code.
      throw RestException(
        statusCode: response.statusCode,
        message:    'POST $path failed: ${response.statusCode}\n$responseBody',
      );
    } on SocketException catch (e) {
      throw RestException(
        statusCode: 0,
        message:    'Network error on POST $path: $e',
      );
    }
  }

  void dispose() => _client.close(force: true);
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