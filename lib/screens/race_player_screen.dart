import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/race_controller.dart';
import '../models/race_player.dart';
import '../widgets/animations.dart';
import '../widgets/range_bar.dart';
import '../widgets/ui_components.dart';
import 'home_screen.dart';

/// Player's screen during a RACE. Three states:
///   1. Waiting/Countdown: shows "Race starts in 3... 2... 1..."
///   2. Playing: the player's guessing UI + a sidebar with live standings
///   3. Finished: results screen with winner + standings
///
/// The player's guessing UI is the same as Classic mode (range bar, lives,
/// input field, feedback card) but without the opponent's name — instead,
/// a live standings sidebar shows all players' progress.
class RacePlayerScreen extends StatefulWidget {
  final String code;

  const RacePlayerScreen({super.key, required this.code});

  @override
  State<RacePlayerScreen> createState() => _RacePlayerScreenState();
}

class _RacePlayerScreenState extends State<RacePlayerScreen> {
  final _guessController = TextEditingController();
  bool _endDialogShown = false;

  @override
  void initState() {
    super.initState();
    RacePlayerController.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _guessController.dispose();
    RacePlayerController.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final room = RacePlayerController.instance.currentRoom;
    if (room == null) {
      // Room was deleted by the host.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The host closed the race.')),
      );
      Navigator.of(context).pushReplacement(
        AppTheme.pageRoute(const HomeScreen()),
      );
      return;
    }
    // Show end dialog when race finishes.
    if (room.isFinished && !_endDialogShown) {
      _endDialogShown = true;
      _showResultsDialog();
    }
    setState(() {});
  }

  void _showResultsDialog() {
    final room = RacePlayerController.instance.currentRoom;
    if (room == null) return;
    final myPlayer = RacePlayerController.instance.myPlayer;
    final iWon = room.winnerId != null &&
        myPlayer != null &&
        room.winnerId == myPlayer.playerId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RaceResultsDialog(
        winnerName: room.winnerName ?? 'Nobody',
        isWinner: iWon,
        revealedSecret: room.revealedSecret ?? room.secretNumber,
        myGuessCount: myPlayer?.guessCount ?? 0,
        onLeave: () {
          Navigator.of(context).pop();
          RacePlayerController.instance.leaveRoom();
          Navigator.of(context).pushReplacement(
            AppTheme.pageRoute(const HomeScreen()),
          );
        },
      ),
    );
  }

  Future<void> _submitGuess() async {
    FocusScope.of(context).unfocus();
    final value = int.tryParse(_guessController.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type a whole number.')),
      );
      return;
    }
    HapticFeedback.selectionClick();
    await RacePlayerController.instance.submitGuess(value);
    _guessController.clear();
  }

  Future<void> _leaveRace() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave the race?'),
        content: const Text(
          'You will be removed from this race. You cannot rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await RacePlayerController.instance.leaveRoom();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      AppTheme.pageRoute(const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = RacePlayerController.instance.currentRoom;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Race')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.brightCyan),
        ),
      );
    }

    final myPlayer = RacePlayerController.instance.myPlayer;
    final players = RacePlayerController.instance.players;
    final amOut = myPlayer?.isLost == true || myPlayer?.isOut == true;

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Race'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Leave race',
            onPressed: _leaveRace,
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
                  ? 'Get ready!'
                  : room.isPlaying
                      ? amOut
                          ? 'You are out!'
                          : 'Race in progress!'
                      : room.isFinished
                          ? 'Race finished!'
                          : 'Waiting for host...',
              subtitle: room.isCountdown
                  ? 'Race starts in ${RaceHostController.instance.countdownSeconds}...'
                  : room.isPlaying
                      ? amOut
                          ? 'Watch the others finish the race.'
                          : 'Guess the secret number! First correct wins.'
                      : null,
              icon: Icons.flag,
              accent: AppTheme.brightCyan,
            ),
            const SizedBox(height: 16),
            // Countdown overlay
            if (room.isCountdown)
              Container(
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                child: Text(
                  '${RaceHostController.instance.countdownSeconds}',
                  style: const TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brightCyan,
                    height: 1.0,
                  ),
                ),
              )
            else if (room.isPlaying || room.isFinished) ...[
              // My range bar (if I'm still guessing)
              if (myPlayer != null && !amOut) ...[
                RangeBar(
                  minBound: room.minBound,
                  maxBound: room.maxBound,
                  currentMinBound: myPlayer.currentMinBound,
                  currentMaxBound: myPlayer.currentMaxBound,
                  lastGuess: myPlayer.lastGuess,
                  lastFeedback: myPlayer.lastFeedback,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'LIVES LEFT',
                        value: '${myPlayer.attemptsLeft}',
                        icon: Icons.favorite,
                        accent: AppTheme.crimson,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LivesIndicator(
                    livesLeft: myPlayer.attemptsLeft,
                    totalLives: myPlayer.totalLives,
                  ),
                ),
                const SizedBox(height: 20),
                _GuessInputCard(
                  controller: _guessController,
                  enabled: myPlayer.isGuessing && !room.isFinished,
                  onSubmit: _submitGuess,
                  amOut: amOut,
                ),
              ],
              const SizedBox(height: 20),
              // Live standings sidebar (all players' progress)
              Text(
                'LIVE STANDINGS',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppTheme.mutedText,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              ...players.map((p) => _StandingsRow(
                    player: p,
                    isMe: p.playerId == myPlayer?.playerId,
                    isWinner: room.winnerId == p.playerId,
                  )),
            ] else ...[
              // Waiting for host to start
              Container(
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.hourglass_empty,
                        size: 48,
                        color: AppTheme.mutedText.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Waiting for the host to start the race...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mutedText,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The guess input card. Reuses the styling from the Classic player screen.
class _GuessInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;
  final bool amOut;

  const _GuessInputCard({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
    required this.amOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ENTER YOUR GUESS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: amOut
                  ? 'You are out of the race'
                  : 'Type a number and submit',
              prefixIcon: const Icon(Icons.edit, color: AppTheme.mutedText),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: RacePlayerController.instance,
            builder: (context, _) {
              final controller2 = RacePlayerController.instance;
              return ScaleTap(
                onTap: controller2.isSubmitting || !enabled
                    ? null
                    : onSubmit,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: enabled
                          ? [AppTheme.brightCyan, AppTheme.deepTeal]
                          : [AppTheme.mutedText, AppTheme.mutedText],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: controller2.isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            amOut ? 'Out of race' : 'Submit Guess',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
          // Error message
          ListenableBuilder(
            listenable: RacePlayerController.instance,
            builder: (context, _) {
              final err = RacePlayerController.instance.errorMessage;
              if (err == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  err,
                  style: const TextStyle(
                    color: AppTheme.crimson,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One row in the live standings. Shows the player's name, status,
/// current range, lives, and last guess.
class _StandingsRow extends StatelessWidget {
  final RacePlayer player;
  final bool isMe;
  final bool isWinner;

  const _StandingsRow({
    required this.player,
    required this.isMe,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.brightCyan.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner
              ? AppTheme.brightCyan
              : isMe
                  ? AppTheme.brightCyan.withValues(alpha: 0.30)
                  : AppTheme.outlineVariant,
          width: isWinner ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
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
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${player.playerName} (you)' : player.playerName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.nearBlack,
                  ),
                ),
                Text(
                  '${player.rangeText} · ${player.attemptsLeft} ${player.attemptsLeft == 1 ? "life" : "lives"}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedText,
                  ),
                ),
              ],
            ),
          ),
          if (player.lastGuess != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${player.lastGuess}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor() {
    if (player.isWon) return AppTheme.brightCyan;
    if (player.isLost) return AppTheme.crimson;
    if (player.isGuessing) return AppTheme.deepTeal;
    return AppTheme.mutedText;
  }
}

/// The results dialog shown when the race finishes.
class _RaceResultsDialog extends StatelessWidget {
  final String winnerName;
  final bool isWinner;
  final int revealedSecret;
  final int myGuessCount;
  final VoidCallback onLeave;

  const _RaceResultsDialog({
    required this.winnerName,
    required this.isWinner,
    required this.revealedSecret,
    required this.myGuessCount,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headlineColor = isWinner ? AppTheme.brightCyan : AppTheme.crimson;
    final headline = isWinner ? 'You won!' : 'You lost!';
    final detail = isWinner
        ? 'You guessed the secret in $myGuessCount ${myGuessCount == 1 ? "try" : "tries"}.'
        : '$winnerName won the race.';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: headlineColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWinner ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                color: headlineColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              headline,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: headlineColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppTheme.mutedText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.offWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.outlineVariant, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Secret was ',
                    style: TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '$revealedSecret',
                    style: AppTheme.inviteCodeStyle(
                        size: 24, color: AppTheme.nearBlack),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onLeave,
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
