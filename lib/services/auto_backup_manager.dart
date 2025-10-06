import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'backup_service.dart';
import 'backup_notification_service.dart';

/// Auto-Backup Manager - Handles scheduling and execution of automatic backups
class AutoBackupManager {
  static const String autoBackupTaskName = 'zarq_auto_backup_task';
  static const String autoBackupTaskTag = 'zarq_auto_backup';

  /// Initialize workmanager (call this in main.dart)
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    debugPrint('[AutoBackupManager] Workmanager initialized');
  }

  /// Schedule auto-backup based on settings
  static Future<void> scheduleAutoBackup(AutoBackupSettings settings) async {
    // Cancel existing tasks first
    await cancelAutoBackup();

    if (!settings.enabled || settings.frequency == BackupFrequency.disabled) {
      debugPrint('[AutoBackupManager] Auto-backup is disabled');
      return;
    }

    // Calculate frequency duration
    Duration frequency;
    switch (settings.frequency) {
      case BackupFrequency.daily:
        frequency = const Duration(hours: 24);
        break;
      case BackupFrequency.weekly:
        frequency = const Duration(days: 7);
        break;
      case BackupFrequency.monthly:
        frequency = const Duration(days: 30);
        break;
      case BackupFrequency.disabled:
        return;
    }

    // For Android: Use periodic task
    // For iOS: Use one-off task that reschedules itself
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        autoBackupTaskName,
        autoBackupTaskTag,
        frequency: frequency,
        constraints: Constraints(
          networkType: settings.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
          requiresCharging: false,
          requiresBatteryNotLow: true,
        ),
        initialDelay: _calculateInitialDelay(settings),
      );
      debugPrint('[AutoBackupManager] Scheduled periodic backup (Android): ${settings.frequency.displayName}');
    } else {
      // iOS: Schedule one-off task (will reschedule itself after execution)
      await _scheduleOneOffBackup(settings);
      debugPrint('[AutoBackupManager] Scheduled one-off backup (iOS): ${settings.frequency.displayName}');
    }
  }

  /// Schedule one-off backup (used for iOS and manual triggers)
  static Future<void> _scheduleOneOffBackup(AutoBackupSettings settings) async {
    await Workmanager().registerOneOffTask(
      autoBackupTaskName,
      autoBackupTaskTag,
      constraints: Constraints(
        networkType: settings.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresCharging: false,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: _calculateInitialDelay(settings),
    );
  }

  /// Calculate initial delay before first backup
  static Duration _calculateInitialDelay(AutoBackupSettings settings) {
    if (settings.lastBackupTime == null) {
      // Never backed up, start after 1 hour
      return const Duration(hours: 1);
    }

    final now = DateTime.now();
    final lastBackup = settings.lastBackupTime!;
    final timeSinceLastBackup = now.difference(lastBackup);

    // Calculate when next backup should occur
    Duration targetInterval;
    switch (settings.frequency) {
      case BackupFrequency.daily:
        targetInterval = const Duration(hours: 24);
        break;
      case BackupFrequency.weekly:
        targetInterval = const Duration(days: 7);
        break;
      case BackupFrequency.monthly:
        targetInterval = const Duration(days: 30);
        break;
      case BackupFrequency.disabled:
        return Duration.zero;
    }

    final remainingTime = targetInterval - timeSinceLastBackup;
    return remainingTime.isNegative ? Duration.zero : remainingTime;
  }

  /// Cancel auto-backup
  static Future<void> cancelAutoBackup() async {
    await Workmanager().cancelByUniqueName(autoBackupTaskName);
    debugPrint('[AutoBackupManager] Auto-backup cancelled');
  }

  /// Check connectivity
  static Future<bool> hasRequiredConnectivity(bool wifiOnly) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (wifiOnly) {
        return connectivityResult.contains(ConnectivityResult.wifi);
      } else {
        return connectivityResult.contains(ConnectivityResult.wifi) ||
            connectivityResult.contains(ConnectivityResult.mobile);
      }
    } catch (e) {
      debugPrint('[AutoBackupManager] Error checking connectivity: $e');
      return false;
    }
  }
}

