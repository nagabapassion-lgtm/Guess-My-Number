import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../game_config.dart';
import '../models/feedback_type.dart';
import '../services/bot_game_engine.dart';
import '../services/daily_challenge_service.dart';
import '../services/game_history_service.dart';
import '../widgets/animations.dart';
import '../widgets/range_bar.dart';
import '../widgets/ui_components.dart';
import 'daily_leaderboard_screen.dart';

/// Which solo mode is running.
enum SoloMode { daily, practice }

/// The solo game screen: the player guesses against a computer-held
/// secret. Handles both Daily Challenge (fixed range and lives,
/// leaderboard) and Practice (configurable, endless replays).
///
/// The entire game runs on-device. Nothing touches Firestore until the
/// player wins the Daily Challenge and chooses to submit their score.
class SoloGameScreen extends StatefulWidget {
  final SoloMode mode;

  // Practice-only configuration. Ignored in daily mode.
  final int? practiceMin;
  final int? practiceMax;
  final int? practiceLives;

  const SoloGameScreen({
    super.key,
    required this.mode,
    this.practiceMin,
    this.practiceMax,
    this.practiceLives,
  });

  @override
  State<SoloGameScreen> createState() => _SoloGameScreenState();
}

class _SoloGameScreenState extends State<SoloGameScreen> {
  late BotGameEngine _engine;
  final _guessController = TextEditingController();

  // Track when the game started so we can show the duration in the
  // end-game dialog and (for daily) send it with the leaderboard entry.
  late DateTime _startedAt;

  // Daily-mode bookkeeping.
  final _dailyService = DailyChallengeService();
  bool _alreadySubmitted = false;
  bool _checkingSubmitted = true; // loading state for the daily check

  @override
  void initState() {
    super.initState();
    if (widget.mode == SoloMode.daily) {
      // For Daily Challenge: FIRST check if the user has already
      // played today. If they have, show a "you already played" screen
      // instead of starting a new game. This prevents the bug where
      // users could play the daily challenge unlimited times.
      _checkSubmittedThenStart();
    } else {
      // Practice mode: always start a new game (no daily limit).
      _startNewGame();
      _checkingSubmitted = false;
    }
  }

  /// Check if the user has already submitted today's Daily Challenge.
  /// If yes, set _alreadySubmitted = true (the UI shows a "come back
  /// tomorrow" screen instead of the game). If no, start a fresh game.
  Future<void> _checkSubmittedThenStart() async {
    try {
      final submitted = await _dailyService.hasSubmittedToday();
      if (!mounted) return;
      setState(() {
        _alreadySubmitted = submitted;
        _checkingSubmitted = false;
      });
      if (!submitted) {
        // Only start the game if the user hasn't played today.
        _startNewGame();
      }
    } catch (_) {
      // Offline or auth not ready: default to "not submitted yet"
      // and start the game. Submitting will surface a friendly error
      // if it turns out they already have an entry today.
      if (!mounted) return;
      setState(() {
        _alreadySubmitted = false;
        _checkingSubmitted = false;
      });
      _startNewGame();
    }
  }

  void _startNewGame() {
    final bool isDaily = widget.mode == SoloMode.daily;
    final min = isDaily
        ? GameConfig.dailyChallengeMin
        : (widget.practiceMin ?? GameConfig.practiceDefaultMin);
    final max = isDaily
        ? GameConfig.dailyChallengeMax
        : (widget.practiceMax ?? GameConfig.practiceDefaultMax);
    final lives = isDaily
        ? GameConfig.dailyChallengeLives
        : (widget.practiceLives ?? GameConfig.practiceDefaultLives);

    final secret = isDaily
        ? generateDailySecret(DateTime.now(), min: min, max: max)
        : generatePracticeSecret(min: min, max: max);

    _engine = BotGameEngine(
      secret: secret,
      minBound: min,
      maxBound: max,
      lives: lives,
    );
    _startedAt = DateTime.now();
    _guessController.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _guessController.dispose();
    super.dispose();
  }

