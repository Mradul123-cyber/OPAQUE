import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pointycastle/export.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'database_service.dart';
import 'SignalService.dart';
import 'secure_storage_service.dart';
import 'google_drive_media_service.dart';
import 'backup_notification_service.dart';

/// Backup Data Model
class BackupData {
  final String version;
  final int timestamp;
  final String userUid;
  final String deviceId;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> conversations;
  final Map<String, dynamic> signalProtocolState;
  final List<BackupAttachment> attachments;

  BackupData({
    required this.version,
    required this.timestamp,
    required this.userUid,
    required this.deviceId,
    required this.messages,
    required this.conversations,
    required this.signalProtocolState,
    required this.attachments,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'timestamp': timestamp,
        'userUid': userUid,
        'deviceId': deviceId,
        'messages': messages,
        'conversations': conversations,
        'signalProtocolState': signalProtocolState,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory BackupData.fromJson(Map<String, dynamic> json) => BackupData(
        version: json['version'] as String,
        timestamp: json['timestamp'] as int,
        userUid: json['userUid'] as String,
        deviceId: json['deviceId'] as String,
        messages: List<Map<String, dynamic>>.from(json['messages']),
        conversations: List<Map<String, dynamic>>.from(json['conversations']),
        signalProtocolState: json['signalProtocolState'] as Map<String, dynamic>,
        attachments: (json['attachments'] as List)
            .map((a) => BackupAttachment.fromJson(a))
            .toList(),
      );
}

/// Backup Attachment Model - E2EE with Signal/Sender Keys
class BackupAttachment {
  final int attachmentId;
  final String type; // image/video/audio/document
  final String extension;
  final String encryptedDataBase64;

  // E2EE: Store ENCRYPTED AES key (not raw)
  final String encryptedAesKey; // AES key encrypted with Signal Protocol or Sender Keys
  final String encryptionIv;

  // Metadata to decrypt the AES key
  final String encryptionType; // 'signal' (1-on-1) or 'sender_keys' (group)
  final String? recipientUid; // For Signal Protocol (1-on-1)
  final int? recipientDeviceId; // For Signal Protocol (1-on-1)
  final String? groupId; // For Sender Keys (group)
  final String? senderUid; // Who encrypted this (for sender keys decryption)
  final int? senderDeviceId; // Sender's device (for sender keys decryption)

  BackupAttachment({
    required this.attachmentId,
    required this.type,
    required this.extension,
    required this.encryptedDataBase64,
    required this.encryptedAesKey,
    required this.encryptionIv,
    required this.encryptionType,
    this.recipientUid,
    this.recipientDeviceId,
    this.groupId,
    this.senderUid,
    this.senderDeviceId,
  });

  Map<String, dynamic> toJson() => {
        'attachmentId': attachmentId,
        'type': type,
        'extension': extension,
        'encryptedDataBase64': encryptedDataBase64,
        'encryptedAesKey': encryptedAesKey,
        'encryptionIv': encryptionIv,
        'encryptionType': encryptionType,
        'recipientUid': recipientUid,
        'recipientDeviceId': recipientDeviceId,
        'groupId': groupId,
        'senderUid': senderUid,
        'senderDeviceId': senderDeviceId,
      };

  factory BackupAttachment.fromJson(Map<String, dynamic> json) => BackupAttachment(
        attachmentId: json['attachmentId'] as int,
        type: json['type'] as String,
        extension: json['extension'] as String,
        encryptedDataBase64: json['encryptedDataBase64'] as String,
        encryptedAesKey: json['encryptedAesKey'] as String,
        encryptionIv: json['encryptionIv'] as String,
        encryptionType: json['encryptionType'] as String,
        recipientUid: json['recipientUid'] as String?,
        recipientDeviceId: json['recipientDeviceId'] as int?,
        groupId: json['groupId'] as String?,
        senderUid: json['senderUid'] as String?,
        senderDeviceId: json['senderDeviceId'] as int?,
      );
}

/// Backup Frequency Enum
enum BackupFrequency {
  daily,
  weekly,
  monthly,
  disabled;

  String get displayName {
    switch (this) {
      case BackupFrequency.daily:
        return 'Daily';
      case BackupFrequency.weekly:
        return 'Weekly';
      case BackupFrequency.monthly:
        return 'Monthly';
      case BackupFrequency.disabled:
        return 'Disabled';
    }
  }

  static BackupFrequency fromString(String value) {
    return BackupFrequency.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BackupFrequency.disabled,
    );
  }
}

/// Backup Destination Enum
enum BackupDestination {
  local,
  googleDrive,
  both;

  String get displayName {
    switch (this) {
      case BackupDestination.local:
        return 'Local Storage';
      case BackupDestination.googleDrive:
        return 'Google Drive';
      case BackupDestination.both:
        return 'Local & Google Drive';
    }
  }

  static BackupDestination fromString(String value) {
    return BackupDestination.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BackupDestination.local,
    );
  }
}

/// Auto-Backup Settings Model
class AutoBackupSettings {
  final bool enabled;
  final BackupFrequency frequency;
  final BackupDestination destination;
  final bool wifiOnly;
  final int? mediaAgeLimitDays; // null means include all media
  final DateTime? lastBackupTime;
  final String? lastBackupPassphrase; // Encrypted passphrase for auto-backup

  AutoBackupSettings({
    this.enabled = false,
    this.frequency = BackupFrequency.weekly,
    this.destination = BackupDestination.local,
    this.wifiOnly = true,
    this.mediaAgeLimitDays = 30, // Default: 30 days
    this.lastBackupTime,
    this.lastBackupPassphrase,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'frequency': frequency.name,
        'destination': destination.name,
        'wifiOnly': wifiOnly,
        'mediaAgeLimitDays': mediaAgeLimitDays,
        'lastBackupTime': lastBackupTime?.toIso8601String(),
        // Passphrase NOT stored in SharedPreferences - stored securely in SecureStorageService
      };

  factory AutoBackupSettings.fromJson(Map<String, dynamic> json, {String? passphrase}) => AutoBackupSettings(
        enabled: json['enabled'] as bool? ?? false,
        frequency: BackupFrequency.fromString(json['frequency'] as String? ?? 'disabled'),
        destination: BackupDestination.fromString(json['destination'] as String? ?? 'local'),
        wifiOnly: json['wifiOnly'] as bool? ?? true,
        mediaAgeLimitDays: json['mediaAgeLimitDays'] as int?,
        lastBackupTime: json['lastBackupTime'] != null
            ? DateTime.parse(json['lastBackupTime'] as String)
            : null,
        lastBackupPassphrase: passphrase, // Loaded separately from SecureStorageService
      );

  AutoBackupSettings copyWith({
    bool? enabled,
    BackupFrequency? frequency,
    BackupDestination? destination,
    bool? wifiOnly,
    int? mediaAgeLimitDays,
    DateTime? lastBackupTime,
    String? lastBackupPassphrase,
  }) {
    return AutoBackupSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      destination: destination ?? this.destination,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      mediaAgeLimitDays: mediaAgeLimitDays ?? this.mediaAgeLimitDays,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      lastBackupPassphrase: lastBackupPassphrase ?? this.lastBackupPassphrase,
    );
  }
}


/// Backup Service - Handles E2EE backup/restore for messages and attachments
class BackupService {
  static const String backupVersion = '1.0.0';
  static const int pbkdf2Iterations = 100000;
  static const int aesKeySize = 32; // 256-bit
  static const int nonceSize = 12; // GCM nonce
  static const int authTagSize = 16; // GCM auth tag

