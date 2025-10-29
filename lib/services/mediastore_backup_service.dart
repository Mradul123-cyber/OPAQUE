import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to handle backups using MediaStore Downloads API (Android 10+)
/// This is the Google Play compliant way - NO MANAGE_EXTERNAL_STORAGE needed!
///
/// Benefits:
/// - Files persist after app uninstall
/// - No special permissions required
/// - Google Play approved
/// - Works on all Android versions 10+
class MediaStoreBackupService {
  static const MethodChannel _channel = MethodChannel('com.zarq/mediastore_backup');

  /// Save a backup file to MediaStore Downloads
  /// Returns the MediaStore URI if successful, null otherwise
  static Future<String?> saveBackupFile(File sourceFile, String fileName) async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping MediaStore');
        return null;
      }

      debugPrint('[MediaStoreBackup] 📁 Saving backup: $fileName');

      final String? uri = await _channel.invokeMethod('saveBackup', {
        'sourceFilePath': sourceFile.path,
        'fileName': fileName,
      });

      if (uri != null) {
        debugPrint('[MediaStoreBackup] ✅ Backup saved successfully: $uri');
      } else {
        debugPrint('[MediaStoreBackup] ❌ Failed to save backup');
      }

      return uri;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error saving backup: $e');
      return null;
    }
  }

  /// List all backup files from MediaStore Downloads
  /// Returns list of backup info maps with keys: uri, name, size, dateModified
  static Future<List<Map<String, dynamic>>> listBackupFiles() async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping MediaStore');
        return [];
      }

      debugPrint('[MediaStoreBackup] 📋 Listing backup files...');

      final List<dynamic>? backups = await _channel.invokeMethod('listBackups');

      if (backups == null) {
        debugPrint('[MediaStoreBackup] ⚠️  No backups returned');
        return [];
      }

      final List<Map<String, dynamic>> typedBackups = backups
          .map((backup) => Map<String, dynamic>.from(backup as Map))
          .toList();

      debugPrint('[MediaStoreBackup] ✅ Found ${typedBackups.length} backups');
      return typedBackups;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error listing backups: $e');
      return [];
    }
  }

  /// Read backup file content from MediaStore URI
  static Future<Uint8List?> readBackupFile(String uri) async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping MediaStore');
        return null;
      }

      debugPrint('[MediaStoreBackup] 📖 Reading backup from URI...');

      final Uint8List? bytes = await _channel.invokeMethod('readBackup', {
        'uri': uri,
      });

      if (bytes != null) {
        debugPrint('[MediaStoreBackup] ✅ Read ${bytes.length} bytes');
      } else {
        debugPrint('[MediaStoreBackup] ❌ Failed to read backup');
      }

      return bytes;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error reading backup: $e');
      return null;
    }
  }

  /// Delete backup file from MediaStore
  static Future<bool> deleteBackupFile(String uri) async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping MediaStore');
        return false;
      }

      debugPrint('[MediaStoreBackup] 🗑️  Deleting backup...');

      final bool success = await _channel.invokeMethod('deleteBackup', {
        'uri': uri,
      });

      if (success) {
        debugPrint('[MediaStoreBackup] ✅ Backup deleted successfully');
      } else {
        debugPrint('[MediaStoreBackup] ⚠️  Failed to delete backup');
      }

      return success;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error deleting backup: $e');
      return false;
    }
  }

  /// Get display path for backup (for UI purposes only)
  static String getDisplayPath(String fileName) {
    return 'Download/Zarq_Backups/$fileName';
  }

  /// Format bytes to human-readable size
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// TEMPORARY: List old backups from file system (for migration period only)
  /// This allows detecting backups created before MediaStore implementation
  /// TODO: Remove this after migration period
  static Future<List<Map<String, dynamic>>> listOldBackupsFromFileSystem() async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping old backup detection');
        return [];
      }

      debugPrint('[MediaStoreBackup] 🔍 Checking for old backups in file system...');

      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');
      debugPrint('[MediaStoreBackup] 📂 Checking directory: ${downloadsDir.path}');

      final exists = await downloadsDir.exists();
      debugPrint('[MediaStoreBackup] 📂 Directory exists: $exists');

      if (!exists) {
        debugPrint('[MediaStoreBackup] ⚠️  Old backup folder does not exist');
        return [];
      }

      debugPrint('[MediaStoreBackup] 📂 Attempting to list files...');
      final files = await downloadsDir.list().toList();
      debugPrint('[MediaStoreBackup] 📂 Total files/folders found: ${files.length}');

      // Log all files found
      for (final file in files) {
        debugPrint('[MediaStoreBackup] 📄 Found item: ${file.path} (type: ${file.runtimeType})');
      }

      final backupFiles = files
          .where((f) => f is File && f.path.endsWith('.encrypted'))
          .cast<File>()
          .toList();

      debugPrint('[MediaStoreBackup] 📁 Found ${backupFiles.length} old backup files (.encrypted)');

      final List<Map<String, dynamic>> oldBackups = [];
      for (final file in backupFiles) {
        try {
          final stat = await file.stat();
          final fileName = file.path.split('/').last;

          oldBackups.add({
            'uri': 'file://${file.path}', // Special prefix to identify old backups
            'name': fileName,
            'size': stat.size,
            'dateModified': stat.modified.millisecondsSinceEpoch,
            'isOldBackup': true, // Flag to identify old backups
          });
        } catch (e) {
          debugPrint('[MediaStoreBackup] ❌ Error reading file ${file.path}: $e');
        }
      }

      return oldBackups;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error listing old backups: $e');
      return [];
    }
  }

  /// TEMPORARY: Combined list of both MediaStore and old file system backups
  /// TODO: Remove this after migration period
  static Future<List<Map<String, dynamic>>> listAllBackups() async {
    try {
      debugPrint('[MediaStoreBackup] 🔍 Listing ALL backups (MediaStore + old files)...');

      // Get backups from MediaStore (new method)
      final mediaStoreBackups = await listBackupFiles();
      debugPrint('[MediaStoreBackup] 📱 Found ${mediaStoreBackups.length} MediaStore backups');

      // Get backups from old file system (old method)
      final oldBackups = await listOldBackupsFromFileSystem();
      debugPrint('[MediaStoreBackup] 📁 Found ${oldBackups.length} old file system backups');

      // Combine both lists
      final allBackups = [...mediaStoreBackups, ...oldBackups];

      // Sort by modification time (newest first)
      allBackups.sort((a, b) {
        final aTime = a['dateModified'] as int;
        final bTime = b['dateModified'] as int;
        return bTime.compareTo(aTime);
      });

      debugPrint('[MediaStoreBackup] ✅ Total: ${allBackups.length} backups (${mediaStoreBackups.length} new + ${oldBackups.length} old)');
      return allBackups;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error listing all backups: $e');
      return [];
    }
  }

  /// TEMPORARY: Read backup from either MediaStore or old file system
  /// TODO: Remove this after migration period
  static Future<Uint8List?> readBackupFileUniversal(String uri) async {
    try {
      // Check if this is an old file system backup
      if (uri.startsWith('file://')) {
        debugPrint('[MediaStoreBackup] 📖 Reading old backup from file system...');
        final filePath = uri.replaceFirst('file://', '');
        final file = File(filePath);

        if (!await file.exists()) {
          debugPrint('[MediaStoreBackup] ❌ Old backup file not found: $filePath');
          return null;
        }

        final bytes = await file.readAsBytes();
        debugPrint('[MediaStoreBackup] ✅ Read ${bytes.length} bytes from old backup');
        return bytes;
      } else {
        // This is a MediaStore backup, use normal method
        return await readBackupFile(uri);
      }
    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error reading backup: $e');
      return null;
    }
  }

  /// TEMPORARY: Delete backup from either MediaStore or old file system
  /// TODO: Remove this after migration period
  static Future<bool> deleteBackupFileUniversal(String uri) async {
    try {
      // Check if this is an old file system backup
      if (uri.startsWith('file://')) {
        debugPrint('[MediaStoreBackup] 🗑️  Deleting old backup from file system...');
        final filePath = uri.replaceFirst('file://', '');
        final file = File(filePath);

        if (!await file.exists()) {
          debugPrint('[MediaStoreBackup] ⚠️  Old backup file not found: $filePath');
          return false;
        }

        await file.delete();
        debugPrint('[MediaStoreBackup] ✅ Old backup deleted successfully');
        return true;
      } else {
        // This is a MediaStore backup, use normal method
        return await deleteBackupFile(uri);
      }
    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error deleting backup: $e');
      return false;
    }
  }

  /// Import/Scan backup files from Downloads folder into MediaStore
  /// This allows users to manually copy backup files and then import them
  /// Usage: User copies .encrypted files to Download/Zarq_Backups/, then taps "Scan for Backups"
  static Future<int> scanAndImportBackups() async {
    try {
      if (!Platform.isAndroid) {
        debugPrint('[MediaStoreBackup] ⚠️  Not on Android, skipping import');
        return 0;
      }

      debugPrint('[MediaStoreBackup] 🔍 Scanning for backup files to import...');

      final downloadsDir = Directory('/storage/emulated/0/Download/Zarq_Backups');

      if (!await downloadsDir.exists()) {
        debugPrint('[MediaStoreBackup] ⚠️  Backup folder does not exist');
        return 0;
      }

      // Get all .encrypted files in the folder
      final files = await downloadsDir.list().toList();
      final backupFiles = files
          .where((f) => f is File && f.path.endsWith('.encrypted'))
          .cast<File>()
          .toList();

      debugPrint('[MediaStoreBackup] 📁 Found ${backupFiles.length} backup files in folder');

      // Get existing MediaStore backups to avoid duplicates
      final existingBackups = await listBackupFiles();
      final existingNames = existingBackups.map((b) => b['name'] as String).toSet();

      int importedCount = 0;

      for (final file in backupFiles) {
        try {
          final fileName = file.path.split('/').last;

          // Skip if already in MediaStore
          if (existingNames.contains(fileName)) {
            debugPrint('[MediaStoreBackup] ⏭️  Skipping $fileName (already in MediaStore)');
            continue;
          }

          // Import this file into MediaStore
          debugPrint('[MediaStoreBackup] 📥 Importing $fileName...');
          final uri = await saveBackupFile(file, fileName);

          if (uri != null) {
            debugPrint('[MediaStoreBackup] ✅ Imported $fileName → $uri');
            importedCount++;

            // Optional: Delete the original file after successful import
            // Uncomment if you want to clean up after import
            // await file.delete();
            // debugPrint('[MediaStoreBackup] 🗑️  Cleaned up original file');
          } else {
            debugPrint('[MediaStoreBackup] ❌ Failed to import $fileName');
          }
        } catch (e) {
          debugPrint('[MediaStoreBackup] ❌ Error importing file: $e');
        }
      }

      debugPrint('[MediaStoreBackup] ✅ Import complete: $importedCount new backups imported');
      return importedCount;

    } catch (e) {
      debugPrint('[MediaStoreBackup] ❌ Error during scan and import: $e');
      return 0;
    }
  }
}
