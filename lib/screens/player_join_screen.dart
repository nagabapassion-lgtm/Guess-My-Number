import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/player_controller.dart';
import '../services/game_rules.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'player_guess_screen.dart';

/// Screen where the player enters a 6-character invite code and their
/// display name, then joins a waiting room.
///
/// The code is uppercased automatically as the user types. Submissions
/// are wrapped in a try/catch and any error returned by the controller
/// (or thrown by Firestore) is mapped to a short, friendly message
/// shown inline under the fields. The code field is preserved on error
/// so the user can fix a typo, and cleared on success.
class PlayerJoinScreen extends StatefulWidget {
  const PlayerJoinScreen({super.key});

  @override
  State<PlayerJoinScreen> createState() => _PlayerJoinScreenState();
}

class _PlayerJoinScreenState extends State<PlayerJoinScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  /// Friendly, human-readable error message shown above the Join Game
  /// button. We own this string (not the controller) so we can guarantee
  /// no raw Firestore exception text ever leaks to the UI.
  String? _friendlyError;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Rebuild on every keystroke so [canSubmit] stays in sync with the
  /// field values, and clear any stale inline error as soon as the user
  /// starts editing either field.
  void _onFieldChanged() {
    setState(() {
      _friendlyError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Join a Game'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StaggeredFadeSlide(
          verticalSpacing: 16,
          stepDelayMs: 90,
          children: [
            AccentBanner(
              title: 'Have your invite code ready?',
              subtitle:
                  'Type the 6-letter code your friend gave you and pick a name. You will join their game space instantly.',
              icon: Icons.key,
              accent: AppTheme.brightCyan,
            ),
            _LabelledField(
              label: 'Room code',
              hint: 'e.g. ABX923',
              controller: _codeController,
              icon: Icons.key,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                UpperCaseTextFormatter(),
              ],
              onChanged: _onFieldChanged,
            ),
            _LabelledField(
              label: 'Your name',
              hint: 'e.g. Bob',
              controller: _nameController,
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _onJoin(),
              onChanged: _onFieldChanged,
              keyboardType: TextInputType.text,
            ),
            ListenableBuilder(
              listenable: PlayerController.instance,
              builder: (context, _) {
                final controller = PlayerController.instance;
                final codeValid =
                    GameRules.isValidRoomCode(_codeController.text);
                final nameValid =
                    _nameController.text.trim().isNotEmpty;
                final canSubmit =
                    codeValid && nameValid && !controller.isJoining;
                return _JoinButton(
                  isJoining: controller.isJoining,
                  // Always show our friendly message; never the
                  // controller's raw errorMessage. This is the single
                  // chokepoint that prevents Firestore exception text
                  // from reaching the user.
                  errorMessage: _friendlyError,
                  canSubmit: canSubmit,
                  onTap: _onJoin,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Handle the Join Game tap.
  ///
  /// Flow:
  ///   1. Pre-validate locally (empty / bad format / missing name) so
  ///      we never hit Firestore with obviously wrong input. These
  ///      messages are the most actionable, so they get dedicated copy.
  ///   2. Clear any previous error and kick off the join attempt.
  ///   3. The controller may either throw OR set its own errorMessage
  ///      internally - we handle both (try/catch for the throw case,
  ///      read [PlayerController.errorMessage] after the await for the
  ///      other). This makes the screen work whether the controller is
  ///      the current throwing kind or a future result-returning kind.
  ///   4. Map the raw error to a friendly message. The code field is
  ///      intentionally left intact so the user can fix a typo.
  ///   5. On success, clear the fields so stale data doesn't linger if
  ///      the user comes back to this screen later.
  Future<void> _onJoin() async {
    FocusScope.of(context).unfocus();

    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    // 1) Local pre-validation.
    if (code.isEmpty) {
      setState(() => _friendlyError = 'Enter a 6-character code.');
      return;
    }
    if (!GameRules.isValidRoomCode(code)) {
      setState(() => _friendlyError =
          'Codes are 6 letters and numbers. Check it and try again.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _friendlyError =
          'Enter a name so your friend knows who joined.');
      return;
    }

    // 2) Clear previous error and start the join attempt.
    setState(() => _friendlyError = null);

    // 3) Try/catch + post-await errorMessage check covers both controller
    //    styles.
    String? caughtRaw;
    try {
      await PlayerController.instance.joinRoom(
        code: code,
        playerName: name,
      );
    } catch (e) {
      caughtRaw = e.toString();
    }
    if (!mounted) return;

    final rawError = PlayerController.instance.errorMessage ?? caughtRaw;
    if (rawError != null && rawError.isNotEmpty) {
      // 4) Map to friendly message. Code field is intentionally kept.
      setState(() => _friendlyError = _mapError(rawError));
      return;
    }

    // 5) Success: clear fields and navigate.
    _codeController.clear();
    _nameController.clear();
    setState(() => _friendlyError = null);

    Navigator.of(context).pushReplacement(
      AppTheme.pageRoute(const PlayerGuessScreen()),
    );
  }

  /// Map a raw controller/Firestore error string to a short, friendly
  /// message the user can act on.
  ///
  /// We use string matching because we cannot change the controller's
  /// exception types from this screen. The patterns below cover the
  /// FirebasePlatformException codes (e.g. 'permission-denied',
  /// 'not-found', 'unavailable', 'deadline-exceeded') as well as the
  /// most common human-readable variants produced by cloud_firestore
  /// (e.g. 'Missing or insufficient permissions',
  /// 'Failed to get document').
  ///
  /// Order matters: more specific buckets are checked first so we
  /// never accidentally bucket a permission-denied as a network error,
  /// etc.
  String _mapError(String raw) {
    final lower = raw.toLowerCase();

    // Permission denied: Firestore security rules blocked the read or
    // write. For the join flow this usually means the room exists but
    // is no longer in a joinable state (already started, full, or
    // owned by a different player).
    if (lower.contains('permission-denied') ||
        lower.contains('permission_denied') ||
        lower.contains('insufficient permissions') ||
        lower.contains('missing or insufficient')) {
      return "Couldn't join that game. It may have already started.";
    }

    // Not found: the document doesn't exist. Typo in the code, the
    // host cancelled, or the room was never created.
    if (lower.contains('not-found') ||
        lower.contains('not_found') ||
        lower.contains('no such document') ||
        lower.contains('does not exist') ||
        lower.contains("doesn't exist") ||
        lower.contains('no game found') ||
        lower.contains('no room') ||
        lower.contains('unknown code') ||
        lower.contains('code not found') ||
        lower.contains('invalid code')) {
      return 'No game found with that code. Check it and try again.';
    }

    // Network / availability: server unreachable, timeout, offline.
    // 'Failed to get document' is cloud_firestore's generic wrapper
    // message for transport-level failures, so it lives here.
    if (lower.contains('unavailable') ||
        lower.contains('deadline-exceeded') ||
        lower.contains('deadline_exceeded') ||
        lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('unreachable') ||
        lower.contains('failed to get document') ||
        lower.contains('stream interrupted') ||
        lower.contains('offline')) {
      return "Couldn't reach the server. Check your connection.";
    }

    // Already started / in progress / full: same user-facing message
    // as permission-denied, since both boil down to "you can't join
    // this room right now".
    if (lower.contains('already started') ||
        lower.contains('already in progress') ||
        lower.contains('already joined') ||
        lower.contains('game full') ||
        lower.contains('room full')) {
      return "Couldn't join that game. It may have already started.";
    }

    // Fallback: never leak the raw exception text.
    return 'Something went wrong. Try again.';
  }
}

/// A labelled text input. Reduces boilerplate.
class _LabelledField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization? textCapitalization;
  final int? maxLength;
  final VoidCallback? onChanged;
  // TextField.onSubmitted passes the submitted string, so we accept it
  // here too. Callers that don't care about the value can use `_`.
  final ValueChanged<String>? onSubmitted;

  const _LabelledField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppTheme.mutedText,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppTheme.mutedText),
            counterText: maxLength != null ? '' : null,
          ),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          maxLength: maxLength,
          textInputAction:
              onSubmitted != null ? TextInputAction.done : TextInputAction.next,
          onSubmitted: onSubmitted,
          onChanged: (_) => onChanged?.call(),
        ),
      ],
    );
  }
}

class _JoinButton extends StatelessWidget {
  final bool isJoining;
  final String? errorMessage;
  final bool canSubmit;
  final VoidCallback onTap;

  const _JoinButton({
    required this.isJoining,
    required this.errorMessage,
    required this.canSubmit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: errorMessage != null
              ? Container(
                  key: ValueKey(errorMessage),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.crimson.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: AppTheme.crimson,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (errorMessage != null) const SizedBox(height: 12),
        ScaleTap(
          onTap: (canSubmit && !isJoining) ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: canSubmit
                    ? [AppTheme.brightCyan, AppTheme.deepTeal]
                    : [AppTheme.mutedText, AppTheme.mutedText],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: canSubmit
                  ? [
                      BoxShadow(
                        color: AppTheme.brightCyan.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isJoining
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Join Game',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple TextInputFormatter that uppercases text as the user types.
/// Used for the invite code field so the player sees the code in the
/// same shape it will be sent to Firestore.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
