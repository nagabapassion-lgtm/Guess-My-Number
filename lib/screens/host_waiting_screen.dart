import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/host_controller.dart';
import '../widgets/animations.dart';
import 'host_live_screen.dart';

/// Screen shown to the host after they create a room.
///
/// Displays the invite code prominently with a one-tap copy button so
/// the host can paste it into a chat with their friend. While waiting
/// for the player, a friendly animated indicator pulses gently.
///
/// The screen subscribes to the room document via [HostController] so
/// the moment the player joins, we automatically navigate to the live
/// view without any further taps.
class HostWaitingScreen extends StatefulWidget {
  const HostWaitingScreen({super.key});

  @override
  State<HostWaitingScreen> createState() => _HostWaitingScreenState();
}

class _HostWaitingScreenState extends State<HostWaitingScreen> {
  @override
  void initState() {
    super.initState();
    HostController.instance.addListener(_onRoomChanged);
    // Fire once in case the player joined before this screen mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRoomChanged());
  }

  @override
  void dispose() {
    HostController.instance.removeListener(_onRoomChanged);
    super.dispose();
  }

  void _onRoomChanged() {
    final room = HostController.instance.currentRoom;
    if (room == null) return;
    if (room.phase.name == 'playing' ||
        room.phase.name == 'won' ||
        room.phase.name == 'lost') {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        AppTheme.pageRoute(const HostLiveScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = HostController.instance.currentRoom;
    final code = room?.id ?? '';

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Waiting for Player'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () async {
            await HostController.instance.leaveRoom();
            if (!mounted) return;
            Navigator.of(context).pop();
          },
        ),
      ),
      body: room == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            )
          : SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: StaggeredFadeSlide(
                verticalSpacing: 20,
                stepDelayMs: 90,
                children: [
                  Text(
                    'Your room is ready',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.nearBlack,
                            ),
                  ),
                  Text(
                    'Share this code with your friend. They will enter it on their device to join the game.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedText,
                          height: 1.5,
                        ),
                  ),
                  _InviteCodeCard(code: code),
                  _WaitingIndicator(),
                  _SettingsSummary(
                    hostName: room.hostName,
                    range: '${room.minBound} to ${room.maxBound}',
                    lives: room.attemptsLeft,
                  ),
                ],
              ),
            ),
    );
  }
}

/// Big, easy-to-read invite code display with a copy button. The code
/// uses a monospaced font so visually similar characters (e.g. B vs 8)
/// are easier to tell apart. A gentle pulse animation draws attention
/// to the code while waiting.
class _InviteCodeCard extends StatelessWidget {
  final String code;

  const _InviteCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return GentlePulse(
      maxScale: 1.015,
      duration: const Duration(milliseconds: 2200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.deepTeal, AppTheme.brightCyan],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.deepTeal.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'ROOM CODE',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 3,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              code,
              style: AppTheme.inviteCodeStyle(size: 48, color: Colors.white),
            ),
            const SizedBox(height: 20),
            _CopyButton(code: code),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String code;

  const _CopyButton({required this.code});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _justCopied = false;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        setState(() => _justCopied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _justCopied = false);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Container(
          key: ValueKey(_justCopied),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _justCopied ? Icons.check : Icons.copy,
                color: AppTheme.deepTeal,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _justCopied ? 'Copied' : 'Copy code',
                style: const TextStyle(
                  color: AppTheme.deepTeal,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.brightCyan.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Waiting for a player to join...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mutedText,
              ),
        ),
      ],
    );
  }
}

/// Small summary of the host's chosen settings so they can sanity-check
/// while they wait.
class _SettingsSummary extends StatelessWidget {
  final String hostName;
  final String range;
  final int lives;

  const _SettingsSummary({
    required this.hostName,
    required this.range,
    required this.lives,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Game settings',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.nearBlack,
            ),
          ),
          const SizedBox(height: 14),
          _SettingsRow(label: 'Your name', value: hostName),
          const SizedBox(height: 8),
          _SettingsRow(label: 'Number range', value: range),
          const SizedBox(height: 8),
          _SettingsRow(label: "Player's lives", value: '$lives'),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mutedText,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.nearBlack,
              ),
        ),
      ],
    );
  }
}
