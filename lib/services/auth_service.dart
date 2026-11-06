import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper around FirebaseAuth so the rest of the app does not
/// import firebase_auth directly.
///
/// v2.1: Added Google sign-in alongside anonymous. Uses Firebase
/// Auth's native signInWithPopup method (instead of the
/// google_sign_in package) which is more reliable on Flutter Web
/// and doesn't require a separate OAuth client config.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sign in anonymously, reusing the existing session when present.
  Future<User> signInAnonymously() async {
    var user = _auth.currentUser;
    if (user != null) return user;
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  /// Sign in with Google via Firebase Auth's popup flow.
  ///
  /// This is the recommended way for Flutter Web. It uses Firebase
  /// Auth's built-in OAuth flow which:
  ///   - Uses the API key from firebase_options.dart (already configured)
  ///   - Doesn't need a separate OAuth client ID
  ///   - Doesn't need the google_sign_in package
  ///   - Handles the popup, consent, and redirect automatically
  ///
  /// THROWS if the user closes the popup or denies permission.
  Future<User> signInWithGoogle() async {
    // Create the Google provider.
    final googleProvider = GoogleAuthProvider();

    // Request the scopes we need (email + profile).
    googleProvider.addScope('email');
    googleProvider.addScope('profile');

    // Set the language for the consent screen (uses the browser's
    // language by default).
    _auth.setLanguageCode('en');

    // Trigger the popup. This opens a new browser window with the
    // Google account picker.
    final userCredential = await _auth.signInWithPopup(googleProvider);
    return userCredential.user!;
  }

  /// The currently signed-in user, or null if not signed in.
  User? get currentUser => _auth.currentUser;

  /// True if the current user signed in with Google (vs anonymous).
  bool get isGoogleUser {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((info) => info.providerId == 'google.com');
  }

  /// Sign out. Used by the "Sign out" button on the home screen.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}