import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_config.dart';
import '../models/feedback_type.dart';
import '../models/game_phase.dart';
import '../models/game_room.dart';
import '../models/race_player.dart';
import 'game_rules.dart';

/// All Firestore reads and writes for RACE MODE rooms go through here.
///
/// This is a separate service from [RoomService] (which handles Classic
/// 1v1 mode). The two modes have fundamentally different state machines
/// and schemas:
///   - Classic: single playerId on the room doc, turn-based, won/lost
///   - Race: players subcollection (2-5 players), simultaneous, finished
///
/// Keeping them separate means:
///   1. We don't risk breaking Classic mode with race-specific bugs.
///   2. Each service is optimized for its own flow.
///   3. The Classic mode code stays simple (no race conditionals everywhere).
///
/// Race flow:
///   1. Host creates race room (phase=waiting, mode='race', maxPlayers set)
///   2. Players join (each adds a doc to players subcollection)
///   3. Host taps Start → phase=countdown (3-second timer on host client)
///   4. After 3 seconds, host flips phase=playing (all players start guessing)
///   5. Players guess simultaneously. Each guess is processed atomically:
///      - If correct: that player wins, room flips to phase=finished
///      - If wrong: player's range narrows + loses a life
///      - If player runs out of lives: player status=lost (race continues)
///   6. When someone wins (or all players are out), phase=finished
///   7. Host can rematch (new round, same code) or close the room
class RaceRoomService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get roomsRef =>
      _db.collection('rooms');

  /// Create a new race room. The host picks the range, secret, and max
  /// players (2-5). The room starts in 'waiting' phase — players can
  /// join with the 6-char code.
  ///
  /// Returns the created room (with the generated code).
  Future<GameRoom> createRaceRoom({
    required String hostId,
    required String hostName,
    required int secretNumber,
    required int minBound,
    required int maxBound,
    required int maxPlayers,
  }) async {
    if (maxPlayers < 2 || maxPlayers > 5) {
      throw ArgumentError('maxPlayers must be between 2 and 5');
    }

    String code;
    int attempts = 0;
    do {
      code = GameRules.generateRoomCode();
      attempts++;
      if (attempts > 10) {
        throw Exception('Could not generate a unique room code.');
      }
    } while (await _roomExists(code));

    final newRoom = GameRoom(
      id: code,
      hostId: hostId,
      hostName: hostName,
      phase: GamePhase.waiting,
      minBound: minBound,
      maxBound: maxBound,
      currentMinBound: minBound,
      currentMaxBound: maxBound,
      attemptsLeft: GameConfig.defaultLives,
      secretNumber: secretNumber,
      round: 1,
      mode: 'race',
      maxPlayers: maxPlayers,
    );

    await roomsRef.doc(code).set(newRoom.toCreateMap());
    return newRoom;
  }

  Future<bool> _roomExists(String code) async {
    final snapshot = await roomsRef.doc(code).get();
    return snapshot.exists;
  }

  /// Read a race room once. Returns null if the code doesn't exist.
  Future<GameRoom?> getRaceRoom(String code) async {
    final snapshot = await roomsRef.doc(code).get();
    if (!snapshot.exists) return null;
    return GameRoom.fromFirestore(snapshot.id, snapshot.data()!);
  }

  /// Live stream of race room updates. Used by both host and player
  /// screens to react to phase changes (waiting → countdown → playing →
  /// finished) and winner announcements in real time.
  Stream<GameRoom?> watchRaceRoom(String code) {
    return roomsRef.doc(code).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return GameRoom.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  /// Live stream of all players in a race room, ordered by join time.
  /// Used by the host's live screen to show the roster and by the
  /// player's screen to show the live standings sidebar.
  Stream<List<RacePlayer>> watchRacePlayers(String code) {
    return roomsRef
        .doc(code)
        .collection('players')
        .orderBy('joinedAt', descending: false)
        .snapshots()
        .map((query) =>
            query.docs.map((doc) => RacePlayer.fromFirestore(doc.data())).toList());
  }

  /// A player joins a race room. Creates a doc in the players
  /// subcollection with the player's initial state (full range, full
  /// lives, status='joining').
  ///
  /// THROWS with a friendly message if:
  ///   - The room doesn't exist
  ///   - The room isn't a race room
  ///   - The room isn't in 'waiting' phase (race already started)
  ///   - The room is full (maxPlayers reached)
  ///   - The player already joined (idempotent — re-joining is a no-op)
  Future<void> joinRaceRoom({
    required String code,
    required String playerId,
    required String playerName,
  }) async {
    final roomRef = roomsRef.doc(code);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw Exception('We could not find a room with that code.');
    }

    final room = GameRoom.fromFirestore(roomSnapshot.id, roomSnapshot.data()!);

    if (!room.isRace) {
      throw Exception('This is not a race room.');
    }

    if (room.phase != GamePhase.waiting) {
      throw Exception('This race has already started.');
    }

    // Check if the player already joined (idempotent re-join).
    final playerRef = roomRef.collection('players').doc(playerId);
    final existingPlayer = await playerRef.get();
    if (existingPlayer.exists) {
      // Already joined — no-op. This handles the case where the player
      // refreshes the page or reconnects.
      return;
    }

    // Check if the room is full.
    final playersSnapshot = await roomRef.collection('players').get();
    final currentCount = playersSnapshot.docs.length;
    final max = room.maxPlayers ?? 5;
    if (currentCount >= max) {
      throw Exception('This race room is full ($max/$max players).');
    }

    // Add the player doc.
    final newPlayer = RacePlayer(
      playerId: playerId,
      playerName: playerName,
      currentMinBound: room.minBound,
      currentMaxBound: room.maxBound,
      attemptsLeft: GameConfig.defaultLives,
      totalLives: GameConfig.defaultLives,
      status: 'joining',
      guessCount: 0,
      finishPosition: 0,
    );
    await playerRef.set(newPlayer.toJoinMap());
  }

  /// A player leaves a race room (before or during the race). Removes
  /// their doc from the players subcollection. Best-effort: if the room
  /// was already deleted by the host, this fails silently.
  Future<void> leaveRaceRoom({
    required String code,
    required String playerId,
  }) async {
    try {
      await roomsRef.doc(code).collection('players').doc(playerId).delete();
    } catch (_) {
      // Best-effort: if the room was deleted, ignore.
    }
  }

  /// Host starts the race countdown. Flips the room from 'waiting' to
  /// 'countdown'. The host's client then runs a 3-second timer and
  /// calls [startRace] to flip to 'playing'.
  ///
  /// Also flips all players from 'joining' to 'guessing' status so they
  /// can start guessing as soon as the countdown ends.
  ///
  /// THROWS if:
  ///   - The room doesn't exist or isn't a race room
  ///   - The room isn't in 'waiting' phase (already started)
  ///   - Few than 2 players have joined (need at least 2 for a race)
  Future<void> startCountdown(String code) async {
    final roomRef = roomsRef.doc(code);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw Exception('This room no longer exists.');
    }

    final room = GameRoom.fromFirestore(roomSnapshot.id, roomSnapshot.data()!);

    if (!room.isRace) {
      throw Exception('This is not a race room.');
    }

    if (room.phase != GamePhase.waiting) {
      throw Exception('This race has already started.');
    }

    // Check that at least 2 players have joined.
    final playersSnapshot = await roomRef.collection('players').get();
    if (playersSnapshot.docs.length < 2) {
      throw Exception('Need at least 2 players to start a race.');
    }

    // Flip the room to 'countdown' and all players to 'guessing'.
    final batch = _db.batch();
    batch.update(roomRef, {
      'phase': GamePhase.countdown.name,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    for (final doc in playersSnapshot.docs) {
      batch.update(doc.reference, RacePlayer.startGuessingMap());
    }
    await batch.commit();
  }

  /// Host flips the room from 'countdown' to 'playing' after the
  /// 3-second countdown ends. Players can now submit guesses.
  Future<void> startRace(String code) async {
    final roomRef = roomsRef.doc(code);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw Exception('This room no longer exists.');
    }

    final room = GameRoom.fromFirestore(roomSnapshot.id, roomSnapshot.data()!);

    if (room.phase != GamePhase.countdown) {
      throw Exception('This race is not in the countdown phase.');
    }

    await roomRef.update({
      'phase': GamePhase.playing.name,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Process a player's guess in a race. This is the core race logic.
  ///
  /// Uses a Firestore TRANSACTION to ensure only ONE player can win
  /// the race, even if multiple players guess correctly at the exact
  /// same millisecond. The transaction:
  ///   1. Re-reads the room doc (closes the race window)
  ///   2. If room.phase != 'playing', abort (race not started or ended)
  ///   3. If room.winnerId is already set, abort (someone already won)
  ///   4. Reads the player's doc
  ///   5. If player.status != 'guessing', abort (already won/lost/out)
  ///   6. Computes the feedback (too low / too high / correct)
  ///   7. Updates the player's range + lives + lastGuess + guessCount
  ///   8. If correct: sets room.winnerId, room.winnerName, room.phase=finished,
  ///      player.status=won, player.finishedAt=now
  ///   9. If player ran out of lives: sets player.status=lost
  ///
  /// THROWS with a friendly message if any precondition fails.
  Future<RaceGuessResult> processRaceGuess({
    required String code,
    required String playerId,
    required int guess,
  }) async {
    final roomRef = roomsRef.doc(code);
    final playerRef = roomRef.collection('players').doc(playerId);

    // Run the entire guess processing inside a transaction so the
    // "first to win" check is atomic.
    return await _db.runTransaction((transaction) async {
      // 1. Re-read the room doc inside the transaction.
      final roomSnapshot = await transaction.get(roomRef);
      if (!roomSnapshot.exists) {
        throw Exception('This room no longer exists.');
      }
      final room = GameRoom.fromFirestore(roomSnapshot.id, roomSnapshot.data()!);

      // 2. Room must be in 'playing' phase.
      if (room.phase != GamePhase.playing) {
        throw Exception('This race is not in progress.');
      }

      // 3. If someone already won, abort (race is over).
      if (room.winnerId != null) {
        throw Exception('This race has already been won.');
      }

      // 4. Read the player's doc.
      final playerSnapshot = await transaction.get(playerRef);
      if (!playerSnapshot.exists) {
        throw Exception('You are not in this race.');
      }
      final player = RacePlayer.fromFirestore(playerSnapshot.data()!);

      // 5. Player must be in 'guessing' status.
      if (player.status != 'guessing') {
        throw Exception('You are no longer guessing in this race.');
      }

      // 6. Compute the feedback.
      final feedback = _computeFeedback(room, player, guess);

      // 7. Compute the new player state.
      bool wonRace = false;
      bool knockedOut = false;
      int newMin = player.currentMinBound;
      int newMax = player.currentMaxBound;
      int newLives = player.attemptsLeft;
      String newStatus = player.status;

      if (feedback == FeedbackType.correct) {
        // Player won the race!
        wonRace = true;
        newStatus = 'won';
      } else if (feedback == FeedbackType.tooLow) {
        newMin = guess + 1;
        newLives -= 1;
      } else if (feedback == FeedbackType.tooHigh) {
        newMax = guess - 1;
        newLives -= 1;
      }
      // outOfBounds: no change to range or lives.

      if (newLives <= 0 && !wonRace) {
        newStatus = 'lost';
        knockedOut = true;
      }

      // 8. Update the player's doc.
      final playerUpdate = <String, dynamic>{
        'currentMinBound': newMin,
        'currentMaxBound': newMax,
        'attemptsLeft': newLives < 0 ? 0 : newLives,
        'lastGuess': guess,
        'lastFeedback': feedback.name,
        'status': newStatus,
        'guessCount': player.guessCount + 1,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (wonRace || knockedOut) {
        playerUpdate['finishedAt'] = FieldValue.serverTimestamp();
      }
      transaction.update(playerRef, playerUpdate);

      // 9. If the player won, flip the room to 'finished' and set
      //    the winner fields.
      if (wonRace) {
        transaction.update(roomRef, {
          'phase': GamePhase.finished.name,
          'winnerId': playerId,
          'winnerName': player.playerName,
          'revealedSecret': room.secretNumber,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      // Build the updated player state to return to the caller.
      final updatedPlayer = RacePlayer(
        playerId: player.playerId,
        playerName: player.playerName,
        currentMinBound: newMin,
        currentMaxBound: newMax,
        attemptsLeft: newLives < 0 ? 0 : newLives,
        totalLives: player.totalLives,
        lastGuess: guess,
        lastFeedback: feedback,
        status: newStatus,
        guessCount: player.guessCount + 1,
        joinedAt: player.joinedAt,
        finishedAt: wonRace || knockedOut ? DateTime.now() : null,
        finishPosition: player.finishPosition,
      );

      return RaceGuessResult(
        updatedPlayer: updatedPlayer,
        feedback: feedback,
        wonRace: wonRace,
        knockedOut: knockedOut,
      );
    });
  }

  /// Compute the feedback for a guess. Pure function — no side effects.
  /// Same rules as Classic mode: out of range = outOfBounds (no life lost),
  /// correct = win, too low/high = narrow range + lose a life.
  FeedbackType _computeFeedback(GameRoom room, RacePlayer player, int guess) {
    // Out of original range: doesn't count.
    if (guess < room.minBound || guess > room.maxBound) {
      return FeedbackType.outOfBounds;
    }
    // Out of narrowed range: doesn't count.
    if (guess < player.currentMinBound || guess > player.currentMaxBound) {
      return FeedbackType.outOfBounds;
    }
    // Correct!
    if (guess == room.secretNumber) {
      return FeedbackType.correct;
    }
    // Too low or too high.
    return guess < room.secretNumber ? FeedbackType.tooLow : FeedbackType.tooHigh;
  }

  /// Host closes the race room (deletes it + all player docs).
  /// Used when the host abandons the room or goes home after the race.
  Future<void> deleteRaceRoom(String code) async {
    final batch = _db.batch();
    final players = await roomsRef.doc(code).collection('players').get();
    for (final doc in players.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(roomsRef.doc(code));
    await batch.commit();
  }

  /// Host rematches: starts a new round with the same code. Resets all
  /// player docs to their initial state (full range, full lives, status
  /// back to 'joining' — players must re-confirm they're ready).
  ///
  /// For v1, rematch is simple: bump round, reset room phase to
  /// 'waiting', reset all players. The host then waits for players to
  /// re-join (or auto-keeps them) and starts a new countdown.
  Future<void> rematchRaceRoom(String code) async {
    final roomRef = roomsRef.doc(code);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      throw Exception('This room no longer exists.');
    }

    final room = GameRoom.fromFirestore(roomSnapshot.id, roomSnapshot.data()!);

    if (room.phase != GamePhase.finished) {
      throw Exception('This race has not finished yet.');
    }

    // Reset the room: phase=waiting, round++, clear winner.
    final batch = _db.batch();
    batch.update(roomRef, {
      'phase': GamePhase.waiting.name,
      'round': room.round + 1,
      'winnerId': null,
      'winnerName': null,
      'revealedSecret': null,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Reset all players to their initial state.
    final players = await roomRef.collection('players').get();
    for (final doc in players.docs) {
      final player = RacePlayer.fromFirestore(doc.data());
      batch.update(doc.reference, {
        'currentMinBound': room.minBound,
        'currentMaxBound': room.maxBound,
        'attemptsLeft': player.totalLives,
        'lastGuess': null,
        'lastFeedback': null,
        'status': 'joining',
        'guessCount': 0,
        'finishPosition': 0,
        'finishedAt': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
