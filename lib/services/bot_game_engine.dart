import 'dart:math';

import '../models/feedback_type.dart';

/// The complete state of a solo game against the computer.
///
/// Immutable by design: every guess produces a new [BotGameState] rather
/// than mutating this one. Mirrors the GameRoom pattern used in the
/// multiplayer flow so the rules stay easy to reason about.
class BotGameState {
  final int secret;
  final int minBound;
  final int maxBound;
  final int currentMinBound;
  final int currentMaxBound;
  final int livesLeft;
  final int totalLives;
  final int guessCount;
  final List<BotGuessRecord> history;
  final bool isWon;
  final bool isLost;
  final int? lastGuess;
  final FeedbackType? lastFeedback;

  const BotGameState({
    required this.secret,
    required this.minBound,
    required this.maxBound,
    required this.currentMinBound,
    required this.currentMaxBound,
    required this.livesLeft,
    required this.totalLives,
    required this.guessCount,
    required this.history,
    required this.isWon,
    required this.isLost,
    this.lastGuess,
    this.lastFeedback,
  });

  /// The current safe range as a human-readable string, e.g. "12 to 87".
  String get rangeText => '$currentMinBound to $currentMaxBound';

  bool get isOver => isWon || isLost;
}

/// One guess the player made, with its feedback and attempt number.
class BotGuessRecord {
  final int value;
  final FeedbackType feedback;
  final int attemptNumber;

  const BotGuessRecord({
    required this.value,
    required this.feedback,
    required this.attemptNumber,
  });
}

/// The result of processing one guess: the new state plus the feedback.
class BotGuessResult {
  final BotGameState state;
  final FeedbackType feedback;

  const BotGuessResult({required this.state, required this.feedback});
}

/// Runs a solo game against the computer.
///
/// Pure Dart: no Firebase, no Flutter imports. The secret lives only in
/// memory on this class, so solo games are private by construction (the
/// only thing that ever touches Firestore is the optional daily
/// leaderboard submission).
class BotGameEngine {
  BotGameState _state;

  BotGameEngine({
    required int secret,
    required int minBound,
    required int maxBound,
    required int lives,
  }) : _state = BotGameState(
          secret: secret,
          minBound: minBound,
          maxBound: maxBound,
          currentMinBound: minBound,
          currentMaxBound: maxBound,
          livesLeft: lives,
          totalLives: lives,
          guessCount: 0,
          history: const [],
          isWon: false,
          isLost: false,
        );

  /// Current immutable state. Read this from the UI; never mutate.
  BotGameState get state => _state;

  /// Process a guess and return the new state plus the feedback.
  ///
  /// Rules (identical to the multiplayer rules for consistency):
  ///   - Out-of-range guesses cost no life and change nothing.
  ///   - A correct guess wins immediately.
  ///   - A wrong guess narrows the range and costs one life.
  ///   - Hitting zero lives loses the game and reveals the secret.
  BotGuessResult processGuess(int guess) {
    final s = _state;

    // Guard: no more guesses once the game is over.
    if (s.isOver) {
      return BotGuessResult(state: s, feedback: s.lastFeedback ?? FeedbackType.outOfBounds);
    }

    // Rule 1: guesses outside the original range do not count.
    if (guess < s.minBound || guess > s.maxBound) {
      return BotGuessResult(state: s, feedback: FeedbackType.outOfBounds);
    }

    // Rule 2: guesses outside the narrowed range do not count either.
    if (guess < s.currentMinBound || guess > s.currentMaxBound) {
      return BotGuessResult(state: s, feedback: FeedbackType.outOfBounds);
    }

    // Rule 3: correct guess ends the game as a win.
    if (guess == s.secret) {
      final newState = BotGameState(
        secret: s.secret,
        minBound: s.minBound,
        maxBound: s.maxBound,
        currentMinBound: s.currentMinBound,
        currentMaxBound: s.currentMaxBound,
        livesLeft: s.livesLeft,
        totalLives: s.totalLives,
        guessCount: s.guessCount + 1,
        history: [
          ...s.history,
          BotGuessRecord(
            value: guess,
            feedback: FeedbackType.correct,
            attemptNumber: s.guessCount + 1,
          ),
        ],
        isWon: true,
        isLost: false,
        lastGuess: guess,
        lastFeedback: FeedbackType.correct,
      );
      _state = newState;
      return BotGuessResult(state: newState, feedback: FeedbackType.correct);
    }

    // Rule 4: wrong guess narrows the range and costs a life.
    final isTooLow = guess < s.secret;
    final newMin = isTooLow ? guess + 1 : s.currentMinBound;
    final newMax = isTooLow ? s.currentMaxBound : guess - 1;
    final feedback = isTooLow ? FeedbackType.tooLow : FeedbackType.tooHigh;
    final newLives = s.livesLeft - 1;
    final outOfLives = newLives <= 0;

    final newState = BotGameState(
      secret: s.secret,
      minBound: s.minBound,
      maxBound: s.maxBound,
      currentMinBound: newMin,
      currentMaxBound: newMax,
      livesLeft: newLives < 0 ? 0 : newLives,
      totalLives: s.totalLives,
      guessCount: s.guessCount + 1,
      history: [
        ...s.history,
        BotGuessRecord(
          value: guess,
          feedback: feedback,
          attemptNumber: s.guessCount + 1,
        ),
      ],
      isWon: false,
      isLost: outOfLives,
      lastGuess: guess,
      lastFeedback: feedback,
    );
    _state = newState;
    return BotGuessResult(state: newState, feedback: feedback);
  }
}

/// Generates the secret for the Daily Challenge.
///
/// The secret must be identical for every player on the same day and on
/// every platform (web, Android). We therefore derive it from a stable
/// hash of the date string - never from Dart's Random() without a fixed
/// seed, and never from hashCode (which differs between web and native).
///
/// The hash below is a djb2-style integer hash: pure arithmetic that is
/// guaranteed to produce the same result on every Dart platform.
int generateDailySecret(DateTime date, {required int min, required int max}) {
  final dateStr = _dateKey(date);
  var hash = 5381;
  for (final codeUnit in dateStr.codeUnits) {
    // hash * 33 + c, kept within 30 bits to avoid platform differences
    // in integer wrapping.
    hash = ((hash * 33) + codeUnit) & 0x3FFFFFFF;
  }
  final span = max - min + 1;
  return min + (hash % span);
}

/// "2026-10-23" - zero-padded, always UTC-independent (uses the local
/// calendar date so everyone in the same timezone sees the same secret;
/// the challenge resets at local midnight).
String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Convenience wrapper used by the UI and the leaderboard service so
/// both derive the same document key for "today".
String dailyChallengeDateKey(DateTime date) => _dateKey(date);

/// Generates a random secret for Practice mode.
int generatePracticeSecret({required int min, required int max}) {
  final random = Random();
  return min + random.nextInt(max - min + 1);
}
