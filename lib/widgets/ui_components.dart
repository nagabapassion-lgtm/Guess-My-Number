import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A small card showing one statistic (label + value), with an icon and
/// accent color. Used on the host live screen and player guess screen for
/// "Safe range" and "Lives left".
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool pulse;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14040F16),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.mutedText,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              value,
              key: ValueKey(value),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.nearBlack,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of heart-shaped life indicators. Filled hearts = lives left,
/// outlined hearts = lives used. When a life is lost, the lost heart
/// animates from filled to outlined with a quick fade + scale.
class LivesIndicator extends StatelessWidget {
  final int livesLeft;
  final int totalLives;

  const LivesIndicator({
    super.key,
    required this.livesLeft,
    this.totalLives = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalLives, (i) {
        final filled = i < livesLeft;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) {
              return ScaleTransition(scale: anim, child: child);
            },
            child: Icon(
              filled ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(filled),
              color: filled ? AppTheme.crimson : AppTheme.outline,
              size: 22,
            ),
          ),
        );
      }),
    );
  }
}

/// A rounded banner shown at the top of most screens. Picks up the
/// accent color passed in and renders an icon + title + optional
/// subtitle. Used for "Set up your game space" on host setup,
/// "Have your invite code ready?" on player join, etc.
class AccentBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final Color? accentContainer;

  const AccentBanner({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    this.accentContainer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = accentContainer ?? accent.withValues(alpha: 0.10);
    final onAccent = accent == AppTheme.brightCyan
        ? AppTheme.nearBlack
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: onAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.nearBlack,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedText,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
