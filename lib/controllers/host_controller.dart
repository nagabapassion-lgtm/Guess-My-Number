import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game_config.dart';
import '../models/game_phase.dart';
import '../models/game_room.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';

/// State holder for the host side of the game.
///
/// Responsibilities:
///   - Authenticate the user anonymously on first action
///   - Create a room with the host's chosen settings
///   - Subscribe to live updates so the host sees the player join
///     and every guess in real time
///   - Offer a rematch: the host enters a NEW secret in the
///     new-round dialog, the same room code and the same player
///     are preserved, the room flips to 'rematchOffered' until
///     the player accepts
///   - Surface friendly error messages to the UI
///
/// The controller is a singleton so any screen can access the same
/// state without threading it through the widget tree.
class HostController extends ChangeNotifier {
  HostController._();
  static final HostController instance = HostController._();

  final AuthService _auth = AuthService();
  final RoomService _roomService = RoomService();

  GameRoom? _currentRoom;
  bool _isWorking = false;
  String? _errorMessage;
  StreamSubscription<GameRoom?>? _roomSubscription;

  GameRoom? get currentRoom => _currentRoom;
  bool get isWorking => _isWorking;
  String? get errorMessage => _errorMessage;

  /// Create a new room and start listening for a player to join.
  Future<void> createRoom({
    required String hostName,
    required int secretNumber,
    required int minBound,
    required int maxBound,
  }) async {
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _auth.signInAnonymously();
      final room = await _roomService.createRoom(
        hostId: user.uid,
        hostName: hostName,
        secretNumber: secretNumber,
        minBound: minBound,
        maxBound: maxBound,
      );
      _currentRoom = room;
      _startListening(room.id);
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// Drop the current room entirely (local subscription + remote doc).
  /// Used when the host taps "Back to Home" or cancels the waiting
  /// screen. Deleting the room also signals the player's screen (their
  /// stream sees the document disappear) to go home gracefully.
  Future<void> leaveRoom() async {
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    if (_currentRoom != null) {
      try {
        await _roomService.deleteRoom(_currentRoom!.id);
      } catch (_) {
        // Deletion failures are not user-actionable; ignore silently.
      }
    }
    _currentRoom = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset the controller to its initial state without touching
  /// Firestore. Used by "Play Again" so the host can configure a
  /// fresh room.
  void reset() {
    _roomSubscription?.cancel();
    _roomSubscription = null;
    _currentRoom = null;
    _errorMessage = null;
    _isWorking = false;
    notifyListeners();
  }

  /// Offer a rematch on the SAME room with a NEW secret the host
  /// just typed in.
  ///
  /// The room code, host name, and player are all preserved. The
  /// room's `round` counter is bumped by 1, so old guesses become
  /// invisible to the UI (they're filtered by round). The phase
  /// flips to 'rematchOffered' - the player must then explicitly
  /// accept (via [PlayerController.acceptRematch]) before the new
  /// round begins.
  ///
  /// GUARDED: only works while the current room is over (won/lost).
  ///
  /// THROWS on Firebase errors - the caller (the new-round dialog)
  /// catches the error and shows an inline message.
  Future<void> offerRematch({required int newSecret}) async {
    final room = _currentRoom;
    if (room == null) {
      throw StateError('No active room to reset.');
    }
    if (!room.isOver) {
      throw StateError('This room is not ready for a new round.');
    }

    _isWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _roomService.offerRematch(
        code: room.id,
        newSecret: newSecret,
        minBound: room.minBound,
        maxBound: room.maxBound,
        currentRound: room.round,
      );

      // Optimistically patch the local in-memory room so the UI
      // updates instantly even before the Firestore listener fires.
      // After offerRematch the room is in 'rematchOffered' - the
      // host's UI shows a "waiting for player to accept" state.
      // The phase will flip to 'playing' (and the UI will re-render
      // again) once the player taps "Keep Playing" on their end.
      _currentRoom = GameRoom(
        id: room.id,
        hostId: room.hostId,
        hostName: room.hostName,
        playerId: room.playerId,
        playerName: room.playerName,
        phase: GamePhase.rematchOffered,
        minBound: room.minBound,
        maxBound: room.maxBound,
        currentMinBound: room.minBound,
        currentMaxBound: room.maxBound,
        attemptsLeft: GameConfig.defaultLives,
        secretNumber: newSecret,
        round: room.round + 1,
        lastGuess: null,
        lastFeedback: null,
        winner: null,
        revealedSecret: null,
        createdAt: room.createdAt,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      _isWorking = false;
      notifyListeners();
      rethrow;
    }

    _isWorking = false;
    notifyListeners();
  }

  void _startListening(String code) {
    _roomSubscription?.cancel();
    _roomSubscription = _roomService.watchRoom(code).listen((room) {
      _currentRoom = room;
      notifyListeners();
    });
  }

  /// Translate raw exception messages into friendly user text.
  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('network') || message.contains('unavailable')) {
      return 'Check your internet connection and try again.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }
}
