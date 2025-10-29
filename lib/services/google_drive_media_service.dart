import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'backup_service.dart';

/// Progress callback: (current, total, currentFileName)
typedef GoogleDriveMediaProgressCallback = void Function(int current, int total, String currentFileName);

/// Google Drive Media Service - Handles separate media upload/download for backups
///
/// WhatsApp Approach:
/// - Backup file contains messages only (~10MB)
/// - Media files uploaded separately to Google Drive
/// - During restore, download media files individually
class GoogleDriveMediaService {
  final BackupService _backupService;

  GoogleDriveMediaService(this._backupService);

  // ================== MEDIA UPLOAD ==================

  /// Upload all media files to Google Drive
  /// Returns list of uploaded file IDs and metadata
  Future<List<Map<String, dynamic>>> uploadMediaFiles({
    required drive.DriveApi driveApi,
    required String backupFolderId,
    required List<Map<String, dynamic>> messages,
    int? excludeMediaOlderThanDays,
    GoogleDriveMediaProgressCallback? onProgress,
    bool Function()? shouldCancel, // Cancellation checker callback
  }) async {
    try {
      debugPrint('[GoogleDriveMedia] Starting media upload to Google Drive...');

      // Create Media subfolder inside backup folder
      final mediaFolderId = await _findOrCreateMediaFolder(driveApi, backupFolderId);
      if (mediaFolderId == null) {
        throw Exception('Failed to create media folder');
      }

      debugPrint('[GoogleDriveMedia] Media folder ID: $mediaFolderId');

      // Collect media file paths from messages
      final mediaFiles = await _collectMediaFilePaths(
        messages: messages,
        excludeOlderThanDays: excludeMediaOlderThanDays,
      );

      debugPrint('[GoogleDriveMedia] Found ${mediaFiles.length} media files to upload');

      final uploadedFiles = <Map<String, dynamic>>[];
      int currentIndex = 0;

      for (final mediaFile in mediaFiles) {
        currentIndex++;

        // CRITICAL: Check for cancellation before uploading each file
        if (shouldCancel?.call() == true) {
          debugPrint('[GoogleDriveMedia] ⚠️ Upload cancelled by user at file $currentIndex/${mediaFiles.length}');
          throw Exception('Media upload cancelled by user');
        }

        final fileName = path.basename(mediaFile['localPath'] as String);

        // CRITICAL: Wrap progress callback in try-catch to ensure it never interrupts upload
        // Progress callback might fail if widget is disposed, but upload must continue
        try {
          onProgress?.call(currentIndex, mediaFiles.length, fileName);
        } catch (e) {
          debugPrint('[GoogleDriveMedia] Progress callback error (non-fatal): $e');
        }

        debugPrint('[GoogleDriveMedia] Uploading $currentIndex/${mediaFiles.length}: $fileName');

        final uploadedId = await _uploadSingleMediaFile(
          driveApi: driveApi,
          folderId: mediaFolderId,
          localPath: mediaFile['localPath'] as String,
          attachmentId: mediaFile['attachmentId'] as int,
          attachmentType: mediaFile['attachmentType'] as String,
        );

        if (uploadedId != null) {
          uploadedFiles.add({
            'driveFileId': uploadedId,
            'attachmentId': mediaFile['attachmentId'],
            'attachmentType': mediaFile['attachmentType'],
            'fileName': fileName,
            'uploadedAt': DateTime.now().toIso8601String(),
          });
          debugPrint('[GoogleDriveMedia] ✅ Uploaded: $fileName (ID: $uploadedId)');
        } else {
          debugPrint('[GoogleDriveMedia] ❌ Failed to upload: $fileName');
        }
      }

      debugPrint('[GoogleDriveMedia] Media upload complete: ${uploadedFiles.length}/${mediaFiles.length} files');
      return uploadedFiles;
    } catch (e, stackTrace) {
      debugPrint('[GoogleDriveMedia] Error uploading media: $e');
      debugPrint('[GoogleDriveMedia] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Find or create Media subfolder in backup folder
  Future<String?> _findOrCreateMediaFolder(drive.DriveApi driveApi, String parentFolderId) async {
    try {
      final folderName = 'Media';

      // Create new folder (each backup has its own Media folder inside its backup folder)
      final folderMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentFolderId];

      final folder = await driveApi.files.create(folderMetadata);
      debugPrint('[GoogleDriveMedia] Created media folder: $folderName (ID: ${folder.id})');
      return folder.id;
    } catch (e) {
      debugPrint('[GoogleDriveMedia] Error creating media folder: $e');
      return null;
    }
  }

  /// Collect media file paths from messages
  Future<List<Map<String, dynamic>>> _collectMediaFilePaths({
    required List<Map<String, dynamic>> messages,
    int? excludeOlderThanDays,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final userUid = currentUser.uid;
    final List<Map<String, dynamic>> mediaFiles = [];

    // Calculate cutoff timestamp if filter is enabled
    final cutoffTimestamp = excludeOlderThanDays != null
        ? DateTime.now().subtract(Duration(days: excludeOlderThanDays)).millisecondsSinceEpoch
        : null;

    for (final messageData in messages) {
      final hasAttachment = messageData['has_attachment'] == 1;
      if (!hasAttachment) continue;

      final attachmentId = messageData['attachment_id'] as int?;
      final attachmentType = messageData['attachment_type'] as String?;
      final timestampStr = messageData['timestamp'] as String?;

      if (attachmentId == null || attachmentType == null) continue;

      // Parse timestamp and skip old media if filter is enabled
      if (cutoffTimestamp != null && timestampStr != null) {
        try {
          final messageTimestamp = DateTime.parse(timestampStr).millisecondsSinceEpoch;
          if (messageTimestamp < cutoffTimestamp) {
            continue;
          }
        } catch (e) {
          debugPrint('[GoogleDriveMedia] Error parsing timestamp for attachment $attachmentId: $e');
        }
      }

      // Determine storage path - Use EXTERNAL storage (WhatsApp approach)
      String? storagePath;

      if (attachmentType == 'image') {
        storagePath = '/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/$userUid/attachment_$attachmentId.jpg';
      } else if (attachmentType == 'video') {
        storagePath = '/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/$userUid/attachment_$attachmentId.mp4';
      } else if (attachmentType == 'audio') {
        storagePath = '/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/$userUid/attachment_$attachmentId.aac';
      } else if (attachmentType == 'document') {
        final docDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/$userUid');
        if (await docDir.exists()) {
          final docFiles = await docDir.list().where((f) => f.path.contains('attachment_$attachmentId')).toList();
          if (docFiles.isNotEmpty) {
            storagePath = docFiles.first.path;
          }
        }
      }

      if (storagePath != null && await File(storagePath).exists()) {
        mediaFiles.add({
          'localPath': storagePath,
          'attachmentId': attachmentId,
          'attachmentType': attachmentType,
        });
      }
    }

    return mediaFiles;
  }

  /// Upload single media file to Google Drive
  Future<String?> _uploadSingleMediaFile({
    required drive.DriveApi driveApi,
    required String folderId,
    required String localPath,
    required int attachmentId,
    required String attachmentType,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        debugPrint('[GoogleDriveMedia] File not found: $localPath');
        return null;
      }

      final fileName = path.basename(localPath);
      final fileSize = await file.length();

      debugPrint('[GoogleDriveMedia] Uploading $fileName (${_formatBytes(fileSize)})...');

      // Create file metadata
      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..description = 'Zarq Media - Attachment $attachmentId ($attachmentType)';

      // Upload file with resumable upload for large files
      final fileStream = file.openRead();
      final media = drive.Media(fileStream, fileSize);

      final uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      return uploadedFile.id;
    } catch (e) {
      debugPrint('[GoogleDriveMedia] Error uploading $localPath: $e');
      return null;
    }
  }

  // ================== MEDIA DOWNLOAD ==================

  /// Download all media files from Google Drive during restore
  Future<void> downloadMediaFiles({
    required drive.DriveApi driveApi,
    required List<Map<String, dynamic>> mediaMetadata,
    GoogleDriveMediaProgressCallback? onProgress,
    bool Function()? shouldCancel, // Cancellation checker callback
  }) async {
    try {
      debugPrint('[GoogleDriveMedia] Starting media download from Google Drive...');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final userUid = currentUser.uid;
      final dir = await getApplicationDocumentsDirectory();

      int currentIndex = 0;
      final totalFiles = mediaMetadata.length;

      for (final media in mediaMetadata) {
        currentIndex++;

        // CRITICAL: Check for cancellation before downloading each file
        if (shouldCancel?.call() == true) {
          debugPrint('[GoogleDriveMedia] ⚠️ Download cancelled by user at file $currentIndex/$totalFiles');
          throw Exception('Media download cancelled by user');
        }

        final fileName = media['fileName'] as String;
        final driveFileId = media['driveFileId'] as String;
        final attachmentId = media['attachmentId'] as int;
        final attachmentType = media['attachmentType'] as String;

        // CRITICAL: Wrap progress callback in try-catch to ensure it never interrupts download
        // Progress callback might fail if widget is disposed, but download must continue
        try {
          onProgress?.call(currentIndex, totalFiles, fileName);
        } catch (e) {
          debugPrint('[GoogleDriveMedia] Progress callback error (non-fatal): $e');
        }

        debugPrint('[GoogleDriveMedia] Downloading $currentIndex/$totalFiles: $fileName');

        await _downloadSingleMediaFile(
          driveApi: driveApi,
          fileId: driveFileId,
          attachmentId: attachmentId,
          attachmentType: attachmentType,
          userUid: userUid,
          dir: dir,
        );
      }

      debugPrint('[GoogleDriveMedia] Media download complete: $currentIndex/$totalFiles files');
    } catch (e, stackTrace) {
      debugPrint('[GoogleDriveMedia] Error downloading media: $e');
      debugPrint('[GoogleDriveMedia] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Download single media file from Google Drive
  Future<void> _downloadSingleMediaFile({
    required drive.DriveApi driveApi,
    required String fileId,
    required int attachmentId,
    required String attachmentType,
    required String userUid,
    required Directory dir,
  }) async {
    try {
      // Determine storage path - Use EXTERNAL storage (WhatsApp approach)
      String storagePath;
      Directory storageDir;

      if (attachmentType == 'image') {
        storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/$userUid');
        storagePath = path.join(storageDir.path, 'attachment_$attachmentId.jpg');
      } else if (attachmentType == 'video') {
        storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/$userUid');
        storagePath = path.join(storageDir.path, 'attachment_$attachmentId.mp4');
      } else if (attachmentType == 'audio') {
        storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/$userUid');
        storagePath = path.join(storageDir.path, 'attachment_$attachmentId.aac');
      } else if (attachmentType == 'document') {
        storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/$userUid');
        // For documents, we need to get the actual file extension from Drive
        final fileInfo = await driveApi.files.get(fileId, $fields: 'name') as drive.File;
        final extension = path.extension(fileInfo.name ?? '');
        storagePath = path.join(storageDir.path, 'attachment_$attachmentId$extension');
      } else {
        debugPrint('[GoogleDriveMedia] Unknown attachment type: $attachmentType');
        return;
      }

      final file = File(storagePath);

      // WhatsApp approach: Skip if file already exists (avoids duplication & saves bandwidth)
      if (await file.exists()) {
        debugPrint('[GoogleDriveMedia] ⏭️ Media already exists in external storage, skipping download: attachment_$attachmentId');
        return;
      }

      // Create directory if needed
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      // Download file from Google Drive
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Save to external storage (persists after uninstall)
      final sink = file.openWrite();

      try {
        await media.stream.pipe(sink);
        debugPrint('[GoogleDriveMedia] ✅ Downloaded to external storage: attachment_$attachmentId');
      } catch (e) {
        debugPrint('[GoogleDriveMedia] Error piping stream: $e');
        rethrow;
      } finally {
        await sink.close();
      }
    } catch (e) {
      debugPrint('[GoogleDriveMedia] Error downloading file $fileId: $e');
      rethrow;
    }
  }

  // ================== MEDIA MANIFEST ==================

  /// Create media manifest file (JSON file listing all uploaded media)
  Future<String?> uploadMediaManifest({
    required drive.DriveApi driveApi,
    required String backupFolderId,
    required List<Map<String, dynamic>> uploadedFiles,
  }) async {
    try {
      debugPrint('[GoogleDriveMedia] Creating media manifest...');

      // Create manifest file content
      final manifest = {
        'version': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'totalFiles': uploadedFiles.length,
        'files': uploadedFiles,
      };

      // Convert to JSON and create temporary file
      final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
      final tempDir = await getTemporaryDirectory();
      final manifestFile = File(path.join(tempDir.path, 'media_manifest.json'));
      await manifestFile.writeAsString(manifestJson);

      // Upload manifest to Drive
      final fileMetadata = drive.File()
        ..name = 'media_manifest.json'
        ..parents = [backupFolderId]
        ..description = 'Zarq Media Manifest';

      final fileStream = manifestFile.openRead();
      final media = drive.Media(fileStream, await manifestFile.length());

      final uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      // Clean up temp file
      await manifestFile.delete();

      debugPrint('[GoogleDriveMedia] ✅ Media manifest uploaded (ID: ${uploadedFile.id})');
      return uploadedFile.id;
    } catch (e) {
      debugPrint('[GoogleDriveMedia] Error uploading manifest: $e');
      return null;
    }
  }

  /// Download and parse media manifest
  Future<List<Map<String, dynamic>>?> downloadMediaManifest({
    required drive.DriveApi driveApi,
    required String backupFolderId,
  }) async {
    try {
      debugPrint('[GoogleDriveMedia] Downloading media manifest...');

      // Find manifest file in backup folder
      final query = "'$backupFolderId' in parents and name='media_manifest.json' and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        debugPrint('[GoogleDriveMedia] No media manifest found');
        return null;
      }

      final manifestFileId = fileList.files!.first.id!;

      // Download manifest
      final media = await driveApi.files.get(
        manifestFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Read content
      final chunks = <List<int>>[];
      await for (final chunk in media.stream) {
        chunks.add(chunk);
      }
      final bytes = chunks.expand((x) => x).toList();
      final jsonString = String.fromCharCodes(bytes);

      // Parse JSON
      final manifest = jsonDecode(jsonString) as Map<String, dynamic>;
      final files = manifest['files'] as List;

      debugPrint('[GoogleDriveMedia] ✅ Media manifest downloaded: ${files.length} files');

      return files.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[GoogleDriveMedia] Error downloading manifest: $e');
      return null;
    }
  }

  // ================== UTILITY ==================

  /// Format bytes to human-readable size
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
