import 'package:flutter/foundation.dart';
import 'backup_service.dart';
import 'auto_backup_manager.dart';

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
      await _backupService.saveAutoBackupSettings(updatedSettings);
      _settings = updatedSettings;
      notifyListeners();
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

  /// Save settings and reschedule auto-backup
  Future<void> _saveAndSchedule(AutoBackupSettings newSettings) async {
    // Save to storage
    await _backupService.saveAutoBackupSettings(newSettings);

    // Update local state
    _settings = newSettings;
    notifyListeners();

    // Reschedule auto-backup
    await AutoBackupManager.scheduleAutoBackup(newSettings);
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
