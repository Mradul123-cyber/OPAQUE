import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GoogleAuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignInInstance;

  /// Sign in with Google - Works for both new users and existing users
  /// Returns UserCredential on success, throws exception on failure
  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web implementation
        return await _signInWithGoogleWeb();
      } else {
        // Mobile implementation (Android/iOS)
        return await _signInWithGoogleMobile();
      }
    } catch (e) {
      // print('[GoogleAuth] Sign-in error: $e');
      rethrow;
    }
  }

  /// Web-specific Google Sign-In
  Future<UserCredential> _signInWithGoogleWeb() async {
    // print('[GoogleAuth] Starting web sign-in...');

    // Create Google Auth Provider
    final GoogleAuthProvider googleProvider = GoogleAuthProvider();

    // Add scopes for additional permissions (optional)
    googleProvider.addScope('email');
    googleProvider.addScope('profile');

    // Sign in with popup
    final UserCredential userCredential = await _firebaseAuth.signInWithPopup(googleProvider);

    // print('[GoogleAuth] Web sign-in successful for: ${userCredential.user?.email}');
    return userCredential;
  }

  /// Mobile-specific Google Sign-In (Android/iOS) using v7.2.0 API
  Future<UserCredential> _signInWithGoogleMobile() async {
    // print('[GoogleAuth] Starting mobile sign-in...');

    // Initialize GoogleSignIn instance using v7.2.0 API
    _googleSignInInstance ??= GoogleSignIn.instance;

    // Initialize (required in v7.x)
    await _googleSignInInstance!.initialize();

    // Disconnect first to force account picker to show
    // This ensures user can choose which Google account to use
    await _googleSignInInstance!.disconnect();

    // Show account picker - user can choose their Google account
    final account = await _googleSignInInstance!.authenticate();

    // print('[GoogleAuth] Google user authenticated: ${account.email}');

    // Get ID token for Firebase authentication
    final authentication = account.authentication;
    final idToken = authentication.idToken;

    if (idToken == null) {
      throw Exception('Failed to get ID token from Google');
    }

    // print('[GoogleAuth] Got Google ID token');

    // Create a new credential for Firebase (v7.2.0 only provides idToken)
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: idToken,
    );

    // Sign in to Firebase with the Google credential
    final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);

    // print('[GoogleAuth] Firebase sign-in successful for: ${userCredential.user?.email}');
    return userCredential;
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      if (!kIsWeb && _googleSignInInstance != null) {
        // Disconnect from Google on mobile using v7.2.0 API
        await _googleSignInInstance!.disconnect();
      }
      await _firebaseAuth.signOut();
      // print('[GoogleAuth] Sign-out successful');
    } catch (e) {
      // print('[GoogleAuth] Sign-out error: $e');
      rethrow;
    }
  }

  /// Check if user is currently signed in with Google
  bool isSignedInWithGoogle() {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;

    // Check if any provider is Google
    return user.providerData.any((info) => info.providerId == 'google.com');
  }

  /// Get current Google user (mobile only) - v7.2.0 API
  Future<GoogleSignInAccount?> getCurrentGoogleUser() async {
    if (kIsWeb) return null;

    try {
      _googleSignInInstance ??= GoogleSignIn.instance;
      await _googleSignInInstance!.initialize();
      return await _googleSignInInstance!.attemptLightweightAuthentication();
    } catch (e) {
      // print('[GoogleAuth] Error getting current user: $e');
      return null;
    }
  }

  /// Generate username from Google email
  /// Example: "john.doe@gmail.com" → "johndoe"
  static String generateUsernameFromEmail(String email) {
    // Extract part before @
    final localPart = email.split('@')[0];

    // Remove dots, underscores, and special characters
    final cleanUsername = localPart
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();

    return cleanUsername;
  }

  /// Get user info from Google account
  Map<String, String?> getUserInfo(User user) {
    return {
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'uid': user.uid,
      'suggestedUsername': user.email != null
          ? generateUsernameFromEmail(user.email!)
          : null,
    };
  }
}
