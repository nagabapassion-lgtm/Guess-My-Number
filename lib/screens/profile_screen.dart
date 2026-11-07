import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../widgets/animations.dart';
import 'home_screen.dart';

/// The user's profile screen. Shows their account info and lets them
/// edit their username (which is used everywhere in the game instead
/// of typed-in names).
///
/// Three sections:
///   1. Account header — avatar (Google photo or default), email
///      (if Google user), "Guest" badge if anonymous.
///   2. Username editor — text field pre-filled with current
///      username, Save button. Saved to Firestore /users/{uid}.
///   3. Sign out button — signs out and returns to sign-in screen.
///
/// Future sections (placeholders for Phase 2.3 game history):
///   - "Your stats" — total games, win rate, average guesses
///   - "Recent games" — list of past games with date, opponent, result
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final _usernameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMessage;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      // Ensure the profile doc exists (seeds it with Google display
      // name on first visit).
      await _userService.ensureProfileExists();
      final profile = await _userService.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _usernameController.text = profile?.username ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your profile. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _saveUsername() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      await _userService.saveUsername(_usernameController.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _successMessage = 'Username saved.';
      });
      // Clear the success message after 2 seconds.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (error) {
      if (!mounted) return;
      final msg = error.toString().toLowerCase();
      setState(() {
        _saving = false;
        if (msg.contains('empty')) {
          _error = 'Username cannot be empty.';
        } else if (msg.contains('24')) {
          _error = 'Username must be 24 characters or fewer.';
        } else if (msg.contains('network') || msg.contains('unavailable')) {
          _error = 'Network error. Check your connection.';
        } else if (msg.contains('permission')) {
          _error = 'Permission denied. Deploy the latest Firestore rules.';
        } else {
          _error = 'Could not save username. Try again.';
        }
      });
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will be returned to the sign-in screen. Your game '
          'history is saved to your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppTheme.pageRoute(const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.offWhite,
        appBar: AppBar(title: const Text('Your Profile')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.brightCyan),
        ),
      );
    }

    final isGoogleUser = _authService.isGoogleUser;
    final displayName = user?.displayName ?? '';
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;

    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Your Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StaggeredFadeSlide(
          verticalSpacing: 20,
          stepDelayMs: 80,
          children: [
            // --- Account header ---
            _AccountHeader(
              photoUrl: photoUrl,
              displayName: displayName,
              email: email,
              isGoogleUser: isGoogleUser,
              username: _profile?.effectiveDisplayName ?? 'Guest',
            ),

            // --- Username editor ---
            _UsernameEditor(
              controller: _usernameController,
              onSave: _saveUsername,
              saving: _saving,
              error: _error,
              successMessage: _successMessage,
            ),

            // --- Stats placeholder (Phase 2.3) ---
            _StatsPlaceholder(),

            // --- Sign out button ---
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.crimson,
                side: const BorderSide(color: AppTheme.crimson, width: 1.5),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Account ID: ${user?.uid ?? "—"}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Account header: avatar + name + email + guest badge.
class _AccountHeader extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final String email;
  final bool isGoogleUser;
  final String username;

  const _AccountHeader({
    required this.photoUrl,
    required this.displayName,
    required this.email,
    required this.isGoogleUser,
    required this.username,
  });

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
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: photoUrl == null
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.deepTeal, AppTheme.brightCyan],
                    )
                  : null,
              image: photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photoUrl == null
                ? const Icon(Icons.person, color: Colors.white, size: 32)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isGoogleUser)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.brightCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'GOOGLE ACCOUNT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.brightCyan,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.mutedText.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'GUEST',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.mutedText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  displayName.isEmpty ? 'Guest' : displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.nearBlack,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedText,
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

/// Username editor: text field + Save button + status messages.
class _UsernameEditor extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSave;
  final bool saving;
  final String? error;
  final String? successMessage;

  const _UsernameEditor({
    required this.controller,
    required this.onSave,
    required this.saving,
    required this.error,
    required this.successMessage,
  });

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
          Row(
            children: [
              const Icon(Icons.edit, color: AppTheme.deepTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your username',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nearBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'This is the name other players see when you host or join a game. '
            'You can change it any time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.mutedText,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            enabled: !saving,
            decoration: InputDecoration(
              hintText: 'e.g. Passion',
              prefixIcon:
                  const Icon(Icons.person_outline, color: AppTheme.mutedText),
              counterText: '${controller.text.length}/24',
            ),
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: error != null
                ? Padding(
                    key: ValueKey(error),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppTheme.crimson,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : successMessage != null
                    ? Padding(
                        key: ValueKey(successMessage),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          successMessage!,
                          style: const TextStyle(
                            color: AppTheme.deepTeal,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text('Save Username'),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for Phase 2.3 game history. We'll replace this with
/// real stats (win rate, total games, average guesses) and a recent
/// games list in the next phase.
class _StatsPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppTheme.mutedText, size: 20),
              const SizedBox(width: 8),
              Text(
                'Game history',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nearBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your stats and recent games will appear here in a future update.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.mutedText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
