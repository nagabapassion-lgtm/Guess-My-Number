import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_config.dart';
import 'feedback_type.dart';
import 'game_phase.dart';

/// The full state of one game room.
///
/// This is the in-memory mirror of the Firestore document at
/// `rooms/{roomId}`. It is intentionally immutable: whenever the room
/// state changes we create a new [GameRoom] rather than mutating fields.
/// This makes the data flow easy to reason about and supports future
/// features like undo / replay without extra plumbing.
///
/// v4 schema changes from v3:
///   - Added [round] field. Each new round (initial + every rematch)
///     bumps this counter. Guesses are stamped with the round they
///     belong to. This replaces the v3 pattern of deleting old guesses
///     on rematch - which was impossible to do atomically (Firestore
///     transactions can't read subcollections). Now we just filter
///     client-side: `where('round', '==', room.round)`. Old guess
///     docs stay in Firestore forever (cheap, harmless, invisible to
///     the player because they're filtered out).
///
/// Trust model: [secretNumber] is intentionally stored here and in
/// Firestore for v1 simplicity. The host does not need to stay online.
/// This means a technically-savvy player could read the secret by
/// querying Firestore directly. v2 can move the secret off Firestore
/// and rely on Cloud Functions for authoritative guess processing.
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

  /// Monotonically increasing round counter. Starts at 1 when the
  /// room is created. Bumped by 1 every time the host stages a new
  /// round (offerRematch). Guesses carry this round number so the
  /// UI can filter to the current round.
  final int round;

  final int? lastGuess;
  final FeedbackType? lastFeedback;
  final String? winner; // 'host' or 'player'
  final int? revealedSecret;
  final DateTime? createdAt;
  final DateTime? lastUpdated;

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
  });

  /// Build a [GameRoom] from a Firestore document snapshot.
  /// All fields are read defensively so a missing value does not crash.
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
    );
  }

  /// The fields written to Firestore when a host creates a new room.
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
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }

  /// Convenience getters used by the UI to decide what to render.
  bool get isWaiting => phase == GamePhase.waiting;
  bool get isPlaying => phase == GamePhase.playing;
  bool get isOver => phase == GamePhase.won || phase == GamePhase.lost;
  bool get isRematchOffered => phase == GamePhase.rematchOffered;
  bool get playerWon => phase == GamePhase.won;
  bool get playerLost => phase == GamePhase.lost;

  /// The current safe range as a human-readable string, e.g. "12 to 87".
  String get rangeText => '$currentMinBound to $currentMaxBound';
}