  void _submitGuess() {
    FocusScope.of(context).unfocus();
    final value = int.tryParse(_guessController.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type a whole number.')),
      );
      return;
    }
    // Light haptic on each guess submission.
    HapticFeedback.selectionClick();
    final wasOver = _engine.state.isOver;
    _engine.processGuess(value);
    _guessController.clear();
    if (!wasOver && _engine.state.isOver) {
      // Record this game in the player's history. Best-effort: errors
      // are caught inside recordGame so they never break the game flow.
      final state = _engine.state;
      final isDaily = widget.mode == SoloMode.daily;
      final gameId = isDaily
          ? 'daily_${dailyChallengeDateKey(DateTime.now())}'
          : 'practice_${DateTime.now().millisecondsSinceEpoch}';
      GameHistoryService().recordGame(
        gameId: gameId,
        mode: isDaily ? 'solo_daily' : 'solo_practice',
        role: 'solo',
        opponentName: isDaily ? 'Daily Challenge' : 'Practice',
        secretNumber: state.secret,
        guessCount: state.guessCount,
        result: state.isWon ? 'won' : 'lost',
        durationSec: DateTime.now().difference(_startedAt).inSeconds,
      );
      // Game just ended: brief delay so the last feedback is visible,
      // then show the end dialog.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showEndDialog();
      });
    }
    setState(() {});
  }

  void _showEndDialog() {
    final state = _engine.state;
    final isWin = state.isWon;
    final isDaily = widget.mode == SoloMode.daily;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SoloEndDialog(
        isWin: isWin,
        isDaily: isDaily,
        secret: state.secret,
        guessCount: state.guessCount,
        durationSec: DateTime.now().difference(_startedAt).inSeconds,
        canSubmit: isDaily && isWin && !_alreadySubmitted,
        onSubmitScore: (name) => _submitScore(name),
        alreadySubmitted: _alreadySubmitted,
        onPlayAgain: isDaily ? null : _startNewGame,
        onViewLeaderboard: isDaily ? _openLeaderboard : null,
      ),
    );
  }

  Future<void> _submitScore(String displayName) async {
    try {
      await _dailyService.submitScore(
        displayName: displayName,
        guessCount: _engine.state.guessCount,
        durationSec: DateTime.now().difference(_startedAt).inSeconds,
      );
      if (mounted) {
        setState(() => _alreadySubmitted = true);
        Navigator.of(context).pop(); // close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Score posted. Check out today\'s leaderboard.'),
          ),
        );
        _openLeaderboard();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
      }
    }
  }

  void _openLeaderboard() {
    Navigator.of(context).push(
      AppTheme.pageRoute(const DailyLeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDaily = widget.mode == SoloMode.daily;

    // Daily Challenge: if we're still checking whether the user has
    // played today, show a loading screen instead of the game.
    if (isDaily && _checkingSubmitted) {
      return Scaffold(
        backgroundColor: AppTheme.offWhite,
        appBar: AppBar(title: const Text('Daily Challenge')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.brightCyan),
        ),
      );
    }

    // Daily Challenge: if the user has already played today, show a
    // "come back tomorrow" screen instead of the game. This prevents
    // the bug where users could play the daily challenge unlimited
    // times by closing the end-game dialog and starting a new game.
    if (isDaily && _alreadySubmitted) {
      return _AlreadyPlayedScreen(
        onViewLeaderboard: _openLeaderboard,
      );
    }

    final state = _engine.state;

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: Text(isDaily ? 'Daily Challenge' : 'Practice'),
        actions: [
          if (!isDaily)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'New practice game',
              onPressed: _startNewGame,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccentBanner(
              title: isDaily
                  ? 'Range ${state.minBound} to ${state.maxBound}'
                  : 'Guess the secret number',
              subtitle: isDaily
                  ? 'Same for everyone today. '
                      '${state.totalLives} lives. Fewer guesses means a better score.'
                  : 'Range ${state.minBound} to ${state.maxBound}. '
                      '${state.totalLives} lives.',
              icon: isDaily ? Icons.calendar_today : Icons.computer,
              accent: AppTheme.brightCyan,
            ),
            const SizedBox(height: 16),
            // Visual range bar (replaces the old text-only StatCard).
            RangeBar(
              minBound: state.minBound,
              maxBound: state.maxBound,
              currentMinBound: state.currentMinBound,
              currentMaxBound: state.currentMaxBound,
              lastGuess: state.lastGuess,
              lastFeedback: state.lastFeedback,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'LIVES LEFT',
                    value: '${state.livesLeft}',
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
                livesLeft: state.livesLeft,
                totalLives: state.totalLives,
              ),
            ),
            const SizedBox(height: 20),
            _SoloFeedbackCard(state: state),
            const SizedBox(height: 20),
            _SoloGuessInput(
              controller: _guessController,
              state: state,
              onSubmit: _submitGuess,
            ),
          ],
        ),
      ),
    );
  }
}

