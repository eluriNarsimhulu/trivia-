// project_folder/lib/main.dart

/// Application entry point.
///
/// Responsibilities:
/// 1. Initialize Flutter bindings.
/// 2. Initialize the ServiceRegistry (creates services + controller).
/// 3. Provide GameController and playerId to the widget tree.
/// 4. Launch the Trivia app starting at LobbyEntryScreen.

import 'package:flutter/material.dart';

import 'core/services/service_registry.dart';
import 'state/game_controller.dart';
import 'features/lobby/lobby_entry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize all services
  final registry = ServiceRegistry(
    apiBaseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      // defaultValue: 'http://192.168.29.220:3000',
      // defaultValue: 'http://10.179.18.147:3000',
      defaultValue: 'https://trivia-server-zbdl.onrender.com',
    ),
  );

  await registry.initialize();

  runApp(
    GameControllerProvider(
      controller: registry.gameController,
      playerId: registry.playerId,
      child: const TriviaApp(),
    ),
  );
}

/// Provides GameController + playerId to the widget tree.
///
/// This avoids passing the controller manually through every widget.
class GameControllerProvider extends InheritedWidget {
  final GameController controller;
  final String playerId;

  const GameControllerProvider({
    super.key,
    required this.controller,
    required this.playerId,
    required super.child,
  });

  static GameControllerProvider of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<GameControllerProvider>();

    assert(
      provider != null,
      'GameControllerProvider not found in widget tree.',
    );

    return provider!;
  }

  @override
  bool updateShouldNotify(GameControllerProvider oldWidget) {
    return controller != oldWidget.controller ||
        playerId != oldWidget.playerId;
  }
}

/// Root app widget.
class TriviaApp extends StatelessWidget {
  const TriviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trivia Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),

      // Start directly with the Lobby entry screen
      home: const LobbyEntryScreen(),
    );
  }
}
