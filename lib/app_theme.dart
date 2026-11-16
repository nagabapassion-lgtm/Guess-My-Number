import 'package:flutter/material.dart';

/// The app's visual identity: colors, typography, and shape language.
///
/// All screens pull from [AppTheme.data] so the look is consistent across
/// the app. The palette is locked to the user's chosen five colors:
///   - Deep Teal #0B4F6C   (primary, host flow)
///   - Bright Cyan #01BAEF (secondary, player flow, success)
///   - Crimson #B80C09     (error, danger, wrong guess)
///   - Off-white #FBFBFF   (background)
///   - Near-black #040F16  (text on light backgrounds)
///
/// IMPORTANT: This version does NOT use the google_fonts package. The
/// google_fonts package fetches Plus Jakarta Sans and JetBrains Mono
/// from fonts.gstatic.com at runtime, which is blocked in some networks
/// (causing a white screen on app boot). Instead, we use system fonts:
///   - Sans-serif: 'Roboto' on Android/web, falls back to 'system-ui',
///     'sans-serif' on iOS/desktop. Geometric, friendly, available
///     everywhere with zero network fetches.
///   - Monospace: 'Roboto Mono' on Android/web, falls back to
///     'monospace'. Used only for the invite code so visually similar
///     characters (B vs 8) are easier to tell apart.
///
/// The visual identity (colors, sizes, weights, shapes) is identical to
/// the v3 design - only the font family changes. If you want to bring
/// back the custom fonts later, bundle the .ttf files in fonts/ and
/// declare them in pubspec.yaml (NOT via google_fonts).
class AppTheme {
  AppTheme._();

  // Raw palette values, exposed so individual screens can reference them
  // for one-off colors (e.g. success vs danger on the live screen).
  static const Color deepTeal = Color(0xFF0B4F6C);
  static const Color brightCyan = Color(0xFF01BAEF);
  static const Color crimson = Color(0xFFB80C09);
  static const Color offWhite = Color(0xFFFBFBFF);
  static const Color nearBlack = Color(0xFF040F16);

  // Derived tints/shades used by various screens.
  static const Color tealContainer = Color(0xFFD6E8F0);
  static const Color cyanContainer = Color(0xFFC8F1FB);
  static const Color surfaceHigh = Color(0xFFF1F2F6);
  static const Color surfaceHighest = Color(0xFFE6E8EE);
  static const Color mutedText = Color(0xFF5A6A75);

  // Outline colors used by borders, dividers, and muted icon fills.
  static const Color outline = Color(0xFFB8C2CC);
  static const Color outlineVariant = Color(0xFFDCE0E6);

  /// The sans-serif font family used everywhere except the invite code.
  /// 'Roboto' is bundled with Android and most web renderers; the
  /// fallback chain ensures something reasonable on every platform.
  static const List<String> sansFamily = [
    'Roboto',
    'system-ui',
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  /// The monospace font family used for the invite code so visually
  /// similar characters (B vs 8) are easier to tell apart.
  static const List<String> monoFamily = [
    'Roboto Mono',
    'Menlo',
    'Monaco',
    'Consolas',
    'Courier New',
    'monospace',
  ];

  static ThemeData get data {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: deepTeal,
      onPrimary: Colors.white,
      primaryContainer: tealContainer,
      onPrimaryContainer: nearBlack,
      secondary: brightCyan,
      onSecondary: nearBlack,
      secondaryContainer: cyanContainer,
      onSecondaryContainer: nearBlack,
      tertiary: brightCyan,
      onTertiary: nearBlack,
      tertiaryContainer: cyanContainer,
      onTertiaryContainer: nearBlack,
      error: crimson,
      onError: Colors.white,
      errorContainer: const Color(0xFFF8D7D5),
      onErrorContainer: nearBlack,
      surface: offWhite,
      onSurface: nearBlack,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFCFCFD),
      surfaceContainer: offWhite,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      onSurfaceVariant: mutedText,
      outline: const Color(0xFFB8C2CC),
      outlineVariant: const Color(0xFFDCE0E6),
      shadow: const Color(0x14040F16),
      scrim: const Color(0x99040F16),
      inverseSurface: nearBlack,
      onInverseSurface: offWhite,
      inversePrimary: brightCyan,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: offWhite,
      brightness: Brightness.light,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Set the default font family at the MaterialApp level too, so
      // any widget that doesn't go through TextTheme still gets our
      // sans-serif.
      fontFamily: 'Roboto',
      fontFamilyFallback: const [
        'system-ui',
        '-apple-system',
        'BlinkMacSystemFont',
        'Segoe UI',
        'Helvetica Neue',
        'Arial',
        'sans-serif',
      ],
    );

    // Build the text theme using system fonts. Sizes/weights match the
    // v3 design (Plus Jakarta Sans had the same metrics).
    const textTheme = TextTheme(
      // Display
      displayLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: [
          'system-ui', 'sans-serif',
        ],
        fontSize: 57,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
        color: nearBlack,
      ),
      displayMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 45,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.5,
        color: nearBlack,
      ),
      displaySmall: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: nearBlack,
      ),
      // Headline
      headlineLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: nearBlack,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: nearBlack,
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: nearBlack,
      ),
      // Title
      titleLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: nearBlack,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: nearBlack,
      ),
      titleSmall: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: nearBlack,
      ),
      // Body
      bodyLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: nearBlack,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: nearBlack,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: mutedText,
      ),
      // Label
      labelLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.1,
        color: nearBlack,
      ),
      labelMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.5,
        color: nearBlack,
      ),
      labelSmall: const TextStyle(
        fontFamily: 'Roboto',
        fontFamilyFallback: ['system-ui', 'sans-serif'],
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.5,
        color: nearBlack,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: deepTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['system-ui', 'sans-serif'],
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['system-ui', 'sans-serif'],
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: deepTeal,
          side: const BorderSide(color: deepTeal, width: 1.5),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['system-ui', 'sans-serif'],
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: deepTeal,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: ['system-ui', 'sans-serif'],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brightCyan, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: crimson, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: crimson, width: 2),
        ),
        hintStyle: const TextStyle(color: mutedText),
        labelStyle: const TextStyle(color: mutedText),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: nearBlack,
        contentTextStyle: const TextStyle(color: offWhite, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['system-ui', 'sans-serif'],
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: nearBlack,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: ['system-ui', 'sans-serif'],
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: nearBlack,
          height: 1.5,
        ),
      ),
      iconTheme: const IconThemeData(color: nearBlack, size: 24),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE6E8EE),
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// A monospaced font for the invite code so visually similar characters
  /// (e.g. B vs 8) are easier to tell apart.
  static TextStyle inviteCodeStyle({double size = 48, Color color = nearBlack}) {
    return TextStyle(
      fontFamily: 'Roboto Mono',
      fontFamilyFallback: const [
        'Menlo', 'Monaco', 'Consolas', 'Courier New', 'monospace',
      ],
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 4,
    );
  }

  /// Page transition used by all routes. A combined fade + slight upward
  /// slide gives a polished feel without being slow.
  static Route<T> pageRoute<T extends Object?>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
    );
  }
}
