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

  static Future<Map<String, String>> headers(User user) async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await user.getIdToken(true)}',
  };
  static AuthApiException failure(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return AuthApiException(
        body['error']?.toString() ?? 'server_error',
        body['message']?.toString() ??
            'Could not complete this request. Please try again.',
      );
    } catch (_) {
      return AuthApiException(
        'server_error',
        response.statusCode == 429
            ? 'Too many attempts. Please wait before trying again.'
            : 'Could not complete this request (${response.statusCode}). Please try again.',
      );
    }
  }

  static Future<bool> profileExists(User user) async {
    final response = await http
        .get(
          Uri.parse('${AppConfig.baseUrl}/profiles/me'),
          headers: await headers(user),
        )
        .timeout(timeout);
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404 &&
        failure(response).code == 'profile_not_found')
      return false;
    throw failure(response);
  }

  static Future<void> checkUsername(String username) async {
    final user = FirebaseAuth.instance.currentUser;
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profiles/check-username'),
          headers: user == null
              ? {'Content-Type': 'application/json'}
              : await headers(user),
          body: jsonEncode({'username': username}),
        )
        .timeout(timeout);
    if (response.statusCode != 200) throw failure(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['available'] != true)
      throw AuthApiException(
        'username_taken',
        body['reason']?.toString() ?? 'That username is unavailable.',
      );
  }

  static Future<void> saveUsername(User user, String username) async {
    await (await SharedPreferences.getInstance()).setString(
      'opaque_signup_username_${user.uid}',
      username,
    );
  }

  static Future<String?> pendingUsername(User user) async =>
      (await SharedPreferences.getInstance()).getString(
        'opaque_signup_username_${user.uid}',
      );
  static Future<void> clearDraft(User user) async {
    await (await SharedPreferences.getInstance()).remove(
      'opaque_signup_username_${user.uid}',
    );
  }

  static Future<void> createProfile(
    User user,
    String username,
    String displayName,
  ) async {
    await user.reload();
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != user.uid)
      throw StateError('Please sign in again.');
    if (needsEmailVerification(current))
      throw StateError('Verify your email before continuing.');
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profiles/create'),
          headers: await headers(current),
          body: jsonEncode({
            'username': username,
            if (displayName.isNotEmpty) 'displayName': displayName,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200 && response.statusCode != 201)
      throw failure(response);
  }

  static Future<void> saveAvatar(User user, String avatar) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.baseUrl}/profile/avatar/update'),
          headers: await headers(user),
          body: jsonEncode({'avatarUrl': avatar}),
        )
        .timeout(timeout);
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
