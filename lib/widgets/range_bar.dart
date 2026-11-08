import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/feedback_type.dart';

/// A visual number-line bar that shows the player's safe range
/// (currentMinBound to currentMaxBound) as a highlighted section of
/// the full range (minBound to maxBound).
///
/// Replaces the old text-only "23 to 87" StatCard. The narrowing
/// range is the CORE MECHANIC of the game — making it visual is the
/// single biggest "feels alive" upgrade.
///
/// Features:
///   - Full range shown as a grey bar (eliminated regions)
///   - Active safe range shown as a teal-to-cyan gradient bar
///   - Last guess marked with a glowing circle + directional arrow
///     (↑ blue for "too low, guess higher", ↓ amber for "too high,
///     guess lower", ✓ cyan for correct)
///   - Animates smoothly (300ms ease-out) when the range narrows
///   - Shows min/max numbers at the ends + active range in the center
class RangeBar extends StatelessWidget {
  final int minBound;
  final int maxBound;
  final int currentMinBound;
  final int currentMaxBound;
  final int? lastGuess;
  final FeedbackType? lastFeedback;

  const RangeBar({
    super.key,
    required this.minBound,
    required this.maxBound,
    required this.currentMinBound,
    required this.currentMaxBound,
    this.lastGuess,
    this.lastFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Clamp to prevent division by zero on degenerate ranges.
    final totalRange = (maxBound - minBound).clamp(1, 1000000);

    // Positions as fractions (0.0 to 1.0) of the full bar width.
    final activeStart =
        (currentMinBound - minBound) / totalRange;
    final activeEnd =
        (currentMaxBound - minBound) / totalRange;
    final activeWidth = activeEnd - activeStart;

    // Last guess position (may be outside the active range, in the
    // eliminated region — that's correct, it shows where you guessed).
    final guessPos = lastGuess != null
        ? (lastGuess! - minBound) / totalRange
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.brightCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.track_changes,
                    color: AppTheme.brightCyan, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'SAFE RANGE',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.mutedText,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Active range number (big, bold)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: Text(
                  '$currentMinBound – $currentMaxBound',
                  key: ValueKey('$currentMinBound-$currentMaxBound'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.deepTeal,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The bar itself
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Column(
                children: [
                  SizedBox(
                    height: 36,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Background bar (full range, grey)
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.outlineVariant,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        // Active range bar (teal-to-cyan gradient)
                        // AnimatedPositioned smoothly moves + resizes
                        // when the range narrows on each guess.
                        AnimatedPositioned(
                          left: barWidth * activeStart,
                          width: (barWidth * activeWidth)
                              .clamp(8.0, barWidth),
                          top: 0,
                          height: 36,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  AppTheme.deepTeal,
                                  AppTheme.brightCyan,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.brightCyan
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Last guess marker (glowing circle + arrow)
                        if (guessPos != null)
                          AnimatedPositioned(
                            left: (barWidth * guessPos - 16)
                                .clamp(0.0, barWidth - 32),
                            top: -2,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: _GuessMarker(
                              feedback: lastFeedback,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Number labels at the ends
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$minBound',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$maxBound',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The glowing circle marker that shows where the last guess landed
/// on the number line, with a directional arrow indicating the
/// feedback (↑ too low, ↓ too high, ✓ correct).
///
/// Semantic colors (WCAG-friendly, distinguishable for color-blind
/// users when paired with the directional icons):
///   - Too low → blue (#2563EB) + ↑
///   - Too high → amber (#F59E0B) + ↓
///   - Correct → cyan + ✓
///   - Out of bounds → crimson + ✕
class _GuessMarker extends StatelessWidget {
  final FeedbackType? feedback;

  const _GuessMarker({this.feedback});

  @override
  Widget build(BuildContext context) {
    final color = _colorForFeedback(feedback);
    final icon = _iconForFeedback(feedback);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Color _colorForFeedback(FeedbackType? feedback) {
    switch (feedback) {
      case FeedbackType.tooLow:
        return const Color(0xFF2563EB); // blue — "guess higher"
      case FeedbackType.tooHigh:
        return const Color(0xFFF59E0B); // amber — "guess lower"
      case FeedbackType.correct:
        return AppTheme.brightCyan;
      case FeedbackType.outOfBounds:
        return AppTheme.crimson;
      case null:
        return AppTheme.mutedText;
    }
  }

  IconData _iconForFeedback(FeedbackType? feedback) {
    switch (feedback) {
      case FeedbackType.tooLow:
        return Icons.arrow_upward;
      case FeedbackType.tooHigh:
        return Icons.arrow_downward;
      case FeedbackType.correct:
        return Icons.check;
      case FeedbackType.outOfBounds:
        return Icons.close;
      case null:
        return Icons.help_outline;
    }
  }
}
