import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.code, this.message);
  final String code, message;
}

class OpaqueAuthService {
  static final interactive = ValueNotifier<bool>(false);
  static const timeout = Duration(seconds: 20);
  static bool needsEmailVerification(User user) =>
      user.providerData.any((p) => p.providerId == 'password') &&
      !user.emailVerified &&
      !user.providerData.any(
        (p) => p.providerId == 'google.com' || p.providerId == 'phone',
      );

  static Future<Map<String, String>> headers(User user, {bool forceRefresh = false}) async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await user.getIdToken(forceRefresh)}',
  };
  static AuthApiException failure(http.Response response) {
    debugPrint('[AuthFlow] ⚠️ Parsing failure response (${response.statusCode}): ${response.body}');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = body['error']?.toString() ?? 'server_error';
      final message = body['message']?.toString() ??
          'Could not complete this request. Please try again.';
      debugPrint('[AuthFlow] ⚠️ Parsed AuthApiException: code="$code", message="$message"');
      return AuthApiException(code, message);
    } catch (e) {
      debugPrint('[AuthFlow] ⚠️ Failed to decode JSON error body: $e');
      return AuthApiException(
        'server_error',
        response.statusCode == 429
            ? 'Too many attempts. Please wait before trying again.'
            : 'Could not complete this request (${response.statusCode}). Please try again.',
      );
    }
  }

  static Future<bool> profileExists(User user) async {
    debugPrint('[AuthFlow] 🌐 GET ${AppConfig.baseUrl}/profiles/me for UID: ${user.uid} (email: ${user.email})');
    final response = await http
        .get(
          Uri.parse('${AppConfig.baseUrl}/profiles/me'),
          headers: await headers(user),
        )
        .timeout(timeout);
    debugPrint('[AuthFlow] ⬅️ GET /profiles/me response: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = (data['display_name'] ?? data['displayName']) as String?;
        final username = (data['username'] ?? data['userName']) as String?;
        final resolved = (displayName?.trim().isNotEmpty == true)
            ? displayName!.trim()
            : ((username?.trim().isNotEmpty == true) ? username!.trim() : null);
        final avatar = (data['avatarUrl'] ?? data['profile_picture_url'] ?? data['avatar_url'] ?? data['avatar']) as String?;
        final prefs = await SharedPreferences.getInstance();
        if (resolved != null && resolved.isNotEmpty) {
          await prefs.setString('cached_user_display_name', resolved);
          unawaited(user.updateDisplayName(resolved).catchError((_) {}));
        }
        if (username != null && username.isNotEmpty) {
          await prefs.setString('cached_user_username', username);
        }
        if (avatar != null && avatar.isNotEmpty && (user.photoURL == null || user.photoURL!.isEmpty)) {
          unawaited(user.updatePhotoURL(avatar).catchError((_) {}));
        }
        await prefs.setString('cached_user_uid', user.uid);
      } catch (e) {
        debugPrint('[AuthFlow] ⚠️ profileExists error caching profile details: $e');
      }
      return true;
    }
    if (response.statusCode == 404 &&
        failure(response).code == 'profile_not_found')
      return false;
    throw failure(response);
  }

  static Future<void> checkUsername(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('[AuthFlow] 🌐 POST ${AppConfig.baseUrl}/profiles/check-username username="$username"');
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profiles/check-username'),
          headers: user == null
              ? {'Content-Type': 'application/json'}
              : await headers(user),
          body: jsonEncode({'username': username}),
        )
        .timeout(timeout);
    debugPrint('[AuthFlow] ⬅️ POST /profiles/check-username response: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode != 200) throw failure(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['available'] != true) {
      debugPrint('[AuthFlow] ❌ Username "$username" is unavailable: ${body['reason']}');
      throw AuthApiException(
        'username_taken',
        body['reason']?.toString() ?? 'That username is unavailable.',
      );
    }
    debugPrint('[AuthFlow] ✅ Username "$username" is available');
  }

  static Future<void> saveUsername(User user, String username) async {
    debugPrint('[AuthFlow] 💾 saveUsername to prefs for UID: ${user.uid} -> "$username"');
    await (await SharedPreferences.getInstance()).setString(
      'opaque_signup_username_${user.uid}',
      username,
    );
  }

  static Future<String?> pendingUsername(User user) async {
    final pending = (await SharedPreferences.getInstance()).getString(
      'opaque_signup_username_${user.uid}',
    );
    debugPrint('[AuthFlow] 🔍 pendingUsername for UID ${user.uid}: "$pending"');
    return pending;
  }

  static Future<void> clearDraft(User user) async {
    debugPrint('[AuthFlow] 🧹 clearDraft for UID: ${user.uid}');
    await (await SharedPreferences.getInstance()).remove(
      'opaque_signup_username_${user.uid}',
    );
  }

  static Future<void> createProfile(
    User user,
    String username,
    String displayName,
  ) async {
    debugPrint('[AuthFlow] ➡️ createProfile called. UID: ${user.uid}, email: "${user.email}", emailVerified: ${user.emailVerified}, username: "$username", displayName: "$displayName"');
    await user.reload();
    final current = FirebaseAuth.instance.currentUser;
    debugPrint('[AuthFlow] ➡️ After reload: current UID: ${current?.uid}, email: "${current?.email}", emailVerified: ${current?.emailVerified}');
    if (current == null || current.uid != user.uid)
      throw StateError('Please sign in again.');
    if (needsEmailVerification(current))
      throw StateError('Verify your email before continuing.');

    final payload = {
      'username': username,
      if (displayName.isNotEmpty) 'displayName': displayName,
    };
    debugPrint('[AuthFlow] 🌐 POST ${AppConfig.baseUrl}/profiles/create payload: ${jsonEncode(payload)}');
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profiles/create'),
          headers: await headers(current),
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    debugPrint('[AuthFlow] ⬅️ POST /profiles/create response code: ${response.statusCode}, body: ${response.body}');
    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('[AuthFlow] ❌ POST /profiles/create failed with status ${response.statusCode}');
      throw failure(response);
    }
    debugPrint('[AuthFlow] ✅ Profile created successfully on backend!');
    try {
      final resolved = displayName.trim().isNotEmpty ? displayName.trim() : username.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_display_name', resolved);
      await prefs.setString('cached_user_username', username.trim());
      await prefs.setString('cached_user_uid', user.uid);
      unawaited(user.updateDisplayName(resolved).catchError((_) {}));
    } catch (_) {}
  }

  static Future<void> saveAvatar(User user, String avatar) async {
    debugPrint('[AuthFlow] 🌐 POST ${AppConfig.baseUrl}/profile/avatar/update avatarUrl: $avatar');
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profile/avatar/update'),
          headers: await headers(user),
          body: jsonEncode({'avatarUrl': avatar}),
        )
        .timeout(timeout);
    debugPrint('[AuthFlow] ⬅️ POST /profile/avatar/update response: ${response.statusCode}');
    if (response.statusCode != 200) throw failure(response);
  }

  static String errorMessage(Object error) {
    if (error is AuthApiException) return error.message;
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Could not sign in. Check your details and try again.',
        'email-already-in-use' =>
          'An account already uses this email. Please log in instead.',
        'account-exists-with-different-credential' =>
          'Use your existing sign-in method for this account.',
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' => 'Choose a stronger password.',
        'invalid-phone-number' =>
          'Enter a valid phone number with country code.',
        'invalid-verification-code' =>
          'That code does not match. Please try again.',
        'session-expired' => 'This code has expired. Request a new one.',
        'too-many-requests' || 'quota-exceeded' =>
          'Too many attempts. Please wait before trying again.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        'user-disabled' => 'This account is unavailable. Contact support.',
        'requires-recent-login' =>
          'Please sign in again before making this change.',
        'operation-not-allowed' =>
          'This operation is currently not allowed by the authentication service.',
        _ => 'Authentication could not be completed. Please try again.',
      };
    }
    if (error is TimeoutException)
      return 'The connection timed out. Please try again.';
    if (error is StateError) return error.message.toString();
    return 'Something went wrong. Please try again.';
  }
}
