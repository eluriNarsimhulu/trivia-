/// Application entry point.
///
/// Responsibilities:
///   1. Ensure Flutter bindings are initialised before any async work.
///   2. Build the ServiceRegistry and await full initialisation.
///   3. Pass the GameController and playerId down to the UI layer via
///      an InheritedWidget (GameControllerProvider).
///   4. Run the app.
///
/// Architecture note:
///   main() is the only place that knows about ServiceRegistry and concrete
///   service types. Everything below main() depends only on interfaces and
///   the GameController — never on the registry itself.
///
///   We use an InheritedWidget (GameControllerProvider) to thread the
///   controller through the widget tree without passing it as a constructor
///   argument at every level. UI widgets read it via:
///     GameControllerProvider.of(context).controller

import 'package:flutter/material.dart';

import 'core/services/service_registry.dart';
import 'state/game_controller.dart';

Future<void> main() async {
  // Required before any async Flutter or plugin work.
  WidgetsFlutterBinding.ensureInitialized();

  // Build and initialise all services.
  final registry = ServiceRegistry(
    apiBaseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.trivia.example.com',
    ),
  );
  await registry.initialize();

  runApp(
    GameControllerProvider(
      controller: registry.gameController,
      playerId:   registry.playerId,
      child: const TriviaApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// GameControllerProvider — InheritedWidget
// ---------------------------------------------------------------------------

/// Threads GameController and playerId through the widget tree.
///
/// Why InheritedWidget instead of a package (Provider, Riverpod)?
///   The project rules say avoid unnecessary dependencies.
///   InheritedWidget is built into Flutter, has zero overhead,
///   and is exactly sufficient for this use case — one controller,
///   app-wide access.
class GameControllerProvider extends InheritedWidget {
  final GameController controller;
  final String playerId;

  const GameControllerProvider({
    super.key,
    required this.controller,
    required this.playerId,
    required super.child,
  });

  /// Access the provider from any widget in the tree.
  ///
  /// Usage:
  ///   final provider = GameControllerProvider.of(context);
  ///   final controller = provider.controller;
  ///   final playerId = provider.playerId;
  static GameControllerProvider of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<GameControllerProvider>();
    assert(
      provider != null,
      'GameControllerProvider not found in widget tree. '
      'Ensure it wraps your MaterialApp.',
    );
    return provider!;
  }

  /// Only rebuild dependants if the controller or playerId instance changes.
  /// In practice this never happens — both are created once at startup.
  @override
  bool updateShouldNotify(GameControllerProvider oldWidget) {
    return controller != oldWidget.controller ||
           playerId   != oldWidget.playerId;
  }
}

// ---------------------------------------------------------------------------
// TriviaApp — root widget
// ---------------------------------------------------------------------------

class TriviaApp extends StatelessWidget {
  const TriviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trivia Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Router / initial route wired in Stage 5 (UI binding).
      home: const _AppEntryPoint(),
    );
  }
}

/// Temporary placeholder — replaced with real routing in Stage 5.
class _AppEntryPoint extends StatelessWidget {
  const _AppEntryPoint();

