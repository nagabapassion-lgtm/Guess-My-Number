/// All possible phases a game room can be in.
///
/// Stored as a name string in Firestore (e.g. "waiting"), parsed back into
/// this enum when read. Keeping it an enum (instead of raw strings) makes
/// the rest of the code type-safe and lets the compiler catch typos.
enum GamePhase {
  /// Host has created the room but no player has joined yet.
  /// UI on host side: show invite code, "waiting" message.
  waiting,

  /// Player has joined and is actively guessing.
  /// Both screens show live game state.
  playing,

  /// Player guessed the secret correctly. Player wins, host loses.
  /// Both screens show a victory dialog for the player.
  won,

  /// Player ran out of lives. Host wins, player loses.
  /// Both screens show a defeat dialog for the player.
  lost,

  /// Host offered a new round by entering a new secret number.
  /// The room is paused in this state until the player either:
  ///   - accepts (phase -> playing, the new round begins), or
  ///   - declines (phase -> waiting, the room is vacated so the
  ///     host can invite someone new with the same code).
  ///
  /// This intermediate phase is what makes the rematch flow race-free:
  ///   - The player cannot submit guesses (RoomService.processPlayerGuess
  ///     rejects any phase that is not 'playing').
  ///   - The host's UI shows "Waiting for player to accept...".
  ///   - Old guesses are filtered out by the `round` counter (no need
  ///     to delete them, which would require a transaction that reads
  ///     a subcollection - impossible in Firestore).
  ///
  /// Industry precedent: chess.com / Lichess use an equivalent "rematch
  /// offer pending" state for 1v1 games where one side must explicitly
  /// opt in before the new round starts.
  rematchOffered;

  /// Human-readable label for status displays.
  /// No emojis per design rule; words only.
  String get friendlyName {
    switch (this) {
      case GamePhase.waiting:
        return 'Waiting for a player to join';
      case GamePhase.playing:
        return 'Game in progress';
      case GamePhase.won:
        return 'Player won the round';
      case GamePhase.lost:
        return 'Player lost the round';
      case GamePhase.rematchOffered:
        return 'Host offered a new round';
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
