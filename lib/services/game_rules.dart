import 'dart:math';

import '../game_config.dart';
import '../models/feedback_type.dart';
import '../models/game_phase.dart';
import '../models/game_room.dart';

/// Pure game logic. No Flutter, no Firebase. Easy to unit-test.
///
/// Two responsibilities:
///   1. Generate invite codes that are unambiguous when read aloud
///      (no I/O/0/1) - see [generateRoomCode] and [isValidRoomCode].
///   2. Compute the result of a guess - see [processGuess]. This is
///      called from inside a Firestore transaction so it MUST be
///      pure (no side effects, no I/O).
class GameRules {
  GameRules._(); // prevent instantiation

  /// Generate a random room code of [GameConfig.roomCodeLength]
  /// characters from [GameConfig.roomCodeAlphabet]. The alphabet
  /// excludes I, O, 0, 1 so the code is unambiguous when read aloud
  /// over a phone call or typed from a screenshot.
  static String generateRoomCode() {
    final random = Random();
    const alphabet = GameConfig.roomCodeAlphabet;
    final code = StringBuffer();
    for (var i = 0; i < GameConfig.roomCodeLength; i++) {
      code.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return code.toString();
  }

  /// Validate a room code entered by the player. The code must be
  /// non-empty, the right length, and contain only characters from
  /// the alphabet. Used by the player's join screen for instant
  /// feedback before hitting Firestore.
  static bool isValidRoomCode(String code) {
    if (code.length != GameConfig.roomCodeLength) return false;
    const alphabet = GameConfig.roomCodeAlphabet;
    // Use split('') instead of .characters (which needs the
    // `characters` package) so we have zero extra deps.
    for (final char in code.split('')) {
      if (!alphabet.contains(char)) return false;
    }
    return true;
  }

  /// Validate the host's setup inputs before creating a room.
  ///
  /// Returns null if everything is OK, or a user-facing error message
  /// if something is wrong. The host's setup screen calls this before
  /// [HostController.createRoom] so we can show a snackbar instead of
  /// hitting Firestore with invalid data.
  ///
  /// Rules:
  ///   - hostName must not be empty (1..24 chars is reasonable).
  ///   - minBound must be strictly less than maxBound.
  ///   - The range must contain at least 10 numbers (otherwise the
  ///     game is trivially solved in 1-2 guesses).
  ///   - secretNumber must be within [minBound, maxBound].
  static String? validateHostSetup({
    required int minBound,
    required int maxBound,
    required int secretNumber,
    required String hostName,
  }) {
    final trimmedName = hostName.trim();
    if (trimmedName.isEmpty) {
      return 'Please enter a name so the player knows who they are playing against.';
    }
    if (trimmedName.length > 24) {
      return 'Name must be 24 characters or fewer.';
    }
    if (minBound >= maxBound) {
      return 'The minimum must be less than the maximum.';
    }
    if (maxBound - minBound < 10) {
      return 'The range must contain at least 10 numbers.';
    }
    if (secretNumber < minBound || secretNumber > maxBound) {
      return 'The secret number must be between $minBound and $maxBound.';
    }
    return null;
  }

  /// Compute the result of a player's guess.
  ///
  /// Rules (identical to solo mode for consistency):
  ///   - Out-of-range guesses cost no life and change nothing.
  ///   - A correct guess wins immediately (phase -> won).
  ///   - A wrong guess narrows the range and costs one life.
  ///   - Hitting zero lives loses the game (phase -> lost) and
  ///     reveals the secret.
  ///
  /// Returns a [GuessResult] containing the new room state and the
  /// feedback to show the player. The caller writes both back to
  /// Firestore inside a transaction.
  static GuessResult processGuess(GameRoom room, int guess) {
    // Rule 1: guesses outside the original range do not count.
    if (guess < room.minBound || guess > room.maxBound) {
      return GuessResult(
        updatedRoom: room,
        feedback: FeedbackType.outOfBounds,
      );
    }

    // Rule 2: guesses outside the narrowed range do not count either.
    if (guess < room.currentMinBound || guess > room.currentMaxBound) {
      return GuessResult(
        updatedRoom: room,
        feedback: FeedbackType.outOfBounds,
      );
    }

    // Rule 3: correct guess ends the game as a win.
    if (guess == room.secretNumber) {
      final updated = GameRoom(
        id: room.id,
        hostId: room.hostId,
        hostName: room.hostName,
        playerId: room.playerId,
        playerName: room.playerName,
        phase: GamePhase.won,
        minBound: room.minBound,
        maxBound: room.maxBound,
        currentMinBound: room.currentMinBound,
        currentMaxBound: room.currentMaxBound,
        attemptsLeft: room.attemptsLeft,
        secretNumber: room.secretNumber,
        round: room.round,
        lastGuess: guess,
        lastFeedback: FeedbackType.correct,
        winner: 'player',
        revealedSecret: room.secretNumber,
        createdAt: room.createdAt,
        lastUpdated: DateTime.now(),
      );
      return GuessResult(
        updatedRoom: updated,
        feedback: FeedbackType.correct,
      );
    }

    // Rule 4: wrong guess narrows the range and costs a life.
    final isTooLow = guess < room.secretNumber;
    final newMin = isTooLow ? guess + 1 : room.currentMinBound;
    final newMax = isTooLow ? room.currentMaxBound : guess - 1;
    final feedback = isTooLow ? FeedbackType.tooLow : FeedbackType.tooHigh;
    final newLives = room.attemptsLeft - 1;
    final outOfLives = newLives <= 0;

    final updated = GameRoom(
      id: room.id,
      hostId: room.hostId,
      hostName: room.hostName,
      playerId: room.playerId,
      playerName: room.playerName,
      phase: outOfLives ? GamePhase.lost : GamePhase.playing,
      minBound: room.minBound,
      maxBound: room.maxBound,
      currentMinBound: newMin,
      currentMaxBound: newMax,
      attemptsLeft: newLives < 0 ? 0 : newLives,
      secretNumber: room.secretNumber,
      round: room.round,
      lastGuess: guess,
      lastFeedback: feedback,
      winner: outOfLives ? 'host' : null,
      revealedSecret: outOfLives ? room.secretNumber : null,
      createdAt: room.createdAt,
      lastUpdated: DateTime.now(),
    );
    return GuessResult(
      updatedRoom: updated,
      feedback: feedback,
    );
  }
}

/// The result of processing one guess: the new room state plus the
/// feedback to show the player. Used by [RoomService.processPlayerGuess]
/// to write both back to Firestore inside one transaction.
class GuessResult {
  final GameRoom updatedRoom;
  final FeedbackType feedback;

  const GuessResult({required this.updatedRoom, required this.feedback});
}