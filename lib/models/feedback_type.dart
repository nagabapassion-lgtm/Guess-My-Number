/// Feedback given to the player after each guess.
///
/// Stored as a name string in Firestore (e.g. "tooLow"), parsed back into
/// this enum when read. Keeping it an enum makes the UI type-safe and
/// lets the compiler catch typos.
enum FeedbackType {
  /// The guess was below the safe range. Doesn't cost a life.
  /// Tells the player to guess higher.
  tooLow,

  /// The guess was above the safe range. Doesn't cost a life.
  /// Tells the player to guess lower.
  tooHigh,

  /// The guess matched the secret. Game over, player wins.
  correct,

  /// The guess was outside the original [minBound, maxBound] range.
  /// Doesn't cost a life. Usually means the player typed wrong.
  outOfBounds;

  /// Human-readable message shown on the feedback card and in the
  /// end-game dialog. No emojis per design rule; words only.
  String get friendlyMessage {
    switch (this) {
      case FeedbackType.tooLow:
        return 'Too low. Guess higher.';
      case FeedbackType.tooHigh:
        return 'Too high. Guess lower.';
      case FeedbackType.correct:
        return 'Correct. You guessed the secret.';
      case FeedbackType.outOfBounds:
        return 'Out of range. Try a number in the safe range.';
    }
  }

  /// Short label shown in the guess history chips. Uppercase, terse.
  String get shortLabel {
    switch (this) {
      case FeedbackType.tooLow:
        return 'LOW';
      case FeedbackType.tooHigh:
        return 'HIGH';
      case FeedbackType.correct:
        return 'WIN';
      case FeedbackType.outOfBounds:
        return 'OOR';
    }
  }

  /// Convert a string from Firestore into a [FeedbackType].
  /// Returns null if the value is unknown or null (the caller decides
  /// what to render for "no feedback yet").
  static FeedbackType? fromString(String? value) {
    if (value == null) return null;
    return FeedbackType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => FeedbackType.outOfBounds,
    );
  }
}
