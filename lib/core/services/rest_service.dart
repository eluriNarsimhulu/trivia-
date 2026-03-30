// project_folder/lib/core/services/rest_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'rest_service_interface.dart';

class RestService implements RestServiceInterface {
  final String _baseUrl;
  final HttpClient _client;

  RestService({
    required String baseUrl,
  })  : _baseUrl = baseUrl,
        _client = HttpClient();

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

  @override
  Future<void> goToLobby({
    required String sessionId,
    required String hostId,
  }) async {
    final body = jsonEncode({'host_id': hostId});
    await _post('/sessions/$sessionId/lobby', body);
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required String hostId,
  }) async {
    await _deleteNoBody('/sessions/$sessionId?host_id=$hostId');
  }

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

  @override
  Future<Map<String, dynamic>> syncSession({
    required String sessionId,
  }) async {
    return _get('/sessions/$sessionId/sync');
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    debugPrint('[RestService] GET $uri');

    try {
      final request = await _client.getUrl(uri);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('[RestService] ${response.statusCode} $uri');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseBody.isEmpty) return const {};
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      throw RestException(
        statusCode: response.statusCode,
        message: 'GET $path failed: ${response.statusCode}\n$responseBody',
      );
    } on SocketException catch (e) {
      throw RestException(
        statusCode: 0,
        message: 'Network error on GET $path: $e',
      );
    }
  }

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

      throw RestException(
        statusCode: response.statusCode,
        message: 'POST $path failed: ${response.statusCode}\n$responseBody',
      );
    } on SocketException catch (e) {
      throw RestException(
        statusCode: 0,
        message: 'Network error on POST $path: $e',
      );
    }
  }

  Future<void> _deleteNoBody(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    debugPrint('[RestService] DELETE $uri');

    try {
      final request = await _client.openUrl('DELETE', uri);
      request.headers.contentType = ContentType.json;
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('[RestService] ${response.statusCode} $uri');

      if (response.statusCode >= 200 && response.statusCode < 300) return;

      throw RestException(
        statusCode: response.statusCode,
        message: 'DELETE $path failed: ${response.statusCode}\n$responseBody',
      );
    } on SocketException catch (e) {
      throw RestException(
        statusCode: 0,
        message: 'Network error on DELETE $path: $e',
      );
    }
  }

  void dispose() => _client.close(force: true);
}