import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper around FirebaseAuth so the rest of the app does not
/// import firebase_auth directly. This makes the controllers easy to
/// unit-test (substitute a fake AuthService) and keeps the auth
/// details in one place.
///
/// v1 / v4: anonymous auth only. Phase 2 will add Google sign-in
/// (the same AuthService will gain a `signInWithGoogle()` method
/// that returns a UserCredential - controllers stay the same shape).
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sign in anonymously, reusing the existing session when present.
  /// Safe to call repeatedly - if a user is already signed in, this
  /// returns the same user without making a new auth call.
  Future<User> signInAnonymously() async {
    var user = _auth.currentUser;
    if (user != null) return user;
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  /// The currently signed-in user, or null if not signed in yet.
  /// The controllers call this before any Firestore write so they
  /// can re-trigger sign-in if needed.
  User? get currentUser => _auth.currentUser;

  /// Sign out. Currently unused but kept for Phase 2 (Google sign-in
  /// needs a way to switch accounts).
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
