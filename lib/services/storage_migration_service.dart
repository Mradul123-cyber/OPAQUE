import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to migrate storage from old location to new Android/media directory
/// Migration: /storage/emulated/0/Zarq_Messenger/ -> /storage/emulated/0/Android/media/com.zarq.messenger/
class StorageMigrationService {
  static const String _migrationCompletedKey = 'storage_migration_completed_v1';

  /// Check if migration has already been completed
  static Future<bool> isMigrationCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_migrationCompletedKey) ?? false;
    } catch (e) {
      debugPrint('[StorageMigration] Error checking migration status: $e');
      return false;
    }
  }

  /// Mark migration as completed
  static Future<void> markMigrationCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migrationCompletedKey, true);
      debugPrint('[StorageMigration] ✅ Migration marked as completed');
    } catch (e) {
      debugPrint('[StorageMigration] Error marking migration complete: $e');
    }
  }

  /// Main migration function - migrates all data from old to new storage
  static Future<bool> migrateStorage() async {
    debugPrint('[StorageMigration] 🚀 Starting storage migration...');

    try {
      // Check if already migrated
      if (await isMigrationCompleted()) {
        debugPrint('[StorageMigration] ⏭️  Migration already completed, skipping');
        return true;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('[StorageMigration] ⚠️  No user logged in, skipping migration');
        await markMigrationCompleted(); // Mark as complete to avoid repeated attempts
        return true;
      }

      final userUid = currentUser.uid;

      // Define old and new base directories
      const oldBase = '/storage/emulated/0/Zarq_Messenger';
      const newBase = '/storage/emulated/0/Android/media/com.zarq.messenger';

      final oldBaseDir = Directory(oldBase);

      debugPrint('[StorageMigration] 🔍 Checking old storage path: $oldBase');

      // Check if old directory exists
      if (!await oldBaseDir.exists()) {
        debugPrint('[StorageMigration] ⚠️  No old storage found at: $oldBase');
        debugPrint('[StorageMigration] ℹ️  Marking as complete (nothing to migrate)');
        await markMigrationCompleted();
        return true;
      }

      debugPrint('[StorageMigration] ✅ Old storage found at: $oldBase');
      debugPrint('[StorageMigration] 🎯 Target location: $newBase');
      debugPrint('[StorageMigration] 📂 Beginning migration...');

      // Migrate Media files
      await _migrateMediaFiles(userUid, oldBase, newBase);

      // Migrate Backups
      await _migrateBackups(oldBase, newBase);

      // Mark migration as complete
      await markMigrationCompleted();

      debugPrint('[StorageMigration] ✅ Migration completed successfully!');
      return true;

    } catch (e, stackTrace) {
      debugPrint('[StorageMigration] ❌ Migration failed: $e');
      debugPrint('[StorageMigration] Stack trace: $stackTrace');
      // Don't mark as complete if failed - will retry next launch
      return false;
    }
  }

  /// Migrate media files (Images, Videos, Audio, Documents, Thumbnails)
  static Future<void> _migrateMediaFiles(String userUid, String oldBase, String newBase) async {
    debugPrint('[StorageMigration] 📷 Migrating media files...');

    final mediaTypes = ['Images', 'Videos', 'Audio', 'Documents', 'Thumbnails'];
    int totalFilesMigrated = 0;

    for (final mediaType in mediaTypes) {
      try {
        final oldMediaDir = Directory('$oldBase/Media/$mediaType/$userUid');
        final newMediaDir = Directory('$newBase/Media/$mediaType/$userUid');

        debugPrint('[StorageMigration]   🔍 Checking $mediaType at: ${oldMediaDir.path}');

        if (!await oldMediaDir.exists()) {
          debugPrint('[StorageMigration]   ⏭️  No $mediaType directory found, skipping');
          continue;
        }

        debugPrint('[StorageMigration]   ✅ Found $mediaType directory');

        // Create new directory if doesn't exist
        if (!await newMediaDir.exists()) {
          await newMediaDir.create(recursive: true);
          debugPrint('[StorageMigration]   ✅ Created $mediaType directory');
        }

        // Get all files in old directory
        final files = await oldMediaDir.list().toList();
        final fileList = files.whereType<File>().toList();

        if (fileList.isEmpty) {
          debugPrint('[StorageMigration]   ℹ️  No $mediaType files to migrate');
          continue;
        }

        debugPrint('[StorageMigration]   📦 Migrating ${fileList.length} $mediaType files...');

        for (final file in fileList) {
          try {
            final fileName = file.path.split('/').last;
            final newFilePath = '${newMediaDir.path}/$fileName';
            final newFile = File(newFilePath);

            // Check if file already exists in new location
            if (await newFile.exists()) {
              debugPrint('[StorageMigration]     ⏭️  $fileName already exists, skipping');
              continue;
            }

            // Copy file to new location
            await file.copy(newFilePath);
            totalFilesMigrated++;
            debugPrint('[StorageMigration]     ✅ Migrated $fileName');

          } catch (e) {
            debugPrint('[StorageMigration]     ❌ Failed to migrate file: ${file.path} - $e');
            // Continue with next file even if one fails
          }
        }

        debugPrint('[StorageMigration]   ✅ $mediaType migration complete');

      } catch (e) {
        debugPrint('[StorageMigration]   ❌ Error migrating $mediaType: $e');
        // Continue with next media type even if one fails
      }
    }

    debugPrint('[StorageMigration] ✅ Media migration complete - $totalFilesMigrated files migrated');
  }

  /// Migrate backup files
  static Future<void> _migrateBackups(String oldBase, String newBase) async {
    debugPrint('[StorageMigration] 💾 Migrating backup files...');

    try {
      // Old backups were in /Download/Zarq_Backups
      final oldBackupsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      final newBackupsDir = Directory('$newBase/Backups');

      debugPrint('[StorageMigration]   🔍 Checking old backups at: ${oldBackupsDir.path}');

      if (!await oldBackupsDir.exists()) {
        debugPrint('[StorageMigration]   ⏭️  No old backups directory found');
        return;
      }

      debugPrint('[StorageMigration]   ✅ Found old backups directory');

      // Create new backups directory if doesn't exist
      if (!await newBackupsDir.exists()) {
        await newBackupsDir.create(recursive: true);
        debugPrint('[StorageMigration]   ✅ Created Backups directory');
      }

      // Get all backup files (.encrypted)
      final files = await oldBackupsDir.list().toList();
      final backupFiles = files.whereType<File>()
          .where((f) => f.path.endsWith('.encrypted'))
          .toList();

      if (backupFiles.isEmpty) {
        debugPrint('[StorageMigration]   ℹ️  No backup files to migrate');
        return;
      }

      debugPrint('[StorageMigration]   📦 Migrating ${backupFiles.length} backup files...');
      int migratedCount = 0;

      for (final file in backupFiles) {
        try {
          final fileName = file.path.split('/').last;
          final newFilePath = '${newBackupsDir.path}/$fileName';
          final newFile = File(newFilePath);

          // Check if file already exists in new location
          if (await newFile.exists()) {
            debugPrint('[StorageMigration]     ⏭️  $fileName already exists, skipping');
            continue;
          }

          // Copy file to new location
          await file.copy(newFilePath);
          migratedCount++;
          debugPrint('[StorageMigration]     ✅ Migrated $fileName');

        } catch (e) {
          debugPrint('[StorageMigration]     ❌ Failed to migrate backup: ${file.path} - $e');
          // Continue with next file even if one fails
        }
      }

      debugPrint('[StorageMigration] ✅ Backup migration complete - $migratedCount files migrated');

    } catch (e) {
      debugPrint('[StorageMigration]   ❌ Error migrating backups: $e');
    }
  }

  /// Optional: Clean up old storage after successful migration
  /// WARNING: Only call this after verifying migration was successful!
  static Future<void> cleanupOldStorage() async {
    debugPrint('[StorageMigration] 🗑️  Starting cleanup of old storage...');

    try {
      // Check if migration was completed
      if (!await isMigrationCompleted()) {
        debugPrint('[StorageMigration] ⚠️  Migration not completed, skipping cleanup');
        return;
      }

      // Wait for user confirmation before deleting (implement in UI)
      // For safety, we'll just log the paths that would be deleted
      const oldBase = '/storage/emulated/0/Zarq_Messenger';
      final oldBaseDir = Directory(oldBase);

      if (await oldBaseDir.exists()) {
        // Get total size before deletion (for logging)
        int totalFiles = 0;
        await for (final entity in oldBaseDir.list(recursive: true)) {
          if (entity is File) totalFiles++;
        }

        debugPrint('[StorageMigration] 📊 Old storage contains $totalFiles files');
        debugPrint('[StorageMigration] ⚠️  To delete old storage, user should manually delete: $oldBase');

        // OPTIONAL: Uncomment to actually delete (DANGEROUS!)
        // await oldBaseDir.delete(recursive: true);
        // debugPrint('[StorageMigration] ✅ Old storage deleted');
      }

      // Also check old backups location
      final oldBackupsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      if (await oldBackupsDir.exists()) {
        final backupFiles = await oldBackupsDir.list().toList();
        debugPrint('[StorageMigration] 📊 Old backups contains ${backupFiles.length} files');
        debugPrint('[StorageMigration] ⚠️  To delete old backups, user should manually delete: ${oldBackupsDir.path}');

        // OPTIONAL: Uncomment to actually delete (DANGEROUS!)
        // await oldBackupsDir.delete(recursive: true);
        // debugPrint('[StorageMigration] ✅ Old backups deleted');
      }

    } catch (e) {
      debugPrint('[StorageMigration] ❌ Error during cleanup: $e');
    }
  }

  /// Force re-run migration (for testing or if migration failed)
  static Future<void> resetMigration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_migrationCompletedKey);
      debugPrint('[StorageMigration] 🔄 Migration status reset');
    } catch (e) {
      debugPrint('[StorageMigration] Error resetting migration: $e');
    }
  }

  /// Get migration status info (for UI display)
  static Future<Map<String, dynamic>> getMigrationStatus() async {
    try {
      final isCompleted = await isMigrationCompleted();
      const oldBase = '/storage/emulated/0/Zarq_Messenger';
      final oldBaseDir = Directory(oldBase);
      final oldExists = await oldBaseDir.exists();

      return {
        'completed': isCompleted,
        'oldStorageExists': oldExists,
        'needsMigration': !isCompleted && oldExists,
      };
    } catch (e) {
      return {
        'completed': false,
        'oldStorageExists': false,
        'needsMigration': false,
        'error': e.toString(),
      };
    }
  }
}
