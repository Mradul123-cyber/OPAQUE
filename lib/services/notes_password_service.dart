import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service to manage Notes password lock feature
/// Uses Flutter Secure Storage (Android KeyStore / iOS Keychain) for security
class NotesPasswordService {
  static final NotesPasswordService instance = NotesPasswordService._init();
  final _storage = const FlutterSecureStorage();

  static const String _passwordHashKey = 'notes_password_hash';
  static const String _passwordEnabledKey = 'notes_password_enabled';

  NotesPasswordService._init();

  /// Check if password protection is enabled
  Future<bool> isPasswordEnabled() async {
    final enabled = await _storage.read(key: _passwordEnabledKey);
    return enabled == 'true';
  }

  /// Set up a new password for notes
  /// Returns true if successful
  Future<bool> setPassword(String password) async {
    if (password.isEmpty || password.length < 4) {
      return false; // Minimum 4 characters
    }

    try {
      // Hash the password using SHA-256
      final hash = _hashPassword(password);

      // Store hash in secure storage
      await _storage.write(key: _passwordHashKey, value: hash);
      await _storage.write(key: _passwordEnabledKey, value: 'true');

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Verify if the entered password is correct
  Future<bool> verifyPassword(String password) async {
    try {
      final storedHash = await _storage.read(key: _passwordHashKey);
      if (storedHash == null) {
        return false;
      }

      final enteredHash = _hashPassword(password);
      return storedHash == enteredHash;
    } catch (e) {
      return false;
    }
  }

  /// Change the password
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    // Verify old password first
    final isValid = await verifyPassword(oldPassword);
    if (!isValid) {
      return false;
    }

    // Set new password
    return await setPassword(newPassword);
  }

  /// Disable password protection
  Future<void> disablePassword() async {
    await _storage.delete(key: _passwordHashKey);
    await _storage.write(key: _passwordEnabledKey, value: 'false');
  }

  /// Remove all password data
  Future<void> clearAll() async {
    await _storage.delete(key: _passwordHashKey);
    await _storage.delete(key: _passwordEnabledKey);
  }

  /// Hash password using SHA-256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }
}
