import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/host_controller.dart';
import '../game_config.dart';
import '../models/feedback_type.dart';
import '../models/game_room.dart';
import '../services/game_history_service.dart';
import '../services/room_service.dart';
import '../widgets/animations.dart';
import '../widgets/range_bar.dart';
import '../widgets/ui_components.dart';
import 'host_waiting_screen.dart';

/// The host's live game view.
///
/// Shows everything the host wants to see in real time:
///   - the room code (with a one-tap copy button so it can be re-shared
///     with new players between rounds - the code is preserved across
///     "New Game" resets)
///   - the player's current safe range
///   - the player's remaining lives (heart icons)
///   - the latest guess and its feedback
///   - the full history of guesses the player has made
///
/// Rematch flow (v3 redesign):
///   1. Round ends -> end-game dialog: [Back to Home] or [New Game].
///   2. Host taps "New Game" -> a new-round dialog asks the host to
///      enter a NEW secret number (same range as before).
///   3. On confirm the SAME room is flipped to 'rematchOffered' in
///      place - same code, same player, fresh secret/lives. The old
///      guesses are batch-deleted (safe because no new guesses can
///      land during 'rematchOffered'). The host's dialog switches to
///      "Waiting for player to accept..." mode.
///   4. The player's screen detects the 'rematchOffered' phase and
///      shows them a prompt: [Keep Playing] (-> acceptRematch, phase
///      flips to 'playing') or [Back to Home] (-> declineRematch, room
///      vacates back to 'waiting').
///   5. When the player accepts, the host's dialog auto-dismisses and
///      the live screen re-renders from the controller (fresh round).
///   6. If the player declines or leaves at any point, the room flips
///      back to 'waiting' and this screen automatically returns the
///      host to the waiting screen with the same code so they can
///      invite someone new.
class HostLiveScreen extends StatefulWidget {
  const HostLiveScreen({super.key});

  @override
  State<HostLiveScreen> createState() => _HostLiveScreenState();
}

class _HostLiveScreenState extends State<HostLiveScreen> {
  List<GuessRecord> _guessHistory = [];
  Stream<List<GuessRecord>>? _guessesStream;
  // Store the active subscription so we can cancel it in dispose().
  // Without this the Firestore snapshot listener leaks after the
  // screen is popped.
  StreamSubscription<List<GuessRecord>>? _guessesSub;
  bool _endDialogShown = false;
  bool _navigatedToWaiting = false;