  // Singleton pattern to persist authentication state across screens
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final DatabaseService _dbService = DatabaseService.instance;

  // ================== LOCAL BACKUP CREATION ==================

  /// Create a complete backup of messages and attachments
  Future<BackupData> createLocalBackup({
    int? excludeMediaOlderThanDays,
    bool includeMedia = true, // Default: include media (for backward compatibility)
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final userUid = currentUser.uid;
      final deviceIdInt = await SignalService.getDeviceId();
      final deviceId = deviceIdInt?.toString() ?? 'unknown';
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      debugPrint('[BackupService] Creating backup for user: $userUid, device: $deviceId');
      debugPrint('[BackupService] Include media: $includeMedia');

      // 1. Export all messages
      final messages = await _exportMessages();
      debugPrint('[BackupService] Exported ${messages.length} messages');

      // 2. Derive conversations from messages (no conversations table)
      final conversations = _deriveConversationsFromMessages(messages);
      debugPrint('[BackupService] Derived ${conversations.length} conversations from messages');

      // 3. Export Signal Protocol state from Android SharedPreferences
      final signalState = await _exportSignalProtocolState();
      debugPrint('[BackupService] Exported Signal Protocol state');

      // 4. Collect attachments (skip if includeMedia is false)
      final attachments = includeMedia
          ? await _collectAttachments(
              messages: messages,
              excludeOlderThanDays: excludeMediaOlderThanDays,
            )
          : <BackupAttachment>[]; // Empty list when media is excluded
      debugPrint('[BackupService] Collected ${attachments.length} attachments');

      final backupData = BackupData(
        version: backupVersion,
        timestamp: timestamp,
        userUid: userUid,
        deviceId: deviceId,
        messages: messages,
        conversations: conversations,
        signalProtocolState: signalState,
        attachments: attachments,
      );

      debugPrint('[BackupService] Backup created successfully');
      return backupData;
    } catch (e) {
      debugPrint('[BackupService] Error creating backup: $e');
      rethrow;
    }
  }

  /// Derive conversations from messages (no conversations table)
  List<Map<String, dynamic>> _deriveConversationsFromMessages(List<Map<String, dynamic>> messages) {
    final conversationMap = <int, Map<String, dynamic>>{};

    for (final message in messages) {
      final conversationId = message['conversationId'] as int;

      if (!conversationMap.containsKey(conversationId)) {
        conversationMap[conversationId] = {
          'conversationId': conversationId,
          'lastMessageTimestamp': message['timestamp'],
          'username': message['username'],
          'senderUid': message['senderUid'],
        };
      }
    }

    return conversationMap.values.toList();
  }

