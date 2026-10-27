import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture Flutter framework errors and print them loudly so
  // we never end up with a silent white screen again.
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[FLUTTER ERROR] ${details.exception}');
    debugPrint('[FLUTTER STACK] ${details.stack}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[ASYNC ERROR] $error');
    debugPrint('[ASYNC STACK] $stack');
    return true;
  };

  // Step 1: Initialize Firebase core ONLY.
  // We do NOT pre-warm anonymous auth here - that was the bug that
  // caused the white screen. Each controller (HostController,
  // PlayerController, DailyChallengeService) calls
  // _auth.signInAnonymously() before its first Firestore write,
  // so auth happens on demand. This is the original design that
  // worked before the v3 "fix" introduced the hang.
  debugPrint('[boot] step 1: initializing Firebase core...');
  FirebaseApp? firebaseApp;
  Object? initError;
  try {
    firebaseApp = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'Firebase.initializeApp timed out after 10s. '
        'Check your network and firebase_options.dart.',
      ),
    );
    debugPrint('[boot] step 1 OK: project = '
        '${firebaseApp.options.projectId}');
  } catch (error, stack) {
    initError = error;
    debugPrint('[boot] step 1 FAILED: $error');
    debugPrint('[boot] stack: $stack');
  }

  // Step 2: Run the app IMMEDIATELY. No auth warmup, no waiting.
  // The home screen renders right away. Auth happens when the user
  // taps "Host a Game" / "Join a Game" / "Play Solo" - each
  // controller calls _auth.signInAnonymously() before its first
  // Firestore write, so the auth context is ready by the time the
  // write lands.
  debugPrint('[boot] step 2: runApp...');
  runApp(
    GuessMyNumberApp(
      initializationError: initError,
      projectId: firebaseApp?.options.projectId,
    ),
  );
}

class GuessMyNumberApp extends StatelessWidget {
  final Object? initializationError;
  final String? projectId;

  const GuessMyNumberApp({
    super.key,
    this.initializationError,
    this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    if (initializationError != null) {
      return MaterialApp(
        title: 'Guess My Number - Boot Error',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        home: _BootErrorScreen(
          error: initializationError!,
          projectId: projectId,
        ),
      );
    }
    return MaterialApp(
      title: 'Guess My Number',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.data,
      home: const HomeScreen(),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  final Object error;
  final String? projectId;

  const _BootErrorScreen({required this.error, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final message = error.toString();
    return Scaffold(
      backgroundColor: const Color(0xFFFEF2F2),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              const Text(
                'Could not start the game',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                projectId == null
                    ? 'Firebase did not initialize.'
                    : 'Firebase project: $projectId',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF7F1D1D),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: SelectableText(
                  message,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF7F1D1D),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Open the browser dev tools (F12) → Console tab for more detail. '
                'Every boot step is logged with [boot] prefix.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}