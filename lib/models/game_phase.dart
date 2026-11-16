/// All possible phases a game room can be in.
///
/// Stored as a name string in Firestore (e.g. "waiting"), parsed back into
/// this enum when read. Keeping it an enum (instead of raw strings) makes
/// the rest of the code type-safe and lets the compiler catch typos.
///
/// Two modes share this enum:
///   - Classic (1v1): waiting → playing → won/lost → rematchOffered
///   - Race (2-5 players): waiting → countdown → playing → finished
///
/// The `mode` field on the room doc determines which phases are valid.
/// Classic rooms never use `countdown` or `finished`. Race rooms never
/// use `won`, `lost`, or `rematchOffered`.
enum GamePhase {
  /// Host has created the room but no player has joined yet.
  /// Used by both Classic and Race modes.
  waiting,

  /// Player has joined and is actively guessing.
  /// Classic: 1 player is guessing. Race: all players are guessing
  /// simultaneously.
  playing,

  /// Classic only: Player guessed the secret correctly. Player wins,
  /// host loses.
  won,

  /// Classic only: Player ran out of lives. Host wins, player loses.
  lost,

  /// Classic only: Host offered a new round by entering a new secret
  /// number. The room is paused until the player accepts or declines.
  rematchOffered,

  /// Race only: Host tapped "Start Race". A 3-second countdown is
  /// running before the race actually begins. This gives all joined
  /// players a fair start — without it, the first player to join
  /// would start guessing before others.
  ///
  /// During this phase:
  ///   - Players see "Race starts in 3... 2... 1..."
  ///   - Guesses are rejected (processRaceGuess checks for 'playing')
  ///   - The host's screen shows the countdown
  ///   - After 3 seconds, the host's client flips phase to 'playing'
  countdown,

  /// Race only: Someone won the race (first to guess correctly), OR
  /// all players ran out of lives with no winner. The room is over.
  ///
  /// During this phase:
  ///   - All players see the results screen (winner, standings,
  ///     revealed secret)
  ///   - Guesses are rejected
  ///   - The host can rematch (creates a new round) or close the room
  finished;

  /// Human-readable label for status displays.
  /// No emojis per design rule; words only.
  String get friendlyName {
    switch (this) {
      case GamePhase.waiting:
        return 'Waiting for players to join';
      case GamePhase.playing:
        return 'Game in progress';
      case GamePhase.won:
        return 'Player won the round';
      case GamePhase.lost:
        return 'Player lost the round';
      case GamePhase.rematchOffered:
        return 'Host offered a new round';
      case GamePhase.countdown:
        return 'Race starting...';
      case GamePhase.finished:
        return 'Race finished';
    }
  }

  /// Convert a string from Firestore into a [GamePhase].
  /// Falls back to [waiting] if the value is unknown or null.
  /// This makes the app resilient to schema additions in v2.
  static GamePhase fromString(String? value) {
    if (value == null) return GamePhase.waiting;
    return GamePhase.values.firstWhere(
      (phase) => phase.name == value,
      orElse: () => GamePhase.waiting,
    );
  }
}
