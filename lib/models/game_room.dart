import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_config.dart';
import 'feedback_type.dart';
import 'game_phase.dart';

/// The full state of one game room.
///
/// This is the in-memory mirror of the Firestore document at
/// `rooms/{roomId}`. It is intentionally immutable: whenever the room
/// state changes we create a new [GameRoom] rather than mutating fields.
///
/// v5 (Race mode) changes from v4:
///   - Added [mode] field: "classic" (default) or "race".
///   - Added race-specific fields: [maxPlayers], [winnerId], [winnerName].
///   - The existing fields (playerId, playerName, currentMinBound, etc.)
///     are still used by Classic mode. Race mode uses a `players`
///     subcollection instead — see [RacePlayer].
///
/// Backward compatibility: rooms created before v5 have no `mode` field.
/// `fromFirestore` defaults `mode` to 'classic', so existing Classic
/// rooms continue to work unchanged.
class GameRoom {
  final String id;
  final String hostId;
  final String hostName;
  final String? playerId;
  final String? playerName;
  final GamePhase phase;
  final int minBound;
  final int maxBound;
  final int currentMinBound;
  final int currentMaxBound;
  final int attemptsLeft;
  final int secretNumber;
  final int round;
  final int? lastGuess;
  final FeedbackType? lastFeedback;
  final String? winner; // 'host' or 'player' — Classic only
  final int? revealedSecret;
  final DateTime? createdAt;
  final DateTime? lastUpdated;

  // ----- v5 Race mode fields -----
  /// "classic" (default) or "race". Determines which fields are used.
  final String mode;

  /// Race only: max number of players allowed (2-5). Null for Classic.
  final int? maxPlayers;

  /// Race only: the uid of the player who won the race. Null until
  /// someone guesses correctly (or until the race ends with no winner).
  final String? winnerId;

  /// Race only: display name of the winner. Null until someone wins.
  final String? winnerName;

  const GameRoom({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.playerId,
    this.playerName,
    required this.phase,
    required this.minBound,
    required this.maxBound,
    required this.currentMinBound,
    required this.currentMaxBound,
    required this.attemptsLeft,
    required this.secretNumber,
    this.round = 1,
    this.lastGuess,
    this.lastFeedback,
    this.winner,
    this.revealedSecret,
    this.createdAt,
    this.lastUpdated,
    this.mode = 'classic',
    this.maxPlayers,
    this.winnerId,
    this.winnerName,
  });

  /// Build a [GameRoom] from a Firestore document snapshot.
  /// All fields are read defensively so a missing value does not crash.
  /// v5 fields default to Classic values when absent, so existing
  /// rooms created before Race mode shipped continue to work.
  factory GameRoom.fromFirestore(String id, Map<String, dynamic> data) {
    return GameRoom(
      id: id,
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? 'Host',
      playerId: data['playerId'] as String?,
      playerName: data['playerName'] as String?,
      phase: GamePhase.fromString(data['phase'] as String?),
      minBound: (data['minBound'] as num?)?.toInt() ?? GameConfig.defaultMinBound,
      maxBound: (data['maxBound'] as num?)?.toInt() ?? GameConfig.defaultMaxBound,
      currentMinBound:
          (data['currentMinBound'] as num?)?.toInt() ?? GameConfig.defaultMinBound,
      currentMaxBound:
          (data['currentMaxBound'] as num?)?.toInt() ?? GameConfig.defaultMaxBound,
      attemptsLeft: (data['attemptsLeft'] as num?)?.toInt() ?? GameConfig.defaultLives,
      secretNumber: (data['secretNumber'] as num?)?.toInt() ?? 0,
      round: (data['round'] as num?)?.toInt() ?? 1,
      lastGuess: (data['lastGuess'] as num?)?.toInt(),
      lastFeedback: FeedbackType.fromString(data['lastFeedback'] as String?),
      winner: data['winner'] as String?,
      revealedSecret: (data['revealedSecret'] as num?)?.toInt(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
      // v5 fields — default to Classic values when absent.
      mode: data['mode'] as String? ?? 'classic',
      maxPlayers: (data['maxPlayers'] as num?)?.toInt(),
      winnerId: data['winnerId'] as String?,
      winnerName: data['winnerName'] as String?,
    );
  }

  /// The fields written to Firestore when a host creates a new Classic room.
  /// Server timestamps are used so the values are correct regardless of
  /// the device clock.
  Map<String, dynamic> toCreateMap() {
    return {
      'hostId': hostId,
      'hostName': hostName,
      'playerId': null,
      'playerName': null,
      'phase': phase.name,
      'minBound': minBound,
      'maxBound': maxBound,
      'currentMinBound': minBound,
      'currentMaxBound': maxBound,
      'attemptsLeft': attemptsLeft,
      'secretNumber': secretNumber,
      'round': 1,
      'lastGuess': null,
      'lastFeedback': null,
      'winner': null,
      'revealedSecret': null,
      'mode': mode,
      'maxPlayers': maxPlayers,
      'winnerId': null,
      'winnerName': null,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }

  /// Convenience getters used by the UI to decide what to render.
  bool get isWaiting => phase == GamePhase.waiting;
  bool get isPlaying => phase == GamePhase.playing;
  bool get isOver => phase == GamePhase.won || phase == GamePhase.lost;
  bool get isRematchOffered => phase == GamePhase.rematchOffered;
  bool get isCountdown => phase == GamePhase.countdown;
  bool get isFinished => phase == GamePhase.finished;
  bool get playerWon => phase == GamePhase.won;
  bool get playerLost => phase == GamePhase.lost;

  /// Mode getters.
  bool get isClassic => mode == 'classic';
  bool get isRace => mode == 'race';

  /// True if the room is in a terminal state (game over, regardless of mode).
  /// Classic: won/lost. Race: finished.
  bool get isGameEnded =>
      phase == GamePhase.won ||
      phase == GamePhase.lost ||
      phase == GamePhase.finished;

  /// The current safe range as a human-readable string, e.g. "12 to 87".
  /// Classic only — Race mode uses per-player ranges from the players
  /// subcollection.
  String get rangeText => '$currentMinBound to $currentMaxBound';
}
