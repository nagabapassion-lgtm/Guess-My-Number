import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  debugPrint('[boot] step 1: initializing Firebase core...');
  FirebaseApp? firebaseApp;
  Object? initError;
  try {
    firebaseApp = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'Firebase.initializeApp timed out after 10s.',
      ),
    );
    debugPrint('[boot] step 1 OK: project = '
        '${firebaseApp.options.projectId}');
  } catch (error, stack) {
    initError = error;
    debugPrint('[boot] step 1 FAILED: $error');
    debugPrint('[boot] stack: $stack');
  }

  // Subscribe to auth state changes so the app reacts instantly
  // when the user signs in or out. We don't need to do anything
  // in the callback - MaterialApp reroutes based on the stream
  // below.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    debugPrint('[auth] state changed: ${user == null ? "signed out" : "signed in as ${user.uid}"}');
  });

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
      home: const _AuthGate(),
    );
  }
}

/// Decides which screen to show based on auth state.
///
/// - If the user is signed in (Google or anonymous), shows HomeScreen.
/// - If not, shows SignInScreen.
///
/// Listens to FirebaseAuth.instance.authStateChanges() so the
/// transition is instant when the user signs in or out.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppTheme.offWhite,
            body: const Center(
              child: CircularProgressIndicator(color: AppTheme.brightCyan),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        return const SignInScreen();
      },
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
            ],
          ),
        ),
      ),
    );
  }
}