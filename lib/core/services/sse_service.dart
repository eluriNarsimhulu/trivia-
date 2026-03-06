/// Manages the persistent SSE connection to the game server.
///
/// ## Responsibilities
///   - Open a long-lived HTTP GET to `/sessions/{id}/events?playerId={id}`.
///   - Parse raw SSE frames (event name + JSON data) into typed [GameEvent]s.
///   - Emit parsed events on [events] — a broadcast [Stream<GameEvent>].
///   - Auto-reconnect with exponential backoff on connection loss.
///   - Ensure only one active [HttpClient] and [StreamSubscription] at a time.
///
/// ## Protocol contract
///   READ-ONLY. This service never sends data to the server.
///   All client→server writes go through [RestServiceInterface].
///
/// ## Reconnect behaviour
///   On drop: schedules reconnect with backoff (500ms → 1s → 2s … → 30s cap).
///   On success: resets retry counter to 0.
///   After [_kMaxRetries] failures: emits a terminal error on [events].
///   [GameController] catches the terminal error and moves to [GamePhase.error].
///
/// ## Stream lifecycle
///   [events] is a broadcast stream that stays open across reconnects.
///   [GameController] subscribes once and never re-subscribes.
///   The stream is only closed on an explicit [disconnect] call.


import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/game_events.dart';
import 'sse_service_interface.dart';

/// Maximum number of reconnect attempts before giving up.
const _kMaxRetries = 8;

/// Base delay for exponential backoff. Doubles each attempt.
/// Attempt 1 → 500ms, 2 → 1s, 3 → 2s … capped at 30s.
const _kBaseBackoff = Duration(milliseconds: 500);

/// Hard cap on backoff delay so we never wait more than 30 seconds.
const _kMaxBackoff = Duration(seconds: 30);

class SseService implements SseServiceInterface {
   /// Base API URL injected by ServiceRegistry.
  final String baseUrl;

  SseService({required this.baseUrl});
  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Broadcasts parsed events to all subscribers (GameController).
  /// Using a broadcast controller because GameController may subscribe
  /// after connect() is called, and we do not want buffering issues.
  final StreamController<GameEvent> _controller =
      StreamController<GameEvent>.broadcast();

  /// The active HTTP client. Replaced on every reconnect.
  HttpClient? _httpClient;

  /// Tracks the active byte-stream subscription so we can cancel it cleanly.
  StreamSubscription<String>? _lineSubscription;

  /// Reconnect timer — cancelled if disconnect() is called during backoff.
  Timer? _reconnectTimer;

  /// Session params stored at connect() time — reused on every reconnect.
  String? _sessionId;
  String? _playerId;
  String? _baseUrl;

  /// Reconnect attempt counter. Reset to 0 on a successful connection.
  int _retryCount = 0;

  /// Set to true by disconnect(). Prevents reconnect loop from firing
  /// after an intentional teardown.
  bool _disconnected = false;

  // ---------------------------------------------------------------------------
  // SseServiceInterface — public API
  // ---------------------------------------------------------------------------

  /// The stream GameController subscribes to.
  /// Events are emitted here as soon as they are parsed from the SSE stream.
  @override
  Stream<GameEvent> get events => _controller.stream;

  /// Opens the SSE connection.
  ///
  /// If a connection is already active, it is torn down first —
  /// this prevents duplicate stream subscriptions on reconnect calls.
  ///
  /// [baseUrl] example: "https://api.trivia.example.com"
  @override
  Future<void> connect({
    required String sessionId,
    required String playerId,

  }) async {
    // Store params for reconnect cycles.
    _sessionId = sessionId;
    _playerId = playerId;
    _baseUrl = this.baseUrl;
    _disconnected = false;
    _retryCount = 0;

    await _openConnection();
  }

