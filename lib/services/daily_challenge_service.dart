import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../game_config.dart';
import 'bot_game_engine.dart';

/// Reads and writes the Daily Challenge leaderboard.
///
/// Schema:
///   dailyChallenge/{dateStr}/entries/{uid}
///     uid:          string    - Firebase Auth UID of the player
///     displayName: string    - name typed at submit time
///     guessCount:   number    - fewer is better
///     durationSec:  number    - how long the win took (tie-breaker)
///     submittedAt:  timestamp
///
/// The daily document (e.g. dailyChallenge/2026-10-23) has no fields of
/// its own - the entries subcollection is the whole story. This keeps
/// reads cheap: we only ever query the subcollection, ordered by
/// guessCount, limited to the top 50.
class DailyChallengeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sign in anonymously (reuses the existing session when present) so
  /// every submission has a uid. Safe to call repeatedly - if a user
  /// is already signed in, this returns the same user.
  Future<String> _ensureUid() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      user = credential.user;
    }
    if (user == null) {
      throw Exception('Could not sign in. Please try again.');
    }
    return user.uid;
  }

  /// Submit today's winning score. Throws with a friendly message if
  /// the player has already submitted today (entries are immutable -
  /// your first win is your score, Wordle style).
  Future<void> submitScore({
    required String displayName,
    required int guessCount,
    required int durationSec,
  }) async {
    final uid = await _ensureUid();
    final dateStr = dailyChallengeDateKey(DateTime.now());

    final entryRef = _db
        .collection('dailyChallenge')
        .doc(dateStr)
        .collection('entries')
        .doc(uid);

    final existing = await entryRef.get();
    if (existing.exists) {
      throw Exception('You already submitted today. Come back tomorrow.');
    }

    await entryRef.set({
      'uid': uid,
      'displayName': displayName.trim(),
      'guessCount': guessCount,
      'durationSec': durationSec,
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Whether the signed-in player has already submitted today.
  /// Returns false when there is no signed-in user yet (they simply
  /// have not played).
  Future<bool> hasSubmittedToday() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final dateStr = dailyChallengeDateKey(DateTime.now());
    final snapshot = await _db
        .collection('dailyChallenge')
        .doc(dateStr)
        .collection('entries')
        .doc(user.uid)
        .get();
    return snapshot.exists;
  }

  /// The top entries for today, best (fewest guesses) first.
  /// Limited to the configured cap to keep reads inside the free tier.
  ///
  /// We ensure an anonymous uid before subscribing because the
  /// Firestore rules require `request.auth != null` on every read.
  /// On a cold start the app's bootstrap sign-in may not have
  /// completed by the time the leaderboard screen mounts, which
  /// would otherwise surface as a permission-denied error. The
  /// StreamBuilder turns any remaining error (e.g. rules not yet
  /// deployed) into a tappable Retry card - see the screen.
  Stream<List<DailyLeaderboardEntry>> watchTodayTop() async* {
    await _ensureUid();
    final dateStr = dailyChallengeDateKey(DateTime.now());
    yield* _db
        .collection('dailyChallenge')
        .doc(dateStr)
        .collection('entries')
        .orderBy('guessCount')
        .limit(GameConfig.dailyLeaderboardLimit)
        .snapshots()
        .map((query) =>
            query.docs.map(DailyLeaderboardEntry.fromFirestore).toList());
  }

  /// Read the leaderboard once (used for quick checks without a stream).
  Future<List<DailyLeaderboardEntry>> getTodayTop() async {
    await _ensureUid();
    final dateStr = dailyChallengeDateKey(DateTime.now());
    final query = await _db
        .collection('dailyChallenge')
        .doc(dateStr)
        .collection('entries')
        .orderBy('guessCount')
        .limit(GameConfig.dailyLeaderboardLimit)
        .get();
    return query.docs.map(DailyLeaderboardEntry.fromFirestore).toList();
  }
}

/// One row on the daily leaderboard.
class DailyLeaderboardEntry {
  final String uid;
  final String displayName;
  final int guessCount;
  final int durationSec;
  final DateTime? submittedAt;

  const DailyLeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.guessCount,
    required this.durationSec,
    this.submittedAt,
  });

  factory DailyLeaderboardEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return DailyLeaderboardEntry(
      uid: data['uid'] as String? ?? doc.id,
      displayName: data['displayName'] as String? ?? 'Player',
      guessCount: (data['guessCount'] as num?)?.toInt() ?? 0,
      durationSec: (data['durationSec'] as num?)?.toInt() ?? 0,
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
    );
  }
}