  /// Export messages from database (excluding deleted messages)
  Future<List<Map<String, dynamic>>> _exportMessages() async {
    final db = _dbService.database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    // CRITICAL: Exclude both "delete for me" and "delete for everyone" messages
    // 1. Use LEFT JOIN to exclude messages in deleted_messages table (delete for me)
    // 2. Filter out messages with deletion placeholder content (delete for everyone)
    // 3. Filter out location messages (for privacy/security)
    final messages = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE dm.message_id IS NULL
        AND m.content NOT LIKE 'This message was deleted%'
        AND m.content NOT LIKE '%deleted this message%'
        AND m.content NOT LIKE '{"type":"location"%'
      ORDER BY m.timestamp ASC
    ''', [currentUser.uid]);

    debugPrint('[BackupService] Exported ${messages.length} messages (excluded deleted messages)');
    return messages;
  }

  /// Export Signal Protocol state from Android SharedPreferences
  Future<Map<String, dynamic>> _exportSignalProtocolState() async {
    try {
      debugPrint('[BackupService] Exporting Signal Protocol state via MethodChannel...');

      const platform = MethodChannel('com.zarq/signal');
      final String signalStateJson = await platform.invokeMethod('exportSignalState');

      debugPrint('[BackupService] Signal Protocol state exported successfully');

      return {
        'data': signalStateJson,
        'exported_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('[BackupService] Error exporting Signal state: $e');
      debugPrint('[BackupService] WARNING: Backup will not include Signal sessions');
      debugPrint('[BackupService] Sessions will need to be re-established after restore');
      return {
        'error': e.toString(),
        'exported_at': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Collect attachments from storage with optional date filter
  Future<List<BackupAttachment>> _collectAttachments({
    required List<Map<String, dynamic>> messages,
    int? excludeOlderThanDays,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final userUid = currentUser.uid;
    final dir = await getApplicationDocumentsDirectory();
    final List<BackupAttachment> attachments = [];

    // Calculate cutoff timestamp if filter is enabled
    final cutoffTimestamp = excludeOlderThanDays != null
        ? DateTime.now().subtract(Duration(days: excludeOlderThanDays)).millisecondsSinceEpoch
        : null;

    for (final messageData in messages) {
      final hasAttachment = messageData['has_attachment'] == 1;
      if (!hasAttachment) continue;

      final attachmentId = messageData['attachment_id'] as int?;
      final attachmentType = messageData['attachment_type'] as String?;
      final iv = messageData['media_encryption_iv'] as String?;
      final timestampStr = messageData['timestamp'] as String?;

      // Try NEW E2EE fields first (for sent messages)
      String? encryptedMediaKey = messageData['encrypted_media_key'] as String?;
      String? encryptionType = messageData['media_encryption_type'] as String?;
      String? recipientUid = messageData['media_recipient_uid'] as String?;
      int? recipientDeviceId = messageData['media_recipient_device_id'] as int?;
      String? groupId = messageData['media_group_id'] as String?;
      String? senderUid = messageData['media_sender_uid'] as String?;
      int? senderDeviceId = messageData['media_sender_device_id'] as int?;

      // FALLBACK: For received messages, use media_encryption_key (WhatsApp approach)
      if (encryptedMediaKey == null) {
        encryptedMediaKey = messageData['media_encryption_key'] as String?;
        encryptionType = 'signal'; // Default for received messages
        debugPrint('[BackupService] Using fallback media_encryption_key for received message');
      }

      debugPrint('[BackupService] Processing attachment $attachmentId ($attachmentType)');

      // Skip if missing required data
      if (attachmentId == null || attachmentType == null || encryptedMediaKey == null || iv == null) {
        debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - missing metadata');
        debugPrint('[BackupService]   has_id: ${attachmentId != null}, has_type: ${attachmentType != null}, '
            'has_encrypted_key: ${encryptedMediaKey != null}, has_iv: ${iv != null}');
        continue;
      }

      debugPrint('[BackupService] ✅ Attachment $attachmentId - encryption type: $encryptionType');

      // Parse timestamp and skip old media if filter is enabled
      if (cutoffTimestamp != null && timestampStr != null) {
        try {
          final messageTimestamp = DateTime.parse(timestampStr).millisecondsSinceEpoch;
          if (messageTimestamp < cutoffTimestamp) {
            debugPrint('[BackupService] Skipping old attachment: $attachmentId (age filter)');
            continue;
          }
        } catch (e) {
          debugPrint('[BackupService] Error parsing timestamp for attachment $attachmentId: $e');
        }
      }

      // Determine storage path based on attachment type
      String storagePath;
      String extension;

      if (attachmentType == 'image') {
        final imagePath = path.join(dir.path, 'images', userUid, 'attachment_$attachmentId.jpg');
        if (!await File(imagePath).exists()) {
          debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - file not found: $imagePath');
          continue;
        }
        storagePath = imagePath;
        extension = '.jpg';
      } else if (attachmentType == 'video') {
        final videoPath = path.join(dir.path, 'videos', userUid, 'attachment_$attachmentId.mp4');
        if (!await File(videoPath).exists()) {
          debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - file not found: $videoPath');
          continue;
        }
        storagePath = videoPath;
        extension = '.mp4';
      } else if (attachmentType == 'audio') {
        final audioPath = path.join(dir.path, 'audios', userUid, 'attachment_$attachmentId.aac');
        if (!await File(audioPath).exists()) {
          debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - file not found: $audioPath');
          continue;
        }
        storagePath = audioPath;
        extension = '.aac';
      } else if (attachmentType == 'document') {
        // Documents can have various extensions, try common ones
        final docDir = Directory(path.join(dir.path, 'documents', userUid));
        if (!await docDir.exists()) {
          debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - directory not found: ${docDir.path}');
          continue;
        }

        final docFiles = await docDir.list().where((f) => f.path.contains('attachment_$attachmentId')).toList();
        if (docFiles.isEmpty) {
          debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - no document files found in ${docDir.path}');
          continue;
        }

        storagePath = docFiles.first.path;
        extension = path.extension(storagePath);
      } else {
        debugPrint('[BackupService] ⚠️ Skipping attachment $attachmentId - unknown type: $attachmentType');
        continue;
      }

      // Read encrypted file data
      final file = File(storagePath);
      final encryptedBytes = await file.readAsBytes();
      final encryptedDataBase64 = base64.encode(encryptedBytes);

      attachments.add(BackupAttachment(
        attachmentId: attachmentId,
        type: attachmentType,
        extension: extension,
        encryptedDataBase64: encryptedDataBase64,
        encryptedAesKey: encryptedMediaKey, // Store ENCRYPTED AES key
        encryptionIv: iv,
        encryptionType: encryptionType ?? 'signal', // Default to signal if null
        recipientUid: recipientUid,
        recipientDeviceId: recipientDeviceId,
        groupId: groupId,
        senderUid: senderUid,
        senderDeviceId: senderDeviceId,
      ));

      debugPrint('[BackupService] ✅ Added attachment: $attachmentId ($attachmentType) - type: $encryptionType');
    }

    return attachments;
  }

  // ================== ENCRYPTION ==================

  /// Derive encryption key from passphrase using PBKDF2
  Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, pbkdf2Iterations, aesKeySize));

    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Encrypt backup data with AES-256-GCM (runs in background isolate)
  Future<File> encryptBackup(BackupData backupData, String passphrase) async {
    try {
      debugPrint('[BackupService] Starting backup encryption in background...');

      // Run heavy encryption work in background isolate to prevent UI freeze
      final encryptedData = await compute(_encryptBackupInIsolate, {
        'backupData': backupData.toJson(),
        'passphrase': passphrase,
      });

      // Save to temporary file (fast operation, safe on main thread)
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encryptedFile = File(path.join(tempDir.path, 'zarq_backup_$timestamp.encrypted'));
      await encryptedFile.writeAsBytes(encryptedData);

      debugPrint('[BackupService] Backup encrypted successfully: ${encryptedFile.path}');
      return encryptedFile;
    } catch (e) {
      debugPrint('[BackupService] Encryption error: $e');
      rethrow;
    }
  }

  /// Static method for isolate - encrypts backup data
  static Uint8List _encryptBackupInIsolate(Map<String, dynamic> params) {
    try {
      final backupDataJson = params['backupData'] as Map<String, dynamic>;
      final passphrase = params['passphrase'] as String;

      // Convert backup data to JSON
      final jsonString = jsonEncode(backupDataJson);
      final plaintext = Uint8List.fromList(utf8.encode(jsonString));

      // Generate random salt and nonce
      final random = SecureRandom('Fortuna')
        ..seed(KeyParameter(Uint8List.fromList(
            List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256))));
      final salt = random.nextBytes(32);
      final nonce = random.nextBytes(nonceSize);

      // Derive encryption key from passphrase
      final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, pbkdf2Iterations, aesKeySize));
      final key = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));

      // Encrypt with AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(key), authTagSize * 8, nonce, Uint8List(0)),
        );

      final ciphertext = cipher.process(plaintext);

      // Combine: salt (32) + nonce (12) + ciphertext + authTag (16)
      return Uint8List.fromList([...salt, ...nonce, ...ciphertext]);
    } catch (e) {
      throw Exception('Encryption failed in isolate: $e');
    }
  }

  /// Decrypt backup data with AES-256-GCM (runs in background isolate)
  Future<BackupData> decryptBackup(File encryptedFile, String passphrase) async {
    bool decryptionComplete = false;
    try {
      debugPrint('[BackupService] Starting backup decryption in background...');

      // Read encrypted data (fast operation)
      final encryptedData = await encryptedFile.readAsBytes();

      // Start periodic notification updates to keep it alive during decryption
      int notificationProgress = 26;
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (decryptionComplete) {
          timer.cancel();
          return;
        }
        notificationProgress = (notificationProgress + 1).clamp(26, 34);
        BackupNotificationService.showProgressNotification(
          'Decrypting backup...',
          notificationProgress,
        );
      });

      // Run heavy decryption work in background isolate to prevent UI freeze
      final jsonData = await compute(_decryptBackupInIsolate, {
        'encryptedData': encryptedData,
        'passphrase': passphrase,
      });

      decryptionComplete = true; // Stop the periodic updates

      final backupData = BackupData.fromJson(jsonData);
      debugPrint('[BackupService] Backup decrypted successfully');

      return backupData;
    } catch (e) {
      decryptionComplete = true; // CRITICAL: Stop timer on error
      debugPrint('[BackupService] Decryption error: $e');
      throw Exception('Failed to decrypt backup. Incorrect passphrase or corrupted file.');
    }
  }

  /// Static method for isolate - decrypts backup data
  static Map<String, dynamic> _decryptBackupInIsolate(Map<String, dynamic> params) {
    try {
      final encryptedData = params['encryptedData'] as Uint8List;
      final passphrase = params['passphrase'] as String;

      // Extract components
      final salt = encryptedData.sublist(0, 32);
      final nonce = encryptedData.sublist(32, 32 + nonceSize);
      final ciphertext = encryptedData.sublist(32 + nonceSize);

      // Derive decryption key
      final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, pbkdf2Iterations, aesKeySize));
      final key = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));

      // Decrypt with AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), authTagSize * 8, nonce, Uint8List(0)),
        );

      final plaintext = cipher.process(ciphertext);

      // Parse JSON
      final jsonString = utf8.decode(plaintext);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Decryption failed in isolate: $e');
    }
  }

  // ================== RESTORE ==================

  /// Restore backup data to database and storage
  Future<void> restoreBackup(BackupData backupData) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      debugPrint('[BackupService] Starting restore...');

      // Show START notification with sound
      await BackupNotificationService.showStartNotification('Restore');

      // 1. Close and delete existing database (to avoid encryption key mismatch)
      debugPrint('[BackupService] Closing current database...');
      await _dbService.close();

      // Delete the old database file (encrypted with wrong key)
      final dbPath = await getDatabasesPath();
      final userUid = currentUser.uid;
      final dbFile = File(path.join(dbPath, 'zarq_messages_$userUid.db'));
      if (await dbFile.exists()) {
        await dbFile.delete();
        debugPrint('[BackupService] Deleted old database file');
      }

      // 2. Restore Signal Protocol state (CHANGES identity key!)
      await _restoreSignalProtocolState(backupData.signalProtocolState);
      debugPrint('[BackupService] Signal Protocol state restored successfully');

      // 3. Reinitialize database with RESTORED identity key
      debugPrint('[BackupService] Reinitializing database with restored identity key...');
      await _dbService.init();
      debugPrint('[BackupService] Database reinitialized successfully');

      // 4. Restore messages (conversations derived automatically)
      await _restoreMessages(backupData.messages);
      debugPrint('[BackupService] Restored ${backupData.messages.length} messages');

      // 3. Restore attachments to storage
      await _restoreAttachments(backupData.attachments);
      debugPrint('[BackupService] Restored ${backupData.attachments.length} attachments');

      // 5. Set flag for device re-registration after app restart
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('needs_device_reregistration', true);
      debugPrint('[BackupService] ✅ Set flag for device re-registration after restore');

      debugPrint('[BackupService] Restore completed successfully');
    } catch (e) {
      debugPrint('[BackupService] Restore error: $e');
      rethrow;
    }
  }

  /// Restore Signal Protocol state via MethodChannel
  Future<void> _restoreSignalProtocolState(Map<String, dynamic> state) async {
    try {
      // Check if state contains actual data
      if (!state.containsKey('data') || state['data'] == null) {
        debugPrint('[BackupService] No Signal Protocol state data in backup');
        debugPrint('[BackupService] Sessions will be re-established when messaging');
        return;
      }

      final signalStateJson = state['data'] as String;

      debugPrint('[BackupService] Restoring Signal Protocol state via MethodChannel...');

      const platform = MethodChannel('com.zarq/signal');
      final bool success = await platform.invokeMethod('importSignalState', {
        'signalState': signalStateJson,
      });

      if (success) {
        debugPrint('[BackupService] ✅ Signal Protocol state restored successfully');
        debugPrint('[BackupService] All sessions, keys, and prekeys restored');

        // Verify restoration by comparing exported state
        await Future.delayed(const Duration(milliseconds: 100)); // Give time for import to settle
        final verifyExport = await platform.invokeMethod('exportSignalState');
        final originalLength = signalStateJson.length;
        final restoredLength = (verifyExport as String).length;
        debugPrint('[BackupService] VERIFICATION: Original size: $originalLength, Restored size: $restoredLength');
        debugPrint('[BackupService] Data integrity: ${originalLength == restoredLength ? '✅ MATCH' : '⚠️ MISMATCH'}');
      } else {
        debugPrint('[BackupService] ❌ Failed to restore Signal Protocol state');
      }
    } catch (e) {
      debugPrint('[BackupService] Error restoring Signal state: $e');
      debugPrint('[BackupService] Sessions will be re-established when messaging');
    }
  }

  /// Restore messages (optimized with batch insert)
  Future<void> _restoreMessages(List<Map<String, dynamic>> messages) async {
    final db = _dbService.database;

    debugPrint('[BackupService] Restoring ${messages.length} messages to database');

    // Clear existing messages first (fresh restore)
    await db.delete('messages');
    debugPrint('[BackupService] Cleared existing messages');

    // Use batch insert for performance (100x faster than one-by-one)
    final batch = db.batch();
    int batchCount = 0;
    const batchSize = 100; // Insert in chunks of 100

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];

      batch.insert(
        'messages',
        message,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batchCount++;

      // Commit batch every 100 messages or at the end
      if (batchCount >= batchSize || i == messages.length - 1) {
        await batch.commit(noResult: true);
        debugPrint('[BackupService] Inserted batch of $batchCount messages (${i + 1}/${messages.length})');

        // CRITICAL: Update notification to keep it alive during long restore
        final progress = 40 + ((i + 1) / messages.length * 8).toInt(); // 40-48%
        await BackupNotificationService.showProgressNotification(
          'Restoring messages (${i + 1}/${messages.length})',
          progress,
        );

        batchCount = 0;
      }
    }

    debugPrint('[BackupService] Successfully inserted ${messages.length} messages');

    // Verify insertion
    final count = await db.rawQuery('SELECT COUNT(*) as count FROM messages');
    final messageCount = count.first['count'] as int;
    debugPrint('[BackupService] Database now contains $messageCount messages');

    // Verify encryption keys for attachments
    final attachmentMessages = await db.query(
      'messages',
      where: 'has_attachment = ?',
      whereArgs: [1],
    );
    debugPrint('[BackupService] Verifying ${attachmentMessages.length} messages with attachments:');
    for (final msg in attachmentMessages) {
      final hasEncryptedKey = msg['encrypted_media_key'] != null;
      final hasEncryptionType = msg['media_encryption_type'] != null;
      debugPrint('  Message ${msg['id']}: '
          'attachment_id=${msg['attachment_id']}, '
          'has_encrypted_key=$hasEncryptedKey, '
          'encryption_type=${msg['media_encryption_type']}, '
          'has_iv=${msg['media_encryption_iv'] != null}, '
          'status=${hasEncryptedKey && hasEncryptionType ? '✅' : '❌'}');
    }
  }

  /// Restore attachments to storage
  Future<void> _restoreAttachments(List<BackupAttachment> attachments) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userUid = currentUser.uid;
    int skippedCount = 0;
    int restoredCount = 0;

    for (final attachment in attachments) {
      try {
        // Determine storage path - Use EXTERNAL storage (WhatsApp approach)
        String storagePath;
        Directory storageDir;

        if (attachment.type == 'image') {
          storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Images/$userUid');
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.jpg');
        } else if (attachment.type == 'video') {
          storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Videos/$userUid');
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.mp4');
        } else if (attachment.type == 'audio') {
          storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Audio/$userUid');
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.aac');
        } else if (attachment.type == 'document') {
          storageDir = Directory('/storage/emulated/0/Android/media/com.zarq.messenger/Media/Documents/$userUid');
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}${attachment.extension}');
        } else {
          continue;
        }

        final file = File(storagePath);

        // WhatsApp approach: Skip if file already exists (avoids duplication & saves bandwidth)
        if (await file.exists()) {
          skippedCount++;
          debugPrint('[BackupService] ⏭️ Media already exists, skipping: ${attachment.attachmentId}');
          continue;
        }

        // File doesn't exist, restore it from backup
        final encryptedBytes = base64.decode(attachment.encryptedDataBase64);

        // Create directory if needed
        if (!await storageDir.exists()) {
          await storageDir.create(recursive: true);
        }

        // Write encrypted file to EXTERNAL storage (persists after uninstall)
        await file.writeAsBytes(encryptedBytes);
        restoredCount++;

        debugPrint('[BackupService] ✅ Restored attachment to external storage: ${attachment.attachmentId}');
      } catch (e) {
        debugPrint('[BackupService] ❌ Error restoring attachment ${attachment.attachmentId}: $e');
      }
    }

    debugPrint('[BackupService] 📊 Media restore summary: $restoredCount restored, $skippedCount skipped (already exist)');
  }

  // ================== UTILITY ==================

  /// Calculate backup size in bytes
  Future<int> calculateBackupSize(BackupData backupData) async {
    final jsonString = jsonEncode(backupData.toJson());
    return utf8.encode(jsonString).length;
  }

  /// Format bytes to human-readable size
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ================== GOOGLE DRIVE INTEGRATION ==================

  /// Drive API scopes
  /// Using drive.file scope (recommended by Google) which provides access to:
  /// - Files created by this app
  /// - Files explicitly selected/shared by user via Picker API
  ///
  /// Note: Manual file uploads to app folders are NOT visible with this scope.
  /// Users must use the "Import Backup File" feature (Picker API) to grant access.
  static const List<String> _driveScopes = <String>[
    drive.DriveApi.driveFileScope,
    'https://www.googleapis.com/auth/drive.file',
  ];

  GoogleSignIn? _googleSignInInstance;
  GoogleSignInAccount? _cachedAccount;
  drive.DriveApi? _cachedDriveApi; // Cache DriveApi instance to avoid repeated authentication

  /// Get authenticated Google Drive API client with persistent scopes
  /// Uses cached instance to avoid repeated authentication
  Future<drive.DriveApi?> getDriveApi() async {
    try {
      // Return cached instance if available (no authentication needed)
      if (_cachedDriveApi != null) {
        debugPrint('[BackupService] ✅ Using cached Drive API instance (no authentication needed)');
        return _cachedDriveApi;
      }

      debugPrint('[BackupService] Authenticating with Google Drive...');

      // Initialize GoogleSignIn instance if not already done
      _googleSignInInstance ??= GoogleSignIn.instance;

      // Initialize
      await _googleSignInInstance!.initialize();

      // Try lightweight authentication first (if user already signed in before)
      debugPrint('[BackupService] Attempting lightweight authentication...');
      var account = await _googleSignInInstance!.attemptLightweightAuthentication();

      // If lightweight auth failed, do full authentication
      if (account == null) {
        debugPrint('[BackupService] Lightweight auth failed, showing account picker...');
        account = await _googleSignInInstance!.authenticate();
      }

      if (account == null) {
        debugPrint('[BackupService] User cancelled sign-in');
        return null;
      }

      _cachedAccount = account;
      debugPrint('[BackupService] Signed in as: ${account.email}');

      // Get authorization for Drive scopes (automatically persisted by GoogleSignIn)
      debugPrint('[BackupService] Checking authorization for Drive scopes...');
      var authorization = await account.authorizationClient.authorizationForScopes(_driveScopes);

      // If no existing authorization, explicitly authorize scopes
      // This will prompt user once, then persist for future app launches
      if (authorization == null) {
        debugPrint('[BackupService] No existing authorization, requesting Drive permissions from user...');
        authorization = await account.authorizationClient.authorizeScopes(_driveScopes);

        if (authorization == null) {
          debugPrint('[BackupService] ❌ User denied Drive API permissions or authorization failed');
          return null;
        }

        debugPrint('[BackupService] ✅ Drive API scopes authorized and persisted');
      } else {
        debugPrint('[BackupService] ✅ Using existing Drive API authorization (persisted)');
      }

      // Get authenticated HTTP client using extension
      final authClient = authorization.authClient(scopes: _driveScopes);

      debugPrint('[BackupService] ✅ Got authenticated client');

      // Create Drive API instance and cache it for future use
      _cachedDriveApi = drive.DriveApi(authClient);
      debugPrint('[BackupService] ✅ Google Drive API authenticated and cached successfully');

      return _cachedDriveApi;
    } catch (e, stackTrace) {
      debugPrint('[BackupService] ❌ Error getting Drive API: $e');
      debugPrint('[BackupService] Stack trace: $stackTrace');

      // Clear cache on error (token might be expired)
      _clearDriveCache();

      return null;
    }
  }

  /// Clear cached Drive API instance (called on sign out or authentication errors)
  void _clearDriveCache() {
    _cachedDriveApi = null;
    debugPrint('[BackupService] Cleared Drive API cache');
  }

  /// Execute Drive API operation with automatic retry on authentication errors
  /// Clears cache and retries once if 401 Unauthorized error occurs
  Future<T?> _executeDriveOperation<T>(
    Future<T> Function(drive.DriveApi driveApi) operation, {
    String operationName = 'Drive operation',
  }) async {
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) {
        debugPrint('[BackupService] ❌ $operationName failed: No DriveApi available');
        return null;
      }

      return await operation(driveApi);
    } catch (e) {
      // Check if it's an authentication error (401 Unauthorized)
      if (e.toString().contains('401') || e.toString().toLowerCase().contains('unauthorized')) {
        debugPrint('[BackupService] ⚠️ $operationName failed with auth error, clearing cache and retrying...');
        _clearDriveCache();

        // Retry once with fresh authentication
        try {
          final driveApi = await getDriveApi();
          if (driveApi == null) {
            debugPrint('[BackupService] ❌ $operationName retry failed: No DriveApi available');
            return null;
          }

          return await operation(driveApi);
        } catch (retryError) {
          debugPrint('[BackupService] ❌ $operationName retry failed: $retryError');
          rethrow;
        }
      }

      // Not an auth error, rethrow
      rethrow;
    }
  }

  /// Sign out from Google Drive
  Future<void> signOutFromGoogleDrive() async {
    try {
      if (_googleSignInInstance != null) {
        await _googleSignInInstance!.disconnect();
        _cachedAccount = null;
        _clearDriveCache(); // Clear cached DriveApi instance
        debugPrint('[BackupService] Signed out from Google Drive');
      }
    } catch (e) {
      debugPrint('[BackupService] Error signing out from Google Drive: $e');
    }
  }

  /// Check if user is signed in to Google Drive
  /// Returns true if account is authenticated, even if Drive scopes need to be re-authorized
  Future<bool> isSignedInToGoogleDrive() async {
    try {
      // Return cached state immediately if available
      if (_cachedAccount != null) {
        debugPrint('[BackupService] User is signed in (cached): ${_cachedAccount!.email}');
        return true; // Account exists, consider signed in
      }

      // Initialize GoogleSignIn instance if not already done
      _googleSignInInstance ??= GoogleSignIn.instance;
      await _googleSignInInstance!.initialize();

      // Check if user is already signed in (persisted authentication)
      final account = await _googleSignInInstance!.attemptLightweightAuthentication();

      if (account != null) {
        _cachedAccount = account; // Update cache
        debugPrint('[BackupService] User is signed in: ${account.email}');
        return true; // Account exists, consider signed in (scopes will be requested when needed)
      }

      debugPrint('[BackupService] User is not signed in');
      return false;
    } catch (e) {
      debugPrint('[BackupService] Error checking Google Drive sign-in status: $e');
      return false;
    }
  }

  /// Get current Google Drive account email (instant response from cache)
  Future<String?> getGoogleDriveAccountEmail() async {
    try {
      // Return cached email immediately if available
      if (_cachedAccount != null) {
        return _cachedAccount!.email;
      }

      // Initialize GoogleSignIn instance if not already done
      _googleSignInInstance ??= GoogleSignIn.instance;
      await _googleSignInInstance!.initialize();

      // Get current signed in account (persisted authentication)
      final account = await _googleSignInInstance!.attemptLightweightAuthentication();

      if (account != null) {
        _cachedAccount = account; // Update cache
        return account.email;
      }

      return null;
    } catch (e) {
      debugPrint('[BackupService] Error getting Google Drive account email: $e');
      return null;
    }
  }

  /// Upload encrypted backup to Google Drive
  Future<String?> uploadToGoogleDrive(File encryptedBackup) async {
    try {
      debugPrint('[BackupService] Uploading backup to Google Drive...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // Check for existing backup folder
      final folderName = 'Zarq Messenger Backups';
      String? folderId = await _findOrCreateFolder(driveApi, folderName);

      if (folderId == null) {
        throw Exception('Failed to create backup folder');
      }

      // Create backup file metadata
      final fileName = 'zarq_backup_${DateTime.now().millisecondsSinceEpoch}.encrypted';
      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..description = 'Zarq Messenger E2EE Backup';

      // Upload file
      final fileStream = encryptedBackup.openRead();
      final media = drive.Media(fileStream, encryptedBackup.lengthSync());

      final uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      debugPrint('[BackupService] Backup uploaded successfully: ${uploadedFile.id}');
      return uploadedFile.id;
    } catch (e) {
      debugPrint('[BackupService] Error uploading to Google Drive: $e');
      rethrow;
    }
  }

  /// Find or create backup folder in Google Drive
  Future<String?> _findOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
    try {
      // Search for existing folder
      final query = "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        return fileList.files!.first.id;
      }

      // Create new folder
      final folderMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final folder = await driveApi.files.create(folderMetadata);
      return folder.id;
    } catch (e) {
      debugPrint('[BackupService] Error finding/creating folder: $e');
      return null;
    }
  }

  /// Import a backup file from Google Drive using file picker
  /// This allows users to explicitly select backup files they want to import
  /// Works with drive.file scope (no verification needed)
  Future<String?> importBackupFileFromGoogleDrive() async {
    try {
      debugPrint('[BackupService] Opening Google Drive file picker...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // For Flutter, we'll use a simpler approach:
      // List all .encrypted files in user's Drive and let them choose
      debugPrint('[BackupService] Searching for .encrypted files in Drive...');

      // Search for .encrypted files across entire Drive
      final query = "name contains '.encrypted' and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        pageSize: 100,
        orderBy: 'modifiedTime desc',
        $fields: 'files(id, name, createdTime, modifiedTime, size)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        debugPrint('[BackupService] No .encrypted files found in Drive');
        return null;
      }

      // Filter to only .encrypted files (since 'contains' does prefix matching)
      final encryptedFiles = fileList.files!
          .where((file) => file.name != null && file.name!.endsWith('.encrypted'))
          .toList();

      if (encryptedFiles.isEmpty) {
        debugPrint('[BackupService] No .encrypted files found after filtering');
        return null;
      }

      debugPrint('[BackupService] Found ${encryptedFiles.length} .encrypted files');

      // Return the file list for UI to display and let user choose
      // The UI will call this method and handle selection
      return 'files_available'; // Signal to UI to show file list

    } catch (e) {
      debugPrint('[BackupService] Error opening file picker: $e');
      return null;
    }
  }

  /// List contents of a specific folder in Google Drive
  /// Returns both folders and .encrypted files for navigation
  Future<List<drive.File>> listDriveFolderContents(String folderId) async {
    try {
      debugPrint('[BackupService] Listing contents of folder: $folderId');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // List all items in the folder
      final query = "'$folderId' in parents and trashed=false";
      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        pageSize: 100,
        orderBy: 'name',
        $fields: 'files(id, name, createdTime, modifiedTime, size, mimeType)',
      );

      if (fileList.files == null) {
        return [];
      }

      // Filter to show only folders and .encrypted files
      final items = fileList.files!.where((file) {
        final isFolder = file.mimeType == 'application/vnd.google-apps.folder';
        final isEncrypted = file.name != null && file.name!.endsWith('.encrypted');
        return isFolder || isEncrypted;
      }).toList();

      debugPrint('[BackupService] Found ${items.length} items (folders + .encrypted files)');
      return items;

    } catch (e) {
      debugPrint('[BackupService] Error listing folder contents: $e');
      return [];
    }
  }

  /// Get the root "Zarq Messenger Backups" folder or search from Drive root
  Future<String?> getRootBackupFolderId() async {
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) {
        return null;
      }

      // Try to find "Zarq Messenger Backups" folder
      final rootFolderQuery = "name='Zarq Messenger Backups' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final rootFolderList = await driveApi.files.list(
        q: rootFolderQuery,
        spaces: 'drive',
        $fields: 'files(id)',
      );

      if (rootFolderList.files != null && rootFolderList.files!.isNotEmpty) {
        return rootFolderList.files!.first.id;
      }

      return null; // No root folder found, will use Drive root
    } catch (e) {
      debugPrint('[BackupService] Error getting root folder: $e');
      return null;
    }
  }

  /// List all backup folders from Google Drive
  Future<List<drive.File>> listBackupsFromGoogleDrive() async {
    try {
      debugPrint('[BackupService] Listing backups from Google Drive...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // DIAGNOSTIC: Get current user's email to verify account
      try {
        final about = await driveApi.about.get($fields: 'user');
        debugPrint('[BackupService] 👤 Signed in as: ${about.user?.emailAddress}');
      } catch (e) {
        debugPrint('[BackupService] ⚠️ Could not get user info: $e');
      }

      // Find root backup folder
      final rootFolderName = 'Zarq Messenger Backups';
      final rootFolderQuery = "name='$rootFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final rootFolderList = await driveApi.files.list(
        q: rootFolderQuery,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      debugPrint('[BackupService] 📂 Found ${rootFolderList.files?.length ?? 0} folders named "$rootFolderName"');

      if (rootFolderList.files == null || rootFolderList.files!.isEmpty) {
        debugPrint('[BackupService] No root backup folder found');
        return [];
      }

      final rootFolderId = rootFolderList.files!.first.id;
      debugPrint('[BackupService] 📂 Using root folder ID: $rootFolderId');

      // List all backup folders (Backup_timestamp) created by the app
      // These are folders created through the app's backup feature
      // Exclude any manual/system folders by filtering for Backup_ prefix
      final backupFolderQuery = "'$rootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final backupFolderList = await driveApi.files.list(
        q: backupFolderQuery,
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, createdTime, modifiedTime)',
      );

      // Filter out any folders that don't match the app's backup naming pattern
      // App backups are named "Backup_timestamp"
      final appBackups = (backupFolderList.files ?? [])
          .where((folder) => folder.name != null && folder.name!.startsWith('Backup_'))
          .toList();

      debugPrint('[BackupService] Found ${backupFolderList.files?.length ?? 0} total folders, ${appBackups.length} are app-created backups');

      // Note: Manual backup imports are now handled through the "Import Backup File" feature
      // which uses searchBackupFilesInDrive() to let users select files from anywhere in Drive

      return appBackups;
    } catch (e) {
      debugPrint('[BackupService] Error listing backups: $e');
      return [];
    }
  }

  /// Download backup from Google Drive
  Future<File?> downloadFromGoogleDrive(String fileId) async {
    try {
      debugPrint('[BackupService] Downloading backup from Google Drive...');

      // Keep notification alive during authentication (can take 5-10 seconds)
      await BackupNotificationService.showProgressNotification('Authenticating with Google Drive...', 12);

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // Update notification after authentication
      await BackupNotificationService.showProgressNotification('Starting download...', 15);

      // Download file
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'zarq_restore_$fileId.encrypted'));

      // Use pipe to properly handle the stream
      final sink = tempFile.openWrite();
      try {
        await media.stream.pipe(sink);
      } catch (e) {
        debugPrint('[BackupService] Error piping stream: $e');
        rethrow;
      } finally {
        await sink.close();
      }

      debugPrint('[BackupService] Backup downloaded: ${tempFile.path}');
      return tempFile;
    } catch (e) {
      debugPrint('[BackupService] Error downloading from Google Drive: $e');
      return null;
    }
  }

  /// Delete backup from Google Drive
  Future<bool> deleteFromGoogleDrive(String fileId) async {
    try {
      debugPrint('[BackupService] Deleting backup from Google Drive...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      await driveApi.files.delete(fileId);
      debugPrint('[BackupService] Backup deleted successfully');
      return true;
    } catch (e) {
      debugPrint('[BackupService] Error deleting backup: $e');
      return false;
    }
  }

  /// Get backup info from Google Drive
  Future<Map<String, dynamic>?> getBackupInfo(String fileId) async {
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) return null;

      final file = await driveApi.files.get(
        fileId,
        $fields: 'id, name, size, createdTime, modifiedTime',
      ) as drive.File;

      return {
        'id': file.id,
        'name': file.name,
        'size': file.size,
        'createdTime': file.createdTime?.toIso8601String(),
        'modifiedTime': file.modifiedTime?.toIso8601String(),
      };
    } catch (e) {
      debugPrint('[BackupService] Error getting backup info: $e');
      return null;
    }
  }

  // ================== AUTO-BACKUP SETTINGS ==================

  static const String _autoBackupSettingsKey = 'auto_backup_settings';

  /// Get auto-backup settings (with passphrase loaded from secure storage)
  Future<AutoBackupSettings> getAutoBackupSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_autoBackupSettingsKey);

      if (jsonString == null) {
        return AutoBackupSettings(); // Return default settings
      }

      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Load passphrase from secure storage (NOT from SharedPreferences)
      final secureStorage = SecureStorageService();
      final passphrase = await secureStorage.getAutoBackupPassphrase();

      return AutoBackupSettings.fromJson(jsonData, passphrase: passphrase);
    } catch (e) {
      debugPrint('[BackupService] Error loading auto-backup settings: $e');
      return AutoBackupSettings();
    }
  }

  /// Save auto-backup settings (with passphrase saved to secure storage)
  Future<void> saveAutoBackupSettings(AutoBackupSettings settings) async {
    try {
      // Save passphrase to secure storage (NOT to SharedPreferences)
      if (settings.lastBackupPassphrase != null) {
        final secureStorage = SecureStorageService();
        await secureStorage.saveAutoBackupPassphrase(settings.lastBackupPassphrase!);
        debugPrint('[BackupService] Auto-backup passphrase saved to secure storage');
      }

      // Save other settings to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(settings.toJson());
      await prefs.setString(_autoBackupSettingsKey, jsonString);
      debugPrint('[BackupService] Auto-backup settings saved');
    } catch (e) {
      debugPrint('[BackupService] Error saving auto-backup settings: $e');
      rethrow;
    }
  }

  /// Update last backup time
  Future<void> updateLastBackupTime(DateTime time) async {
    try {
      final settings = await getAutoBackupSettings();
      final updatedSettings = settings.copyWith(lastBackupTime: time);
      await saveAutoBackupSettings(updatedSettings);
    } catch (e) {
      debugPrint('[BackupService] Error updating last backup time: $e');
    }
  }

  /// Check if backup is due based on frequency
  bool isBackupDue(AutoBackupSettings settings) {
    if (!settings.enabled || settings.lastBackupTime == null) {
      return settings.enabled; // If enabled but never backed up, it's due
    }

    final now = DateTime.now();
    final lastBackup = settings.lastBackupTime!;
    final difference = now.difference(lastBackup);

    switch (settings.frequency) {
      case BackupFrequency.daily:
        return difference.inHours >= 24;
      case BackupFrequency.weekly:
        return difference.inDays >= 7;
      case BackupFrequency.monthly:
        return difference.inDays >= 30;
      case BackupFrequency.disabled:
        return false;
    }
  }

  // ================== GOOGLE DRIVE WITH MEDIA ==================

  /// Create Google Drive backup with separate media upload (WhatsApp approach)
  /// Returns backup folder ID from Google Drive
  Future<String?> createGoogleDriveBackup({
    required String passphrase,
    int? excludeMediaOlderThanDays,
    GoogleDriveMediaProgressCallback? onMediaProgress,
    bool Function()? shouldCancel, // Cancellation checker callback
  }) async {
    try {
      debugPrint('[BackupService] Creating Google Drive backup with media...');

      // 1. Create backup data (messages only, no embedded media)
      debugPrint('[BackupService] Collecting messages...');
      await BackupNotificationService.showProgressNotification('Collecting messages...', 12);

      final backupData = await createLocalBackup(
        includeMedia: false, // Don't embed media in backup file
        excludeMediaOlderThanDays: excludeMediaOlderThanDays,
      );

      // 2. Encrypt backup
      debugPrint('[BackupService] Encrypting backup...');
      await BackupNotificationService.showProgressNotification('Encrypting backup...', 15);

      final encryptedFile = await encryptBackup(backupData, passphrase);

      // Check cancellation after encryption
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled after encryption');
        await encryptedFile.delete(); // Clean up
        throw Exception('Backup cancelled by user');
      }

      // 3. Get root backup folder
      debugPrint('[BackupService] Preparing Google Drive...');
      await BackupNotificationService.showProgressNotification('Preparing Google Drive...', 20);

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // Check cancellation after authentication
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled after authentication');
        await encryptedFile.delete(); // Clean up
        throw Exception('Backup cancelled by user');
      }

      final rootFolderName = 'Zarq Messenger Backups';
      final rootFolderId = await _findOrCreateFolder(driveApi, rootFolderName);
      if (rootFolderId == null) {
        throw Exception('Failed to get root backup folder');
      }

      // 4. Create a new backup-specific folder (Backup_timestamp)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupFolderName = 'Backup_$timestamp';
      final backupFolderMetadata = drive.File()
        ..name = backupFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [rootFolderId];

      final backupFolder = await driveApi.files.create(backupFolderMetadata);
      final backupFolderId = backupFolder.id!;
      debugPrint('[BackupService] Created backup folder: $backupFolderName (ID: $backupFolderId)');

      // Check cancellation after folder creation
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled after folder creation');
        await encryptedFile.delete(); // Clean up
        // TODO: Optionally delete the empty folder
        throw Exception('Backup cancelled by user');
      }

      // 5. Upload encrypted backup file inside backup folder
      debugPrint('[BackupService] Uploading messages backup...');
      await BackupNotificationService.showProgressNotification('Uploading messages backup...', 25);

      final fileMetadata = drive.File()
        ..name = 'backup.encrypted'
        ..parents = [backupFolderId]
        ..description = 'Zarq Messenger E2EE Backup';

      final fileStream = encryptedFile.openRead();
      final media = drive.Media(fileStream, encryptedFile.lengthSync());

      final uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      debugPrint('[BackupService] Backup file uploaded: ${uploadedFile.id}');

      // Check cancellation after message backup upload
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled after message upload');
        await encryptedFile.delete(); // Clean up
        // TODO: Optionally delete the backup folder and uploaded file
        throw Exception('Backup cancelled by user');
      }

      // 6. Starting media upload
      debugPrint('[BackupService] Starting media upload...');
      await BackupNotificationService.showProgressNotification('Preparing media upload...', 28);

      // 6. Upload media files separately (inside backup folder)
      final mediaService = GoogleDriveMediaService(this);
      final messages = await _exportMessages();

      final uploadedMedia = await mediaService.uploadMediaFiles(
        driveApi: driveApi, // CRITICAL: Pass authenticated instance to avoid re-auth hang
        backupFolderId: backupFolderId,
        messages: messages,
        excludeMediaOlderThanDays: excludeMediaOlderThanDays,
        onProgress: onMediaProgress,
        shouldCancel: shouldCancel, // Pass cancellation checker
      );

      debugPrint('[BackupService] Uploaded ${uploadedMedia.length} media files');

      // Check cancellation after media upload
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled after media upload');
        await encryptedFile.delete(); // Clean up
        throw Exception('Backup cancelled by user');
      }

      // 7. Create and upload media manifest (inside backup folder)
      if (uploadedMedia.isNotEmpty) {
        await mediaService.uploadMediaManifest(
          driveApi: driveApi, // CRITICAL: Pass authenticated instance to avoid re-auth hang
          backupFolderId: backupFolderId,
          uploadedFiles: uploadedMedia,
        );
        debugPrint('[BackupService] Media manifest uploaded');

        // Check cancellation after manifest upload
        if (shouldCancel?.call() == true) {
          debugPrint('[BackupService] Backup cancelled after manifest upload');
          await encryptedFile.delete(); // Clean up
          throw Exception('Backup cancelled by user');
        }
      }

      // Clean up temp encrypted file
      await encryptedFile.delete();

      // Final cancellation check before returning success
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Backup cancelled at final stage');
        throw Exception('Backup cancelled by user');
      }

      debugPrint('[BackupService] ✅ Google Drive backup complete (folder: $backupFolderId, media: ${uploadedMedia.length} files)');
      return backupFolderId;
    } catch (e, stackTrace) {
      debugPrint('[BackupService] Error creating Google Drive backup: $e');
      debugPrint('[BackupService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Restore from Google Drive with media download
  Future<void> restoreFromGoogleDrive({
    required String backupFolderId,
    required String passphrase,
    GoogleDriveMediaProgressCallback? onMediaProgress,
    bool Function()? shouldCancel, // Cancellation checker callback
  }) async {
    try {
      debugPrint('[BackupService] Restoring from Google Drive with media...');
      debugPrint('[BackupService] Cancellation callback provided: ${shouldCancel != null}');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // Check cancellation after authentication
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Restore cancelled after authentication');
        throw Exception('Restore cancelled by user');
      }

      // 1. Check if this is a direct .encrypted file or a folder
      final fileInfo = await driveApi.files.get(
        backupFolderId,
        $fields: 'id, name, mimeType',
      ) as drive.File;

      String backupFileId;

      if (fileInfo.mimeType == 'application/vnd.google-apps.folder') {
        // This is a folder (app-created backup) - find backup.encrypted inside
        debugPrint('[BackupService] Detected folder backup, looking for backup.encrypted inside...');
        final backupFileQuery = "'$backupFolderId' in parents and name='backup.encrypted' and trashed=false";
        final backupFileList = await driveApi.files.list(
          q: backupFileQuery,
          spaces: 'drive',
          $fields: 'files(id, name)',
        );

        if (backupFileList.files == null || backupFileList.files!.isEmpty) {
          throw Exception('Backup file not found in folder');
        }

        backupFileId = backupFileList.files!.first.id!;
        debugPrint('[BackupService] Found backup file in folder: $backupFileId');
      } else {
        // This is a direct .encrypted file (manually copied by user)
        debugPrint('[BackupService] Detected direct .encrypted file (manually copied)');
        backupFileId = backupFolderId; // The ID itself is the file ID
      }

      // Check cancellation before download
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Restore cancelled before backup download');
        throw Exception('Restore cancelled by user');
      }

      // 2. Download encrypted backup file
      final encryptedFile = await downloadFromGoogleDrive(backupFileId);
      if (encryptedFile == null) {
        throw Exception('Failed to download backup from Google Drive');
      }

      // Update notification after download
      await BackupNotificationService.showProgressNotification('Backup downloaded', 20);

      // CRITICAL: Check cancellation after download
      final cancelledAfterDownload = shouldCancel?.call() == true;
      debugPrint('[BackupService] Cancellation check after download: $cancelledAfterDownload');
      if (cancelledAfterDownload) {
        debugPrint('[BackupService] ⚠️ Restore cancelled after backup download');
        await encryptedFile.delete(); // Clean up
        throw Exception('Restore cancelled by user');
      }

      // 3. Decrypt backup
      debugPrint('[BackupService] Starting decryption...');
      await BackupNotificationService.showProgressNotification('Decrypting backup...', 25);
      final backupData = await decryptBackup(encryptedFile, passphrase);
      debugPrint('[BackupService] Decryption complete');
      await BackupNotificationService.showProgressNotification('Backup decrypted', 35);

      // CRITICAL: Check cancellation after decryption
      final cancelledAfterDecryption = shouldCancel?.call() == true;
      debugPrint('[BackupService] Cancellation check after decryption: $cancelledAfterDecryption');
      if (cancelledAfterDecryption) {
        debugPrint('[BackupService] ⚠️ Restore cancelled after decryption');
        await encryptedFile.delete(); // Clean up
        throw Exception('Restore cancelled by user');
      }

      // 4. Restore messages and Signal Protocol state
      debugPrint('[BackupService] Starting database restore...');
      await BackupNotificationService.showProgressNotification('Restoring messages...', 40);
      await restoreBackup(backupData);
      debugPrint('[BackupService] Database restore complete');
      await BackupNotificationService.showProgressNotification('Messages restored', 48);

      // CRITICAL: Check cancellation after restore
      final cancelledAfterRestore = shouldCancel?.call() == true;
      debugPrint('[BackupService] Cancellation check after restore: $cancelledAfterRestore');
      if (cancelledAfterRestore) {
        debugPrint('[BackupService] ⚠️ Restore cancelled after message restore');
        await encryptedFile.delete(); // Clean up
        throw Exception('Restore cancelled by user');
      }

      // 5. Download media files from Google Drive (from same backup folder)
      await BackupNotificationService.showProgressNotification('Checking for media files...', 50);
      final mediaService = GoogleDriveMediaService(this);
      final mediaMetadata = await mediaService.downloadMediaManifest(
        driveApi: driveApi, // CRITICAL: Pass authenticated instance to avoid re-auth hang
        backupFolderId: backupFolderId,
      );

      // Check cancellation after manifest download
      if (shouldCancel?.call() == true) {
        debugPrint('[BackupService] Restore cancelled after manifest download');
        await encryptedFile.delete(); // Clean up
        throw Exception('Restore cancelled by user');
      }

      if (mediaMetadata != null && mediaMetadata.isNotEmpty) {
        debugPrint('[BackupService] Found ${mediaMetadata.length} media files to download');
        await BackupNotificationService.showProgressNotification(
          'Found ${mediaMetadata.length} media files',
          52,
        );

        // Download all media files
        await mediaService.downloadMediaFiles(
          driveApi: driveApi, // CRITICAL: Pass authenticated instance to avoid re-auth hang
          mediaMetadata: mediaMetadata,
          onProgress: onMediaProgress,
          shouldCancel: shouldCancel, // Pass cancellation checker
        );

        debugPrint('[BackupService] ✅ Downloaded ${mediaMetadata.length} media files');
        await BackupNotificationService.showProgressNotification('All media downloaded', 95);
      } else {
        debugPrint('[BackupService] No media manifest found or empty');
        await BackupNotificationService.showProgressNotification('No media files to download', 95);
      }

      // Clean up temp encrypted file
      await encryptedFile.delete();

      debugPrint('[BackupService] ✅ Google Drive restore complete');
      await BackupNotificationService.showProgressNotification('Restore complete', 98);
    } catch (e, stackTrace) {
      debugPrint('[BackupService] Error restoring from Google Drive: $e');
      debugPrint('[BackupService] Stack trace: $stackTrace');
      rethrow;
    }
  }
}
