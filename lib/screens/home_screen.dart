import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/host_controller.dart';
import '../controllers/player_controller.dart';
import '../widgets/animations.dart';
import 'host_setup_screen.dart';
import 'player_join_screen.dart';
import 'solo_setup_screen.dart';

/// The first screen the user sees after the app launches.
///
/// Three paths, ordered by friction (lowest first):
///   1. Play Solo - no friends needed, instant start.
///   2. Host a New Game - set a secret, share an invite code.
///   3. Join a Game - enter a friend's code.
///
/// The solo card sits on top with a distinct gradient treatment because
/// it is the mode anyone can play at any time, even alone at 2am.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 260),
                  child: const _SoloCard(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 340),
                  child: const _SectionLabel('Play with friends'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 400),
                  child: _RoleCard(
                    label: 'Host a New Game',
                    description:
                        'Pick a secret number and a range, then invite a friend to guess it.',
                    icon: Icons.lock_outline,
                    accent: AppTheme.deepTeal,
                    onTap: () => _goToHostSetup(context),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 460),
                  child: _RoleCard(
                    label: 'Join a Game',
                    description:
                        'Enter the 6-character code your friend gave you and start guessing.',
                    icon: Icons.key,
                    accent: AppTheme.brightCyan,
                    onTap: () => _goToPlayerJoin(context),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 520),
                  child: const _HowItWorksCard(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  void _goToHostSetup(BuildContext context) {
    // Reset any stale state from a previous session.
    HostController.instance.reset();
    Navigator.of(context).push(
      AppTheme.pageRoute(const HostSetupScreen()),
    );
  }

  void _goToPlayerJoin(BuildContext context) {
    PlayerController.instance.leaveRoom();
    Navigator.of(context).push(
      AppTheme.pageRoute(const PlayerJoinScreen()),
    );
  }
}

/// The top of the home screen: the app icon, the title, and the intro.
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            child: _AppIconBadge(),
          ),
          const SizedBox(height: 24),
          FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Text(
              'Number Guessing Game',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.nearBlack,
                    height: 1.1,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: Text(
              'A real-time guessing game. Hide a number, chase a secret, '
              'or challenge today\'s puzzle solo.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.mutedText,
                    height: 1.55,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app icon badge: a "?" on the teal-to-cyan gradient.
class _AppIconBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.deepTeal, AppTheme.brightCyan],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepTeal.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            color: AppTheme.offWhite,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section label used between card groups.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// The solo mode card. Distinct gradient treatment so it reads as the
/// "always available" option, not just another button.
class _SoloCard extends StatelessWidget {
  const _SoloCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTap(
      onTap: () => _openSolo(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.deepTeal, AppTheme.brightCyan],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.deepTeal.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.computer,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Play Solo',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Daily Challenge or free practice against the computer.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 28),
          ],
        ),
      ),
    );
  }

  void _openSolo(BuildContext context) {
    Navigator.of(context).push(
      AppTheme.pageRoute(const SoloSetupScreen()),
    );
  }
}

/// A large tappable card that lets the user pick the host or player role.
class _RoleCard extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.outlineVariant, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14040F16),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                color: accent.withValues(alpha: 0.7), size: 28),
          ],
        ),
      ),
    );
  }
}

/// A short explainer at the bottom of the home screen.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: AppTheme.brightCyan, size: 22),
              const SizedBox(width: 8),
              Text(
                'How it works',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nearBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HowItem(
            number: '1',
            text:
                'Solo: race the Daily Challenge or practice freely against the computer.',
          ),
          const SizedBox(height: 12),
          _HowItem(
            number: '2',
            text:
                'With friends: the host hides a number and shares a 6-letter code.',
          ),
          const SizedBox(height: 12),
          _HowItem(
            number: '3',
            text:
                'Guessers get feedback after every try - "too low" or "too high" - and the safe range narrows.',
          ),
          const SizedBox(height: 12),
          _HowItem(
            number: '4',
            text:
                'Find the secret before your lives run out. Fewer guesses means a better score.',
          ),
        ],
      ),
    );
  }
}

class _HowItem extends StatelessWidget {
  final String number;
  final String text;

  const _HowItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.nearBlack,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
