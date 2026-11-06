import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import '../widgets/animations.dart';
import 'home_screen.dart';

/// The sign-in screen shown when the user opens the app and is not
/// yet authenticated. Two choices:
///   - Sign in with Google (recommended — persistent identity, can
///     play across devices, display name + photo auto-loaded)
///   - Continue as guest (anonymous — works fine but identity is
///     tied to this browser's cookies; clearing cookies loses your
///     game history)
///
/// After successful sign-in (either method), the screen navigates
/// to the HomeScreen with a pushReplacement.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final AuthService _auth = AuthService();
  bool _working = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await _auth.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        AppTheme.pageRoute(const HomeScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      final msg = error.toString();
      setState(() {
        _working = false;
        if (msg.contains('cancelled')) {
          _error = null; // silent — user just closed the popup
        } else if (msg.contains('network') ||
            msg.contains('unavailable')) {
          _error = 'Network error. Check your connection and try again.';
        } else {
          _error = 'Could not sign in with Google. Try again or continue as guest.';
        }
      });
    }
  }

  Future<void> _continueAsGuest() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await _auth.signInAnonymously();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        AppTheme.pageRoute(const HomeScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Could not start guest session. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              FadeSlideIn(
                child: Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.deepTeal, AppTheme.brightCyan],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '?',
                        style: TextStyle(
                          color: AppTheme.offWhite,
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
                child: Text(
                  'Guess My Number',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.nearBlack,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: Text(
                  'Sign in to keep your game history, compete on '
                  'leaderboards, and play across devices.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.mutedText,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              FadeSlideIn(
                delay: const Duration(milliseconds: 260),
                child: FilledButton.icon(
                  onPressed: _working ? null : _signInWithGoogle,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.g_mobiledata, size: 22),
                  label: const Text('Sign in with Google'),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 340),
                child: TextButton(
                  onPressed: _working ? null : _continueAsGuest,
                  child: const Text('Continue as guest'),
                ),
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(_error),
                        padding: const EdgeInsets.only(top: 8),
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
              const SizedBox(height: 48),
              FadeSlideIn(
                delay: const Duration(milliseconds: 420),
                child: Text(
                  'By continuing you agree to our Privacy Policy.\n'
                  'Guest mode stores no personal data.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedText,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}