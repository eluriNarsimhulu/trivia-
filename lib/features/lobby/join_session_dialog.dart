// project_folder/lib/features/lobby/join_session_dialog.dart

/// JoinSessionDialog — modal for entering a room code.
///
/// Architecture note:
///   This dialog is a pure input widget. It returns the entered room code
///   as the Navigator pop result — it does NOT call any controller method.
///   The controller call happens in LobbyEntryScreen._onJoinGame(), which
///   owns the dialog result and decides what to do with it.
///
///   Keeping the dialog controller-agnostic means it can be shown from
///   any screen without threading in GameControllerProvider, and it
///   remains trivially testable as a standalone widget.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JoinSessionDialog extends StatefulWidget {
  const JoinSessionDialog({super.key});

  @override
  State<JoinSessionDialog> createState() => _JoinSessionDialogState();
}

class _JoinSessionDialogState extends State<JoinSessionDialog> {
  final _codeController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onJoin() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a room code.');
      return;
    }
    // Return the validated code to the caller.
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16213E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter Room Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask the host for the 6-character code.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              autofocus: true,
              // Force uppercase display to match server room codes.
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: const TextStyle(
                  color: Colors.white24,
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE94560),
                    width: 2,
                  ),
                ),
                errorText: _error,
                errorStyle: const TextStyle(color: Color(0xFFE94560)),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _onJoin(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _onJoin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Join',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Forces all input to uppercase as the user types.
/// Room codes are always uppercase on the server — matching this in the
/// UI prevents "abc123 not found" errors caused by case mismatch.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
// ```

// ---

// ## Data Flow Summary
// ```
// User types name + taps "Create Game"
//           │
//           ▼
// LobbyEntryScreen._onCreateGame()
//           │
//           ▼
// controller.createAndJoinSession(
//   hostId:      provider.playerId,   ← from PlayerIdentityService
//   displayName: "Alice",
//   totalRounds: 5,
// )
//           │
//           ├── RestService.createSession() → { session_id, room_code }
//           ├── GameController builds GameSession
//           ├── _transitionTo(GamePhase.lobby)  ← state.phase = lobby
//           └── SseService.connect()
//                     │
//                     ▼
//           ValueListenableBuilder rebuilds LobbyEntryScreen
//                     │
//           phase == lobby → Navigator.pushReplacement(LobbyScreen)

// ─────────────────────────────────────────────
// Inside LobbyScreen — live player updates:
// ─────────────────────────────────────────────
// Server broadcasts PLAYER_JOINED over SSE
//           │
//           ▼
// SseService parses → PlayerJoinedEvent
//           │
//           ▼
// GameController._handlePlayerJoined()
//   → replaces session.players list (immutable)
//   → _emit(newState)
//           │
//           ▼
// ValueListenableBuilder<GameState> rebuilds
//   → PlayerListWidget receives updated players list
//   → new tile animates in