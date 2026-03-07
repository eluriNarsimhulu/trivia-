// project_folder/lib/core/services/service_registry.dart

/// ServiceRegistry — single source of service instantiation.
///
/// Architecture note:
///   This is a lightweight manual service locator — NOT a dependency
///   injection framework. We deliberately avoid packages like get_it or
///   riverpod at this layer to keep the architecture transparent and
///   the dependency graph explicitly visible in one place.
///
///   Why a registry instead of direct instantiation in main.dart?
///     • Services have async initialisation (SharedPreferences).
///     • Some services depend on other services (GameController needs
///       both SseService and RestService).
///     • Grouping this in one file makes the wiring auditable at a glance.
///     • Tests can subclass or replace ServiceRegistry with a test double.
///
///   Lifecycle:
///     ServiceRegistry.initialize() is called once in main().
///     The registry holds the single instance of each service for the
///     lifetime of the app. There is no dispose cascade — each service
///     disposes itself when GameController.dispose() is called.

import 'player_identity_service.dart';
import 'rest_service.dart';
import 'rest_service_interface.dart';
import 'sse_service.dart';
import '../../state/game_controller.dart';
import 'sse_service_interface.dart';

class ServiceRegistry {
  // ---------------------------------------------------------------------------
  // Singleton instances — one of each for the entire app lifetime.
  // ---------------------------------------------------------------------------

  late final PlayerIdentityService playerIdentityService;
  late final SseServiceInterface    sseService;
  late final RestServiceInterface   restService;
  late final GameController         gameController;

  /// The resolved playerId — available after initialize() completes.
  /// Exposed here so main.dart and UI entry points can read it without
  /// injecting PlayerIdentityService everywhere.
  late final String playerId;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Base URL for REST calls. Override for staging/production environments.
  /// In a real project this would come from a build-time --dart-define flag.
  final String _apiBaseUrl;

  ServiceRegistry({
    // String apiBaseUrl = 'http://192.168.29.220:3000',
    // String apiBaseUrl = 'http://10.179.18.147:3000',
    String apiBaseUrl = 'https://trivia-server-zbdl.onrender.com',
  }) : _apiBaseUrl = apiBaseUrl;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialises all services in dependency order.
  ///
  /// Must be awaited before runApp() so the controller is ready before
  /// the first frame is painted.
  ///
  /// Order matters:
  ///   1. PlayerIdentityService  — needs SharedPreferences (async)
  ///   2. SseService             — no dependencies
  ///   3. RestService            — no dependencies
  ///   4. GameController         — depends on SseService + RestService
  Future<void> initialize() async {
    // 1. Resolve persistent player identity.
    playerIdentityService = await PlayerIdentityService.create();
    playerId = await playerIdentityService.getOrCreatePlayerId();

    // 2. Network services — constructed synchronously.
    sseService  = SseService(baseUrl: _apiBaseUrl);
    restService = RestService(baseUrl: _apiBaseUrl);

    // 3. Controller — receives interfaces, never concrete types.
    //    This is where the dependency inversion rule is enforced:
    //    GameController only knows about the abstract interfaces.
    gameController = GameController(
      sseService:  sseService,
      restService: restService,
    );
  }

  /// Tears down all services cleanly.
  /// Called when the app is permanently closing (not on background/pause).
  Future<void> dispose() async {
    gameController.dispose();
    // RestService holds an HttpClient — close it.
    if (restService is RestService) {
      (restService as RestService).dispose();
    }
  }
}