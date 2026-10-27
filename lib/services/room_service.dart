import 'package:cloud_firestore/cloud_firestore.dart';

import '../game_config.dart';
import '../models/feedback_type.dart';
import '../models/game_phase.dart';
import '../models/game_room.dart';
import 'game_rules.dart';

/// All Firestore reads and writes for the rooms collection go through here.
///
/// The controllers never touch Firestore directly. This makes the
/// controllers easy to unit-test (substitute a fake RoomService) and
/// keeps the Firestore schema details in one place.
///
/// v4 schema changes from v3:
///   - Added `round` integer field on the room doc.
///   - Each guess doc carries a `round` integer matching the room's
///     round at the time of the guess.
///   - Rematch no longer deletes old guesses - it just bumps `round`.
///     The UI filters guesses by `where('round', '==', room.round)`.
///     Old guess docs stay in Firestore forever (cheap, harmless,
///     invisible to the player because they're filtered out).
///   - This eliminates the v3 bug where `transaction.get(collection)`
///     was used (a hard compile error - Firestore transactions can
///     only read DocumentReferences, not collections).
class RoomService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Underlying collection reference. Exposed for tests and for any
  /// future callers that need to build their own queries.
  CollectionReference<Map<String, dynamic>> get roomsRef =>
      _db.collection('rooms');

  /// Create a new room with the given host settings.
  ///
  /// Generates a unique invite code by retrying until we find one
  /// that does not already exist in Firestore. After 10 failed
  /// attempts we give up (extremely unlikely with 30 characters
  /// and length 6, but kept as a safety net).
  Future<GameRoom> createRoom({
    required String hostId,
    required String hostName,
    required int secretNumber,
    required int minBound,
    required int maxBound,
  }) async {
    String code;
    int attempts = 0;
    do {
      code = GameRules.generateRoomCode();
      attempts++;
      if (attempts > 10) {
        throw Exception(
          'Could not generate a unique room code. Please try again.',
        );
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
    );

    await roomsRef.doc(code).set(newRoom.toCreateMap());
    return newRoom;
  }

  /// Check whether a document exists at /rooms/{code}. Used by
  /// [createRoom] to avoid collisions on the invite code.
  Future<bool> _roomExists(String code) async {
    final snapshot = await roomsRef.doc(code).get();
    return snapshot.exists;
  }

  /// Read a room once. Returns null if the code does not exist.
  Future<GameRoom?> getRoom(String code) async {
    final snapshot = await roomsRef.doc(code).get();
    if (!snapshot.exists) return null;
    return GameRoom.fromFirestore(snapshot.id, snapshot.data()!);
  }

  /// Live stream of room updates. Emits the current room immediately,
  /// then re-emits whenever any field changes in Firestore. Both the
  /// host and player controllers use this to keep their UI in sync.
  Stream<GameRoom?> watchRoom(String code) {
    return roomsRef.doc(code).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return GameRoom.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  /// Atomically claim a waiting room as the joining player.
  ///
  /// Uses a Firestore transaction so that if two players try to join
  /// the same room at the same time, only one succeeds. The other
  /// one will see "Someone else already joined this room."
  ///
  /// Throws with a friendly message if the room does not exist, is
  /// no longer waiting, or already has a player.
  Future<void> joinRoom({
    required String code,
    required String playerId,
    required String playerName,
  }) async {
    await _db.runTransaction((transaction) async {
      final ref = roomsRef.doc(code);
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception(
            'We could not find a room with that code. Please check it and try again.');
      }

      final room = GameRoom.fromFirestore(snapshot.id, snapshot.data()!);

      if (room.phase != GamePhase.waiting) {
        throw Exception('This game has already started or finished.');
      }

      if (room.playerId != null) {
        throw Exception('Someone else already joined this room.');
      }

      transaction.update(ref, {
        'playerId': playerId,
        'playerName': playerName,
        'phase': GamePhase.playing.name,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Process a player's guess and write the resulting state back to
  /// Firestore atomically.
  ///
  /// In the Trust model this runs on the player's device. The host
  /// does not need to be online for the game to progress. The
  /// transaction ensures we never lose a guess or double-decrement
  /// lives.
  ///
  /// Side effects:
  ///   - updates /rooms/{code} with new bounds, lives, lastGuess,
  ///     lastFeedback, and possibly phase/winner/revealedSecret
  ///   - appends a new doc to /rooms/{code}/guesses with the guess,
  ///     the computed feedback, AND the current round number (so
  ///     the UI can filter to the current round).
  Future<void> processPlayerGuess({
    required String code,
    required int guess,
    required String playerId,
  }) async {
    await _db.runTransaction((transaction) async {
      final ref = roomsRef.doc(code);
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception('This room no longer exists.');
      }

      final room = GameRoom.fromFirestore(snapshot.id, snapshot.data()!);

      if (room.phase != GamePhase.playing) {
        throw Exception('This game is not in progress anymore.');
      }

      if (room.playerId != playerId) {
        throw Exception('Only the player can submit guesses for this room.');
      }

      // Compute the result of the guess using pure game rules.
      final result = GameRules.processGuess(room, guess);
      final updated = result.updatedRoom;

      transaction.update(ref, {
        'currentMinBound': updated.currentMinBound,
        'currentMaxBound': updated.currentMaxBound,
        'attemptsLeft': updated.attemptsLeft,
        'lastGuess': guess,
        'lastFeedback': result.feedback.name,
        'phase': updated.phase.name,
        'winner': updated.winner,
        'revealedSecret': updated.revealedSecret,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Append the guess to the history subcollection. Stamping
      // `round` lets the UI filter to the current round via
      // `where('round', '==', room.round)` - no deletes needed.
      final guessRef = ref.collection('guesses').doc();
      final attemptNumber =
          GameConfig.defaultLives - updated.attemptsLeft + 1;
      transaction.set(guessRef, {
        'playerId': playerId,
        'value': guess,
        'feedback': result.feedback.name,
        'attemptNumber': attemptNumber,
        'round': room.round,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  // ====================================================================
  // Rematch flow (v4 redesign with round counter)
  // --------------------------------------------------------------------
  // The v3 design tried to delete old guesses inside a transaction
  // (`transaction.get(collection)`) which is a HARD COMPILE ERROR -
  // Firestore transactions only accept DocumentReference, never
  // CollectionReference. The file never compiled, so reset never ran.
  //
  // The v4 fix: instead of deleting old guesses, bump a `round`
  // counter on the room doc. Each guess carries the round it belongs
  // to. The UI filters by round, so old guesses are invisible.
  //
  // The rematch flow still has two phases (offerRematch -> acceptRematch)
  // because we need the player's explicit consent before the new round
  // starts. The intermediate `rematchOffered` phase makes the flow
  // race-free: the player can't submit guesses during the offer
  // window (processPlayerGuess rejects any phase that's not 'playing').
  //
  //   won/lost ──offerRematch()──> rematchOffered ──acceptRematch()──> playing
  //                                       │
  //                                       └──declineRematch()──> waiting
  // ====================================================================

  /// Host: stage a new round with a fresh secret, then wait for the
  /// player to accept.
  ///
  /// Single transaction on the room doc only (reads a
  /// DocumentReference - allowed in transactions). Bumps `round` by
  /// 1, writes the new secret, restores lives and bounds, flips
  /// phase to 'rematchOffered'. The player must then call
  /// [acceptRematch] to start the round, or [declineRematch] to
  /// return the room to 'waiting'.
  ///
  /// No guesses are deleted - they stay in Firestore with their
  /// original `round` value. The UI filters by current round, so
  /// they're invisible to the player.
  ///
  /// THROWS with a friendly message if any precondition fails.
  Future<void> offerRematch({
    required String code,
    required int newSecret,
    required int minBound,
    required int maxBound,
    required int currentRound,
  }) async {
    final roomRef = roomsRef.doc(code);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(roomRef);

      if (!snapshot.exists) {
        throw Exception('This room no longer exists.');
      }

      final room = GameRoom.fromFirestore(snapshot.id, snapshot.data()!);

      // Precondition 1: only an ENDED round can be reset.
      if (!room.isOver) {
        throw Exception('This room is not ready for a new round.');
      }

      // Precondition 2: the player must still be in the room.
      if (room.playerId == null || room.phase == GamePhase.waiting) {
        throw Exception('The player has already left this room.');
      }

      // Precondition 3: newSecret must be in range.
      if (newSecret < minBound || newSecret > maxBound) {
        throw Exception(
            'The new secret must be between $minBound and $maxBound.');
      }

      // Patch the room doc to a 'rematchOffered' state with the new
      // secret and a bumped round counter. Old guesses stay in
      // Firestore (filtered out by round on the client side).
      transaction.update(roomRef, <String, dynamic>{
        'phase': GamePhase.rematchOffered.name,
        'secretNumber': newSecret,
        'revealedSecret': null,
        'attemptsLeft': GameConfig.defaultLives,
        'currentMinBound': minBound,
        'currentMaxBound': maxBound,
        'lastGuess': null,
        'lastFeedback': null,
        'winner': null,
        'round': currentRound + 1,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Player: accept the offered rematch. Flips the room from
  /// 'rematchOffered' to 'playing'. The host's UI is driven by the
  /// same onSnapshot stream and immediately re-renders.
  ///
  /// Single conditional update - no transaction needed because we
  /// don't need to read first; the Firestore rules enforce that
  /// only the room's current player can make this transition.
  Future<void> acceptRematch({
    required String code,
    required String playerId,
  }) async {
    final ref = roomsRef.doc(code);
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      throw Exception('This room no longer exists.');
    }

    final room = GameRoom.fromFirestore(snapshot.id, snapshot.data()!);

    if (room.phase != GamePhase.rematchOffered) {
      throw Exception('This room is not waiting for a rematch decision.');
    }

    if (room.playerId != playerId) {
      throw Exception('Only the player can accept the rematch.');
    }

    await ref.update({
      'phase': GamePhase.playing.name,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Player: decline the offered rematch. Vacates the room back to
  /// 'waiting' so the host can invite someone new with the same code.
  /// Delegates to [vacateRoom].
  Future<void> declineRematch({
    required String code,
    required int minBound,
    required int maxBound,
  }) async {
    await vacateRoom(code: code, minBound: minBound, maxBound: maxBound);
  }

  /// Return a room to a pristine 'waiting' state with no player, so a
  /// new player can join with the SAME code.
  ///
  /// Called by the PLAYER whenever they leave in any state (mid-game,
  /// after the round ended, or when declining the rematch). The
  /// bounds and lives are restored so whoever joins next gets a
  /// fresh round. The round counter is NOT reset - it keeps
  /// incrementing across rematches so old guesses never collide
  /// with new ones.
  ///
  /// Best-effort by design: callers wrap this in try/catch and never
  /// block the player's exit on it.
  Future<void> vacateRoom({
    required String code,
    required int minBound,
    required int maxBound,
  }) async {
    await roomsRef.doc(code).update({
      'phase': GamePhase.waiting.name,
      'playerId': null,
      'playerName': null,
      'currentMinBound': minBound,
      'currentMaxBound': maxBound,
      'attemptsLeft': GameConfig.defaultLives,
      'lastGuess': null,
      'lastFeedback': null,
      'winner': null,
      'revealedSecret': null,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Stream the guesses subcollection for the CURRENT round only,
  /// ordered oldest-first so the host can render the live history.
  ///
  /// Filters by `round` so old guesses from previous rounds are
  /// invisible. This replaces the v3 pattern of deleting old guesses
  /// on rematch (which was impossible to do atomically).
  Stream<List<GuessRecord>> watchGuesses(String code, int round) {
    return roomsRef
        .doc(code)
        .collection('guesses')
        .where('round', isEqualTo: round)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((query) =>
            query.docs.map(GuessRecord.fromFirestore).toList());
  }

  /// Delete a room and all its guesses (across all rounds). Only
  /// callable by the host (enforced by Firestore security rules).
  /// Used when the host abandons a waiting room or goes home after
  /// a game. Deleting the room is also the signal that sends the
  /// player home: their stream emits null and their screen reacts
  /// gracefully.
  Future<void> deleteRoom(String code) async {
    final batch = _db.batch();
    final guesses = await roomsRef.doc(code).collection('guesses').get();
    for (final doc in guesses.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(roomsRef.doc(code));
    await batch.commit();
  }
}

/// A single entry in the /rooms/{roomId}/guesses subcollection.
///
/// Used by the host's live screen to render the guess history. Not
/// used in the player's flow because the player only needs the
/// latest state.
class GuessRecord {
  final String id;
  final String playerId;
  final int value;
  final FeedbackType feedback;
  final int attemptNumber;
  final int round;
  final DateTime? timestamp;

  const GuessRecord({
    required this.id,
    required this.playerId,
    required this.value,
    required this.feedback,
    required this.attemptNumber,
    required this.round,
    this.timestamp,
  });

  factory GuessRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return GuessRecord(
      id: doc.id,
      playerId: data['playerId'] as String? ?? '',
      value: (data['value'] as num?)?.toInt() ?? 0,
      feedback: FeedbackType.fromString(data['feedback'] as String?) ??
          FeedbackType.outOfBounds,
      attemptNumber: (data['attemptNumber'] as num?)?.toInt() ?? 0,
      round: (data['round'] as num?)?.toInt() ?? 1,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}