  @override
  Widget build(BuildContext context) {
    final provider = GameControllerProvider.of(context);

    return Scaffold(
      body: Center(
        child: Text(
          'Player ID: ${provider.playerId}\n'
          'Stage 5 UI coming next.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
// ```

// ---

// ## How The Services Connect Together
// ```
// main()
//   │
//   ▼
// ServiceRegistry.initialize()
//   │
//   ├── PlayerIdentityService.create()
//   │       │
//   │       └── SharedPreferences → getOrCreate UUID → playerId
//   │
//   ├── SseService()          (no deps)
//   ├── RestService(baseUrl)  (no deps)
//   │
//   └── GameController(
//             sseService:  SseServiceInterface  ◄── only sees the interface
//             restService: RestServiceInterface ◄── only sees the interface
//         )
//   │
//   ▼
// runApp(
//   GameControllerProvider(        ← threads controller + playerId into tree
//     controller: gameController,
//     playerId:   playerId,
//     child: TriviaApp()
//   )
// )
  // │
  // ▼
// Any widget in the tree:
//   GameControllerProvider.of(context).controller.joinSession(...)
//   GameControllerProvider.of(context).playerId
// ```

// **Session flow end-to-end:**
// ```
// HOST path:
//   Widget calls controller.createAndJoinSession(
//     hostId:      provider.playerId,     ← from PlayerIdentityService
//     displayName: "Alice",
//     totalRounds: 5,
//   )
//   │
//   ├── RestService.createSession() → { session_id, room_code }
//   ├── GameController builds GameSession from response
//   ├── _transitionTo(GamePhase.lobby)
//   └── SseService.connect(sessionId, playerId)
//         └── Stream<GameEvent> flows into GameController._onEvent()

// PLAYER path:
//   Widget calls controller.joinSession(
//     roomCode:    "ABC123",
//     playerId:    provider.playerId,     ← same persistent UUID
//     displayName: "Bob",
//   )
//   │
//   ├── RestService.joinSession() → { session_id, session: { full snapshot } }
//   ├── GameController builds GameSession from full snapshot (handles late-join)
//   ├── _transitionTo(GamePhase.lobby)
//   └── SseService.connect(sessionId, playerId)
//         └── Stream<GameEvent> flows into GameController._onEvent()





















// import 'package:flutter/material.dart';

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   // This widget is the root of your application.
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Flutter Demo',
//       theme: ThemeData(
//         // This is the theme of your application.
//         //
//         // TRY THIS: Try running your application with "flutter run". You'll see
//         // the application has a purple toolbar. Then, without quitting the app,
//         // try changing the seedColor in the colorScheme below to Colors.green
//         // and then invoke "hot reload" (save your changes or press the "hot
//         // reload" button in a Flutter-supported IDE, or press "r" if you used
//         // the command line to start the app).
//         //
//         // Notice that the counter didn't reset back to zero; the application
//         // state is not lost during the reload. To reset the state, use hot
//         // restart instead.
//         //
//         // This works for code too, not just values: Most code changes can be
//         // tested with just a hot reload.
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
//       ),
//       home: const MyHomePage(title: 'Flutter Demo Home Page'),
//     );
//   }
// }

// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});

//   // This widget is the home page of your application. It is stateful, meaning
//   // that it has a State object (defined below) that contains fields that affect
//   // how it looks.

//   // This class is the configuration for the state. It holds the values (in this
//   // case the title) provided by the parent (in this case the App widget) and
//   // used by the build method of the State. Fields in a Widget subclass are
//   // always marked "final".

//   final String title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

// class _MyHomePageState extends State<MyHomePage> {
//   int _counter = 0;

//   void _incrementCounter() {
//     setState(() {
//       // This call to setState tells the Flutter framework that something has
//       // changed in this State, which causes it to rerun the build method below
//       // so that the display can reflect the updated values. If we changed
//       // _counter without calling setState(), then the build method would not be
//       // called again, and so nothing would appear to happen.
//       _counter++;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     // This method is rerun every time setState is called, for instance as done
//     // by the _incrementCounter method above.
//     //
//     // The Flutter framework has been optimized to make rerunning build methods
//     // fast, so that you can just rebuild anything that needs updating rather
//     // than having to individually change instances of widgets.
//     return Scaffold(
//       appBar: AppBar(
//         // TRY THIS: Try changing the color here to a specific color (to
//         // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
//         // change color while the other colors stay the same.
//         backgroundColor: Theme.of(context).colorScheme.inversePrimary,
//         // Here we take the value from the MyHomePage object that was created by
//         // the App.build method, and use it to set our appbar title.
//         title: Text(widget.title),
//       ),
//       body: Center(
//         // Center is a layout widget. It takes a single child and positions it
//         // in the middle of the parent.
//         child: Column(
//           // Column is also a layout widget. It takes a list of children and
//           // arranges them vertically. By default, it sizes itself to fit its
//           // children horizontally, and tries to be as tall as its parent.
//           //
//           // Column has various properties to control how it sizes itself and
//           // how it positions its children. Here we use mainAxisAlignment to
//           // center the children vertically; the main axis here is the vertical
//           // axis because Columns are vertical (the cross axis would be
//           // horizontal).
//           //
//           // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
//           // action in the IDE, or press "p" in the console), to see the
//           // wireframe for each widget.
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: <Widget>[
//             const Text('You have pushed the button this many times:'),
//             Text(
//               '$_counter',
//               style: Theme.of(context).textTheme.headlineMedium,
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _incrementCounter,
//         tooltip: 'Increment',
//         child: const Icon(Icons.add),
//       ), // This trailing comma makes auto-formatting nicer for build methods.
//     );
//   }
// }


