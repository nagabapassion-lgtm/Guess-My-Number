import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../game_config.dart';
import '../widgets/animations.dart';
import 'daily_leaderboard_screen.dart';
import 'solo_game_screen.dart';

/// Where the player picks which solo mode to play.
///
/// Two options:
///   - Daily Challenge: one fixed game per day (range 1-1000, 5 lives),
///     same secret for everyone, winners can post to the leaderboard.
///   - Practice: pick any range and number of lives, unlimited
///     replays, no leaderboard. For learning and warmups.
///
/// The Daily Challenge card gets a distinct look (gradient border and
/// a "today" label) because it is the flagship solo experience.
class SoloSetupScreen extends StatelessWidget {
  const SoloSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Play Solo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StaggeredFadeSlide(
          verticalSpacing: 16,
          stepDelayMs: 90,
          children: [
            // ----------------------------------------------------------
            // Daily Challenge card (flagship)
            // ----------------------------------------------------------
            _DailyChallengeCard(),
            const SizedBox(height: 8),
            // ----------------------------------------------------------
            // Practice card
            // ----------------------------------------------------------
            _PracticeCard(),
          ],
        ),
      ),
    );
  }
}

/// The Daily Challenge entry card. Shows today's date and the fixed
/// settings so the player knows exactly what they are signing up for.
class _DailyChallengeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _todayLabel();

    return ScaleTap(
      onTap: () => _openDaily(context),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.brightCyan.withValues(alpha: 0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brightCyan.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.deepTeal, AppTheme.brightCyan],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.calendar_today,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Challenge',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.nearBlack,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        today,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.mutedText,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppTheme.brightCyan, size: 28),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'One secret per day, the same for everyone worldwide. '
              'Range ${GameConfig.dailyChallengeMin} to '
              '${GameConfig.dailyChallengeMax}, '
              '${GameConfig.dailyChallengeLives} lives. '
              'Win and post your guess count to today\'s leaderboard.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.mutedText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _openLeaderboard(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              child: const Text('View today\'s leaderboard'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLeaderboard(BuildContext context) {
    Navigator.of(context).push(
      AppTheme.pageRoute(const DailyLeaderboardScreen()),
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

  void _openDaily(BuildContext context) {
    Navigator.of(context).push(
      AppTheme.pageRoute(
        const SoloGameScreen(mode: SoloMode.daily),
      ),
    );
  }
}

/// The Practice entry card. Leads to a small config form (range and
/// lives) before the game starts.
class _PracticeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTap(
      onTap: () => _openPractice(context),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.outlineVariant, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.tune,
                  color: AppTheme.deepTeal, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Practice',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pick your own range and lives. Play as much as you want.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.mutedText, size: 28),
          ],
        ),
      ),
    );
  }

  void _openPractice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _PracticeConfigSheet(),
    );
  }
}

/// Bottom sheet that collects the practice settings before starting
/// a practice game. Small and focused: two numbers and a lives picker.
class _PracticeConfigSheet extends StatefulWidget {
  const _PracticeConfigSheet();

  @override
  State<_PracticeConfigSheet> createState() => _PracticeConfigSheetState();
}

class _PracticeConfigSheetState extends State<_PracticeConfigSheet> {
  final _minController = TextEditingController(
    text: GameConfig.practiceDefaultMin.toString(),
  );
  final _maxController = TextEditingController(
    text: GameConfig.practiceDefaultMax.toString(),
  );
  int _lives = GameConfig.practiceDefaultLives;

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Practice settings',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Lowest',
                  controller: _minController,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: 'Highest',
                  controller: _maxController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Lives',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppTheme.mutedText,
            ),
          ),
          const SizedBox(height: 8),
          _LivesPicker(
            value: _lives,
            onChanged: (v) => setState(() => _lives = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _start,
            child: const Text('Start Practice'),
          ),
        ],
      ),
    );
  }

  void _start() {
    final min = int.tryParse(_minController.text.trim());
    final max = int.tryParse(_maxController.text.trim());
    if (min == null || max == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter numbers for the range.')),
      );
      return;
    }
    if (min >= max) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The lowest number must be smaller than the highest.')),
      );
      return;
    }
    if (max - min > 1000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Keep the range within a million for sanity.')),
      );
      return;
    }
    // Capture the navigator BEFORE popping the sheet; using a context
    // after its route is popped throws a "deactivated widget" error.
    final navigator = Navigator.of(context);
    navigator.pop(); // close the bottom sheet
    navigator.push(
      AppTheme.pageRoute(
        SoloGameScreen(
          mode: SoloMode.practice,
          practiceMin: min,
          practiceMax: max,
          practiceLives: _lives,
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _NumberField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.mutedText,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0'),
        ),
      ],
    );
  }
}

/// A compact segmented picker for the number of lives (3 to 10).
class _LivesPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _LivesPicker({required this.value, required this.onChanged});

  static const options = [3, 4, 5, 6, 7, 8, 10];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final lives in options)
          _LivesChip(
            label: '$lives',
            selected: lives == value,
            onTap: () => onChanged(lives),
          ),
      ],
    );
  }
}

class _LivesChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LivesChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.deepTeal : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.deepTeal : AppTheme.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.nearBlack,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
