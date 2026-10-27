import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/host_controller.dart';
import '../game_config.dart';
import '../services/game_rules.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'host_waiting_screen.dart';

/// Screen where the host configures and creates a new game room.
///
/// Inputs collected:
///   - Host display name (so the player knows who they are playing against)
///   - Lowest number in the range (default 1)
///   - Highest number in the range (default 100)
///   - Secret number (must be within the range)
///
/// All inputs are validated locally before hitting Firestore so we can
/// give immediate, friendly feedback. The "Create Room" button is
/// disabled while a network call is in flight to prevent double-submit.
class HostSetupScreen extends StatefulWidget {
  const HostSetupScreen({super.key});

  @override
  State<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends State<HostSetupScreen> {
  final _nameController = TextEditingController();
  final _minController =
      TextEditingController(text: GameConfig.defaultMinBound.toString());
  final _maxController =
      TextEditingController(text: GameConfig.defaultMaxBound.toString());
  final _secretController = TextEditingController();

  bool _obscureSecret = true;

  @override
  void dispose() {
    _nameController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Host a New Game'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StaggeredFadeSlide(
          verticalSpacing: 16,
          stepDelayMs: 90,
          children: [
            AccentBanner(
              title: 'Set up your game space',
              subtitle:
                  'Fill in the details below. Your friend will get an invite code to join.',
              icon: Icons.lock_outline,
              accent: AppTheme.deepTeal,
            ),
            _LabelledField(
              label: 'Your name',
              hint: 'e.g. Alice',
              controller: _nameController,
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
            ),
            Row(
              children: [
                Expanded(
                  child: _LabelledField(
                    label: 'Lowest',
                    hint: '1',
                    controller: _minController,
                    icon: Icons.south,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabelledField(
                    label: 'Highest',
                    hint: '100',
                    controller: _maxController,
                    icon: Icons.north,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
              ],
            ),
            _LabelledField(
              label: 'Your secret number',
              hint: 'Pick something between low and high',
              controller: _secretController,
              icon: Icons.lock_outline,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              obscureText: _obscureSecret,
              suffix: IconButton(
                icon: Icon(
                  _obscureSecret
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppTheme.mutedText,
                ),
                onPressed: () {
                  setState(() => _obscureSecret = !_obscureSecret);
                },
                tooltip: _obscureSecret ? 'Show number' : 'Hide number',
              ),
            ),
            _HintCard(
              text:
                  'The secret number must be inside the range you picked. The player will not see it.',
            ),
            ListenableBuilder(
              listenable: HostController.instance,
              builder: (context, _) {
                final controller = HostController.instance;
                return _CreateRoomButton(
                  isWorking: controller.isWorking,
                  errorMessage: controller.errorMessage,
                  onTap: _onCreate,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCreate() async {
    // Dismiss keyboard before we move on.
    FocusScope.of(context).unfocus();

    final hostName = _nameController.text.trim();
    final minBound = int.tryParse(_minController.text.trim());
    final maxBound = int.tryParse(_maxController.text.trim());
    final secret = int.tryParse(_secretController.text.trim());

    if (minBound == null || maxBound == null || secret == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all the numbers using digits only.'),
        ),
      );
      return;
    }

    final validationError = GameRules.validateHostSetup(
      minBound: minBound,
      maxBound: maxBound,
      secretNumber: secret,
      hostName: hostName,
    );
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    await HostController.instance.createRoom(
      hostName: hostName,
      secretNumber: secret,
      minBound: minBound,
      maxBound: maxBound,
    );

    if (!mounted) return;
    if (HostController.instance.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(HostController.instance.errorMessage!)),
      );
      return;
    }

    // Success: move to the waiting screen.
    Navigator.of(context).pushReplacement(
      AppTheme.pageRoute(const HostWaitingScreen()),
    );
  }
}

/// A labelled text input. Reduces boilerplate in the setup screen.
class _LabelledField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffix;
  final TextCapitalization? textCapitalization;

  const _LabelledField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.suffix,
    this.textCapitalization,
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
            suffixIcon: suffix,
          ),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;

  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.brightCyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.brightCyan.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: AppTheme.deepTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.nearBlack,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateRoomButton extends StatelessWidget {
  final bool isWorking;
  final String? errorMessage;
  final VoidCallback onTap;

  const _CreateRoomButton({
    required this.isWorking,
    required this.errorMessage,
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
          onTap: isWorking ? null : onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.deepTeal, AppTheme.brightCyan],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.deepTeal.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: isWorking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Room',
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
