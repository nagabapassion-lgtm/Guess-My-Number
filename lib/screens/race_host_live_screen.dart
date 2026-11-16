import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/race_controller.dart';
import '../models/race_player.dart';
import '../widgets/animations.dart';
import '../widgets/range_bar.dart';
import '../widgets/ui_components.dart';
import '../screens/home_screen.dart';

/// Host's live view during a RACE. Three states:
///   1. Countdown: shows "3... 2... 1..." with the roster
///   2. Playing: shows all players' live progress (range, lives, last guess, status)
///   3. Finished: shows the winner + final standings + rematch button
class RaceHostLiveScreen extends StatefulWidget {
  const RaceHostLiveScreen({super.key});

  @override
  State<RaceHostLiveScreen> createState() => _RaceHostLiveScreenState();
}

class _RaceHostLiveScreenState extends State<RaceHostLiveScreen> {
  @override
  void initState() {
    super.initState();
    RaceHostController.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    RaceHostController.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final room = RaceHostController.instance.currentRoom;
    if (room == null) {
      // Room was deleted (host left from another path).
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  Future<void> _leaveRoom() async {
    await RaceHostController.instance.leaveRoom();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _rematch() async {
    await RaceHostController.instance.rematch();
    if (!mounted) return;
    // After rematch, the room goes back to 'waiting' — navigate
    // back to the waiting screen.
    Navigator.of(context).pushReplacement(
      AppTheme.pageRoute(const _BackToWaiting()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = RaceHostController.instance.currentRoom;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Race')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.brightCyan),
        ),
      );
    }

    final players = RaceHostController.instance.players;

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Race'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Close room',
            onPressed: _leaveRoom,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentBanner(
              title: room.isCountdown
                  ? 'Get ready...'
                  : room.isPlaying
                      ? 'Race in progress!'
                      : room.isFinished
                          ? 'Race finished!'
                          : 'Race',
              subtitle: room.isCountdown
                  ? 'Race starts in ${RaceHostController.instance.countdownSeconds}...'
                  : room.isPlaying
                      ? 'First to guess ${room.secretNumber == 0 ? "the secret" : "correctly"} wins!'
                      : room.isFinished
                          ? '${room.winnerName ?? "Nobody"} won the race!'
                          : null,
              icon: Icons.flag,
              accent: AppTheme.brightCyan,
            ),
            const SizedBox(height: 16),
            // Player standings
            Text(
              'STANDINGS (${players.length} players)',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.mutedText,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            ...players.map((p) => _PlayerStandingsCard(
                  player: p,
                  isWinner: room.winnerId == p.playerId,
                )),
            const SizedBox(height: 24),
            // Finished: rematch button
            if (room.isFinished) ...[
              FilledButton.icon(
                onPressed: RaceHostController.instance.isWorking ? null : _rematch,
                icon: RaceHostController.instance.isWorking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Rematch (same code)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _leaveRoom,
                child: const Text('Close room'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One player's standings card on the host's live screen. Shows their
/// name, status, range, lives, and last guess.
class _PlayerStandingsCard extends StatelessWidget {
  final RacePlayer player;
  final bool isWinner;

  const _PlayerStandingsCard({
    required this.player,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(player);
    final statusLabel = _statusLabel(player);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWinner ? AppTheme.brightCyan : AppTheme.outlineVariant,
          width: isWinner ? 2 : 1,
        ),
        boxShadow: isWinner
            ? [
                BoxShadow(
                  color: AppTheme.brightCyan.withValues(alpha: 0.20),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWinner
                      ? Icons.emoji_events
                      : player.isGuessing
                          ? Icons.person
                          : player.isLost
                              ? Icons.close
                              : Icons.check,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.playerName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.nearBlack,
                      ),
                    ),
                    Text(
                      '$statusLabel · ${player.guessCount} ${player.guessCount == 1 ? "guess" : "guesses"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              if (player.attemptsLeft > 0 && !player.isFinished)
                LivesIndicator(
                  livesLeft: player.attemptsLeft,
                  totalLives: player.totalLives,
                ),
            ],
          ),
          if (player.lastGuess != null) ...[
            const SizedBox(height: 12),
            RangeBar(
              minBound: 1, // Will use the room's bounds in production; using 1-100 as fallback for display
              maxBound: 100,
              currentMinBound: player.currentMinBound,
              currentMaxBound: player.currentMaxBound,
              lastGuess: player.lastGuess,
              lastFeedback: player.lastFeedback,
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(RacePlayer p) {
    if (p.isWon) return AppTheme.brightCyan;
    if (p.isLost) return AppTheme.crimson;
    if (p.isGuessing) return AppTheme.deepTeal;
    return AppTheme.mutedText;
  }

  String _statusLabel(RacePlayer p) {
    if (p.isWon) return 'Won!';
    if (p.isLost) return 'Out of lives';
    if (p.isGuessing) return 'Guessing...';
    return 'Waiting';
  }
}

/// Helper widget to navigate back to the waiting screen after rematch.
class _BackToWaiting extends StatelessWidget {
  const _BackToWaiting();

  @override
  Widget build(BuildContext context) {
    // Pop back to home, then push the waiting screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context)
          .push(AppTheme.pageRoute(const RaceHostLiveScreen()));
    });
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppTheme.brightCyan),
      ),
    );
  }
}
