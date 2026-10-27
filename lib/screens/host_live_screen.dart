import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/host_controller.dart';
import '../models/feedback_type.dart';
import '../models/game_room.dart';
import '../services/room_service.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'host_waiting_screen.dart';

/// The host's live game view.
///
/// Rematch flow (v4 fix):
///   1. Round ends -> end-game dialog: [Back to Home] or [New Game].
///   2. Host taps "New Game" -> new-round dialog asks for a NEW secret.
///   3. On confirm the room flips to 'rematchOffered'. Host's dialog
///      switches to "Waiting for player to accept..." mode.
///   4. Player gets [Keep Playing] / [Back to Home] prompt.
///   5. Player accepts -> room -> 'playing'. Both dialogs auto-dismiss.
///      Live screen re-renders with fresh round, full lives, empty
///      guess history.
///   6. If player declines or leaves -> room -> 'waiting'. Host is
///      sent to waiting screen with same code.
class HostLiveScreen extends StatefulWidget {
  const HostLiveScreen({super.key});

  @override
  State<HostLiveScreen> createState() => _HostLiveScreenState();
}

class _HostLiveScreenState extends State<HostLiveScreen> {
  List<GuessRecord> _guessHistory = [];
  Stream<List<GuessRecord>>? _guessesStream;
  StreamSubscription<List<GuessRecord>>? _guessesSub;
  bool _endDialogShown = false;
  bool _endDialogOpen = false;       // end-game dialog currently on screen
  bool _newRoundDialogOpen = false;  // new-round dialog currently on screen
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
    _guessesSub?.cancel();
    _guessesSub = null;
    HostController.instance.removeListener(_onRoomChanged);
    super.dispose();
  }

  void _startGuessesStream() {
    final room = HostController.instance.currentRoom;
    if (room == null) return;
    _guessesStream = RoomService().watchGuesses(room.id, room.round);
    _guessesSub = _guessesStream!.listen((records) {
      if (!mounted) return;
      setState(() => _guessHistory = records);
    });
  }

  void _onRoomChanged() {
    final room = HostController.instance.currentRoom;
    if (room == null || !mounted) return;

    // Player left -> go to waiting screen with same code.
    if (room.isWaiting) {
      if (_navigatedToWaiting) return;
      _navigatedToWaiting = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(AppTheme.pageRoute(const HostWaitingScreen()));
      return;
    }

    // Player accepted the rematch -> pop any open dialogs, reset flags,
    // restart guesses stream with the new round.
    if (room.isPlaying) {
      if (_newRoundDialogOpen) {
        _newRoundDialogOpen = false;
        Navigator.of(context).pop();
      }
      if (_endDialogOpen) {
        _endDialogOpen = false;
        Navigator.of(context).pop();
      }
      _endDialogShown = false;
      _guessesSub?.cancel();
      _startGuessesStream();
      return;
    }

    // Host offered rematch - don't show end-game dialog; new-round
    // dialog is handling the UI in WAITING mode.
    if (room.isRematchOffered) {
      _endDialogShown = true;
      return;
    }

    // Round just ended -> show end-game dialog (only once per round).
    if (room.isOver && !_endDialogShown && !_endDialogOpen) {
      _endDialogShown = true;
      _showEndGameDialog(room);
    }
  }

  void _showEndGameDialog(GameRoom room) {
    final isHostWin = room.winner == 'host';
    _endDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EndGameDialog(
        isWin: isHostWin,
        revealedSecret: room.revealedSecret,
        isHostSide: true,
        livesLeft: room.attemptsLeft,
        onBackHome: () {
          _endDialogOpen = false;
          HostController.instance.leaveRoom();
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        onNewGame: _startNewRound,
      ),
    );
  }

  void _startNewRound() {
    final room = HostController.instance.currentRoom;
    if (room == null || !room.isOver) {
      if (!mounted) return;
      if (_navigatedToWaiting) return;
      _navigatedToWaiting = true;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(AppTheme.pageRoute(const HostWaitingScreen()));
      return;
    }
    _endDialogOpen = false;
    Navigator.of(context).pop();
    _showNewRoundDialog(room);
  }

  void _showNewRoundDialog(GameRoom room) {
    _newRoundDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewRoundDialog(
        minBound: room.minBound,
        maxBound: room.maxBound,
        playerName: room.playerName,
        onCancel: () {
          _newRoundDialogOpen = false;
          Navigator.of(context).pop();
          _endDialogShown = false;
          _endDialogOpen = false;
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

/// The room code chip with copy-to-clipboard.
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
            decoration: const BoxDecoration(
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
/// The end-game dialog. Shows the round result and offers the host
/// two choices: go home (deletes the room) or start a new round
/// (opens the secret-entry dialog).
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      border: Border.all(color: AppTheme.outlineVariant, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Secret was ',
                          style: TextStyle(color: AppTheme.mutedText, fontSize: 14),
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
    );
  }
}

/// The new-round dialog. Has TWO modes:
///   - SECRET_ENTRY (initial): host types a new secret and taps Start Round.
///     On confirm, offerRematch() runs - room flips to 'rematchOffered'.
///     Dialog switches to WAITING mode.
///   - WAITING (after offer succeeds): shows "Waiting for {player} to
///     accept..." with a spinner and Cancel button. Auto-dismisses when
///     room transitions to 'playing' (player accepted). If player declines,
///     room flips to 'waiting' and the live screen navigates us away.
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
  bool _waiting = false;
  String? _error;

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
    if (!_waiting) return;
    final room = HostController.instance.currentRoom;
    if (room == null) return;
    if (room.isPlaying) {
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _onStart() async {
    if (_starting) return;

    final room = HostController.instance.currentRoom;
    if (room == null || !room.isOver) return;

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
          _error = 'Permission denied. Deploy the latest Firestore rules '
              '(firebase deploy --only firestore:rules) and try again.';
        } else if (raw.contains('network') || raw.contains('unavailable')) {
          _error = 'Could not reach the server. Check your connection.';
        } else if (raw.contains('already left') || raw.contains('not ready')) {
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
          child: const Icon(Icons.casino, color: AppTheme.brightCyan, size: 40),
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
            hintText: 'Between ${widget.minBound} and ${widget.maxBound}',
            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.mutedText),
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
          child: const Icon(Icons.hourglass_top,
              color: AppTheme.brightCyan, size: 40),
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
            HostController.instance.leaveRoom();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Cancel and go home'),
        ),
      ],
    );
  }
}