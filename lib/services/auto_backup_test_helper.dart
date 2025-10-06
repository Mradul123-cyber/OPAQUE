import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'backup_service.dart';
import 'auto_backup_manager.dart';

/// Helper class for testing auto-backup functionality
class AutoBackupTestHelper {
  /// Manually trigger auto-backup (for testing only)
  static Future<void> triggerManualAutoBackup() async {
    try {
      debugPrint('[TEST] Manually triggering auto-backup...');

      final backupService = BackupService();
      final settings = await backupService.getAutoBackupSettings();

      if (!settings.enabled) {
        debugPrint('[TEST] Auto-backup is disabled');
        return;
      }

      if (settings.lastBackupPassphrase == null || settings.lastBackupPassphrase!.isEmpty) {
        debugPrint('[TEST] No passphrase set for auto-backup');
        return;
      }

      // Check connectivity
      final hasConnectivity = await AutoBackupManager.hasRequiredConnectivity(settings.wifiOnly);
      if (!hasConnectivity) {
        debugPrint('[TEST] Required connectivity not available');
        return;
      }

      debugPrint('[TEST] Creating backup...');
      final backupData = await backupService.createLocalBackup(
        excludeMediaOlderThanDays: settings.mediaAgeLimitDays,
      );

      debugPrint('[TEST] Encrypting backup...');
      final encryptedFile = await backupService.encryptBackup(
        backupData,
        settings.lastBackupPassphrase!,
      );

      debugPrint('[TEST] Backup created: ${encryptedFile.path}');

      // Save based on destination
      if (settings.destination == BackupDestination.local ||
          settings.destination == BackupDestination.both) {
        debugPrint('[TEST] Saving to local storage...');

        // Copy to Downloads folder
        final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }

        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final backupPath = '${downloadsDir.path}/backup_$timestamp.encrypted';
        await encryptedFile.copy(backupPath);

        debugPrint('[TEST] Local backup saved: $backupPath');
      }

      if (settings.destination == BackupDestination.googleDrive ||
          settings.destination == BackupDestination.both) {
        debugPrint('[TEST] Uploading to Google Drive...');
        final fileId = await backupService.uploadToGoogleDrive(encryptedFile);
        debugPrint('[TEST] Google Drive backup: $fileId');
      }

      // Update last backup time
      await backupService.updateLastBackupTime(DateTime.now());
      debugPrint('[TEST] ✅ Auto-backup test completed successfully');

    } catch (e, stackTrace) {
      debugPrint('[TEST] ❌ Auto-backup test failed: $e');
      debugPrint('[TEST] Stack trace: $stackTrace');
    }
  }

  /// Check if auto-backup is properly scheduled
  static Future<Map<String, dynamic>> checkScheduleStatus() async {
    final backupService = BackupService();
    final settings = await backupService.getAutoBackupSettings();

    return {
      'enabled': settings.enabled,
      'frequency': settings.frequency.displayName,
      'destination': settings.destination.displayName,
      'wifiOnly': settings.wifiOnly,
      'hasPassphrase': settings.lastBackupPassphrase != null,
      'lastBackupTime': settings.lastBackupTime?.toIso8601String() ?? 'Never',
      'isBackupDue': backupService.isBackupDue(settings),
    };
  }
}
