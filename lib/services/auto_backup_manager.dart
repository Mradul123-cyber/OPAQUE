import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'backup_service.dart';
import 'backup_notification_service.dart';
import 'secure_storage_service.dart';
import 'mediastore_backup_service.dart';

/// Auto-Backup Manager - Handles scheduling and execution of automatic backups
class AutoBackupManager {
  static const String autoBackupTaskName = 'zarq_auto_backup_task';
  static const String autoBackupTaskTag = 'zarq_auto_backup';
  static const MethodChannel _backupChannel = MethodChannel('com.zarq/backup');

  /// Initialize workmanager (call this in main.dart)
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    debugPrint('[AutoBackupManager] Workmanager initialized');
  }

  /// Schedule auto-backup based on settings (using AlarmManager for exact-time execution)
  static Future<void> scheduleAutoBackup(AutoBackupSettings settings) async {
    // debugPrint('');
    //debugPrint('╔════════════════════════════════════════════════════════════╗');
    //debugPrint('║ 📅 SCHEDULING AUTO-BACKUP WITH ALARMMANAGER               ║');
    //debugPrint('╚════════════════════════════════════════════════════════════╝');
    //debugPrint('[AutoBackupManager] Current time: ${DateTime.now()}');
    // debugPrint('[AutoBackupManager] Settings enabled: ${settings.enabled}');
    //  debugPrint('[AutoBackupManager] Frequency: ${settings.frequency.name}');

    // Cancel existing tasks first
     await cancelAutoBackup();

    if (!settings.enabled || settings.frequency == BackupFrequency.disabled) {
      debugPrint('[AutoBackupManager] ❌ Auto-backup is disabled, not scheduling');
      return;
    }

    // For Android: Use AlarmManager for exact-time execution
    if (Platform.isAndroid) {
      try {
        // First check if we can schedule exact alarms (Android 12+)
        if (Platform.isAndroid) {
          final bool canSchedule = await _backupChannel.invokeMethod('canScheduleExactAlarms') ?? false;
          if (!canSchedule) {
            debugPrint('[AutoBackupManager] ⚠️ Cannot schedule exact alarms! User needs to grant permission.');
            debugPrint('[AutoBackupManager] 📱 Opening settings for user to enable exact alarms...');

            // Request permission from user
            await _backupChannel.invokeMethod('requestExactAlarmPermission');
            return; // Exit for now, user needs to re-enable after granting permission
          }
        }

        const int hour = 0;
        const int minute = 30;

        debugPrint('[AutoBackupManager] Scheduling AlarmManager for $hour:${minute.toString().padLeft(2, '0')}');

        final bool success = await _backupChannel.invokeMethod('scheduleExactAlarm', {
          'hour': hour,
          'minute': minute,
        });

        if (success) {
         // debugPrint('[AutoBackupManager] ✅ AlarmManager scheduled successfully!');
          //debugPrint('[AutoBackupManager] ⏰ Backup will trigger at $hour:${minute.toString().padLeft(2, '0')} daily');
          //debugPrint('[AutoBackupManager] 📱 Ensure battery optimization is DISABLED!');
        } else {
          //debugPrint('[AutoBackupManager] ❌ Failed to schedule AlarmManager');
        }

        return;
      } catch (e) {
        //debugPrint('[AutoBackupManager] ❌ Error scheduling AlarmManager: $e');
        //debugPrint('[AutoBackupManager] Falling back to WorkManager...');
        // Fall through to WorkManager as backup
      }
    }

    // Calculate frequency duration
    Duration frequency;
    switch (settings.frequency) {
      case BackupFrequency.daily:
        frequency = const Duration(hours: 24);
        //debugPrint('[AutoBackupManager] Frequency duration: 24 hours');
        break;
      case BackupFrequency.weekly:
        frequency = const Duration(days: 7);
        //debugPrint('[AutoBackupManager] Frequency duration: 7 days');
        break;
      case BackupFrequency.monthly:
        frequency = const Duration(days: 30);
        //debugPrint('[AutoBackupManager] Frequency duration: 30 days');
        break;
      case BackupFrequency.disabled:
        return;
    }

    // For Android: Use periodic task
    // For iOS: Use one-off task that reschedules itself
    if (Platform.isAndroid) {
      final initialDelay = _calculateInitialDelay(settings);
      //debugPrint('[AutoBackupManager] Platform: Android');
      //debugPrint('[AutoBackupManager] Task name: $autoBackupTaskName');
      //debugPrint('[AutoBackupManager] Task tag: $autoBackupTaskTag');
      //debugPrint('[AutoBackupManager] Initial delay: ${initialDelay.inMinutes} minutes (${initialDelay.inSeconds} seconds)');
      //debugPrint('[AutoBackupManager] Constraints: networkType=notRequired, charging=false, batteryNotLow=false');

      await Workmanager().registerPeriodicTask(
        autoBackupTaskName,
        autoBackupTaskTag,
        frequency: frequency,
        constraints: Constraints(
          networkType: NetworkType.notRequired, // Local backup - no network needed!
          requiresCharging: false,
          requiresBatteryNotLow: false, // FIXED: Allow backup even when battery is low
        ),
        initialDelay: initialDelay,
      );

      //debugPrint('[AutoBackupManager] ✅ WorkManager.registerPeriodicTask() called successfully');
      //debugPrint('[AutoBackupManager] ✅ Scheduled periodic backup (Android): ${settings.frequency.displayName}');
     // debugPrint('[AutoBackupManager] 🕐 Next backup scheduled for: ${DateTime.now().add(initialDelay)}');
      //debugPrint('[AutoBackupManager] 📱 Make sure battery optimization is DISABLED for this app!');
      //debugPrint('');
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
        networkType: NetworkType.notRequired, // Local backup - no network needed!
        requiresCharging: false,
        requiresBatteryNotLow: false, // FIXED: Allow backup even when battery is low
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: _calculateInitialDelay(settings),
    );
    //debugPrint('[AutoBackupManager] ✅ Scheduled one-off backup, delay: ${_calculateInitialDelay(settings)}');
  }

  /// Calculate initial delay before first backup (scheduled for 11:13 PM for testing)
  static Duration _calculateInitialDelay(AutoBackupSettings settings) {
    final now = DateTime.now();

    // Calculate next 11:13 PM (23:13)
    DateTime nextBackupTime = DateTime(now.year, now.month, now.day, 23, 13); // Today at 11:13 PM

    // If it's already past 11:13 PM today, schedule for tomorrow at 11:13 PM
    if (now.isAfter(nextBackupTime)) {
      //debugPrint('[AutoBackupManager] ⏭️ Already past 11:13 PM today, scheduling for tomorrow');
      nextBackupTime = nextBackupTime.add(const Duration(days: 1));
    }

    // If this is first time or last backup was a long time ago
    if (settings.lastBackupTime == null) {
     // debugPrint('[AutoBackupManager] 🆕 First time backup - no previous backup found');
      //debugPrint('[AutoBackupManager] 📅 First backup scheduled for: $nextBackupTime');
      final delay = nextBackupTime.difference(now);
      //debugPrint('[AutoBackupManager] ⏱️ Time until backup: ${delay.inHours}h ${delay.inMinutes % 60}m ${delay.inSeconds % 60}s');
      return delay;
    }

    final lastBackup = settings.lastBackupTime!;
    final timeSinceLastBackup = now.difference(lastBackup);

    // Calculate when next backup should occur based on frequency
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

    // If backup is overdue, schedule for next 11:13 PM
    if (timeSinceLastBackup >= targetInterval) {
      //debugPrint('[AutoBackupManager] ⏰ Backup is OVERDUE (last backup: $lastBackup)');
      //debugPrint('[AutoBackupManager] Backup overdue, scheduling for next 11:13 PM: $nextBackupTime');
      return nextBackupTime.difference(now);
    }

    // Otherwise, schedule for the appropriate interval from last backup
    final nextBackupDate = lastBackup.add(targetInterval);
    DateTime scheduledTime = DateTime(
      nextBackupDate.year,
      nextBackupDate.month,
      nextBackupDate.day,
      00, // 12 am
      30, // 30 minutes
    );

    // If scheduled time is in the past, use next 11:13 PM
    if (scheduledTime.isBefore(now)) {
      //debugPrint('[AutoBackupManager] Calculated time is in the past, using next 11:13 PM');
      scheduledTime = nextBackupTime;
    }

    //debugPrint('[AutoBackupManager] Next backup scheduled for: $scheduledTime');
    final delay = scheduledTime.difference(now);
    debugPrint('[AutoBackupManager] ⏱️ Time until backup: ${delay.inHours}h ${delay.inMinutes % 60}m ${delay.inSeconds % 60}s');
    return delay;
  }

  /// Get next scheduled backup time
  static DateTime? getNextBackupTime(AutoBackupSettings settings) {
    if (!settings.enabled || settings.frequency == BackupFrequency.disabled) {
      return null;
    }

    final now = DateTime.now();
    final delay = _calculateInitialDelay(settings);
    return now.add(delay);
  }

  /// Cancel auto-backup
  static Future<void> cancelAutoBackup() async {
    // Cancel AlarmManager alarm
    if (Platform.isAndroid) {
      try {
        await _backupChannel.invokeMethod('cancelExactAlarm');
        //debugPrint('[AutoBackupManager] ❌ AlarmManager alarm cancelled');
      } catch (e) {
        //debugPrint('[AutoBackupManager] Error cancelling alarm: $e');
      }
    }

    // Also cancel WorkManager task
    await Workmanager().cancelByUniqueName(autoBackupTaskName);
    //debugPrint('[AutoBackupManager] ❌ WorkManager task cancelled');
  }

  /// Get scheduled tasks (for debugging)
  static Future<void> debugPrintScheduledTasks() async {
    try {
      //debugPrint('[AutoBackupManager] 🔍 Checking scheduled WorkManager tasks...');
      // Note: WorkManager doesn't expose a direct API to list tasks
      // But we can check if our task is scheduled by trying to cancel and reschedule
      //debugPrint('[AutoBackupManager] Task name: $autoBackupTaskName');
      //debugPrint('[AutoBackupManager] Task tag: $autoBackupTaskTag');
    } catch (e) {
      //debugPrint('[AutoBackupManager] Error checking scheduled tasks: $e');
    }
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
    final startTime = DateTime.now();
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════════════════╗');
    debugPrint('║ 🔥 AUTO-BACKUP BACKGROUND TASK TRIGGERED                  ║');
    debugPrint('╠════════════════════════════════════════════════════════════╣');
    debugPrint('║ Task name: $task');
    debugPrint('║ Input data: $inputData');
    debugPrint('║ Time: $startTime');
    debugPrint('║ Device time: ${startTime.toLocal()}');
    debugPrint('╚════════════════════════════════════════════════════════════╝');
    debugPrint('');

    try {
      // Load settings
      debugPrint('[AutoBackupManager] Loading auto-backup settings...');
      final backupService = BackupService();
      final settings = await backupService.getAutoBackupSettings();
      debugPrint('[AutoBackupManager] Settings loaded: enabled=${settings.enabled}, freq=${settings.frequency.name}');

      // Check if backup is still enabled
      if (!settings.enabled) {
        debugPrint('[AutoBackupManager] Auto-backup is disabled, skipping');
        return Future.value(true);
      }

      // No connectivity check needed for local backups!
      debugPrint('[AutoBackupManager] Local backup - no network required');

      // Check if backup is actually due
      debugPrint('[AutoBackupManager] Checking if backup is due...');
      final isDue = backupService.isBackupDue(settings);
      debugPrint('[AutoBackupManager] Backup due check: $isDue (last backup: ${settings.lastBackupTime})');
      if (!isDue) {
        debugPrint('[AutoBackupManager] ⏭️ Backup not due yet, skipping');
        return Future.value(true);
      }

      debugPrint('[AutoBackupManager] ✅ All checks passed, executing backup...');

      // Execute auto-backup
      await _executeAutoBackup(backupService, settings);

      // For iOS: Reschedule the next backup
      if (Platform.isIOS) {
        await AutoBackupManager._scheduleOneOffBackup(settings);
      }

      final duration = DateTime.now().difference(startTime);
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║ ✅ AUTO-BACKUP COMPLETED SUCCESSFULLY                     ║');
      debugPrint('╠════════════════════════════════════════════════════════════╣');
      debugPrint('║ Duration: ${duration.inSeconds} seconds');
      debugPrint('║ Completed at: ${DateTime.now()}');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      return Future.value(true);
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════════════════╗');
      debugPrint('║ ❌ AUTO-BACKUP FAILED                                     ║');
      debugPrint('╠════════════════════════════════════════════════════════════╣');
      debugPrint('║ Error: $e');
      debugPrint('║ Stack trace:');
      debugPrint('║ $stackTrace');
      debugPrint('╚════════════════════════════════════════════════════════════╝');
      debugPrint('');
      return Future.value(false);
    }
  });
}

