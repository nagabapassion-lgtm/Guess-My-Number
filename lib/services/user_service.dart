import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reads and writes the user's profile document at /users/{uid}.
///
/// Schema:
///   users/{uid}:
///     username:      string (1..24 chars) — the editable display name
///     displayName:   string — Google display name (or empty for guests)
///     photoUrl:      string — Google photo URL (or empty)
///     isAnonymous:   bool   — true if signed in as guest
///     updatedAt:     timestamp
///
/// The username is used everywhere in the UI instead of typed-in names.
/// It defaults to the Google display name on first sign-in, but the
/// user can change it once and it sticks across all games and devices.
///
/// v1 (this file): usernames are NOT unique. Two users can have the
/// same name. The real identity is the Firebase Auth uid, not the
/// username. This is how Wordle, Codenames, and most casual games
/// work. We can add uniqueness in a future phase if needed.
class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// The current user's profile, or null if not signed in.
  /// Stream emits immediately with the cached value, then re-emits
  /// whenever the profile changes in Firestore.
  Stream<UserProfile?> watchMyProfile() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(null);
    }
    return _db.collection('users').doc(user.uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return UserProfile.fromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  /// Read the current user's profile once. Returns null if not signed
  /// in or if the profile doc doesn't exist yet (first sign-in).
  Future<UserProfile?> getMyProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snapshot = await _db.collection('users').doc(user.uid).get();
    if (!snapshot.exists) return null;
    return UserProfile.fromFirestore(snapshot.id, snapshot.data()!);
  }

  /// Get a display name to use in the UI. Falls back through:
  ///   1. Custom username from Firestore (if set)
  ///   2. Google display name (if signed in with Google)
  ///   3. 'Guest' (if anonymous)
  ///
  /// Used by the host setup and player join screens to pre-fill the
  /// name field. The user can still edit it for a single game if
  /// they want, but the saved username is what shows up next time.
  Future<String> getDisplayName() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    // Try Firestore profile first.
    final profile = await getMyProfile();
    if (profile != null && profile.username.trim().isNotEmpty) {
      return profile.username.trim();
    }

    // Fall back to Google display name.
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }

    // Final fallback.
    return 'Guest';
  }

  /// Save the username for the current user. Creates the profile
  /// doc if it doesn't exist; updates it if it does. Also stores
  /// the Google display name and photo URL so we have a complete
  /// picture of the user even if they later change their username.
  ///
  /// THROWS with a friendly message if:
  ///   - The user is not signed in
  ///   - The username is empty or longer than 24 chars
  ///   - The Firestore write fails (network, permissions, etc.)
  Future<void> saveUsername(String username) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You are not signed in. Please restart the app.');
    }

    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      throw Exception('Username cannot be empty.');
    }
    if (trimmed.length > 24) {
      throw Exception('Username must be 24 characters or fewer.');
    }

    final ref = _db.collection('users').doc(user.uid);
    await ref.set({
      'username': trimmed,
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'isAnonymous': user.isAnonymous,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Ensure a profile doc exists for the current user. Called on app
  /// boot so the user's profile is seeded with their Google display
  /// name even before they visit the profile screen. No-op if the
  /// doc already exists.
  Future<void> ensureProfileExists() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    if (snapshot.exists) return;

    // Profile doesn't exist yet — seed it with defaults from the
    // Google account (or empty for guests).
    await ref.set({
      'username': user.displayName ?? '',
      'displayName': user.displayName ?? '',
      'photoUrl': user.photoURL ?? '',
      'isAnonymous': user.isAnonymous,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// One user's profile. Mirrors the Firestore document at /users/{uid}.
class UserProfile {
  final String uid;
  final String username;
  final String displayName;
  final String photoUrl;
  final bool isAnonymous;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.photoUrl,
    required this.isAnonymous,
    this.updatedAt,
  });

  factory UserProfile.fromFirestore(String id, Map<String, dynamic> data) {
    return UserProfile(
      uid: id,
      username: data['username'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String? ?? '',
      isAnonymous: data['isAnonymous'] as bool? ?? false,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// The name to show in the UI: custom username if set, otherwise
  /// Google display name, otherwise 'Guest'.
  String get effectiveDisplayName {
    if (username.trim().isNotEmpty) return username.trim();
    if (displayName.trim().isNotEmpty) return displayName.trim();
    return 'Guest';
  }
}
