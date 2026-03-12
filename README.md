# Multiplayer Trivia Game

A real-time multiplayer trivia game built with **Flutter** (client) and **Node.js** (server).  
Players join a shared room by code, answer questions simultaneously, and see a live leaderboard after each round.

---

## How it works

The Flutter app communicates with the Node.js server over two channels:

- **REST** — player actions (create room, join, start game, submit answer)
- **SSE (Server-Sent Events)** — server pushes game events to all clients in real time (questions, scores, leaderboard)

All game state lives in the server's memory. No database required.

---

## Project structure

```
project_folder/
│
├── trivia-server/                        Node.js backend
│   │
│   ├── server.js                         Entry point — Express app, routes, graceful shutdown
│   ├── store.js                          In-memory session store (sessions Map + room code index)
│   ├── broadcast.js                      Writes SSE event frames to all connected clients
│   ├── scoring.js                        Server-authoritative score calculation (base + speed + streak)
│   ├── questions.js                      Question bank — 20 questions used each game
│   │
│   └── routes/
│       ├── sessions.js                   POST /sessions            create a room
│       │                                 POST /sessions/join       join by room code
│       │                                 DELETE /sessions/:id      cancel from lobby
│       │
│       ├── game.js                       POST /sessions/:id/start      host starts the game
│       │                                 POST /sessions/:id/answers    player submits an answer
│       │                                 POST /sessions/:id/restart    play again with same players
│       │
│       └── events.js                     GET /sessions/:id/events      open SSE stream (long-lived)
│
│
└── lib/                                  Flutter client
    │
    ├── main.dart                         App entry — initialises services, launches LobbyEntryScreen
    │
    ├── state/
    │   ├── game_controller.dart          Sole authority on state transitions; handles all SSE events
    │   └── game_state.dart               Immutable snapshot of the full client-side game state
    │
    ├── core/
    │   ├── models/
    │   │   ├── game_phase.dart           Enum of every phase (lobby → countdown → questionActive → …)
    │   │   ├── game_session.dart         Session data shared across all players (id, roomCode, phase)
    │   │   ├── game_events.dart          Typed classes for each incoming SSE event
    │   │   ├── player.dart               Single player model (id, displayName, isHost)
    │   │   ├── question.dart             Immutable question model (text, options, timer, type)
    │   │   └── scoring.dart              ScoringRules model — received once in GAME_START
    │   │
    │   ├── services/
    │   │   ├── rest_service.dart         Concrete HTTP client — all REST calls to the server
    │   │   ├── rest_service_interface.dart   Abstract contract GameController depends on
    │   │   ├── sse_service.dart          Manages the persistent SSE connection + auto-reconnect
    │   │   ├── sse_service_interface.dart    Abstract contract GameController depends on
    │   │   ├── player_identity_service.dart  Generates and persists a UUID for this device
    │   │   └── service_registry.dart     Wires all services together; called once in main()
    │   │
    │   └── utils/
    │       └── logger.dart               Centralised debug logging utility
    │
    └── features/
        ├── lobby/
        │   ├── lobby_entry_screen.dart   First screen — create room or join by code
        │   ├── lobby_screen.dart         Waiting room — shows player list before game starts
        │   ├── join_session_dialog.dart  Modal dialog for entering a room code
        │   └── player_list_widget.dart   Roster of players currently in the lobby
        │
        └── game/
            ├── game_screen.dart          Root gameplay screen — switches UI based on GamePhase
            ├── question_view.dart        Displays question + answer options during active phase
            ├── answer_options_widget.dart  Renders the correct input type per question format
            ├── countdown_widget.dart     3-second get-ready screen between rounds
            ├── result_banner.dart        Shows correct answer + per-player score delta
            └── leaderboard_widget.dart   Top-player standings shown between rounds and at game end
```

---

## Getting started

### 1. Run the server

```bash
cd trivia-server
npm install
npm run dev        # uses nodemon for auto-reload
# or
npm start          # plain node
```

Server starts on `http://localhost:3000`.  
A health check is available at `GET /health`.

### 2. Run the Flutter app

Point the app at your server. In `lib/main.dart`, set the `API_BASE_URL`:

```dart
defaultValue: 'http://<YOUR-IP>:3000',
```

Find your local IP:
- macOS / Linux: `ifconfig | grep inet`
- Windows: `ipconfig`

Then run:

```bash
flutter pub get
flutter run
```

---

## Gameplay

1. One player creates a room and shares the **6-character room code**
2. Other players join using the code
3. Host starts the game — questions are shuffled automatically
4. Each round: question opens → players answer → server scores → leaderboard shown
5. After all rounds: final standings and winner announced
6. Host can restart with the same players, or cancel from the lobby

---

## Scoring

Scoring is calculated server-side. The client displays exactly what the server sends.

| Component | Points |
|---|---|
| Correct answer | 100 |
| Speed bonus | 0 – 50 (full 50 if answered instantly) |
| Streak bonus | streak × 10, capped at 50 |
| Wrong answer | 0, streak resets |

---

## Tech stack

| Layer | Technology |
|---|---|
| Client | Flutter (Dart) |
| Server | Node.js, Express |
| Real-time | Server-Sent Events (SSE) |
| State management | ValueNotifier + custom GameController |
| Storage | In-memory (no database) |

---

## Configuration

| Variable | Where | Default | Purpose |
|---|---|---|---|
| `API_BASE_URL` | `lib/main.dart` | Render dev URL | Server the Flutter app talks to |
| `PORT` | environment | `3000` | Port the Node.js server listens on |
| `total_rounds` | set by host at room creation | `3` | Number of questions per game |
