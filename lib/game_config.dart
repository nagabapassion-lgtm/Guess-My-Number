/// Game configuration constants.
///
/// Centralizes all the "magic numbers" of the game so they can be tuned in
/// one place. Designed to be extensible: future versions can load these from
/// Firestore or from a user profile without changing call sites.
class GameConfig {
  GameConfig._(); // prevent instantiation

  /// Default lower bound the host sees when the setup screen opens.
  /// The host can change this freely.
  static const int defaultMinBound = 1;

  /// Default upper bound the host sees when the setup screen opens.
  /// The host can change this freely.
  static const int defaultMaxBound = 100;

  /// How many wrong guesses the player is allowed before they lose.
  static const int defaultLives = 5;

  /// Length of the human-readable invite code shown to the host.
  /// 6 characters is short enough to read aloud over a phone call
  /// and long enough to avoid frequent collisions.
  static const int roomCodeLength = 6;

  /// Alphabet used for invite codes. Ambiguous characters are removed
  /// so friends cannot misread them: no I, O, 0, or 1.
  static const String roomCodeAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // ------------------------------------------------------------------
  // Solo mode (vs the computer)
  // ------------------------------------------------------------------

  /// Daily Challenge range. Wider than the multiplayer default so a
  /// once-a-day brain teaser feels substantial: 1 to 1000 with 7 lives
  /// means an average solver needs ~10 guesses (binary search), so
  /// winning inside 7 lives takes real skill but is more forgiving
  /// than 5 lives for new players.
  static const int dailyChallengeMin = 1;
  static const int dailyChallengeMax = 1000;
  static const int dailyChallengeLives = 7;

  /// Practice mode defaults (the player can override these freely).
  static const int practiceDefaultMin = 1;
  static const int practiceDefaultMax = 100;
  static const int practiceDefaultLives = 5;

  /// How many leaderboard rows the daily challenge screen loads.
  /// Kept small to stay well inside the Firestore free tier.
  static const int dailyLeaderboardLimit = 50;
}
