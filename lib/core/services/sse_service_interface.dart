import '../models/game_events.dart';

abstract class SseServiceInterface {
  /// Stream of parsed GameEvent objects coming from the SSE connection
  Stream<GameEvent> get events;

  /// Opens the SSE connection
  Future<void> connect({
    required String sessionId,
    required String playerId,
  });

  /// Closes the SSE connection
  Future<void> disconnect();
}