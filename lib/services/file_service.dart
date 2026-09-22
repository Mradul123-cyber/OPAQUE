import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:zarq_messenger/app_config.dart';

class FileService {
  static const String baseUrl = '${AppConfig.baseUrl}';
  static const int maxImageSize = 1920; // Max width/height for images
  static const int imageQuality = 85; // JPEG quality (0-100)
  static const int maxCompressedVideoSize = 300 * 1024 * 1024; // 300MB max COMPRESSED video size
  static const int maxDocumentSize = 150 * 1024 * 1024; // 150MB max document size
  static const int videoBitrate = 1000000; // 1Mbps for compressed video

  // Native video compression MethodChannel
  static const MethodChannel _videoCompressionChannel = MethodChannel('com.zarq/video_compression');

  /// Pick image from gallery or camera
  static Future<XFile?> pickImage({required ImageSource source}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: maxImageSize.toDouble(),
        maxHeight: maxImageSize.toDouble(),
        imageQuality: imageQuality,
      );
      return image;
    } catch (e) {
      // print('[FileService] Error picking image: $e');
      return null;
    }
  }

  /// Compress image before encryption
  static Future<Uint8List?> compressImage(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();

      // If already small, don't compress
      if (bytes.length < 500 * 1024) {
        // Less than 500KB
        // print('[FileService] Image already small, skipping compression');
        return bytes;
      }

      // Compress
      final result = await FlutterImageCompress.compressWithFile(
        imagePath,
        quality: imageQuality,
        minWidth: maxImageSize,
        minHeight: maxImageSize,
      );

      if (result == null) {
        // print('[FileService] Compression failed, using original');
        return bytes;
      }

      // print('[FileService] Compressed: ${bytes.length} bytes → ${result.length} bytes');
      return result;
    } catch (e) {
      // print('[FileService] Error compressing image: $e');
      return null;
    }
  }

  /// Get image dimensions
  static Future<Map<String, int>?> getImageDimensions(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      return {
        'width': frame.image.width,
        'height': frame.image.height,
      };
    } catch (e) {
      // print('[FileService] Error getting image dimensions: $e');
      return null;
    }
  }

  /// Single-pass image preparation: reads file once, extracts dimensions, and compresses in memory if needed.
  static Future<Map<String, dynamic>?> prepareImageForSending(String imagePath) async {
    try {
      final file = File(imagePath);
      final rawBytes = await file.readAsBytes();

      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      Uint8List finalBytes = rawBytes;
      if (rawBytes.length >= 500 * 1024) {
        final compressed = await FlutterImageCompress.compressWithList(
          rawBytes,
          quality: imageQuality,
          minWidth: maxImageSize,
          minHeight: maxImageSize,
        );
        if (compressed.isNotEmpty) {
          finalBytes = compressed;
        }
      }

      return {
        'bytes': finalBytes,
        'width': width,
        'height': height,
      };
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // VIDEO METHODS
  // ============================================================

  /// Pick video from gallery or camera
  static Future<XFile?> pickVideo({required ImageSource source}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5), // Max 5 min video
      );
      return video;
    } catch (e) {
      // print('[FileService] Error picking video: $e');
      return null;
    }
  }

  /// Compress video before encryption (using native Kotlin MediaCodec API)
  /// Returns the file path (compressed or original)
  static Future<File?> compressVideo(String videoPath) async {
    final file = File(videoPath);
    try {
      final fileSize = await file.length();

      // print('[FileService] Original video size: ${fileSize / (1024 * 1024)} MB');

      // If video is already small, don't compress
      if (fileSize < 10 * 1024 * 1024) {
        // Less than 10MB
        // print('[FileService] Video already small, skipping compression');
        return file;
      }

      // print('[FileService] Compressing video with native MediaCodec...');

      // Create output path in temp directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(tempDir.path, 'compressed_$timestamp.mp4');

      // Call native compression
      final result = await _videoCompressionChannel.invokeMethod('compressVideo', {
        'inputPath': videoPath,
        'outputPath': outputPath,
        'quality': 'MEDIUM', // LOW, MEDIUM, or HIGH
      });

      if (result != null) {
        final compressedFile = File(result);
        final compressedSize = await compressedFile.length();
        // print('[FileService] ✅ Native compression: ${fileSize / (1024 * 1024)} MB → ${compressedSize / (1024 * 1024)} MB');
        return compressedFile;
      } else {
        // print('[FileService] Compression failed, using original');
        return file;
      }
    } catch (e) {
      // print('[FileService] Error compressing video: $e');
      // Return original file instead of null to prevent crashes
      return file;
    }
  }

  /// Generate video thumbnail
  static Future<Uint8List?> generateVideoThumbnail(String videoPath) async {
    try {
      // print('[FileService] Generating video thumbnail...');
      final uint8list = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320, // Thumbnail width
        quality: 75,
      );

      if (uint8list != null) {
        // print('[FileService] ✅ Thumbnail generated: ${uint8list.length} bytes');
      }

      return uint8list;
    } catch (e) {
      // print('[FileService] Error generating thumbnail: $e');
      return null;
    }
  }

  /// Get video metadata (duration, dimensions) using native Android MediaMetadataRetriever
  static Future<Map<String, dynamic>?> getVideoMetadata(String videoPath) async {
    try {
      final result = await _videoCompressionChannel.invokeMethod('getVideoMetadata', {
        'videoPath': videoPath,
      });

      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      // print('[FileService] Error getting video metadata: $e');
      return null;
    }
  }

  // ============================================================
  // DOCUMENT METHODS
  // ============================================================

  /// Pick document file (PDF, Word, Excel, etc.)
  static Future<PlatformFile?> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'zip', 'rar'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
      return null;
    } catch (e) {
      // print('[FileService] Error picking document: $e');
      return null;
    }
  }

  /// Get file extension and MIME type from file path
  static Map<String, String> getFileMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();

    final mimeTypes = {
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.ppt': 'application/vnd.ms-powerpoint',
      '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.txt': 'text/plain',
      '.csv': 'text/csv',
      '.zip': 'application/zip',
      '.rar': 'application/x-rar-compressed',
    };

    return {
      'extension': extension,
      'mimeType': mimeTypes[extension] ?? 'application/octet-stream',
    };
  }

  // ============================================================
  // ENCRYPTION METHODS (Used for images, videos, and documents)
  // ============================================================

  /// Generate a random AES-256 key (32 bytes)
  static Uint8List generateAESKey() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// Generate a random IV (12 bytes for GCM)
  static Uint8List generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
  }

  /// Encrypt data using AES-256-GCM
  /// Returns a map with: {encryptedData, key, iv}
  static Map<String, dynamic> encryptWithAES({
    required Uint8List data,
    Uint8List? key,
    Uint8List? iv,
  }) {
    try {
      // Generate key and IV if not provided
      final aesKey = key ?? generateAESKey();
      final aesIv = iv ?? generateIV();

      // print('[FileService] Encrypting ${data.length} bytes with AES-256-GCM');

      // Create AES-GCM cipher
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(aesKey),
        128, // tag length in bits
        aesIv,
        Uint8List(0), // additional authenticated data (empty)
      );

      cipher.init(true, params); // true = encrypt

      // Encrypt the data
      final encryptedBytes = cipher.process(data);

      // print('[FileService] ✅ Encrypted to ${encryptedBytes.length} bytes');

      return {
        'encryptedData': encryptedBytes,
        'key': aesKey,
        'iv': aesIv,
      };
    } catch (e) {
      // print('[FileService] Error in AES encryption: $e');
      rethrow;
    }
  }

  /// Decrypt data using AES-256-GCM
  static Uint8List decryptWithAES({
    required Uint8List encryptedData,
    required Uint8List key,
    required Uint8List iv,
  }) {
    try {
      // print('[FileService] Decrypting ${encryptedData.length} bytes with AES-256-GCM');

      // Create AES-GCM cipher
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(key),
        128, // tag length in bits
        iv,
        Uint8List(0), // additional authenticated data (empty)
      );

      cipher.init(false, params); // false = decrypt

      // Decrypt the data
      final decryptedBytes = cipher.process(encryptedData);

      // print('[FileService] ✅ Decrypted to ${decryptedBytes.length} bytes');

      return decryptedBytes;
    } catch (e) {
      // print('[FileService] Error in AES decryption: $e');
      rethrow;
    }
  }

  /// Encrypt image data using AES-256-GCM (Hybrid encryption)
  /// Returns: {encryptedData, key, iv}
  static Map<String, dynamic> encryptImageData({
    required Uint8List imageData,
  }) {
    try {
      // print('[FileService] Encrypting image with AES-256-GCM (${imageData.length} bytes)');
      return encryptWithAES(data: imageData);
    } catch (e) {
      // print('[FileService] Error in image encryption: $e');
      rethrow;
    }
  }

  /// Decrypt image data using AES-256-GCM
  static Uint8List decryptImageData({
    required Uint8List encryptedData,
    required Uint8List key,
    required Uint8List iv,
  }) {
    try {
      // print('[FileService] Decrypting image with AES-256-GCM');
      return decryptWithAES(
        encryptedData: encryptedData,
        key: key,
        iv: iv,
      );
    } catch (e) {
      // print('[FileService] Error in image decryption: $e');
      rethrow;
    }
  }

  /// Upload encrypted file to server
  static Future<Map<String, dynamic>?> uploadEncryptedFile({
    required Uint8List encryptedData,
    required int messageId,
    required int conversationId,
    required String fileType,
    required String mimeType,
    int? width,
    int? height,
    String? mediaEncryptionKey,
    String? mediaEncryptionIv,
    String? senderMediaEncryptionKey,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final token = await currentUser.getIdToken();
      if (token == null) throw Exception('Failed to get auth token');

      // print('[FileService] Uploading encrypted file...');
      // print('[FileService] DEBUG - mediaEncryptionKey length: ${mediaEncryptionKey?.length ?? 0}');
      // print('[FileService] DEBUG - mediaEncryptionIv length: ${mediaEncryptionIv?.length ?? 0}');
      if (mediaEncryptionKey != null) {
        // print('[FileService] DEBUG - Encryption key (first 20 chars): ${mediaEncryptionKey.substring(0, 20)}...');
      } else {
        // print('[FileService] DEBUG - ⚠️ NO encryption key provided to uploadEncryptedFile!');
      }

      // Create multipart request
      final uri = Uri.parse('$baseUrl/v1/files/upload');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $token';

      // Add file
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        encryptedData,
        filename: 'encrypted_${DateTime.now().millisecondsSinceEpoch}.enc',
      ));

      // Add metadata
      request.fields['message_id'] = messageId.toString();
      request.fields['conversation_id'] = conversationId.toString();
      request.fields['file_type'] = fileType;
      request.fields['mime_type'] = mimeType;
      if (width != null) request.fields['width'] = width.toString();
      if (height != null) request.fields['height'] = height.toString();
      if (mediaEncryptionKey != null) request.fields['media_encryption_key'] = mediaEncryptionKey;
      if (mediaEncryptionIv != null) request.fields['media_encryption_iv'] = mediaEncryptionIv;
      if (senderMediaEncryptionKey != null) request.fields['sender_media_encryption_key'] = senderMediaEncryptionKey;

      // DEBUG: Log all fields being sent
      // print('[FileService] DEBUG - Request fields: ${request.fields.keys.toList()}');
      // print('[FileService] DEBUG - Has media_encryption_key: ${request.fields.containsKey('media_encryption_key')}');
      // print('[FileService] DEBUG - Has media_encryption_iv: ${request.fields.containsKey('media_encryption_iv')}');

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        // print('[FileService] ✅ File uploaded: ${data['attachment_id']}');
        // print('[FileService] DEBUG - Response keys: ${data.keys.toList()}');
        // print('[FileService] DEBUG - Has media_encryption_key in response: ${data.containsKey('media_encryption_key')}');
        // print('[FileService] DEBUG - Has media_encryption_iv in response: ${data.containsKey('media_encryption_iv')}');
        if (data['media_encryption_key'] != null) {
          // print('[FileService] DEBUG - Response media_encryption_key length: ${(data['media_encryption_key'] as String).length}');
        }
        return data;
      } else {
        final errorMsg = 'Upload failed with status ${response.statusCode}: $responseBody';
        // print('[FileService] ❌ $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e) {
      // print('[FileService] ❌ Error uploading file: $e');
      rethrow;
    }
  }

  /// Fetch attachment metadata from server (including encryption keys)
  static Future<Map<String, dynamic>?> fetchAttachmentMetadata(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      final token = await currentUser.getIdToken();
      if (token == null) return null;

      // print('[FileService] Fetching attachment metadata for $attachmentId...');

      final uri = Uri.parse('$baseUrl/v1/files/$attachmentId/metadata');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // print('[FileService] ✅ Metadata fetched: ${data.keys.toList()}');
        return data;
      } else {
        // print('[FileService] Metadata fetch failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error fetching metadata: $e');
      return null;
    }
  }

  /// Download encrypted file from server
  static Future<Uint8List?> downloadEncryptedFile(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      final token = await currentUser.getIdToken();
      if (token == null) return null;

      // print('[FileService] Downloading encrypted file $attachmentId...');

      final uri = Uri.parse('$baseUrl/v1/files/$attachmentId');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        // print('[FileService] ✅ File downloaded: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        // print('[FileService] Download failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error downloading file: $e');
      return null;
    }
  }

  /// Save decrypted image to cache for displaying
  static Future<File?> saveToCacheFile(Uint8List data, String filename) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, filename));
      await file.writeAsBytes(data);
      // print('[FileService] Saved to cache: ${file.path}');
      return file;
    } catch (e) {
      // print('[FileService] Error saving to cache: $e');
      return null;
    }
  }

  /// Save image to persistent storage (UID-isolated)
  /// WhatsApp approach: Store in external storage so media survives app uninstall
  static Future<File?> saveImageToPersistentStorage(Uint8List data, int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Use Android/media directory like WhatsApp - media persists after uninstall, Google Play compliant
      final imagesDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/${currentUser.uid}');

      // Create user-specific images directory if it doesn't exist
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final file = File(path.join(imagesDir.path, 'attachment_$attachmentId.jpg'));
      await file.writeAsBytes(data);
      // print('[FileService] Saved image to external storage: ${file.path}');
      return file;
    } catch (e) {
      // print('[FileService] Error saving to external storage: $e');
      return null;
    }
  }

  /// Load image from persistent storage (UID-isolated)
  static Future<Uint8List?> loadImageFromPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Load from Android/media directory
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/${currentUser.uid}/attachment_$attachmentId.jpg');

      if (await file.exists()) {
        // print('[FileService] Loading image from external storage: ${file.path}');
        return await file.readAsBytes();
      } else {
        // print('[FileService] Image not found in external storage');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error loading from external storage: $e');
      return null;
    }
  }

  /// Check if image exists in persistent storage (UID-isolated)
  static Future<bool> imageExistsInPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Check external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/${currentUser.uid}/attachment_$attachmentId.jpg');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // VIDEO STORAGE METHODS
  // ============================================================

  /// Save video to persistent storage (UID-isolated)
  /// WhatsApp approach: Store in external storage so media survives app uninstall
  static Future<File?> saveVideoToPersistentStorage(Uint8List data, int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Use external storage like WhatsApp - media persists after uninstall
      final videosDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/${currentUser.uid}');

      // Create user-specific videos directory if it doesn't exist
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }

      final file = File(path.join(videosDir.path, 'attachment_$attachmentId.mp4'));
      await file.writeAsBytes(data);
      // print('[FileService] Saved video to external storage: ${file.path}');
      return file;
    } catch (e) {
      // print('[FileService] Error saving video to external storage: $e');
      return null;
    }
  }

  /// Load video from persistent storage (UID-isolated)
  static Future<Uint8List?> loadVideoFromPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Load from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/${currentUser.uid}/attachment_$attachmentId.mp4');

      if (await file.exists()) {
        // print('[FileService] Loading video from external storage: ${file.path}');
        return await file.readAsBytes();
      } else {
        // print('[FileService] Video not found in external storage');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error loading video from external storage: $e');
      return null;
    }
  }

  /// Check if video exists in persistent storage (UID-isolated)
  static Future<bool> videoExistsInPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Check external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/${currentUser.uid}/attachment_$attachmentId.mp4');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get video file path from persistent storage (for video player) (UID-isolated)
  static Future<String?> getVideoFilePath(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Get from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/${currentUser.uid}/attachment_$attachmentId.mp4');

      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      // print('[FileService] Error getting video file path: $e');
      return null;
    }
  }

  // ==================== THUMBNAIL STORAGE ====================

  /// Save video thumbnail to persistent storage (UID-isolated)
  /// WhatsApp approach: Store in external storage so media survives app uninstall
  static Future<bool> saveThumbnailToPersistentStorage(Uint8List thumbnailData, int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Use external storage like WhatsApp - media persists after uninstall
      final thumbnailsDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Thumbnails/${currentUser.uid}');

      // Create user-specific thumbnails directory if it doesn't exist
      if (!await thumbnailsDir.exists()) {
        await thumbnailsDir.create(recursive: true);
      }

      final file = File(path.join(thumbnailsDir.path, 'thumb_$attachmentId.jpg'));
      await file.writeAsBytes(thumbnailData);
      // print('[FileService] Saved thumbnail to external storage: ${file.path}');
      return true;
    } catch (e) {
      // print('[FileService] Error saving thumbnail to external storage: $e');
      return false;
    }
  }

  /// Load thumbnail from persistent storage (UID-isolated)
  static Future<Uint8List?> loadThumbnailFromPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Load from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Thumbnails/${currentUser.uid}/thumb_$attachmentId.jpg');

      if (await file.exists()) {
        // print('[FileService] Loading thumbnail from external storage: ${file.path}');
        return await file.readAsBytes();
      } else {
        // print('[FileService] Thumbnail not found in external storage');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error loading thumbnail from external storage: $e');
      return null;
    }
  }

  /// Check if thumbnail exists in persistent storage (UID-isolated)
  static Future<bool> thumbnailExistsInPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Check external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Thumbnails/${currentUser.uid}/thumb_$attachmentId.jpg');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // DOCUMENT STORAGE METHODS
  // ============================================================

  /// Save document to persistent storage (UID-isolated)
  /// WhatsApp approach: Store in external storage so media survives app uninstall
  static Future<File?> saveDocumentToPersistentStorage(Uint8List data, int attachmentId, String extension) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Use external storage like WhatsApp - media persists after uninstall
      final documentsDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/${currentUser.uid}');

      // Create user-specific documents directory if it doesn't exist
      if (!await documentsDir.exists()) {
        await documentsDir.create(recursive: true);
      }

      final file = File(path.join(documentsDir.path, 'attachment_$attachmentId$extension'));
      await file.writeAsBytes(data);
      // print('[FileService] Saved document to external storage: ${file.path}');
      return file;
    } catch (e) {
      // print('[FileService] Error saving document to external storage: $e');
      return null;
    }
  }

  /// Load document from persistent storage (UID-isolated)
  static Future<Uint8List?> loadDocumentFromPersistentStorage(int attachmentId, String extension) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Load from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/${currentUser.uid}/attachment_$attachmentId$extension');

      if (await file.exists()) {
        // print('[FileService] Loading document from external storage: ${file.path}');
        return await file.readAsBytes();
      } else {
        // print('[FileService] Document not found in external storage');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error loading document from external storage: $e');
      return null;
    }
  }

  /// Check if document exists in persistent storage (UID-isolated)
  static Future<bool> documentExistsInPersistentStorage(int attachmentId, String extension) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Check external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/${currentUser.uid}/attachment_$attachmentId$extension');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get document file path from persistent storage (UID-isolated)
  static Future<String?> getDocumentFilePath(int attachmentId, String extension) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Get from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/${currentUser.uid}/attachment_$attachmentId$extension');

      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      // print('[FileService] Error getting document file path: $e');
      return null;
    }
  }

  // ============================================================
  // AUDIO VOICE MESSAGE METHODS
  // ============================================================

  /// Encrypt audio data using AES-256-GCM (same as images/videos)
  static Map<String, dynamic> encryptAudioData({
    required Uint8List audioData,
  }) {
    try {
      // print('[FileService] Encrypting audio with AES-256-GCM (${audioData.length} bytes)');
      return encryptWithAES(data: audioData);
    } catch (e) {
      // print('[FileService] Error in audio encryption: $e');
      rethrow;
    }
  }

  /// Decrypt audio data using AES-256-GCM
  static Uint8List decryptAudioData({
    required Uint8List encryptedData,
    required Uint8List key,
    required Uint8List iv,
  }) {
    try {
      // print('[FileService] Decrypting audio with AES-256-GCM');
      return decryptWithAES(
        encryptedData: encryptedData,
        key: key,
        iv: iv,
      );
    } catch (e) {
      // print('[FileService] Error in audio decryption: $e');
      rethrow;
    }
  }

  /// Save audio to persistent storage (UID-isolated)
  /// WhatsApp approach: Store in external storage so media survives app uninstall
  static Future<File?> saveAudioToPersistentStorage(Uint8List data, int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Use external storage like WhatsApp - media persists after uninstall
      final audiosDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/${currentUser.uid}');

      // Create user-specific audios directory if it doesn't exist
      if (!await audiosDir.exists()) {
        await audiosDir.create(recursive: true);
      }

      final file = File(path.join(audiosDir.path, 'attachment_$attachmentId.aac'));
      await file.writeAsBytes(data);
      // print('[FileService] Saved audio to external storage: ${file.path}');
      return file;
    } catch (e) {
      // print('[FileService] Error saving audio to external storage: $e');
      return null;
    }
  }

  /// Load audio from persistent storage (UID-isolated)
  static Future<Uint8List?> loadAudioFromPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Load from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/${currentUser.uid}/attachment_$attachmentId.aac');

      if (await file.exists()) {
        // print('[FileService] Loading audio from external storage: ${file.path}');
        return await file.readAsBytes();
      } else {
        // print('[FileService] Audio not found in external storage');
        return null;
      }
    } catch (e) {
      // print('[FileService] Error loading audio from external storage: $e');
      return null;
    }
  }

  /// Check if audio exists in persistent storage (UID-isolated)
  static Future<bool> audioExistsInPersistentStorage(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // Check external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/${currentUser.uid}/attachment_$attachmentId.aac');
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get audio file path from persistent storage (for audio player) (UID-isolated)
  static Future<String?> getAudioFilePath(int attachmentId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // Get from external storage
      final file = File('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/${currentUser.uid}/attachment_$attachmentId.aac');

      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      // print('[FileService] Error getting audio file path: $e');
      return null;
    }
  }
}