import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_room.dart';
import '../services/auth_service.dart';
import '../services/game_rules.dart';
import '../services/room_service.dart';

/// State holder for the player side of the game.
///
/// Responsibilities:
///   - Authenticate the user anonymously on first action
///   - Join an existing waiting room using a 6-character invite code
///   - Subscribe to live updates so the player sees feedback, narrowed
///     range, and lives left in real time
///   - Submit guesses (the Trust model: the player's device computes
///     the result and writes it back via [RoomService.processPlayerGuess])
///   - Accept or decline a host-offered rematch:
///       accept  -> [RoomService.acceptRematch] flips phase to 'playing'
///       decline -> [RoomService.declineRematch] vacates the room
///   - Vacate the room on exit: leaving returns the room to a pristine
///     'waiting' state so a new player can join with the same code
class PlayerController extends ChangeNotifier {
  PlayerController._();
  static final PlayerController instance = PlayerController._();

  final AuthService _auth = AuthService();
  final RoomService _roomService = RoomService();

  GameRoom? _currentRoom;
  bool _isJoining = false;
  bool _isSubmitting = false;
  bool _isRematchWorking = false;
  String? _errorMessage;
  StreamSubscription<GameRoom?>? _roomSubscription;

  GameRoom? get currentRoom => _currentRoom;
  bool get isJoining => _isJoining;
  bool get isSubmitting => _isSubmitting;
  bool get isRematchWorking => _isRematchWorking;
  String? get errorMessage => _errorMessage;

  /// Attempt to join the room with the given code and player name.
  /// Validates the code locally first to give immediate feedback.
  Future<void> joinRoom({
    required String code,
    required String playerName,
  }) async {
    final cleaned = code.toUpperCase().trim();
    if (!GameRules.isValidRoomCode(cleaned)) {
      _errorMessage = 'Invalid code.';
      notifyListeners();
      return;
    }

    if (playerName.trim().isEmpty) {
      _errorMessage =
          'Please enter a name so the host knows who is playing.';
      notifyListeners();
      return;
    }

    _isJoining = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _auth.signInAnonymously();
      await _roomService.joinRoom(
        code: cleaned,
        playerId: user.uid,
        playerName: playerName.trim(),
      );
      _startListening(cleaned);
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  /// Submit a guess. The validation, computation, and Firestore write
  /// all happen inside [RoomService.processPlayerGuess] (atomic
  /// transaction).
  Future<void> submitGuess(int guess) async {
    if (_currentRoom == null) return;

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception(
            'You are not signed in. Please restart the app.');
      }
      await _roomService.processPlayerGuess(
        code: _currentRoom!.id,
        guess: guess,
        playerId: user.uid,
      );
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Accept the host's rematch offer. Flips the room from
  /// 'rematchOffered' to 'playing'. The host's UI is driven by the
  /// same onSnapshot stream and immediately re-renders. The player's
  /// screen dismisses the rematch prompt and continues in the same
  /// room with a fresh round.
  Future<void> acceptRematch() async {
    final room = _currentRoom;
    if (room == null) return;

    final user = _auth.currentUser;
    if (user == null) {
      _errorMessage =
          'You are not signed in. Please restart the app.';
      notifyListeners();
      return;
    }

    _isRematchWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _roomService.acceptRematch(
        code: room.id,
        playerId: user.uid,
      );
      // The onSnapshot listener will fire with phase=playing and
      // the screen will react. No optimistic patch needed here.
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isRematchWorking = false;
      notifyListeners();
    }
  }

  /// Decline the host's rematch offer. Vacates the room back to
  /// 'waiting' so the host can invite someone new with the same code.
  /// The player is then sent home by the screen.
  Future<void> declineRematch() async {
    final room = _currentRoom;
    if (room == null) return;

    _isRematchWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _roomService.declineRematch(
        code: room.id,
        minBound: room.minBound,
        maxBound: room.maxBound,
      );
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isRematchWorking = false;
      notifyListeners();
    }
  }

  /// Leave the current room.
  ///
  /// The room document is VACATED: returned to a pristine 'waiting'
  /// state with no player, so a new player can join with the same
  /// code. The host's screen watches for that transition and sends
  /// them back to the waiting screen with the code still visible.
  Future<void> leaveRoom() async {
    _roomSubscription?.cancel();
    _roomSubscription = null;

    final room = _currentRoom;
    _currentRoom = null;
    _errorMessage = null;
    notifyListeners();

    if (room != null) {
      try {
        await _roomService.vacateRoom(
          code: room.id,
          minBound: room.minBound,
          maxBound: room.maxBound,
        );
      } catch (_) {
        // E.g. the host deleted the room concurrently. Ignore.
      }
    }
  }

  void _startListening(String code) {
    _roomSubscription?.cancel();
    _roomSubscription = _roomService.watchRoom(code).listen((room) {
      _currentRoom = room;
      notifyListeners();
    });
  }

  /// Translate raw exception messages into SHORT canonical strings
  /// that the player_join_screen's _mapError() can reliably bucket
  /// into user-friendly copy.
  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('network') ||
        message.contains('unavailable') ||
        message.contains('deadline-exceeded') ||
        message.contains('timeout')) {
      return 'Network unavailable.';
    }

    if (message.contains('permission-denied') ||
        message.contains('permission_denied') ||
        message.contains('insufficient permissions') ||
        message.contains('missing or insufficient')) {
      return 'permission-denied';
    }

    if (message.contains('could not find a room') ||
        message.contains('no room') ||
        message.contains('does not exist') ||
        message.contains('not-found')) {
      return 'No game found with that code.';
    }

    if (message.contains('already started') ||
        message.contains('already finished')) {
      return 'Game already started.';
    }

    if (message.contains('already joined') ||
        message.contains('room full')) {
      return 'Room full.';
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }
}
