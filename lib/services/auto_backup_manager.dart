import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
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
  static const MethodChannel _nativeBackupChannel = MethodChannel('com.zarq/native_backup');

  /// Initialize workmanager (call this in main.dart)
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    debugPrint('[AutoBackupManager] Workmanager initialized');
  }

  static Future<Map<String, dynamic>> nativeStatus() async {
    if (!Platform.isAndroid) return {};
    final result = await _nativeBackupChannel.invokeMapMethod<String, dynamic>('getNativeBackupStatus');
    return result ?? {};
  }

  static Future<void> cancelNativeRun(String run) async {
    await _nativeBackupChannel.invokeMethod('cancelNativeBackupRun', {'run': run});
  }

  static Future<bool> ensureBackupStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await nativeStatus();
    if (status['needsStoragePermission'] != true) return true;
    return (await Permission.storage.request()).isGranted;
  }

  /// Enable native auto-backup (Android only - Play Store compliant)
  /// This uses fully native Kotlin WorkManager-based backup
  static Future<bool> enableNativeAutoBackup({
    required String userUid,
    required String dbPassword,
    required String passphrase,
    required BackupFrequency frequency,
    int hour = 0,
    int minute = 30,
  }) async {
    if (!Platform.isAndroid) {
      debugPrint('[AutoBackupManager] Native backup only available on Android');
      return false;
    }

    // Convert frequency to hours
    int intervalHours;
    String frequencyName;
    switch (frequency) {
      case BackupFrequency.daily:
        intervalHours = 24;
        frequencyName = 'Daily';
        break;
      case BackupFrequency.weekly:
        intervalHours = 24 * 7; // 168 hours
        frequencyName = 'Weekly';
        break;
      case BackupFrequency.monthly:
        intervalHours = 24 * 30; // 720 hours
        frequencyName = 'Monthly';
        break;
      case BackupFrequency.disabled:
        debugPrint('[AutoBackupManager] Frequency is disabled, not scheduling');
        return false;
    }

    try {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════╗');
      debugPrint('║  🚀 ENABLING NATIVE AUTO-BACKUP           ║');
      debugPrint('╠════════════════════════════════════════════╣');
      debugPrint('║  Time: $hour:${minute.toString().padLeft(2, '0')}');
      debugPrint('║  Frequency: $frequencyName ($intervalHours hours)');
      debugPrint('║  Method: Native Kotlin + WorkManager      ║');
      debugPrint('╚════════════════════════════════════════════╝');
      debugPrint('');

      // Account credentials and scheduling are committed together by native code.
      // Step 4: Schedule native auto-backup with WorkManager
      final scheduled = await _nativeBackupChannel.invokeMethod<bool>('scheduleNativeAutoBackup', {
        'userUid': userUid,
        'dbPassword': dbPassword,
        'passphrase': passphrase,
        'hour': hour,
        'minute': minute,
        'intervalHours': intervalHours,
      });
      if (scheduled != true) return false;
      debugPrint('[AutoBackupManager] ✅ Native auto-backup scheduled successfully!');
      debugPrint('');

      return true;
    } catch (e) {
      debugPrint('[AutoBackupManager] ❌ Error enabling native auto-backup: $e');
      return false;
    }
  }

  /// Disable native auto-backup (Android only)
  static Future<bool> disableNativeAutoBackup() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      await _nativeBackupChannel.invokeMethod('cancelNativeAutoBackup');
      debugPrint('[AutoBackupManager] ✅ Native auto-backup disabled');
      return true;
    } catch (e) {
      debugPrint('[AutoBackupManager] ❌ Error disabling native auto-backup: $e');
      return false;
    }
  }

  /// Test native auto-backup immediately (Android only - for debugging)
  static Future<bool> testNativeAutoBackup() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      debugPrint('[AutoBackupManager] 🧪 Testing native auto-backup...');
      await _nativeBackupChannel.invokeMethod('testNativeBackup');
      debugPrint('[AutoBackupManager] ✅ Test backup completed!');
      return true;
    } catch (e) {
      debugPrint('[AutoBackupManager] ❌ Test backup failed: $e');
      return false;
    }
  }

  /// Schedule a test backup after a delay (Android only - for debugging)
  static Future<bool> scheduleTestBackup({int delaySeconds = 5}) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      debugPrint('[AutoBackupManager] ⏰ Scheduling test backup in $delaySeconds seconds...');
      await _nativeBackupChannel.invokeMethod('scheduleTestBackup', {
        'delaySeconds': delaySeconds,
      });
      debugPrint('[AutoBackupManager] ✅ Test backup scheduled!');
      return true;
    } catch (e) {
      debugPrint('[AutoBackupManager] ❌ Failed to schedule test backup: $e');
      return false;
    }
  }

  /// Schedule auto-backup based on settings (using WorkManager for Google Play compliance)
  static Future<void> scheduleAutoBackup(AutoBackupSettings settings) async {
    // debugPrint('');
    //debugPrint('╔════════════════════════════════════════════════════════════╗');
    //debugPrint('║ 📅 SCHEDULING AUTO-BACKUP WITH WORKMANAGER                ║');
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

    // AlarmManager code removed - now using WorkManager only for Google Play compliance

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

  /// Calculate initial delay before first backup (scheduled for 7:59 PM for testing)
  static Duration _calculateInitialDelay(AutoBackupSettings settings) {
    final now = DateTime.now();

    // Calculate next 7:59 PM (19:59)
    DateTime nextBackupTime = DateTime(now.year, now.month, now.day, settings.hour, settings.minute); // Today at 7:59 PM

    // If it's already past 7:59 PM today, schedule for tomorrow at 7:59 PM
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
      settings.hour,
      settings.minute,
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
    // Cancel WorkManager task (AlarmManager code removed)
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
    if (Platform.isAndroid) return true; // Android uses account-bound native workers.
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
