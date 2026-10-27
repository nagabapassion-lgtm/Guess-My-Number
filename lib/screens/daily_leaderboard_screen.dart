import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/daily_challenge_service.dart';
import '../widgets/animations.dart';

/// Today's Daily Challenge leaderboard.
///
/// Shows the top 50 entries (fewest guesses first, time as the
/// tie-breaker) in real time - new submissions appear live as other
/// players finish their games. The player's own entry is highlighted
/// when present.
///
/// Error handling: a failed read (most commonly a permission-denied
/// caused by missing firestore.rules deployment) is NOT reported as a
/// connectivity problem. We show a specific "couldn't load" message
/// with a Retry button that re-subscribes to the stream.
class DailyLeaderboardScreen extends StatefulWidget {
  const DailyLeaderboardScreen({super.key});

  @override
  State<DailyLeaderboardScreen> createState() =>
      _DailyLeaderboardScreenState();
}

class _DailyLeaderboardScreenState extends State<DailyLeaderboardScreen> {
  final _service = DailyChallengeService();

  /// Held in state so the Retry button can swap in a fresh stream.
  /// Firestore's `.snapshots()` does NOT auto-retry permission-denied
  /// errors, so after the user (or the developer) fixes the cause we
  /// recreate the subscription on demand.
  late Stream<List<DailyLeaderboardEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchTodayTop();
  }

  void _retry() {
    setState(() {
      // watchTodayTop() returns a brand-new Stream; assigning it to
      // _stream triggers StreamBuilder.didUpdateWidget, which
      // cancels the old subscription and opens a new one.
      _stream = _service.watchTodayTop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _todayLabel();

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Daily Leaderboard'),
      ),
      body: StreamBuilder<List<DailyLeaderboardEntry>>(
        stream: _stream,
        builder: (context, snapshot) {
          // 1. Initial loading - no data yet, still waiting on the
          //    first snapshot. (Subsequent rebuilds while the stream
          //    is active have hasData == true and skip this branch.)
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            );
          }

          // 2. Error - permission-denied, network, expired auth,
          //    etc. We deliberately do NOT say "check your internet"
          //    here: the most common cause in practice is a missing
          //    firestore.rules deployment, which has nothing to do
          //    with the user's connection. The Retry button lets
          //    them recover once the rules are deployed.
          if (snapshot.hasError) {
            return _MessageCard(
              icon: Icons.error_outline,
              text: "Couldn't load the leaderboard. Tap to retry.",
              onRetry: _retry,
            );
          }

          final entries = snapshot.data ?? const [];

          // 3. Empty - the collection is reachable but nobody has
          //    posted yet today. This is a happy state, not an error.
          if (entries.isEmpty) {
            return const _MessageCard(
              icon: Icons.emoji_events_outlined,
              text: 'Be the first to post today! Win the Daily '
                  'Challenge and your name appears here.',
            );
          }

          // 4. Data - the live leaderboard.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: FadeSlideIn(
                  child: Text(
                    today,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nearBlack,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return FadeSlideIn(
                      delay: Duration(
                          milliseconds: (index * 40).clamp(0, 400)),
                      child: _LeaderboardRow(
                        rank: index + 1,
                        entry: entry,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

/// A single ranked row. Top 3 get medal styling; the rest are plain.
class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final DailyLeaderboardEntry entry;

  const _LeaderboardRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop3 = rank <= 3;

    final Color medalColor;
    switch (rank) {
      case 1:
        medalColor = const Color(0xFFF5A623); // gold
        break;
      case 2:
        medalColor = const Color(0xFF9AA5B1); // silver
        break;
      case 3:
        medalColor = const Color(0xFFC77D3D); // bronze
        break;
      default:
        medalColor = AppTheme.deepTeal;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTop3
              ? medalColor.withValues(alpha: 0.6)
              : AppTheme.outlineVariant,
          width: isTop3 ? 1.5 : 1,
        ),
        boxShadow: isTop3
            ? [
                BoxShadow(
                  color: medalColor.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop3
                  ? medalColor.withValues(alpha: 0.15)
                  : AppTheme.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(
                color: isTop3
                    ? medalColor.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: isTop3 ? medalColor : AppTheme.mutedText,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Name
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.nearBlack,
              ),
            ),
          ),
          // Guess count + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.guessCount} ${entry.guessCount == 1 ? 'guess' : 'guesses'}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.deepTeal,
                ),
              ),
              if (entry.durationSec > 0)
                Text(
                  '${entry.durationSec}s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen friendly message used for loading errors and empty boards.
///
/// When [onRetry] is non-null, a Retry button is shown below the
/// message. Used by the error state so the player can recover after
/// the underlying cause (typically missing firestore.rules) is fixed.
class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  const _MessageCard({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.mutedText.withValues(alpha: 0.6)),
            const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppTheme.mutedText,
                height: 1.55,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.deepTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