/// Execute the actual auto-backup
Future<void> _executeAutoBackup(BackupService backupService, AutoBackupSettings settings) async {
  try {
    debugPrint('[AutoBackupManager] Executing auto-backup...');

    // Load passphrase from secure storage
    final secureStorage = SecureStorageService();
    final passphrase = await secureStorage.getAutoBackupPassphrase();

    if (passphrase == null || passphrase.isEmpty) {
      debugPrint('[AutoBackupManager] No passphrase available for auto-backup');
      throw Exception('Auto-backup passphrase not configured in secure storage');
    }

    debugPrint('[AutoBackupManager] Passphrase loaded from secure storage');

    // Show initial progress notification
    await BackupNotificationService.showProgressNotification('Starting auto-backup...', 0);

    // Create backup (messages only, no media to prevent OOM)
    await BackupNotificationService.showProgressNotification('Collecting messages...', 20);
    final backupData = await backupService.createLocalBackup(
      includeMedia: false, // Auto-backup: Messages only (WhatsApp approach)
    );
    debugPrint('[AutoBackupManager] Backup data collected: ${backupData.messages.length} messages, ${backupData.attachments.length} attachments');

    // Encrypt backup
    await BackupNotificationService.showProgressNotification('Encrypting backup...', 50);
    final encryptedFile = await backupService.encryptBackup(
      backupData,
      passphrase, // Use passphrase from secure storage
    );
    debugPrint('[AutoBackupManager] Backup encrypted: ${encryptedFile.path}');

    // Auto-backup always saves to local storage only
    await BackupNotificationService.showProgressNotification('Saving to local storage...', 70);

    // CRITICAL: Clean up old auto-backups BEFORE creating new one
    // Keep only 2 most recent auto-backups (safety net for corruption)
    // Manual backups (starting with "backup_") are NOT touched
    await _cleanupOldAutoBackups();

    // Use "auto_backup_" prefix to differentiate from manual backups
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = 'auto_backup_$timestamp.encrypted';

    // Save to MediaStore Downloads
    final uri = await MediaStoreBackupService.saveBackupFile(encryptedFile, fileName);

    bool success = uri != null;
    if (success) {
      debugPrint('[AutoBackupManager] Auto-backup saved to MediaStore: $uri');
    } else {
      debugPrint('[AutoBackupManager] ❌ Failed to save auto-backup to MediaStore');
    }

    if (success) {
      // Update last backup time
      await BackupNotificationService.showProgressNotification('Finalizing...', 95);
      await backupService.updateLastBackupTime(DateTime.now());
      debugPrint('[AutoBackupManager] Auto-backup completed successfully');

      // Show success notification
      await BackupNotificationService.showSuccessNotification('Local');
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

/// Clean up old auto-backups, keeping only the 2 most recent
/// Manual backups (filename starts with "backup_") are NOT deleted
Future<void> _cleanupOldAutoBackups() async {
  try {
    debugPrint('[AutoBackupManager] Cleaning up old auto-backups...');

    // List all backup files from MediaStore
    final allBackups = await MediaStoreBackupService.listBackupFiles();

    // Filter only auto-backups (filename starts with "auto_backup_")
    final autoBackups = allBackups
        .where((backup) => (backup['name'] as String).startsWith('auto_backup_'))
        .toList();

    debugPrint('[AutoBackupManager] Found ${autoBackups.length} auto-backup files');

    // If 2 or fewer auto-backups exist, don't delete anything
    if (autoBackups.length <= 2) {
      debugPrint('[AutoBackupManager] Only ${autoBackups.length} auto-backups, no cleanup needed');
      return;
    }

    // Sort by modification time (newest first)
    autoBackups.sort((a, b) {
      final aTime = a['dateModified'] as int;
      final bTime = b['dateModified'] as int;
      return bTime.compareTo(aTime);
    });

    // Keep only the 2 most recent, delete the rest
    final backupsToDelete = autoBackups.sublist(2);
    debugPrint('[AutoBackupManager] Deleting ${backupsToDelete.length} old auto-backups (keeping 2 most recent)');

    for (final backup in backupsToDelete) {
      try {
        final uri = backup['uri'] as String;
        final name = backup['name'] as String;
        final deleted = await MediaStoreBackupService.deleteBackupFile(uri);
        if (deleted) {
          debugPrint('[AutoBackupManager] ✅ Deleted old auto-backup: $name');
        } else {
          debugPrint('[AutoBackupManager] ❌ Failed to delete $name');
        }
      } catch (e) {
        debugPrint('[AutoBackupManager] ❌ Failed to delete backup: $e');
      }
    }

    debugPrint('[AutoBackupManager] Auto-backup cleanup complete');
  } catch (e) {
    debugPrint('[AutoBackupManager] Error during cleanup: $e');
    // Don't rethrow - cleanup failure shouldn't stop backup creation
  }
}
