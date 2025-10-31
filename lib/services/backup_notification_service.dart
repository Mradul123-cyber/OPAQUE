import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for showing backup-related notifications
class BackupNotificationService {
  static const MethodChannel _channel = MethodChannel('com.zarq/backup');

  /// Show start notification when backup/restore begins (with sound)
  static Future<void> showStartNotification(String operationType) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('showBackupStartNotification', {
        'operationType': operationType, // "Backup" or "Restore"
      });
      debugPrint('[BackupNotification] Start notification shown for $operationType');
    } catch (e) {
      debugPrint('[BackupNotification] Error showing start notification: $e');
    }
  }

  /// Show progress notification during auto-backup
  static Future<void> showProgressNotification(String status, int progress) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('showBackupProgressNotification', {
        'status': status,
        'progress': progress, // 0-100
      });
      debugPrint('[BackupNotification] Progress notification: $status ($progress%)');
    } catch (e) {
      debugPrint('[BackupNotification] Error showing progress notification: $e');
    }
  }

  /// Show success notification after backup completes
  static Future<void> showSuccessNotification(String backupType) async {
    if (!Platform.isAndroid) return; // iOS notifications can be added later

    try {
      await _channel.invokeMethod('showBackupSuccessNotification', {
        'backupType': backupType,
      });
      debugPrint('[BackupNotification] Success notification shown for $backupType');
    } catch (e) {
      debugPrint('[BackupNotification] Error showing success notification: $e');
    }
  }

  /// Show failure notification when backup fails
  static Future<void> showFailureNotification(String backupType, String errorMessage) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('showBackupFailureNotification', {
        'backupType': backupType,
        'errorMessage': errorMessage,
      });
      debugPrint('[BackupNotification] Failure notification shown for $backupType');
    } catch (e) {
      debugPrint('[BackupNotification] Error showing failure notification: $e');
    }
  }

  /// Show warning about battery optimization
  static Future<void> showBatteryOptimizationWarning() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('showBatteryOptimizationWarning');
      debugPrint('[BackupNotification] Battery optimization warning shown');
    } catch (e) {
      debugPrint('[BackupNotification] Error showing battery warning: $e');
    }
  }

  /// Cancel all backup notifications
  static Future<void> cancelAllNotifications() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('cancelBackupNotifications');
      debugPrint('[BackupNotification] All backup notifications cancelled');
    } catch (e) {
      debugPrint('[BackupNotification] Error cancelling notifications: $e');
    }
  }

  /// Check if battery optimization is disabled for the app
  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true; // iOS doesn't have this

    try {
      final result = await _channel.invokeMethod('isBatteryOptimizationDisabled');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[BackupNotification] Error checking battery optimization: $e');
      return false;
    }
  }

  /// Check battery optimization and show warning if needed
  static Future<void> checkAndWarnBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    try {
      final isDisabled = await isBatteryOptimizationDisabled();
      if (!isDisabled) {
        await showBatteryOptimizationWarning();
      }
    } catch (e) {
      debugPrint('[BackupNotification] Error in battery optimization check: $e');
    }
  }

  /// Request battery optimization exemption (for auto-backup reliability)
  static Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod('requestBatteryOptimizationExemption');
      debugPrint('[BackupNotification] Battery optimization exemption result: $result');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[BackupNotification] Error requesting battery optimization exemption: $e');
      return false;
    }
  }
}