/// The animated feedback card. Reuses the pattern from the multiplayer
/// guess screen: icon + message swap on each new guess.
class _SoloFeedbackCard extends StatelessWidget {
  final BotGameState state;

  const _SoloFeedbackCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFeedback = state.lastFeedback != null && state.lastGuess != null;
    final feedbackColor = _colorForFeedback(state.lastFeedback);

    final IconData feedbackIcon;
    if (!hasFeedback) {
      feedbackIcon = Icons.lightbulb_outline;
    } else {
      switch (state.lastFeedback!) {
        case FeedbackType.correct:
          feedbackIcon = Icons.check_circle;
          break;
        case FeedbackType.tooLow:
          feedbackIcon = Icons.arrow_upward;
          break;
        case FeedbackType.tooHigh:
          feedbackIcon = Icons.arrow_downward;
          break;
        case FeedbackType.outOfBounds:
          feedbackIcon = Icons.error_outline;
          break;
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: anim,
          child: SizeTransition(sizeFactor: anim, child: child),
        );
      },
      child: Container(
        key: ValueKey('${state.lastGuess}-${state.lastFeedback?.name}'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: hasFeedback
              ? feedbackColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasFeedback
                ? feedbackColor.withValues(alpha: 0.30)
                : AppTheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hasFeedback
                    ? feedbackColor.withValues(alpha: 0.15)
                    : AppTheme.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(feedbackIcon, color: feedbackColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasFeedback)
                    Text(
                      'You guessed ${state.lastGuess}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    hasFeedback
                        ? _feedbackMessage(state.lastFeedback!)
                        : 'Take your first guess. Pick a number in the safe range below.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color:
                          hasFeedback ? feedbackColor : AppTheme.nearBlack,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorForFeedback(FeedbackType? feedback) {
  switch (feedback) {
    case FeedbackType.correct:
      return AppTheme.brightCyan;
    case FeedbackType.tooLow:
    case FeedbackType.tooHigh:
      return AppTheme.deepTeal;
    case FeedbackType.outOfBounds:
      return AppTheme.crimson;
    case null:
      return AppTheme.mutedText;
  }
}

/// Friendly on-card message for each feedback type. Kept here (not on the
/// enum) so this file does not depend on whether the v1 FeedbackType has
/// a friendlyMessage getter.
String _feedbackMessage(FeedbackType feedback) {
  switch (feedback) {
    case FeedbackType.correct:
      return 'Bullseye! That\'s the secret.';
    case FeedbackType.tooLow:
      return 'Too low. The secret is higher.';
    case FeedbackType.tooHigh:
      return 'Too high. The secret is lower.';
    case FeedbackType.outOfBounds:
      return 'Out of range. That guess didn\'t count.';
  }
}

/// The guess input card. Disabled once the game is over.
class _SoloGuessInput extends StatelessWidget {
  final TextEditingController controller;
  final BotGameState state;
  final VoidCallback onSubmit;

  const _SoloGuessInput({
    required this.controller,
    required this.state,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
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
          TextField(
            controller: controller,
            enabled: !state.isOver,
            decoration: InputDecoration(
              hintText: state.isOver
                  ? 'Game over'
                  : 'Between ${state.currentMinBound} and ${state.currentMaxBound}',
              prefixIcon: const Icon(Icons.edit, color: AppTheme.mutedText),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 16),
          ScaleTap(
            onTap: state.isOver ? null : onSubmit,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: state.isOver
                      ? [AppTheme.mutedText, AppTheme.mutedText]
                      : [AppTheme.brightCyan, AppTheme.deepTeal],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: state.isOver
                    ? null
                    : [
                        BoxShadow(
                          color: AppTheme.brightCyan.withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  state.isOver ? 'Game over' : 'Submit Guess',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The end-game dialog for solo play.
///
/// Daily + win: offers to post the score to the leaderboard (asks for
/// a display name if the player has not submitted one before).
/// Daily + loss: encourages coming back tomorrow and links to the
/// leaderboard. Practice: Play Again restarts instantly.
class _SoloEndDialog extends StatefulWidget {
  final bool isWin;
  final bool isDaily;
  final int secret;
  final int guessCount;
  final int durationSec;
  final bool canSubmit;
  final bool alreadySubmitted;
  final Future<void> Function(String displayName) onSubmitScore;
  final VoidCallback? onPlayAgain;
  final VoidCallback? onViewLeaderboard;

  const _SoloEndDialog({
    required this.isWin,
    required this.isDaily,
    required this.secret,
    required this.guessCount,
    required this.durationSec,
    required this.canSubmit,
    required this.alreadySubmitted,
    required this.onSubmitScore,
    this.onPlayAgain,
    this.onViewLeaderboard,
  });

  @override
  State<_SoloEndDialog> createState() => _SoloEndDialogState();
}

class _SoloEndDialogState extends State<_SoloEndDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final ConfettiController _confettiController;

  final _nameController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    )..forward();
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    // Confetti: play a 2-second burst when the player wins.
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    if (widget.isWin) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _confettiController.play();
        HapticFeedback.mediumImpact();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _confettiController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color headlineColor =
        widget.isWin ? AppTheme.brightCyan : AppTheme.crimson;
    final String headline =
        widget.isWin ? 'You won!' : 'Out of lives';
    final IconData headlineIcon = widget.isWin
        ? Icons.emoji_events
        : Icons.sentiment_very_dissatisfied;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Confetti overlay — bursts when the player wins.
          if (widget.isWin)
            Positioned(
              top: -10,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: math.pi / 2,
                maxBlastForce: 12,
                minBlastForce: 6,
                emissionFrequency: 0.4,
                numberOfParticles: 18,
                gravity: 0.15,
                blastDirectionality: BlastDirectionality.directional,
                colors: const [
                  AppTheme.deepTeal,
                  AppTheme.brightCyan,
                  Color(0xFFFFD700),
                  Colors.white,
                ],
              ),
            ),
          // The dialog content
          FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
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
                      child: Icon(headlineIcon, color: headlineColor, size: 40),
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
                  widget.isWin
                      ? 'You found the secret in ${widget.guessCount} '
                          '${widget.guessCount == 1 ? 'guess' : 'guesses'} '
                          '(${widget.durationSec}s).'
                      : 'The secret was ${widget.secret}. '
                          'You used all your lives.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.mutedText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // --- Score submission (daily + win only) ---
                if (widget.canSubmit) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Your name for the leaderboard',
                      prefixIcon:
                          Icon(Icons.person_outline, color: AppTheme.mutedText),
                    ),
                    textCapitalization: TextCapitalization.words,
                    maxLength: 20,
                  ),
                  const SizedBox(height: 14),
                  ScaleTap(
                    onTap: _submitting ? null : _onSubmit,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.brightCyan, AppTheme.deepTeal],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Post my score',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (widget.isDaily && widget.alreadySubmitted) ...[
                  Text(
                    'You already posted today. Come back tomorrow.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedText,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // --- Secondary actions ---
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                    if (widget.onViewLeaderboard != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          // Pop the dialog FIRST, then navigate - otherwise
                          // the dialog stays stacked on top of the new route.
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onViewLeaderboard?.call();
                          },
                          child: const Text('Leaderboard'),
                        ),
                      ),
                    ] else if (widget.onPlayAgain != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onPlayAgain?.call();
                          },
                          child: const Text('Play Again'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    await widget.onSubmitScore(name);
    if (mounted) {
      setState(() => _submitting = false);
    }
  }
}

/// Shown when the user opens the Daily Challenge but has already
/// submitted today. Replaces the game screen with a "come back
/// tomorrow" message + a button to view today's leaderboard.
///
/// This is the fix for the bug where users could play the daily
/// challenge unlimited times by closing the end-game dialog and
/// starting a new game from the home screen.
class _AlreadyPlayedScreen extends StatelessWidget {
  final VoidCallback onViewLeaderboard;

  const _AlreadyPlayedScreen({required this.onViewLeaderboard});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(title: const Text('Daily Challenge')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 88,
                height: 88,
                margin: const EdgeInsets.only(bottom: 24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brightCyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.brightCyan,
                  size: 48,
                ),
              ),
              Text(
                'You already played today!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.nearBlack,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The Daily Challenge resets at midnight. Come back '
                'tomorrow for a new puzzle!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppTheme.mutedText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onViewLeaderboard,
                icon: const Icon(Icons.leaderboard, size: 20),
                label: const Text("View today's leaderboard"),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
