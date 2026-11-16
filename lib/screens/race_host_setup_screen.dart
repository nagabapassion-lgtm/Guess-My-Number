import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/race_controller.dart';
import '../game_config.dart';
import '../services/game_rules.dart';
import '../services/user_service.dart';
import '../widgets/animations.dart';
import '../widgets/ui_components.dart';
import 'race_host_waiting_screen.dart';

/// Screen where the host configures and creates a RACE MODE room.
///
/// Inputs:
///   - Host display name (pre-filled from Firestore username)
///   - Lowest number in the range (default 1)
///   - Highest number in the range (default 100)
///   - Secret number (must be within the range)
///   - Max players (2-5, default 4)
///
/// On submit, creates the race room and navigates to the waiting screen
/// where the host watches the roster fill up.
class RaceHostSetupScreen extends StatefulWidget {
  const RaceHostSetupScreen({super.key});

  @override
  State<RaceHostSetupScreen> createState() => _RaceHostSetupScreenState();
}

class _RaceHostSetupScreenState extends State<RaceHostSetupScreen> {
  final _nameController = TextEditingController();
  final _minController =
      TextEditingController(text: GameConfig.defaultMinBound.toString());
  final _maxController =
      TextEditingController(text: GameConfig.defaultMaxBound.toString());
  final _secretController = TextEditingController();
  int _maxPlayers = 4;

  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    UserService().getDisplayName().then((name) {
      if (mounted && name.isNotEmpty) {
        setState(() => _nameController.text = name);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final hostName = _nameController.text.trim();
    final minBound = int.tryParse(_minController.text.trim());
    final maxBound = int.tryParse(_maxController.text.trim());
    final secret = int.tryParse(_secretController.text.trim());

    if (minBound == null || maxBound == null || secret == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in all the numbers using digits only.')),
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

    await RaceHostController.instance.createRaceRoom(
      hostName: hostName,
      secretNumber: secret,
      minBound: minBound,
      maxBound: maxBound,
      maxPlayers: _maxPlayers,
    );

    if (!mounted) return;
    if (RaceHostController.instance.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RaceHostController.instance.errorMessage!)),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      AppTheme.pageRoute(const RaceHostWaitingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(title: const Text('Host a Race')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: StaggeredFadeSlide(
          verticalSpacing: 16,
          stepDelayMs: 90,
          children: [
            AccentBanner(
              title: 'Set up your race',
              subtitle:
                  'Pick a secret number and a range. 2-5 players will race '
                  'to guess it first. Everyone guesses at the same time.',
              icon: Icons.groups,
              accent: AppTheme.brightCyan,
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
                    label: 'Min',
                    hint: '1',
                    controller: _minController,
                    icon: Icons.arrow_downward,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabelledField(
                    label: 'Max',
                    hint: '100',
                    controller: _maxController,
                    icon: Icons.arrow_upward,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            _LabelledField(
              label: 'Secret number',
              hint: 'Between min and max',
              controller: _secretController,
              icon: Icons.lock_outline,
              keyboardType: TextInputType.number,
              obscure: _obscureSecret,
              suffix: IconButton(
                icon: Icon(_obscureSecret
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureSecret = !_obscureSecret),
              ),
            ),
            // Max players selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.outlineVariant, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_outline,
                      color: AppTheme.mutedText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Max players',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  ...List.generate(4, (i) {
                    final count = i + 2; // 2, 3, 4, 5
                    final selected = _maxPlayers == count;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _maxPlayers = count),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.deepTeal : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? AppTheme.deepTeal
                                  : AppTheme.outlineVariant,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: selected ? Colors.white : AppTheme.nearBlack,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: RaceHostController.instance,
              builder: (context, _) {
                final controller = RaceHostController.instance;
                return ScaleTap(
                  onTap: controller.isWorking ? null : _createRoom,
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
                          color: AppTheme.brightCyan.withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: controller.isWorking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Create Race Room',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
  final TextCapitalization? textCapitalization;
  final int? maxLength;
  final bool obscure;
  final Widget? suffix;

  const _LabelledField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization,
    this.maxLength,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.mutedText,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization ?? TextCapitalization.none,
          maxLength: maxLength,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppTheme.mutedText),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