/// Workmanager callback dispatcher (must be top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[AutoBackupManager] Background task started: $task');

    try {
      // Load settings
      final backupService = BackupService();
      final settings = await backupService.getAutoBackupSettings();

      // Check if backup is still enabled
      if (!settings.enabled) {
        debugPrint('[AutoBackupManager] Auto-backup is disabled, skipping');
        return Future.value(true);
      }

      // Check connectivity
      final hasConnectivity = await AutoBackupManager.hasRequiredConnectivity(settings.wifiOnly);
      if (!hasConnectivity) {
        debugPrint('[AutoBackupManager] Required connectivity not available');
        return Future.value(false); // Retry later
      }

      // Check if backup is actually due
      if (!backupService.isBackupDue(settings)) {
        debugPrint('[AutoBackupManager] Backup not due yet, skipping');
        return Future.value(true);
      }

      // Execute auto-backup
      await _executeAutoBackup(backupService, settings);

      // For iOS: Reschedule the next backup
      if (Platform.isIOS) {
        await AutoBackupManager._scheduleOneOffBackup(settings);
      }

      debugPrint('[AutoBackupManager] Background task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('[AutoBackupManager] Background task failed: $e');
      return Future.value(false);
    }
  });
}

/// Execute the actual auto-backup
Future<void> _executeAutoBackup(BackupService backupService, AutoBackupSettings settings) async {
  try {
    debugPrint('[AutoBackupManager] Executing auto-backup...');

    // Check if passphrase is available
    if (settings.lastBackupPassphrase == null || settings.lastBackupPassphrase!.isEmpty) {
      debugPrint('[AutoBackupManager] No passphrase available for auto-backup');
      throw Exception('Auto-backup passphrase not configured');
    }

    // Create backup with media age filter
    final backupData = await backupService.createLocalBackup(
      excludeMediaOlderThanDays: settings.mediaAgeLimitDays,
    );

    // Encrypt backup
    final encryptedFile = await backupService.encryptBackup(
      backupData,
      settings.lastBackupPassphrase!,
    );

    // Save based on destination
    bool success = false;

    if (settings.destination == BackupDestination.local ||
        settings.destination == BackupDestination.both) {
      // Copy to Downloads folder for local backup
      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupPath = '${downloadsDir.path}/backup_$timestamp.encrypted';
      await encryptedFile.copy(backupPath);

      success = true;
      debugPrint('[AutoBackupManager] Local backup saved: $backupPath');
    }

    if (settings.destination == BackupDestination.googleDrive ||
        settings.destination == BackupDestination.both) {
      // Upload to Google Drive
      final fileId = await backupService.uploadToGoogleDrive(encryptedFile);
      if (fileId != null) {
        success = true;
        debugPrint('[AutoBackupManager] Google Drive backup uploaded: $fileId');
      } else {
        debugPrint('[AutoBackupManager] Failed to upload to Google Drive');
      }
    }

    if (success) {
      // Update last backup time
      await backupService.updateLastBackupTime(DateTime.now());
      debugPrint('[AutoBackupManager] Auto-backup completed successfully');

      // Show success notification
      await BackupNotificationService.showSuccessNotification(
        settings.destination == BackupDestination.local
            ? 'Local'
            : settings.destination == BackupDestination.googleDrive
                ? 'Google Drive'
                : 'Local & Google Drive',
      );
    } else {
      // Show failure notification
      await BackupNotificationService.showFailureNotification(
        'Auto',
        'Failed to save backup to destination',
      );
    }
  } catch (e) {
    debugPrint('[AutoBackupManager] Auto-backup execution failed: $e');

    // Show failure notification
    await BackupNotificationService.showFailureNotification(
      'Auto',
      e.toString().length > 100 ? 'Backup error occurred' : e.toString(),
    );

    rethrow;
  }
}
