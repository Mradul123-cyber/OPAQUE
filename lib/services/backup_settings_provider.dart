import 'dart:async';
import 'app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'backup_service.dart';
import 'auto_backup_manager.dart';
import 'SignalService.dart';

/// Backup Settings Provider - Manages auto-backup settings state
class BackupSettingsProvider with ChangeNotifier {
  final BackupService _backupService = BackupService();

  AutoBackupSettings _settings = AutoBackupSettings();
  bool _isLoading = false;
  bool _saving = false;
  bool _refreshingNative = false;
  Map<String, dynamic> _native = {};
  int get lastNativeSuccess => _native['lastSuccess'] as int? ?? 0;
  String get nativeStatusMessage => _native['message'] as String? ?? '';
  bool get nativeRunning => ['running', 'cancelling'].contains(_native['status']);
  bool get nativeCancelling => _native['status'] == 'cancelling';
  double get nativeProgress => ((_native['progress'] as num? ?? 0) / 100).clamp(0.0, 1.0);
  DateTime? get nextNativeRun {
    final value = _native['nextRun'] as int?;
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> refreshNativeStatus() async {
    if (!Platform.isAndroid || _disposed || _saving || _refreshingNative) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _refreshingNative = true;
    try {
      final status = await AutoBackupManager.nativeStatus();
      if (_disposed || _saving || FirebaseAuth.instance.currentUser?.uid != uid || status['userUid'] != uid) return;
      _native = status;
      _settings = _settings.copyWith(enabled: status['enabled'] == true);
      notifyListeners();
    } catch (e) { debugPrint('[BackupSettings] Status unavailable: $e'); }
    finally { _refreshingNative = false; }
  }

  Future<void> cancelNativeRun() async {
    await AutoBackupManager.cancelNativeRun(_native['run'] as String? ?? '');
    await refreshNativeStatus();
  }

  Future<void> setTime(int hour, int minute) => _saveAndSchedule(_settings.copyWith(hour: hour, minute: minute));

  AutoBackupSettings get settings => _settings;
  bool get isLoading => _isLoading;

  StreamSubscription<User?>? _authSubscription;
  bool _disposed = false;
  bool _needsReconfiguration = false;
  bool get needsReconfiguration => _needsReconfiguration;

  BackupSettingsProvider() {
    unawaited(_bindAccount());
  }

  Future<void> _bindAccount() async {
    try {
      await AppStorage.firebaseInitFuture;
      if (_disposed) return;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        _settings = AutoBackupSettings();
        _native = {};
        unawaited(_loadSettings());
      });
    } catch (e) { debugPrint('[BackupSettings] Initialization failed: $e'); }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    try {
      _isLoading = true;
      notifyListeners();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final loaded = await _backupService.getAutoBackupSettings();
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;
      _settings = loaded;
      await refreshNativeStatus();
      if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;
      _needsReconfiguration = prefs.getBool('backup_reconfigure_$uid') ?? false;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
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
      final updatedSettings = _settings.copyWith(enabled: enabled,
        frequency: enabled && _settings.frequency == BackupFrequency.disabled ? BackupFrequency.weekly : _settings.frequency);
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
  Future<void> setBackupPassphrase(String passphrase) =>
      _saveAndSchedule(_settings.copyWith(lastBackupPassphrase: passphrase));

  /// Update all settings at once
  Future<void> updateSettings(AutoBackupSettings newSettings) async {
    try {
      await _saveAndSchedule(newSettings);
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Error updating settings: $e');
      rethrow;
    }
  }

  /// Get database encryption key derived securely in native Android Keystore
  Future<String> _deriveDatabaseKey() async {
    try {
      final dbKey = await SignalService.getDatabaseEncryptionKey();
      if (dbKey == null) {
        throw Exception('Database encryption key not available');
      }
      return dbKey;
    } catch (e) {
      debugPrint('[BackupSettingsProvider] Failed to retrieve database key: $e');
      rethrow;
    }
  }

  /// Save settings and reschedule auto-backup
  Future<void> _saveAndSchedule(AutoBackupSettings newSettings) async {
    if (_saving) throw StateError('Backup settings are being updated');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to configure backups');
    _saving = true;
    var scheduled = false;
    try {
      final enabled = newSettings.enabled && newSettings.frequency != BackupFrequency.disabled;
      final updated = newSettings.copyWith(enabled: enabled);
      if (Platform.isAndroid) {
        if (enabled) {
          final passphrase = updated.lastBackupPassphrase;
          if (passphrase == null || passphrase.isEmpty) throw StateError('Set a backup passphrase first');
          if (!await AutoBackupManager.ensureBackupStoragePermission()) throw StateError('Storage permission is required');
          final password = await _deriveDatabaseKey();
          if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Account changed');
          scheduled = await AutoBackupManager.enableNativeAutoBackup(userUid: uid,
              dbPassword: password, passphrase: passphrase, frequency: updated.frequency,
              hour: updated.hour, minute: updated.minute);
          if (!scheduled) throw StateError('Could not schedule automatic backups');
        } else if (!await AutoBackupManager.disableNativeAutoBackup()) {
          throw StateError('Could not disable automatic backups');
        }
      } else {
        await AutoBackupManager.scheduleAutoBackup(updated);
      }
      if (FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Account changed');
      await _backupService.saveAutoBackupSettings(updated);
      final prefs = await SharedPreferences.getInstance();
      if (scheduled) await prefs.remove('backup_reconfigure_$uid');
      if (_disposed || FirebaseAuth.instance.currentUser?.uid != uid) return;
      _settings = updated;
      if (scheduled) _needsReconfiguration = false;
      notifyListeners();
    } catch (_) {
      if (scheduled && FirebaseAuth.instance.currentUser?.uid == uid) {
        await AutoBackupManager.disableNativeAutoBackup();
      }
      rethrow;
    } finally {
      _saving = false;
      await refreshNativeStatus();
    }
  }

  /// Get formatted last backup time
  String? getLastBackupTimeFormatted() {
    final nativeTime = _native['lastSuccess'] as int? ?? 0;
    final lastBackup = Platform.isAndroid
        ? (nativeTime > 0 ? DateTime.fromMillisecondsSinceEpoch(nativeTime) : null)
        : _settings.lastBackupTime;
    if (lastBackup == null) {
      return null;
    }

    final now = DateTime.now();
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
