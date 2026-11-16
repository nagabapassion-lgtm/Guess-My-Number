import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/race_controller.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'race_host_live_screen.dart';

/// Host's waiting screen for a RACE room. Shows the 6-char invite code
/// and the live roster of joined players. When 2+ players have joined,
/// the "Start Race" button appears.
class RaceHostWaitingScreen extends StatefulWidget {
  const RaceHostWaitingScreen({super.key});

  @override
  State<RaceHostWaitingScreen> createState() => _RaceHostWaitingScreenState();
}

class _RaceHostWaitingScreenState extends State<RaceHostWaitingScreen> {
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
    if (room == null) return;

    // When the room transitions to 'countdown' or 'playing', navigate
    // to the live screen.
    if (room.isCountdown || room.isPlaying || room.isFinished) {
      Navigator.of(context).pushReplacement(
        AppTheme.pageRoute(const RaceHostLiveScreen()),
      );
      return;
    }
    setState(() {});
  }

  Future<void> _startRace() async {
    await RaceHostController.instance.startCountdown();
    if (!mounted) return;
    final error = RaceHostController.instance.errorMessage;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _leaveRoom() async {
    await RaceHostController.instance.leaveRoom();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RaceHostController.instance,
      builder: (context, _) {
        final room = RaceHostController.instance.currentRoom;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Race Room')),
            body: const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            ),
          );
        }
        final players = RaceHostController.instance.players;
        final maxP = room.maxPlayers ?? 5;
        final canStart = players.length >= 2;

        return Scaffold(
          backgroundColor: AppTheme.offWhite,
          appBar: AppBar(
            title: const Text('Race Room'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Close room',
                onPressed: _leaveRoom,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccentBanner(
                  title: 'Share the code',
                  subtitle:
                      'Players join with this 6-character code. You need at '
                      'least 2 to start.',
                  icon: Icons.groups,
                  accent: AppTheme.brightCyan,
                ),
                const SizedBox(height: 16),
                // Invite code display
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.outlineVariant, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tag,
                          size: 18, color: AppTheme.mutedText),
                      const SizedBox(width: 8),
                      Text(
                        'Room code: ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.mutedText,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        room.id,
                        style: AppTheme.inviteCodeStyle(
                            size: 24, color: AppTheme.deepTeal),
                      ),
                      const Spacer(),
                      ScaleTap(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: room.id));
                          if (!context.mounted) return;
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
                            Icon(Icons.copy,
                                size: 16, color: AppTheme.deepTeal),
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
                ),
                const SizedBox(height: 20),
                // Roster
                Row(
                  children: [
                    Text(
                      'PLAYERS (${players.length}/$maxP)',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.mutedText,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    if (!canStart)
                      Text(
                        'Need ${2 - players.length} more to start',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mutedText,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (players.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.outlineVariant, width: 1),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_empty,
                            size: 40,
                            color: AppTheme.mutedText.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Waiting for players to join...',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.mutedText,
                                  ),
                        ),
                      ],
                    ),
                  )
                else
                  ...players.map((p) => _PlayerRow(
                        name: p.playerName,
                        joined: true,
                      )),
                const SizedBox(height: 24),
                // Start button
                ScaleTap(
                  onTap: canStart && !RaceHostController.instance.isWorking
                      ? _startRace
                      : null,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: canStart
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.deepTeal, AppTheme.brightCyan],
                            )
                          : null,
                      color: canStart ? null : AppTheme.outlineVariant,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: RaceHostController.instance.isWorking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              canStart
                                  ? 'Start Race (${players.length} players)'
                                  : 'Waiting for 2+ players',
                              style: TextStyle(
                                color: canStart
                                    ? Colors.white
                                    : AppTheme.mutedText,
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
          ),
        );
      },
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final String name;
  final bool joined;

  const _PlayerRow({required this.name, required this.joined});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outlineVariant, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.brightCyan.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person,
                  color: AppTheme.brightCyan, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.nearBlack,
                    ),
              ),
            ),
            Icon(Icons.check_circle,
                color: joined ? AppTheme.brightCyan : AppTheme.outlineVariant,
                size: 20),
          ],
        ),
      ),
    );
  }
}