  @override
  void initState() {
    super.initState();
    HostController.instance.addListener(_onRoomChanged);
    _startGuessesStream();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoomChanged());
  }

  @override
  void dispose() {
    // Cancel the Firestore guesses subscription before removing the
    // room-changed listener. Order matters: cancel the stream first
    // so no setState can race with teardown.
    _guessesSub?.cancel();
    _guessesSub = null;
    HostController.instance.removeListener(_onRoomChanged);
    super.dispose();
  }

  void _startGuessesStream() {
    final room = HostController.instance.currentRoom;
    if (room == null) return;
    // Filter by the current round so old guesses from previous
    // rounds are invisible. The round is bumped on every rematch.
    _guessesStream = RoomService().watchGuesses(room.id, room.round);
    _guessesSub = _guessesStream!.listen((records) {
      if (!mounted) return;
      setState(() => _guessHistory = records);
    });
  }

  void _onRoomChanged() {
    final room = HostController.instance.currentRoom;
    if (room == null || !mounted) return;

    // The player left (vacated the room back to 'waiting'). Send the
    // host to the waiting screen with the SAME code so they can invite
    // someone new. popUntil(isFirst) cleanly closes any open dialog
    // (end-game, new-round-entry, or waiting-for-acceptance) along
    // with this screen first, so this one path covers every case.
    if (room.isWaiting) {
      if (_navigatedToWaiting) return;
      _navigatedToWaiting = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(
        context,
      ).push(AppTheme.pageRoute(const HostWaitingScreen()));
      return;
    }

    // A reset was detected (phase flipped back to 'playing' from
    // 'rematchOffered' after the player accepted): re-arm the end-game
    // dialog so it can fire again when this round ends. Also restart
    // the guesses stream so it filters to the new round number.
    // The new-round dialog (which is in WAITING mode) has its OWN
    // listener that pops itself when phase becomes 'playing' - so we
    // don't pop anything here, we just reset the end-dialog flag.
    if (room.isPlaying) {
      _endDialogShown = false;
      // Restart the guesses stream with the new round so old guesses
      // are filtered out.
      _guessesSub?.cancel();
      _startGuessesStream();
      return;
    }

    if (room.isOver && !_endDialogShown) {
      _endDialogShown = true;
      // Record this game in the host's history. Best-effort: errors
      // are caught inside recordGame so they never break the game flow.
      final hostWon = room.winner == 'host';
      final guessCount = GameConfig.defaultLives - room.attemptsLeft;
      GameHistoryService().recordGame(
        gameId: 'mp_${room.id}_round_${room.round}',
        mode: 'multiplayer',
        role: 'host',
        opponentName: room.playerName ?? 'Player',
        secretNumber: room.secretNumber,
        guessCount: guessCount,
        result: hostWon ? 'won' : 'lost',
        durationSec: 0,
      );
      _showEndGameDialog(room);
    }
  }

  void _showEndGameDialog(GameRoom room) {
    final isHostWin = room.winner == 'host';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EndGameDialog(
        isWin: isHostWin,
        revealedSecret: room.revealedSecret,
        isHostSide: true,
        livesLeft: room.attemptsLeft,
        onBackHome: () {
          // Delete the room (also signals the player's screen to go
          // home - their stream sees the document disappear) and
          // return to the home screen. Fire-and-forget: the deletion
          // continues in the background while we navigate.
          HostController.instance.leaveRoom();
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        onNewGame: _startNewRound,
      ),
    );
  }

  /// "New Game" was tapped in the end-game dialog.
  ///
  /// Guard first: if the player left while the dialog was open the
  /// room is 'waiting' now, and resetting would start a round nobody
  /// can play. Send the host to the waiting screen instead. (The
  /// room-changed listener usually catches this first and has already
  /// navigated - this is defense in depth for the race window.)
  void _startNewRound() {
    final room = HostController.instance.currentRoom;
    if (room == null || !room.isOver) {
      if (!mounted) return;
      if (_navigatedToWaiting) return;
      _navigatedToWaiting = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(
        context,
      ).push(AppTheme.pageRoute(const HostWaitingScreen()));
      return;
    }
    // Close the end-game dialog and ask the host for the new secret.
    Navigator.of(context).pop();
    _showNewRoundDialog(room);
  }

  void _showNewRoundDialog(GameRoom room) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewRoundDialog(
        minBound: room.minBound,
        maxBound: room.maxBound,
        playerName: room.playerName,
        onCancel: () {
          // Back out of the new-round dialog; bring the end-game dialog
          // back so the host still has both choices. If the player left
          // meanwhile, _onRoomChanged handles the waiting transition.
          Navigator.of(context).pop();
          _endDialogShown = false;
          _onRoomChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HostController.instance,
      builder: (context, _) {
        final room = HostController.instance.currentRoom;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Host View')),
            body: const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppTheme.offWhite,
          appBar: AppBar(
            title: Text('${room.hostName} - Host View'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Leave room',
                onPressed: () async {
                  final confirm = await _confirmLeave(context);
                  if (confirm != true) return;
                  await HostController.instance.leaveRoom();
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
                  title: room.isPlaying
                      ? '${room.playerName ?? "Player"} is playing'
                      : room.isRematchOffered
                          ? 'Waiting for player to accept'
                          : 'Game ended',
                  subtitle: room.isPlaying
                      ? 'Watch the guesses come in real time.'
                      : room.isRematchOffered
                          ? 'The new round is staged. The player must tap "Keep Playing".'
                          : null,
                  icon: Icons.person,
                  accent: AppTheme.deepTeal,
                ),
                const SizedBox(height: 12),
                _RoomCodeChip(code: room.id),
                const SizedBox(height: 16),
                // Visual range bar (replaces the old text-only StatCard).
                // The narrowing range is the core mechanic — making it
                // visual is the biggest "feels alive" upgrade.
                RangeBar(
                  minBound: room.minBound,
                  maxBound: room.maxBound,
                  currentMinBound: room.currentMinBound,
                  currentMaxBound: room.currentMaxBound,
                  lastGuess: room.lastGuess,
                  lastFeedback: room.lastFeedback,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
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
                _LastGuessCard(room: room),
                const SizedBox(height: 20),
                _GuessHistoryCard(history: _guessHistory),
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
        title: const Text('Leave this room?'),
        content: const Text(
          'The room will be deleted and the player will be taken home.',
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

/// The room code, always visible with a one-tap copy button. The code
/// is PRESERVED across "New Game" resets, so the host can re-share it
/// with new players between rounds or after someone leaves.
class _RoomCodeChip extends StatelessWidget {
  final String code;

  const _RoomCodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 18, color: AppTheme.mutedText),
          const SizedBox(width: 8),
          Text(
            'Room code: ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            code,
            style: AppTheme.inviteCodeStyle(size: 18, color: AppTheme.deepTeal),
          ),
          const Spacer(),
          ScaleTap(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Code copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy, size: 16, color: AppTheme.deepTeal),
                SizedBox(width: 4),
                Text(
                  'Copy',
                  style: TextStyle(
                    color: AppTheme.deepTeal,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastGuessCard extends StatelessWidget {
  final GameRoom room;

  const _LastGuessCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGuess = room.lastGuess != null && room.lastFeedback != null;
    final feedbackColor = _colorForFeedback(room.lastFeedback);
    final message = hasGuess
        ? 'Player guessed ${room.lastGuess}'
        : 'The player has not made a guess yet.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        children: [
          Text(
            'LATEST GUESS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (hasGuess)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                '${room.lastGuess}',
                key: ValueKey(room.lastGuess),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: feedbackColor,
                  height: 1.0,
                ),
              ),
            )
          else
            Icon(Icons.hourglass_empty,
                size: 40, color: AppTheme.mutedText.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              hasGuess
                  ? room.lastFeedback!.friendlyMessage
                  : 'Waiting for the player to act.',
              key: ValueKey(message),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: hasGuess ? feedbackColor : AppTheme.mutedText,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
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

class _GuessHistoryCard extends StatelessWidget {
  final List<GuessRecord> history;

  const _GuessHistoryCard({required this.history});

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
            'GUESS HISTORY',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No guesses yet. The player will appear here when they start.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedText),
              ),
            )
          else
            ...history.reversed.map((record) => _HistoryRow(record: record)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final GuessRecord record;

  const _HistoryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedbackColor = _colorForFeedback(record.feedback);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.deepTeal,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${record.attemptNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Guessed ${record.value}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.nearBlack,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: feedbackColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              record.feedback.shortLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: feedbackColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The end-game dialog. Shows the result of the round and offers the
/// host two choices: go home (deletes the room) or start a new round
/// (opens the secret-entry dialog). The reset itself - and its loading
/// and error states - live in [_NewRoundDialog], so this dialog stays
/// simple: both buttons are plain callbacks.
class _EndGameDialog extends StatefulWidget {
  final bool isWin;
  final int? revealedSecret;
  final bool isHostSide;
  final int livesLeft;
  final VoidCallback onBackHome;
  final VoidCallback onNewGame;

  const _EndGameDialog({
    required this.isWin,
    required this.revealedSecret,
    required this.isHostSide,
    required this.livesLeft,
    required this.onBackHome,
    required this.onNewGame,
  });

  @override
  State<_EndGameDialog> createState() => _EndGameDialogState();
}

class _EndGameDialogState extends State<_EndGameDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final ConfettiController _confettiController;

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
    // Confetti: play a 2-second burst when the relevant side wins.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // For host: isWin means host won (player lost).
    // For player: isWin means player won.
    final isHostWin = widget.isHostSide && widget.isWin;
    final isPlayerWin = !widget.isHostSide && widget.isWin;

    final Color headlineColor =
        isHostWin || isPlayerWin ? AppTheme.brightCyan : AppTheme.crimson;
    final String headline =
        (isHostWin || isPlayerWin) ? 'You won!' : 'You lost!';
    final IconData headlineIcon = (isHostWin || isPlayerWin)
        ? Icons.emoji_events
        : Icons.sentiment_very_dissatisfied;

    final String detail = widget.isHostSide
        ? (widget.isWin
            ? 'The player ran out of lives.'
            : 'The player guessed your secret number correctly.')
        : (widget.isWin
            ? 'You guessed the secret number with ${widget.livesLeft} lives left.'
            : 'You ran out of lives.');

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Confetti overlay — bursts from the top center when the
          // relevant side wins.
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onBackHome,
                        child: const Text('Back to Home'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.onNewGame,
                        child: const Text('New Game'),
                      ),
                    ),
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
}

/// The new-round dialog (v3 redesign). Has TWO modes:
///
///   - SECRET_ENTRY mode (initial): the host types a new secret number
///     and taps "Start Round". On confirm, [HostController.offerRematch]
///     runs - it flips the room to 'rematchOffered' in a transaction
///     and batch-deletes the old guesses. The dialog then switches to
///     WAITING mode.
///
///   - WAITING mode (after the offer succeeds): shows "Waiting for
///     {playerName} to accept..." with a spinner and a Cancel button.
///     The dialog auto-dismisses when the room transitions to 'playing'
///     (the live screen's _onRoomChanged listener pops it). If the
///     player declines or leaves, the room flips to 'waiting' and the
///     live screen navigates to the waiting screen, popping this dialog
///     along the way.
///
/// Self-contained on purpose: it validates the secret against the
/// original range, calls the controller itself, shows its own loading
/// state while the reset is in flight, and surfaces its own inline
/// error (never a raw Firestore message) on failure.
class _NewRoundDialog extends StatefulWidget {
  final int minBound;
  final int maxBound;
  final String? playerName;
  final VoidCallback onCancel;

  const _NewRoundDialog({
    required this.minBound,
    required this.maxBound,
    required this.playerName,
    required this.onCancel,
  });

  @override
  State<_NewRoundDialog> createState() => _NewRoundDialogState();
}

class _NewRoundDialogState extends State<_NewRoundDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  final _secretController = TextEditingController();
  bool _starting = false;
  bool _waiting = false; // true once offerRematch succeeded
  String? _error;

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

    // While in WAITING mode, watch the controller for the room
    // transitioning to 'playing' (player accepted) so we can
    // auto-dismiss. Also catches the 'waiting' transition (player
    // declined) - in that case the live screen's listener handles
    // navigation, but we pop here too so the dialog doesn't linger.
    HostController.instance.addListener(_onRoomChanged);
  }

  @override
  void dispose() {
    HostController.instance.removeListener(_onRoomChanged);
    _controller.dispose();
    _secretController.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    if (!_waiting) return; // only react in WAITING mode
    final room = HostController.instance.currentRoom;
    if (room == null) return;
    if (room.isPlaying) {
      // Player accepted the rematch. Pop this dialog - the live
      // screen re-renders from the controller (fresh round, same
      // code).
      if (!mounted) return;
      Navigator.of(context).pop();
    }
    // If the room went back to 'waiting' (player declined), the live
    // screen's listener is already navigating us away - it will pop
    // this dialog via popUntil. Nothing to do here.
  }

  Future<void> _onStart() async {
    if (_starting) return;

    // Guard: the player may have left while the host was typing. The
    // live screen's listener detects the 'waiting' transition and is
    // already navigating us away - do nothing here.
    final room = HostController.instance.currentRoom;
    if (room == null || !room.isOver) return;

    // Validate the secret against the original range.
    final value = int.tryParse(_secretController.text.trim());
    if (value == null || value < widget.minBound || value > widget.maxBound) {
      setState(() => _error =
          'Enter a number between ${widget.minBound} and ${widget.maxBound}.');
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      await HostController.instance.offerRematch(newSecret: value);
      if (!mounted) return;
      // Success: switch to WAITING mode. The dialog stays up until
      // the player accepts (room -> 'playing', _onRoomChanged pops)
      // or declines (room -> 'waiting', live screen navigates us away).
      setState(() {
        _starting = false;
        _waiting = true;
      });
    } catch (error) {
      if (!mounted) return;
      final raw = error.toString().toLowerCase();
      setState(() {
        _starting = false;
        if (raw.contains('permission')) {
          // The most likely cause: the round-2 rules (which allow the
          // host to delete guess docs) are not deployed yet.
          _error = 'Permission denied. Deploy the latest Firestore rules '
              '(firebase deploy --only firestore:rules) and try again.';
        } else if (raw.contains('network') || raw.contains('unavailable')) {
          _error = 'Could not reach the server. Check your connection.';
        } else if (raw.contains('already left') ||
            raw.contains('not ready')) {
          _error = 'The player has left. Waiting for a new player.';
        } else {
          _error = 'Could not start the round. Try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = widget.playerName ?? 'The player';

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
            child: _waiting
                ? _buildWaitingMode(theme, who)
                : _buildEntryMode(theme, who),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryMode(ThemeData theme, String who) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.brightCyan.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.casino,
            color: AppTheme.brightCyan,
            size: 40,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'New Round!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.nearBlack,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Enter a new secret number. $who keeps the same room '
          'code - no re-sharing needed. They will be asked to accept '
          'before the round begins.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppTheme.mutedText,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _secretController,
          enabled: !_starting,
          decoration: InputDecoration(
            hintText:
                'Between ${widget.minBound} and ${widget.maxBound}',
            prefixIcon:
                const Icon(Icons.lock_outline, color: AppTheme.mutedText),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _onStart(),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(_error),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
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
                onPressed: _starting ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _starting ? null : _onStart,
                child: _starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Start Round'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWaitingMode(ThemeData theme, String who) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.brightCyan.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hourglass_top,
            color: AppTheme.brightCyan,
            size: 40,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Waiting for $who...',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.nearBlack,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The new round is staged with your secret. $who must tap '
          '"Keep Playing" to start. If they decline, you will be taken '
          'back to the waiting screen with the same room code.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppTheme.mutedText,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: AppTheme.brightCyan,
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () {
            // Cancel: leave the room (deletes it; the player is sent
            // home) and go back to the home screen.
            HostController.instance.leaveRoom();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Cancel and go home'),
        ),
      ],
    );
  }
}
