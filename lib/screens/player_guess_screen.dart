import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/player_controller.dart';
import '../models/feedback_type.dart';
import '../models/game_room.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'home_screen.dart';

/// The player's live guessing screen.
///
/// Shows the player's current safe range, their remaining lives (heart
/// icons), and the latest feedback message. The guess input field is
/// restricted to digits and disabled while a guess is in flight. The
/// screen reacts to room state changes via [PlayerController].
///
/// Rematch flow (v3 redesign):
///   - When the round ends, the end-game dialog appears (win/lose plus
///     the revealed secret).
///   - When the HOST stages a new round (phase flips to 'rematchOffered'
///     - the host typed a new secret in their new-round dialog), this
///     screen dismisses any stale end dialog and shows the rematch
///     prompt: [Keep Playing] continues with the fresh round
///     (-> acceptRematch, phase -> 'playing'), [Back to Home] vacates
///     the room (-> declineRematch, room -> 'waiting' so the host can
///     invite someone new).
///   - If the host deletes the room (goes home) at any point, the
///     player is automatically sent home with a friendly note.
class PlayerGuessScreen extends StatefulWidget {
  const PlayerGuessScreen({super.key});

  @override
  State<PlayerGuessScreen> createState() => _PlayerGuessScreenState();
}

class _PlayerGuessScreenState extends State<PlayerGuessScreen> {
  final _guessController = TextEditingController();

  bool _endDialogShown = false; // end dialog already shown for this round
  bool _endDialogOpen = false; // end dialog currently on screen
  bool _rematchPromptOpen = false; // rematch prompt currently on screen

  // Host-closed detection: once we have seen a real room, a later
  // null room means the host deleted the document (went home).
  bool _sawRoom = false;

  // True when the player initiated the exit themselves (end dialog,
  // rematch decline, or AppBar leave). Prevents the host-closed handler
  // from double-navigating with a wrong "host closed" message.
  bool _selfLeft = false;

  @override
  void initState() {
    super.initState();
    PlayerController.instance.addListener(_onRoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoomChanged());
  }

  @override
  void dispose() {
    _guessController.dispose();
    PlayerController.instance.removeListener(_onRoomChanged);
    super.dispose();
  }

