import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'backup_service.dart';
import 'auto_backup_manager.dart';
import 'SignalService.dart';
import 'secure_storage_service.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Backup Settings Provider - Manages auto-backup settings state
class BackupSettingsProvider with ChangeNotifier {
  final BackupService _backupService = BackupService();

  AutoBackupSettings _settings = AutoBackupSettings();
  bool _isLoading = false;

  AutoBackupSettings get settings => _settings;
  bool get isLoading => _isLoading;

  BackupSettingsProvider() {
    _loadSettings();
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    try {
      _isLoading = true;
      notifyListeners();

      _settings = await _backupService.getAutoBackupSettings();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error loading settings: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reload settings from storage
  Future<void> refreshSettings() async {
    await _loadSettings();
  }

  /// Update auto-backup enabled status
  Future<void> setEnabled(bool enabled) async {
    try {
      final updatedSettings = _settings.copyWith(enabled: enabled);
      await _saveAndSchedule(updatedSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting enabled: $e');
      rethrow;
    }
  }

  /// Update backup frequency
  Future<void> setFrequency(BackupFrequency frequency) async {
    try {
      final updatedSettings = _settings.copyWith(frequency: frequency);
      await _saveAndSchedule(updatedSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting frequency: $e');
      rethrow;
    }
  }

  /// Update backup destination
  Future<void> setDestination(BackupDestination destination) async {
    try {
      final updatedSettings = _settings.copyWith(destination: destination);
      await _saveAndSchedule(updatedSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting destination: $e');
      rethrow;
    }
  }

  /// Update WiFi-only setting
  Future<void> setWifiOnly(bool wifiOnly) async {
    try {
      final updatedSettings = _settings.copyWith(wifiOnly: wifiOnly);
      await _saveAndSchedule(updatedSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting WiFi only: $e');
      rethrow;
    }
  }

  /// Update media age limit
  Future<void> setMediaAgeLimitDays(int? days) async {
    try {
      final updatedSettings = _settings.copyWith(mediaAgeLimitDays: days);
      await _saveAndSchedule(updatedSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting media age limit: $e');
      rethrow;
    }
  }

  /// Update backup passphrase (encrypted)
  Future<void> setBackupPassphrase(String passphrase) async {
    try {
      final updatedSettings = _settings.copyWith(lastBackupPassphrase: passphrase);

      // Save settings first
      await _backupService.saveAutoBackupSettings(updatedSettings);
      _settings = updatedSettings;
      notifyListeners();

      // If auto-backup is enabled, schedule native auto-backup NOW
      // This is the ONLY place where we actually schedule with credentials
      if (updatedSettings.enabled && Platform.isAndroid) {
        await _scheduleNativeAutoBackup(updatedSettings);
      }
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error setting passphrase: $e');
      rethrow;
    }
  }

  /// Update all settings at once
  Future<void> updateSettings(AutoBackupSettings newSettings) async {
    try {
      await _saveAndSchedule(newSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error updating settings: $e');
      rethrow;
    }
  }

  /// Derive database encryption key from Signal identity key
  /// Same logic as DatabaseService._deriveDatabaseKey()
  Future<String> _deriveDatabaseKey() async {
    try {
      // Get identity key private key (base64 encoded 32 bytes)
      final identityKeyB64 = await SignalService.getIdentityKeyPrivateKey();

      if (identityKeyB64 == null) {
        throw Exception('Identity key not available for database encryption');
      }

      // Decode base64 to get raw bytes
      final identityKeyBytes = base64.decode(identityKeyB64);

      // Derive key using SHA-256(identity_key + salt)
      final salt = 'zarq_database_encryption_v1';
      final input = Uint8List.fromList([...identityKeyBytes, ...utf8.encode(salt)]);
      final hash = sha256.convert(input);

      // Convert hash to hex string for SQLCipher
      return hash.toString();
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Failed to derive database key: $e');
      rethrow;
    }
  }

  /// Save settings and reschedule auto-backup
  Future<void> _saveAndSchedule(AutoBackupSettings newSettings) async {
    // Save to storage
    await _backupService.saveAutoBackupSettings(newSettings);

    // Update local state
    _settings = newSettings;
    notifyListeners();

    // ANDROID ONLY: Use native auto-backup (Play Store compliant)
    if (Platform.isAndroid) {
      if (newSettings.enabled && newSettings.frequency != BackupFrequency.disabled) {
        // Check if passphrase is already set
        if (newSettings.lastBackupPassphrase != null && newSettings.lastBackupPassphrase!.isNotEmpty) {
          // Passphrase exists, schedule immediately
          debugPrint('[BackupSettingsProvider] Auto-backup enabled with existing passphrase. Scheduling now...');
          await _scheduleNativeAutoBackup(newSettings);
        } else {
          // No passphrase yet, wait for user to set it
          debugPrint('[BackupSettingsProvider] Auto-backup enabled. Waiting for passphrase...');
        }
        return;
      } else {
        // Disable native auto-backup
        try {
          await AutoBackupManager.disableNativeAutoBackup();
          debugPrint('[BackupSettingsProvider] ✅ Native auto-backup disabled');
        } catch (e) {
          debugPrint('[BackupSettingsProvider] ❌ Error disabling native auto-backup: $e');
        }
        return;
      }
    }

    // Fallback for non-Android platforms (should not reach here in production)
    debugPrint('[BackupSettingsProvider] Using legacy auto-backup (non-Android)');
    await AutoBackupManager.scheduleAutoBackup(newSettings);
  }

  /// Schedule native auto-backup with credentials
  /// Called when passphrase is set
  Future<void> _scheduleNativeAutoBackup(AutoBackupSettings settings) async {
    try {
      debugPrint('[BackupSettingsProvider] Scheduling native auto-backup with credentials...');

      // Get user UID
      final userUid = FirebaseAuth.instance.currentUser?.uid;
      if (userUid == null) {
        debugPrint('[BackupSettingsProvider] ❌ No user UID available');
        return;
      }

      // Derive database password (same as DatabaseService)
      final dbPassword = await _deriveDatabaseKey();
      debugPrint('[BackupSettingsProvider] ✅ Database password derived');

      // Get backup passphrase from secure storage
      final secureStorage = SecureStorageService();
      final passphrase = await secureStorage.getAutoBackupPassphrase();

      if (passphrase == null || passphrase.isEmpty) {
        debugPrint('[BackupSettingsProvider] ❌ No backup passphrase available');
        return;
      }

      debugPrint('[BackupSettingsProvider] ✅ Backup passphrase retrieved');

      // Enable native auto-backup
      final success = await AutoBackupManager.enableNativeAutoBackup(
        userUid: userUid,
        dbPassword: dbPassword,
        passphrase: passphrase,
        frequency: settings.frequency,
        hour: 0,   // 12:30 AM
        minute: 30,
      );

      if (success) {
        debugPrint('[BackupSettingsProvider] ✅ Native auto-backup scheduled successfully!');
      } else {
        debugPrint('[BackupSettingsProvider] ❌ Failed to schedule native auto-backup');
      }
    } catch (e) {
      debugPrint('[BackupSettingsProvider] ❌ Error scheduling native auto-backup: $e');
    }
  }

  /// Get formatted last backup time
  String? getLastBackupTimeFormatted() {
    if (_settings.lastBackupTime == null) {
      return null;
    }

    final now = DateTime.now();
    final lastBackup = _settings.lastBackupTime!;
    final difference = now.difference(lastBackup);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'} ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
  }

  /// Check if backup is due
  bool isBackupDue() {
    return _backupService.isBackupDue(_settings);
  }
}