  /// Closes everything permanently.
  /// After this call, no reconnect attempts will fire.
  @override
  Future<void> disconnect() async {
    _disconnected = true;
    await _tearDown();
    // Close the broadcast stream only on intentional disconnect.
    // We do NOT close it on reconnect — GameController's subscription
    // must survive reconnects without re-subscribing.
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  /// Opens a single HTTP SSE connection and begins reading lines.
  Future<void> _openConnection() async {
    // Always tear down any existing connection first.
    await _tearDown();

    final sessionId = _sessionId;
    final playerId  = _playerId;
    final baseUrl   = _baseUrl;

    if (sessionId == null || playerId == null || baseUrl == null) {
      debugPrint('[SseService] connect() called without session params.');
      return;
    }

    final uri = Uri.parse(
      '$baseUrl/sessions/$sessionId/events?playerId=$playerId',
    );

    debugPrint('[SseService] Connecting to $uri');

    try {
      _httpClient = HttpClient();

      // SSE connections are long-lived — disable default idle timeout.
      _httpClient!.idleTimeout = Duration.zero;

      final request = await _httpClient!.getUrl(uri);
      // Tell the server we want an SSE stream.
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint('[SseService] Unexpected status: ${response.statusCode}');
        _scheduleReconnect();
        return;
      }

      // Successful connection — reset backoff counter.
      _retryCount = 0;
      debugPrint('[SseService] ✅ Connected. Listening for events...');

      // Decode the byte stream as UTF-8 lines and hand to the SSE parser.
      _lineSubscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: _onStreamError,
            onDone: _onStreamDone,
            cancelOnError: false,
          );
    } catch (e) {
      debugPrint('[SseService] Connection error: $e');
      _scheduleReconnect();
    }
  }

  /// Cancels the active subscription and closes the HTTP client.
  /// Does NOT affect the broadcast StreamController — it stays open.
  Future<void> _tearDown() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _lineSubscription?.cancel();
    _lineSubscription = null;

    _httpClient?.close(force: true);
    _httpClient = null;
  }

  // ---------------------------------------------------------------------------
  // SSE frame parsing
  // ---------------------------------------------------------------------------

  /// Accumulates lines within a single SSE frame.
  String? _currentEventName;
  final StringBuffer _dataBuffer = StringBuffer();

  /// Called for each line received from the HTTP stream.
  ///
  /// SSE framing rules (RFC 8895):
  ///   "event: NAME"  → sets the event type for this frame
  ///   "data: JSON"   → appends to the data buffer (can be multi-line)
  ///   ""             → blank line = end of frame, dispatch it
  ///   ": comment"    → server heartbeat / keep-alive, ignored
  void _onLine(String line) {
    // Blank line → end of SSE frame. Dispatch whatever we have accumulated.
    if (line.isEmpty) {
      _dispatchFrame();
      return;
    }

    // Server heartbeat / comment — discard but do NOT disconnect.
    if (line.startsWith(':')) return;

    // "event: NAME"
    if (line.startsWith('event:')) {
      _currentEventName = line.substring(6).trim();
      return;
    }

    // "data: {...}"
    if (line.startsWith('data:')) {
      // Append to buffer — SSE allows multi-line data fields.
      if (_dataBuffer.isNotEmpty) _dataBuffer.write('\n');
      _dataBuffer.write(line.substring(5).trim());
      return;
    }

    // Unknown field — ignore per RFC 8895.
    debugPrint('[SseService] Unknown SSE field, ignoring: $line');
  }

  /// Parses the accumulated frame and emits a typed GameEvent.
  /// Resets frame state regardless of success or failure.
  void _dispatchFrame() {
    final eventName = _currentEventName;
    final rawData   = _dataBuffer.toString().trim();

    // Always reset frame state before any early return.
    _currentEventName = null;
    _dataBuffer.clear();

    if (eventName == null || rawData.isEmpty) return;

    try {
      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final event = _parseEvent(eventName, json);

      if (event != null) {
        _controller.add(event);
      } else {
        debugPrint('[SseService] ⚠️ Unrecognised event type: "$eventName" — ignored.');
      }
    } catch (e) {
      // Malformed JSON or unexpected payload shape.
      // Log and continue — one bad frame must not kill the stream.
      debugPrint('[SseService] ⚠️ Failed to parse event "$eventName": $e');
    }
  }

  /// Maps a raw SSE event name + JSON payload to a typed GameEvent.
  /// Returns null for unknown event names so the caller can log and skip.
  GameEvent? _parseEvent(String eventName, Map<String, dynamic> json) {
    switch (eventName) {
      case 'ROUND_COUNTDOWN':
        return RoundCountdownEvent.fromJson(json);
      case 'PLAYER_JOINED':
        return PlayerJoinedEvent.fromJson(json);
      case 'PLAYER_LEFT':
        return PlayerLeftEvent.fromJson(json);
      case 'GAME_START':
        return GameStartEvent.fromJson(json);
      case 'QUESTION':
        return QuestionEvent.fromJson(json);
      case 'ANSWER_COUNT':
        return AnswerCountEvent.fromJson(json);
      case 'Q_RESULT':
        return QuestionResultEvent.fromJson(json);
      case 'LEADERBOARD':
        return LeaderboardEvent.fromJson(json);
      case 'GAME_END':
        return GameEndEvent.fromJson(json);
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnection
  // ---------------------------------------------------------------------------

  /// Called when the HTTP stream closes unexpectedly (server restart,
  /// network drop, proxy timeout, etc.).
  void _onStreamDone() {
    debugPrint('[SseService] Stream closed by server.');
    _scheduleReconnect();
  }

  /// Called when the stream emits an error (socket error, IO exception, etc.).
  void _onStreamError(Object error) {
    debugPrint('[SseService] Stream error: $error');
    // Forward to GameController so UI can show a reconnecting banner.
    if (!_controller.isClosed) {
      _controller.addError(error);
    }
    _scheduleReconnect();
  }

  /// Schedules a reconnect attempt using exponential backoff.
  ///
  /// Backoff formula: min(baseDelay * 2^attempt, maxDelay)
  ///   Attempt 0 → 500ms
  ///   Attempt 1 → 1000ms
  ///   Attempt 2 → 2000ms
  ///   Attempt 3 → 4000ms
  ///   ...
  ///   Attempt 6+ → 30000ms (capped)
  ///
  /// After _kMaxRetries failures, we stop trying and add a terminal error
  /// to the stream so GameController can transition to GamePhase.error.
  void _scheduleReconnect() {
    // Do nothing if disconnect() was called intentionally.
    if (_disconnected) return;

    if (_retryCount >= _kMaxRetries) {
      debugPrint('[SseService] ❌ Max retries ($_kMaxRetries) reached. Giving up.');
      if (!_controller.isClosed) {
        _controller.addError(
          SocketException('SSE permanently disconnected after max retries.'),
        );
      }
      return;
    }

    final backoff = _computeBackoff(_retryCount);
    _retryCount++;

    debugPrint(
      '[SseService] Reconnecting in ${backoff.inMilliseconds}ms '
      '(attempt $_retryCount / $_kMaxRetries)...',
    );

    _reconnectTimer = Timer(backoff, () async {
      if (!_disconnected) await _openConnection();
    });
  }

  /// Computes the capped exponential backoff duration for a given attempt.
  Duration _computeBackoff(int attempt) {
    final multiplier = 1 << attempt; // 2^attempt, avoids dart:math import
    final ms = _kBaseBackoff.inMilliseconds * multiplier;
    return Duration(milliseconds: ms.clamp(0, _kMaxBackoff.inMilliseconds));
  }
}
// ```

// ---

// ## Reconnect Strategy Explained
// ```
// Connection drops / stream closes
//            │
//            ▼
//    _scheduleReconnect()
//            │
//            ├─ _disconnected == true? ──► stop (intentional teardown)
//            │
//            ├─ retryCount >= 8? ──────────► addError() to stream
//            │                               GameController → GamePhase.error
//            │
//            └─ compute backoff delay
//                   │
//                   ▼
//              Timer fires
//                   │
//                   ▼
//           _openConnection()
//                   │
//                   ├─ HTTP 200? ──► retryCount = 0, resume listening
//                   │
//                   └─ failed? ──► _scheduleReconnect() again (retryCount++)
// ```

// **Key decisions:**

// | Decision | Reason |
// |---|---|
// | `StreamController.broadcast()` | GameController subscribes once and survives reconnects — the stream never closes between attempts |
// | `_tearDown()` before every `_openConnection()` | Guarantees only one active `HttpClient` and one active `StreamSubscription` at all times |
// | `_disconnected` flag | Prevents the backoff timer from firing after an intentional `leaveSession()` call |
// | Error forwarded to `_controller` | GameController's `onError` handler receives it and can set `errorMessage` in state without crashing |
// | Max 8 retries | Avoids infinite reconnect storms; after exhaustion the game transitions to `GamePhase.error` for the user to see |

// ---

// ## Event Parsing Explained
// ```
// Raw HTTP byte stream
//         │
//         ▼
//   utf8.decoder          (bytes → String)
//         │
//         ▼
//   LineSplitter          (String → individual lines)
//         │
//         ▼
//   _onLine(line)
//         │
//         ├─ "event: X"  → store _currentEventName
//         ├─ "data: {}"  → append to _dataBuffer
//         ├─ ": ..."     → heartbeat, discard
//         └─ ""          → blank line = end of frame → _dispatchFrame()
//                                 │
//                                 ▼
//                         jsonDecode(rawData)
//                                 │
//                                 ▼
//                         _parseEvent(name, json)
//                                 │
//                         switch on event name
//                                 │
//                    ┌────────────┼────────────────────┐
//               fromJson()    fromJson()           fromJson() ...
//                    │
//                    ▼
//            _controller.add(event)   ←── GameController receives it