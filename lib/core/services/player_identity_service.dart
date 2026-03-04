/// PlayerIdentityService — manages persistent local player identity.
///
/// Architecture note:
///   A player's ID must survive app restarts. If we generated a new ID
///   on every launch, the player would appear as a different participant
///   to the server on reconnect — breaking leaderboard continuity and
///   causing ghost entries in the session's player list.
///
///   We use SharedPreferences as the persistence layer because:
///     • It requires zero backend round-trips for identity resolution.
///     • It is the lightest appropriate tool — no database needed for
///       a single string value.
///     • The ID is generated once, then always restored from local storage.
///
///   UUID v4 is generated manually using dart:math to avoid adding the
///   `uuid` package — keeps dependencies minimal as per project rules.
///
///   This service is intentionally narrow: it knows nothing about sessions,
///   game phases, or networking. It does one thing only.

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The SharedPreferences key under which the playerId is persisted.
const _kPlayerIdKey = 'trivia_player_id';

class PlayerIdentityService {
  final SharedPreferences _prefs;

  /// Private constructor — always use [create()] factory.
  /// Keeping SharedPreferences as a constructor argument makes this
  /// class fully testable without touching real device storage.
  PlayerIdentityService._(this._prefs);

  /// Async factory — must be used because SharedPreferences.getInstance()
  /// is async. Called once at app startup by ServiceRegistry.
  static Future<PlayerIdentityService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerIdentityService._(prefs);
  }

  /// Returns the stored playerId, or generates and persists a new one.
  ///
  /// This is idempotent: calling it 100 times returns the same ID.
  /// The ID is created exactly once — on the player's first app launch.
  Future<String> getOrCreatePlayerId() async {
    final existing = _prefs.getString(_kPlayerIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final newId = _generateUuidV4();
    await _prefs.setString(_kPlayerIdKey, newId);
    return newId;
  }

  /// Clears the stored identity.
  ///
  /// Exposed for testing and "sign out / reset" flows only.
  /// Not called during normal gameplay.
  Future<void> clearPlayerId() async {
    await _prefs.remove(_kPlayerIdKey);
  }

  // ---------------------------------------------------------------------------
  // UUID v4 generation — no external package required.
  // ---------------------------------------------------------------------------

  /// Generates a RFC 4122-compliant UUID v4 string.
  ///
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  ///   • All x = random hex digit
  ///   • The '4' is fixed (version 4)
  ///   • y is one of: 8, 9, a, b (variant 1 marker)
  String _generateUuidV4() {
    final random = Random.secure();

    String randomHex(int length) => List.generate(
          length,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();

    final timeLow         = randomHex(8);
    final timeMid         = randomHex(4);
    final versionAndHigh  = '4${randomHex(3)}';  // version 4
    final variantAndSeq   = '${(8 + random.nextInt(4)).toRadixString(16)}'
                            '${randomHex(3)}';    // variant 1
    final node            = randomHex(12);

    return '$timeLow-$timeMid-$versionAndHigh-$variantAndSeq-$node';
  }
}