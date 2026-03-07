// project_folder/lib/features/lobby/lobby_entry_screen.dart

/// LobbyEntryScreen — the first screen a player sees.
///
/// Responsibilities (UI only):
///   • Collect display name from the user.
///   • Offer two paths: Create Game or Join Game.
///   • Delegate all session logic to GameController — zero business logic here.
///   • Navigate to LobbyScreen after the controller confirms the session.
///
/// Architecture note:
///   This widget reads playerId from GameControllerProvider — it never
///   generates or stores identity itself. Identity is a service concern,
///   not a UI concern. The widget is a pure input form that calls controller
///   methods and reacts to state changes.

import 'package:flutter/material.dart';

import '../../main.dart';
import '../../state/game_controller.dart';
import '../../state/game_state.dart';
import '../../core/models/game_phase.dart';
import 'join_session_dialog.dart';
import 'lobby_screen.dart';

class LobbyEntryScreen extends StatefulWidget {
  const LobbyEntryScreen({super.key});

  @override
  State<LobbyEntryScreen> createState() => _LobbyEntryScreenState();
}

class _LobbyEntryScreenState extends State<LobbyEntryScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions — call controller only, never touch state directly
  // ---------------------------------------------------------------------------

  Future<void> _onCreateGame(GameController controller, String playerId) async {
    if (!_validateName()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await controller.createAndJoinSession(
        hostId:      playerId,
        displayName: _nameController.text.trim(),
        totalRounds: 5, // default; could be a UI picker in a future stage
      );
      // Navigation is driven by state change, not by awaiting the call.
      // The listener below watches for GamePhase.lobby and navigates.
    } catch (e) {
      setState(() => _errorMessage = 'Could not create game. Please retry.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onJoinGame(GameController controller, String playerId) async {
    if (!_validateName()) return;

    // Show the room code dialog — it returns the code the user typed.
    final roomCode = await showDialog<String>(
      context: context,
      builder: (_) => const JoinSessionDialog(),
    );
    if (!mounted) return;
    if (roomCode == null || roomCode.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await controller.joinSession(
        roomCode:    roomCode,
        playerId:    playerId,
        displayName: _nameController.text.trim(),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not join game. Check the room code.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validateName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your display name.');
      return false;
    }
    if (name.length > 24) {
      setState(() => _errorMessage = 'Name must be 24 characters or fewer.');
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider   = GameControllerProvider.of(context);
    final controller = provider.controller;
    final playerId   = provider.playerId;

    return ValueListenableBuilder<GameState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        // Once the controller has moved to lobby phase, navigate forward.
        // We do this here rather than in the action methods so the
        // navigation is always driven by state — not by async call order.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.phase == GamePhase.lobby && ModalRoute.of(context)?.isCurrent == true && mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LobbyScreen()),
            );
          }
        });

        return Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    _buildNameField(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _buildErrorMessage(),
                    ],
                    const SizedBox(height: 32),
                    _buildActionButtons(
                      controller: controller,
                      playerId: playerId,
                      isLoading: _isLoading,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.quiz_rounded, size: 72, color: Color(0xFFE94560)),
        const SizedBox(height: 16),
        Text(
          'Trivia Night v2',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Challenge your friends',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      maxLength: 24,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Your display name',
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.person_outline, color: Colors.white54),
        counterStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF16213E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE94560), width: 2),
        ),
      ),
      onChanged: (_) {
        if (_errorMessage != null) setState(() => _errorMessage = null);
      },
    );
  }

  Widget _buildErrorMessage() {
    return Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE94560), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Color(0xFFE94560), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons({
    required GameController controller,
    required String playerId,
    required bool isLoading,
  }) {
    if (isLoading) {
      return const CircularProgressIndicator(color: Color(0xFFE94560));
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => _onCreateGame(controller, playerId),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text(
              'Create Game',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => _onJoinGame(controller, playerId),
            icon: const Icon(Icons.login_rounded),
            label: const Text(
              'Join Game',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}