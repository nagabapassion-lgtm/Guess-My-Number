import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/game_room.dart';
import '../models/race_player.dart';
import '../services/auth_service.dart';
import '../services/race_room_service.dart';

/// State holder for the RACE MODE host side.
///
/// Singleton like [HostController] (Classic). The host creates a race
/// room, watches the roster fill up, starts the countdown, watches the
/// live race, and can rematch or close the room.
class RaceHostController extends ChangeNotifier {
  RaceHostController._();
  static final RaceHostController instance = RaceHostController._();

  final AuthService _auth = AuthService();
  final RaceRoomService _raceService = RaceRoomService();

  GameRoom? _currentRoom;
  List<RacePlayer> _players = [];
  bool _isWorking = false;
  String? _errorMessage;
  StreamSubscription<GameRoom?>? _roomSubscription;
  StreamSubscription<List<RacePlayer>>? _playersSubscription;
  Timer? _countdownTimer;
  int _countdownSeconds = 0;

  GameRoom? get currentRoom => _currentRoom;
  List<RacePlayer> get players => _players;
  bool get isWorking => _isWorking;
  String? get errorMessage => _errorMessage;
  int get countdownSeconds => _countdownSeconds;
  bool get isCountingDown => _countdownTimer != null && _countdownTimer!.isActive;

  /// Create a new race room. Returns the room (with the generated code).
  Future<void> createRaceRoom({
    required String hostName,
    required int secretNumber,
    required int minBound,
    required int maxBound,
    required int maxPlayers,
  }) async {
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _auth.signInAnonymously();
      final room = await _raceService.createRaceRoom(
        hostId: user.uid,
        hostName: hostName,
        secretNumber: secretNumber,
        minBound: minBound,
        maxBound: maxBound,
        maxPlayers: maxPlayers,
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

  /// Host starts the 3-second countdown. Flips room to 'countdown',
  /// then runs a client-side timer. When the timer ends, calls
  /// startRace() to flip to 'playing'.
  Future<void> startCountdown() async {
    final room = _currentRoom;
    if (room == null) return;

    _isWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _raceService.startCountdown(room.id);
      _countdownSeconds = 3;
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _countdownSeconds--;
        if (_countdownSeconds <= 0) {
          timer.cancel();
          _countdownTimer = null;
          _startRace();
        }
        notifyListeners();
      });
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  Future<void> _startRace() async {
    final room = _currentRoom;
    if (room == null) return;

    try {
      await _raceService.startRace(room.id);
    } catch (error) {
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  /// Host closes the race room. Deletes the room + all player docs.
  Future<void> leaveRoom() async {
    await _roomSubscription?.cancel();
    _roomSubscription = null;
    await _playersSubscription?.cancel();
    _playersSubscription = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_currentRoom != null) {
      try {
        await _raceService.deleteRaceRoom(_currentRoom!.id);
      } catch (_) {
        // Best-effort.
      }
    }
    _currentRoom = null;
    _players = [];
    _errorMessage = null;
    notifyListeners();
  }

  /// Host rematches: starts a new round with the same code.
  Future<void> rematch() async {
    final room = _currentRoom;
    if (room == null) return;

    _isWorking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _raceService.rematchRaceRoom(room.id);
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  void _startListening(String code) {
    _roomSubscription?.cancel();
    _roomSubscription = _raceService.watchRaceRoom(code).listen((room) {
      _currentRoom = room;
      notifyListeners();
    });
    _playersSubscription?.cancel();
    _playersSubscription = _raceService.watchRacePlayers(code).listen((players) {
      _players = players;
      notifyListeners();
    });
  }

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
    _playersSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// State holder for the RACE MODE player side.
///
/// The player joins a race room, watches the countdown, guesses
/// simultaneously with other players, and sees the results.
class RacePlayerController extends ChangeNotifier {
  RacePlayerController._();
  static final RacePlayerController instance = RacePlayerController._();

  final AuthService _auth = AuthService();
  final RaceRoomService _raceService = RaceRoomService();

  GameRoom? _currentRoom;
  List<RacePlayer> _players = [];
  bool _isJoining = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  StreamSubscription<GameRoom?>? _roomSubscription;
  StreamSubscription<List<RacePlayer>>? _playersSubscription;

  GameRoom? get currentRoom => _currentRoom;
  List<RacePlayer> get players => _players;
  bool get isJoining => _isJoining;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// The current player's RacePlayer state, or null if not in the room.
  RacePlayer? get myPlayer {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _players
        .where((p) => p.playerId == user.uid)
        .cast<RacePlayer?>()
        .firstWhere((p) => p != null, orElse: () => null);
  }

  /// Join a race room with the given code.
  Future<void> joinRaceRoom({
    required String code,
    required String playerName,
  }) async {
    _isJoining = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _auth.signInAnonymously();
      await _raceService.joinRaceRoom(
        code: code.toUpperCase().trim(),
        playerId: user.uid,
        playerName: playerName.trim(),
      );
      _startListening(code.toUpperCase().trim());
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  /// Submit a guess in the race.
  Future<void> submitGuess(int guess) async {
    final room = _currentRoom;
    final user = FirebaseAuth.instance.currentUser;
    if (room == null || user == null) return;

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _raceService.processRaceGuess(
        code: room.id,
        playerId: user.uid,
        guess: guess,
      );
    } catch (error) {
      _errorMessage = _friendlyError(error);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Leave the race room.
  Future<void> leaveRoom() async {
    final room = _currentRoom;
    final user = FirebaseAuth.instance.currentUser;
    _roomSubscription?.cancel();
    _roomSubscription = null;
    _playersSubscription?.cancel();
    _playersSubscription = null;
    _currentRoom = null;
    _players = [];
    _errorMessage = null;
    notifyListeners();

    if (room != null && user != null) {
      try {
        await _raceService.leaveRaceRoom(
          code: room.id,
          playerId: user.uid,
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  void _startListening(String code) {
    _roomSubscription?.cancel();
    _roomSubscription = _raceService.watchRaceRoom(code).listen((room) {
      _currentRoom = room;
      notifyListeners();
    });
    _playersSubscription?.cancel();
    _playersSubscription = _raceService.watchRacePlayers(code).listen((players) {
      _players = players;
      notifyListeners();
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('network') || message.contains('unavailable')) {
      return 'Network unavailable.';
    }
    if (message.contains('permission-denied') ||
        message.contains('permission_denied')) {
      return 'permission-denied';
    }
    if (message.contains('could not find a room') ||
        message.contains('no room') ||
        message.contains('does not exist') ||
        message.contains('not-found')) {
      return 'No game found with that code.';
    }
    if (message.contains('already started')) {
      return 'This race has already started.';
    }
    if (message.contains('full')) {
      return 'This race room is full.';
    }
    if (message.contains('not a race room')) {
      return 'This is not a race room. Use Join a Game for classic mode.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _playersSubscription?.cancel();
    super.dispose();
  }
}
