import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reads and writes the user's game history at /users/{uid}/games/{gameId}.
///
/// Schema:
///   users/{uid}/games/{gameId}:
///     mode:          string ("multiplayer" | "solo_daily" | "solo_practice")
///     role:          string ("host" | "player" | "solo")
///     opponentName:  string — the other player's name (or "Daily Challenge" / "Practice")
///     secretNumber:  int
///     guessCount:    int — how many guesses the player made
///     result:        string ("won" | "lost")
///     durationSec:   int
///     playedAt:      timestamp
///
/// Each completed game writes ONE record per user. Multiplayer games
/// write two records total (one for the host, one for the player) —
/// each in their own /users/{uid}/games/ subcollection.
///
/// The gameId is deterministic (room_id + round for multiplayer, date
/// for daily, timestamp for practice) so calling recordGame() twice
/// for the same game is a no-op (the second write overwrites with
/// identical data).
class GameHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Record a completed game. Silently skips if the user is not
  /// signed in (guests don't get game history). Silently catches
  /// errors so a failed history write never breaks the game flow.
  ///
  /// The gameId must be deterministic so duplicate calls (e.g. from
  /// a retry) don't create duplicate records. Use:
  ///   - Multiplayer: "mp_${roomId}_round_${round}"
  ///   - Daily: "daily_${dateStr}"
  ///   - Practice: "practice_${timestampInMillis}"
  Future<void> recordGame({
    required String gameId,
    required String mode,
    required String role,
    required String opponentName,
    required int secretNumber,
    required int guessCount,
    required String result,
    required int durationSec,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return; // guests don't get history

    try {
      final ref = _db
          .collection('users')
          .doc(user.uid)
          .collection('games')
          .doc(gameId);

      await ref.set({
        'mode': mode,
        'role': role,
        'opponentName': opponentName,
        'secretNumber': secretNumber,
        'guessCount': guessCount,
        'result': result,
        'durationSec': durationSec,
        'playedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort: a failed history write should never break the
      // game flow. The user just won't see this game in their history.
      // We log nothing to the UI — the game already ended normally.
    }
  }

  /// Stream the user's recent games (last 20), newest first.
  /// Returns an empty stream if not signed in.
  Stream<List<GameRecord>> watchRecentGames() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const []);
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('games')
        .orderBy('playedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) => q.docs.map(GameRecord.fromFirestore).toList());
  }

  /// Compute aggregate stats from all the user's games.
  /// Returns empty stats if not signed in or no games played.
  Future<GameStats> getStats() async {
    final user = _auth.currentUser;
    if (user == null) return GameStats.empty;

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('games')
          .get();

      final games = snapshot.docs.map(GameRecord.fromFirestore).toList();
      if (games.isEmpty) return GameStats.empty;

      final total = games.length;
      final wins = games.where((g) => g.result == 'won').length;
      final winRate = total == 0 ? 0 : ((wins / total) * 100).round();

      final wonGames = games.where((g) => g.result == 'won').toList();
      final avgGuesses = wonGames.isEmpty
          ? 0
          : (wonGames.map((g) => g.guessCount).reduce((a, b) => a + b) /
                  wonGames.length)
              .round();

      final bestGuessCount = wonGames.isEmpty
          ? 0
          : wonGames.map((g) => g.guessCount).reduce((a, b) => a < b ? a : b);

      return GameStats(
        totalGames: total,
        wins: wins,
        winRate: winRate,
        avgGuessesPerWin: avgGuesses,
        bestGuessCount: bestGuessCount,
      );
    } catch (_) {
      return GameStats.empty;
    }
  }
}

/// One completed game record. Mirrors the Firestore document at
/// /users/{uid}/games/{gameId}.
class GameRecord {
  final String id;
  final String mode;
  final String role;
  final String opponentName;
  final int secretNumber;
  final int guessCount;
  final String result;
  final int durationSec;
  final DateTime? playedAt;

  const GameRecord({
    required this.id,
    required this.mode,
    required this.role,
    required this.opponentName,
    required this.secretNumber,
    required this.guessCount,
    required this.result,
    required this.durationSec,
    this.playedAt,
  });

  factory GameRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return GameRecord(
      id: doc.id,
      mode: data['mode'] as String? ?? 'unknown',
      role: data['role'] as String? ?? 'unknown',
      opponentName: data['opponentName'] as String? ?? 'Unknown',
      secretNumber: (data['secretNumber'] as num?)?.toInt() ?? 0,
      guessCount: (data['guessCount'] as num?)?.toInt() ?? 0,
      result: data['result'] as String? ?? 'lost',
      durationSec: (data['durationSec'] as num?)?.toInt() ?? 0,
      playedAt: (data['playedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// True if the player won this game.
  bool get isWin => result == 'won';

  /// Human-readable label for the game mode.
  String get modeLabel {
    switch (mode) {
      case 'multiplayer':
        return 'Multiplayer';
      case 'solo_daily':
        return 'Daily Challenge';
      case 'solo_practice':
        return 'Practice';
      default:
        return 'Game';
    }
  }

  /// Icon for the game mode.
  String get modeIcon {
    switch (mode) {
      case 'multiplayer':
        return '👥';
      case 'solo_daily':
        return '🏆';
      case 'solo_practice':
        return '🎯';
      default:
        return '🎮';
    }
  }
}

/// Aggregate stats computed from the user's game history.
class GameStats {
  final int totalGames;
  final int wins;
  final int winRate; // percentage 0-100
  final int avgGuessesPerWin;
  final int bestGuessCount;

  const GameStats({
    required this.totalGames,
    required this.wins,
    required this.winRate,
    required this.avgGuessesPerWin,
    required this.bestGuessCount,
  });

  static const empty = GameStats(
    totalGames: 0,
    wins: 0,
    winRate: 0,
    avgGuessesPerWin: 0,
    bestGuessCount: 0,
  );

  int get losses => totalGames - wins;
  bool get hasGames => totalGames > 0;
}
