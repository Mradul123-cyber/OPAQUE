import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure Storage Service - Wrapper for flutter_secure_storage
/// Uses Android Keystore (Android) and Keychain (iOS) for secure storage
class SecureStorageService {
  // Singleton instance
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  // Flutter secure storage instance with Android-specific options
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // This uses Android Keystore under the hood
      resetOnError: false, // Do not wipe storage on transient Keystore errors
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // Storage keys
  String get _keyAutoBackupPassphrase {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to access backup credentials');
    return 'auto_backup_passphrase_$uid';
  }

  /// Save auto-backup passphrase securely
  Future<void> saveAutoBackupPassphrase(String passphrase) async {
    try {
      await _storage.write(
        key: _keyAutoBackupPassphrase,
        value: passphrase,
      );
      debugPrint('[SecureStorage] Auto-backup passphrase saved securely');
    } catch (e) {
      debugPrint('[SecureStorage] Error saving passphrase: $e');
      rethrow;
    }
  }

  // Called only after native code confirms ownership of the legacy configuration.
  Future<void> migrateLegacyAutoBackupPassphrase(String uid) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Backup account changed');
    final key = 'auto_backup_passphrase_$uid';
    if (await _storage.read(key: key) != null) return;
    final legacy = await _storage.read(key: 'auto_backup_passphrase');
    if (legacy != null) await _storage.write(key: key, value: legacy);
  }

  /// Get auto-backup passphrase
  Future<String?> getAutoBackupPassphrase() async {
    try {
      final passphrase = await _storage.read(key: _keyAutoBackupPassphrase);
      if (passphrase != null) {
        debugPrint('[SecureStorage] Auto-backup passphrase retrieved');
      } else {
        debugPrint('[SecureStorage] No passphrase found');
      }
      return passphrase;
    } catch (e) {
      debugPrint('[SecureStorage] Error reading passphrase: $e');
      return null;
    }
  }

  /// Delete auto-backup passphrase
  Future<void> deleteAutoBackupPassphrase() async {
    try {
      await _storage.delete(key: _keyAutoBackupPassphrase);
      debugPrint('[SecureStorage] Auto-backup passphrase deleted');
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting passphrase: $e');
      rethrow;
    }
  }

  /// Check if auto-backup passphrase exists
  Future<bool> hasAutoBackupPassphrase() async {
    try {
      final passphrase = await _storage.read(key: _keyAutoBackupPassphrase);
      return passphrase != null && passphrase.isNotEmpty;
    } catch (e) {
      debugPrint('[SecureStorage] Error checking passphrase: $e');
      return false;
    }
  }

  /// Delete all secure storage data (use with caution!)
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
      debugPrint('[SecureStorage] All secure data deleted');
    } catch (e) {
      debugPrint('[SecureStorage] Error deleting all data: $e');
      rethrow;
    }
  }
}