  void _onRoomChanged() {
    final room = PlayerController.instance.currentRoom;

    // The room document is gone: the host deleted it (went home). If
    // the player did not initiate their own exit, send them home with
    // a friendly note instead of leaving them on a dead screen.
    if (room == null) {
      if (_sawRoom && !_selfLeft && mounted) {
        _sawRoom = false;
        Future.microtask(() {
          PlayerController.instance.leaveRoom();
          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The host closed the game.'),
              duration: Duration(seconds: 3),
            ),
          );
        });
      }
      return;
    }

    if (!mounted) return;
    _sawRoom = true;

    // Detect the host's rematch offer: the phase moved to
    // 'rematchOffered'. Dismiss any stale end dialog (it shows the
    // previous round's result) and show the rematch prompt.
    if (room.isRematchOffered) {
      _endDialogShown = false;
      if (_endDialogOpen) {
        _endDialogOpen = false;
        Navigator.of(context).pop(); // closes the end dialog
      }
      if (!_rematchPromptOpen) {
        _showRematchPrompt(room);
      }
      return;
    }

    // Detect the player's own acceptance: the rematch prompt was up
    // and now the room is 'playing'. Dismiss the prompt - the screen
    // re-renders with the fresh round.
    if (room.isPlaying && _rematchPromptOpen) {
      _rematchPromptOpen = false;
      Navigator.of(context).pop(); // closes the rematch prompt
      return;
    }

    // Normal end-of-round: show the end dialog once.
    if (room.isOver && !_endDialogShown) {
      _endDialogShown = true;
      _showEndGameDialog(room);
    }
  }

  void _showEndGameDialog(GameRoom room) {
    final isWin = room.winner == 'player';
    _endDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EndGameDialog(
        isWin: isWin,
        revealedSecret: room.revealedSecret,
        livesLeft: room.attemptsLeft,
        onBackHome: () {
          // The player chose to leave after the round ended. Vacate the
          // room (it returns to 'waiting' with the same code - the host
          // is sent back to their waiting screen) and go home.
          _selfLeft = true;
          _endDialogOpen = false;
          Navigator.of(context).pop(); // close the end dialog
          PlayerController.instance.leaveRoom();
          Navigator.of(context).pushReplacement(
            AppTheme.pageRoute(const HomeScreen()),
          );
        },
      ),
    );
  }

  void _showRematchPrompt(GameRoom room) {
    _rematchPromptOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RematchPromptDialog(
        hostName: room.hostName,
        onKeepPlaying: () {
          // Stay in the same room. acceptRematch flips phase to
          // 'playing' - the screen's listener will dismiss this prompt
          // and re-render with the fresh round.
          PlayerController.instance.acceptRematch();
        },
        onBackHome: () {
          // Decline: vacate the room (returns it to 'waiting' with the
          // same code so the host can invite someone new) and go home.
          _selfLeft = true;
          PlayerController.instance.declineRematch();
          Navigator.of(context).pop(); // close the prompt
          // Wait for the controller's best-effort vacate, then go home.
          // We don't await - the player's exit must not be blocked by
          // a network blip.
          Navigator.of(context).pushReplacement(
            AppTheme.pageRoute(const HomeScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerController.instance,
      builder: (context, _) {
        final room = PlayerController.instance.currentRoom;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Player View')),
            body: const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppTheme.offWhite,
          appBar: AppBar(
            title: const Text('Your Turn to Guess'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Leave game',
                onPressed: () async {
                  final confirm = await _confirmLeave(context);
                  if (confirm != true) return;
                  _selfLeft = true;
                  PlayerController.instance.leaveRoom();
                  if (!mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccentBanner(
                  title: 'You are playing against ${room.hostName}',
                  subtitle: room.isPlaying
                      ? 'Guess the secret number in '
                            '${room.attemptsLeft} '
                            '${room.attemptsLeft == 1 ? "try" : "tries"} '
                            'or fewer.'
                      : room.isRematchOffered
                          ? 'The host staged a new round. Tap "Keep Playing" to accept.'
                          : 'The round has ended.',
                  icon: Icons.shield_outlined,
                  accent: AppTheme.brightCyan,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'SAFE RANGE',
                        value: room.rangeText,
                        icon: Icons.track_changes,
                        accent: AppTheme.brightCyan,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'LIVES LEFT',
                        value: '${room.attemptsLeft}',
                        icon: Icons.favorite,
                        accent: AppTheme.crimson,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LivesIndicator(livesLeft: room.attemptsLeft),
                ),
                const SizedBox(height: 20),
                _FeedbackCard(room: room),
                const SizedBox(height: 20),
                _GuessInputCard(
                  controller: _guessController,
                  room: room,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmLeave(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text(
          'The room will go back to waiting so someone else can join. '
          'You cannot rejoin this round.',
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

class _FeedbackCard extends StatelessWidget {
  final GameRoom room;

  const _FeedbackCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFeedback = room.lastFeedback != null && room.lastGuess != null;
    final feedbackColor = _colorForFeedback(room.lastFeedback);

    final IconData feedbackIcon;
    if (!hasFeedback) {
      feedbackIcon = Icons.lightbulb_outline;
    } else {
      switch (room.lastFeedback!) {
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
          child: SizeTransition(
            sizeFactor: anim,
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_FeedbackKey(room)),
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
                      'You guessed ${room.lastGuess}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    hasFeedback
                        ? room.lastFeedback!.friendlyMessage
                        : 'Take your first guess. Pick a number in the safe range below.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: hasFeedback ? feedbackColor : AppTheme.nearBlack,
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

/// A simple key for the feedback card so [AnimatedSwitcher] knows when
/// to re-trigger the entrance animation.
String _FeedbackKey(GameRoom room) {
  return '${room.lastGuess ?? 'none'}-${room.lastFeedback?.name ?? 'none'}';
}

class _GuessInputCard extends StatelessWidget {
  final TextEditingController controller;
  final GameRoom room;

  const _GuessInputCard({
    required this.controller,
    required this.room,
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
            enabled: room.isPlaying,
            decoration: InputDecoration(
              hintText: room.isOver
                  ? 'The round has ended'
                  : room.isRematchOffered
                      ? 'Waiting for you to accept the new round'
                      : 'Between ${room.currentMinBound} and ${room.currentMaxBound}',
              prefixIcon: const Icon(Icons.edit, color: AppTheme.mutedText),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: PlayerController.instance,
            builder: (context, _) {
              final controller2 = PlayerController.instance;
              return ScaleTap(
                onTap: controller2.isSubmitting || !room.isPlaying
                    ? null
                    : () => _submit(context),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: room.isPlaying
                          ? [AppTheme.brightCyan, AppTheme.deepTeal]
                          : [AppTheme.mutedText, AppTheme.mutedText],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: room.isPlaying
                        ? [
                            BoxShadow(
                              color: AppTheme.brightCyan.withValues(alpha: 0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
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
                            room.isOver
                                ? 'Round over'
                                : room.isRematchOffered
                                    ? 'Accept the new round above'
                                    : 'Submit Guess',
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
          ListenableBuilder(
            listenable: PlayerController.instance,
            builder: (context, _) {
              final err = PlayerController.instance.errorMessage;
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

  Future<void> _submit(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final value = int.tryParse(controller.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type a whole number.')),
      );
      return;
    }
    await PlayerController.instance.submitGuess(value);
    controller.clear();
  }
}

/// The player's end-of-round dialog: win/lose plus the revealed secret.
/// Only offers "Back to Home" - if the host stages a new round while
/// this dialog is up, the screen's listener dismisses it and shows the
/// rematch prompt instead.
class _EndGameDialog extends StatefulWidget {
  final bool isWin;
  final int? revealedSecret;
  final int livesLeft;
  final VoidCallback onBackHome;

  const _EndGameDialog({
    required this.isWin,
    required this.revealedSecret,
    required this.livesLeft,
    required this.onBackHome,
  });

  @override
  State<_EndGameDialog> createState() => _EndGameDialogState();
}

class _EndGameDialogState extends State<_EndGameDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    )..forward();
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color headlineColor =
        widget.isWin ? AppTheme.brightCyan : AppTheme.crimson;
    final String headline = widget.isWin ? 'You won!' : 'You lost!';
    final IconData headlineIcon = widget.isWin
        ? Icons.emoji_events
        : Icons.sentiment_very_dissatisfied;

    final String detail = widget.isWin
        ? 'You guessed the secret number with ${widget.livesLeft} lives left.'
        : 'You ran out of lives.';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: FadeTransition(
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
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: headlineColor,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.mutedText,
                        height: 1.5,
                      ),
                ),
                if (widget.revealedSecret != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.offWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.outlineVariant, width: 1),
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
                          '${widget.revealedSecret}',
                          style: AppTheme.inviteCodeStyle(
                              size: 24, color: AppTheme.nearBlack),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onBackHome,
                    child: const Text('Back to Home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The rematch prompt (v3 redesign): the host staged a new round with a
/// new secret. The player chooses to keep playing (-> acceptRematch,
/// phase -> 'playing', the screen's listener dismisses this prompt and
/// re-renders with the fresh round) or to go home (-> declineRematch,
/// the room vacates back to 'waiting' with the same code so the host
/// can invite someone new).
///
/// Industry precedent: chess.com and Lichess use the same "rematch
/// offer pending" pattern for 1v1 games - the new round only starts
/// after the opponent explicitly accepts.
class _RematchPromptDialog extends StatefulWidget {
  final String hostName;
  final VoidCallback onKeepPlaying;
  final VoidCallback onBackHome;

  const _RematchPromptDialog({
    required this.hostName,
    required this.onKeepPlaying,
    required this.onBackHome,
  });

  @override
  State<_RematchPromptDialog> createState() => _RematchPromptDialogState();
}

class _RematchPromptDialogState extends State<_RematchPromptDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    )..forward();
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: PlayerController.instance,
      builder: (context, _) {
        final working = PlayerController.instance.isRematchWorking;
        final err = PlayerController.instance.errorMessage;

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: FadeTransition(
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
                        color: AppTheme.brightCyan.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.autorenew,
                        color: AppTheme.brightCyan,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'New Round!',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.nearBlack,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.hostName} staged a new round with a new '
                      'secret number. Same room, no new code needed. '
                      'Do you want to keep playing?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppTheme.mutedText,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: err == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(err),
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                err,
                                style: const TextStyle(
                                  color: AppTheme.crimson,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: working ? null : widget.onBackHome,
                            child: const Text('Back to Home'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: working ? null : widget.onKeepPlaying,
                            child: working
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Keep Playing'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
