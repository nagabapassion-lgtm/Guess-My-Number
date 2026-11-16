import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_config.dart';
import 'feedback_type.dart';

/// One player's state in a race room.
///
/// Mirrors the Firestore document at `rooms/{roomId}/players/{playerId}`.
/// Each player in a race (2-5 players) has their own doc with their own
/// narrowed range, lives, last guess, and status.
///
/// The room doc (`rooms/{roomId}`) holds the shared state: the secret
/// number, the phase (countdown/playing/finished), and the winner. This
/// doc holds the per-player state.
///
/// Status flow:
///   joining -> guessing -> (won | lost | out)
///
///   - joining: player just joined, waiting for host to start the race
///   - guessing: race is playing, player is actively guessing
///   - won: player guessed correctly FIRST — they won the race
///   - lost: player ran out of lives before anyone won
///   - out: someone else won the race while this player was still
///     guessing — they didn't win but didn't lose either
class RacePlayer {
  final String playerId;
  final String playerName;
  final int currentMinBound;
  final int currentMaxBound;
  final int attemptsLeft;
  final int totalLives;
  final int? lastGuess;
  final FeedbackType? lastFeedback;
  final String status;
  final int guessCount;
  final DateTime? joinedAt;
  final DateTime? finishedAt;

  /// 1 = winner, 2 = second place, etc. 0 = didn't finish (lost or out
  /// before anyone won). Used to sort the final standings.
  final int finishPosition;

  const RacePlayer({
    required this.playerId,
    required this.playerName,
    required this.currentMinBound,
    required this.currentMaxBound,
    required this.attemptsLeft,
    required this.totalLives,
    this.lastGuess,
    this.lastFeedback,
    required this.status,
    required this.guessCount,
    this.joinedAt,
    this.finishedAt,
    required this.finishPosition,
  });

  /// Build a [RacePlayer] from a Firestore document snapshot.
  /// All fields are read defensively so a missing value does not crash.
  factory RacePlayer.fromFirestore(Map<String, dynamic> data) {
    return RacePlayer(
      playerId: data['playerId'] as String? ?? '',
      playerName: data['playerName'] as String? ?? 'Player',
      currentMinBound:
          (data['currentMinBound'] as num?)?.toInt() ?? GameConfig.defaultMinBound,
      currentMaxBound:
          (data['currentMaxBound'] as num?)?.toInt() ?? GameConfig.defaultMaxBound,
      attemptsLeft:
          (data['attemptsLeft'] as num?)?.toInt() ?? GameConfig.defaultLives,
      totalLives:
          (data['totalLives'] as num?)?.toInt() ?? GameConfig.defaultLives,
      lastGuess: (data['lastGuess'] as num?)?.toInt(),
      lastFeedback: FeedbackType.fromString(data['lastFeedback'] as String?),
      status: data['status'] as String? ?? 'joining',
      guessCount: (data['guessCount'] as num?)?.toInt() ?? 0,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
      finishedAt: (data['finishedAt'] as Timestamp?)?.toDate(),
      finishPosition: (data['finishPosition'] as num?)?.toInt() ?? 0,
    );
  }

  /// The fields written to Firestore when a player joins a race room.
  Map<String, dynamic> toJoinMap() {
    return {
      'playerId': playerId,
      'playerName': playerName,
      'currentMinBound': currentMinBound,
      'currentMaxBound': currentMaxBound,
      'attemptsLeft': attemptsLeft,
      'totalLives': totalLives,
      'lastGuess': null,
      'lastFeedback': null,
      'status': status,
      'guessCount': 0,
      'finishPosition': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    };
  }

  // ----- Status getters -----
  bool get isJoining => status == 'joining';
  bool get isGuessing => status == 'guessing';
  bool get isWon => status == 'won';
  bool get isLost => status == 'lost';
  bool get isOut => status == 'out';
  bool get isFinished => isWon || isLost || isOut;

  /// True if the player is still actively in the race (hasn't won,
  /// lost, or been knocked out).
  bool get isActive => isJoining || isGuessing;

  /// The current safe range as a human-readable string, e.g. "12 to 87".
  String get rangeText => '$currentMinBound to $currentMaxBound';

  /// The fields written to Firestore when the host starts the race
  /// (transition from 'joining' to 'guessing' for all players).
  static Map<String, dynamic> startGuessingMap() {
    return {
      'status': 'guessing',
    };
  }
}

/// The result of processing a race player's guess: the new player state
/// plus the feedback to show. Used by [RaceRoomService.processRaceGuess]
/// to return both the updated player doc and the feedback in one call.
class RaceGuessResult {
  final RacePlayer updatedPlayer;
  final FeedbackType feedback;

  /// True if this guess won the race (the player guessed correctly).
  /// When true, the caller (RaceRoomService) flips the room to
  /// 'finished' and sets the winner.
  final bool wonRace;

  /// True if this guess knocked the player out (they ran out of lives).
  /// The race continues for other players.
  final bool knockedOut;

  const RaceGuessResult({
    required this.updatedPlayer,
    required this.feedback,
    required this.wonRace,
    required this.knockedOut,
  });
}
