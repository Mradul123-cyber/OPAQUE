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
        'lastBackupPassphrase': lastBackupPassphrase,
      };

  factory AutoBackupSettings.fromJson(Map<String, dynamic> json) => AutoBackupSettings(
        enabled: json['enabled'] as bool? ?? false,
        frequency: BackupFrequency.fromString(json['frequency'] as String? ?? 'disabled'),
        destination: BackupDestination.fromString(json['destination'] as String? ?? 'local'),
        wifiOnly: json['wifiOnly'] as bool? ?? true,
        mediaAgeLimitDays: json['mediaAgeLimitDays'] as int?,
        lastBackupTime: json['lastBackupTime'] != null
            ? DateTime.parse(json['lastBackupTime'] as String)
            : null,
        lastBackupPassphrase: json['lastBackupPassphrase'] as String?,
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

  final DatabaseService _dbService = DatabaseService.instance;

  // ================== LOCAL BACKUP CREATION ==================

  /// Create a complete backup of messages and attachments
  Future<BackupData> createLocalBackup({int? excludeMediaOlderThanDays}) async {
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

      // 1. Export all messages
      final messages = await _exportMessages();
      debugPrint('[BackupService] Exported ${messages.length} messages');

      // 2. Derive conversations from messages (no conversations table)
      final conversations = _deriveConversationsFromMessages(messages);
      debugPrint('[BackupService] Derived ${conversations.length} conversations from messages');

      // 3. Export Signal Protocol state from Android SharedPreferences
      final signalState = await _exportSignalProtocolState();
      debugPrint('[BackupService] Exported Signal Protocol state');

      // 4. Collect attachments (with date filter)
      final attachments = await _collectAttachments(
        messages: messages,
        excludeOlderThanDays: excludeMediaOlderThanDays,
      );
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

  /// Export all messages from database
  Future<List<Map<String, dynamic>>> _exportMessages() async {
    final db = _dbService.database;
    final messages = await db.query('messages', orderBy: 'timestamp ASC');
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

  /// Encrypt backup data with AES-256-GCM
  Future<File> encryptBackup(BackupData backupData, String passphrase) async {
    try {
      debugPrint('[BackupService] Encrypting backup...');

      // Convert backup data to JSON
      final jsonString = jsonEncode(backupData.toJson());
      final plaintext = Uint8List.fromList(utf8.encode(jsonString));

      // Generate random salt and nonce
      final random = SecureRandom('Fortuna')..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256))));
      final salt = random.nextBytes(32);
      final nonce = random.nextBytes(nonceSize);

      // Derive encryption key from passphrase
      final key = _deriveKey(passphrase, salt);

      // Encrypt with AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(key), authTagSize * 8, nonce, Uint8List(0)),
        );

      final ciphertext = cipher.process(plaintext);

      // Combine: salt (32) + nonce (12) + ciphertext + authTag (16)
      final encryptedData = Uint8List.fromList([...salt, ...nonce, ...ciphertext]);

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encryptedFile = File(path.join(tempDir.path, 'zarq_backup_$timestamp.encrypted'));
      await encryptedFile.writeAsBytes(encryptedData);

      debugPrint('[BackupService] Backup encrypted: ${encryptedFile.path}');
      return encryptedFile;
    } catch (e) {
      debugPrint('[BackupService] Encryption error: $e');
      rethrow;
    }
  }

  /// Decrypt backup data with AES-256-GCM
  Future<BackupData> decryptBackup(File encryptedFile, String passphrase) async {
    try {
      debugPrint('[BackupService] Decrypting backup...');

      // Read encrypted data
      final encryptedData = await encryptedFile.readAsBytes();

      // Extract components
      final salt = encryptedData.sublist(0, 32);
      final nonce = encryptedData.sublist(32, 32 + nonceSize);
      final ciphertext = encryptedData.sublist(32 + nonceSize);

      // Derive decryption key
      final key = _deriveKey(passphrase, salt);

      // Decrypt with AES-256-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), authTagSize * 8, nonce, Uint8List(0)),
        );

      final plaintext = cipher.process(ciphertext);

      // Parse JSON
      final jsonString = utf8.decode(plaintext);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      final backupData = BackupData.fromJson(jsonData);
      debugPrint('[BackupService] Backup decrypted successfully');

      return backupData;
    } catch (e) {
      debugPrint('[BackupService] Decryption error: $e');
      throw Exception('Failed to decrypt backup. Incorrect passphrase or corrupted file.');
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

  /// Restore messages
  Future<void> _restoreMessages(List<Map<String, dynamic>> messages) async {
    final db = _dbService.database;

    debugPrint('[BackupService] Restoring ${messages.length} messages to database');

    // Clear existing messages first (fresh restore)
    await db.delete('messages');
    debugPrint('[BackupService] Cleared existing messages');

    // Insert messages one by one to ensure proper persistence
    int successCount = 0;
    for (final message in messages) {
      try {
        // Log encryption metadata for messages with attachments
        if (message['has_attachment'] == 1) {
          final attachmentId = message['attachment_id'];
          final encryptedKey = message['encrypted_media_key'];
          final encryptionType = message['media_encryption_type'];
          final iv = message['media_encryption_iv'];

          debugPrint('[BackupService] ══════ Message ${message['id']} with attachment ══════');
          debugPrint('[BackupService]   attachment_id: $attachmentId');
          debugPrint('[BackupService]   encrypted_key exists: ${encryptedKey != null}');
          debugPrint('[BackupService]   encryption_type: $encryptionType');
          debugPrint('[BackupService]   iv exists: ${iv != null}');
          debugPrint('[BackupService] ══════════════════════════════════════════');
        }

        final result = await db.insert(
          'messages',
          message,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint('[BackupService] Inserted message ID: ${message['id']}, result: $result');
        successCount++;
      } catch (e) {
        debugPrint('[BackupService] Error inserting message ${message['id']}: $e');
      }
    }

    debugPrint('[BackupService] Successfully inserted $successCount/${messages.length} messages');

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
    final dir = await getApplicationDocumentsDirectory();

    for (final attachment in attachments) {
      try {
        final encryptedBytes = base64.decode(attachment.encryptedDataBase64);

        // Determine storage path
        String storagePath;
        Directory storageDir;

        if (attachment.type == 'image') {
          storageDir = Directory(path.join(dir.path, 'images', userUid));
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.jpg');
        } else if (attachment.type == 'video') {
          storageDir = Directory(path.join(dir.path, 'videos', userUid));
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.mp4');
        } else if (attachment.type == 'audio') {
          storageDir = Directory(path.join(dir.path, 'audios', userUid));
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}.aac');
        } else if (attachment.type == 'document') {
          storageDir = Directory(path.join(dir.path, 'documents', userUid));
          storagePath = path.join(storageDir.path, 'attachment_${attachment.attachmentId}${attachment.extension}');
        } else {
          continue;
        }

        // Create directory if needed
        if (!await storageDir.exists()) {
          await storageDir.create(recursive: true);
        }

        // Write encrypted file
        final file = File(storagePath);
        await file.writeAsBytes(encryptedBytes);

        debugPrint('[BackupService] Restored attachment: ${attachment.attachmentId}');
      } catch (e) {
        debugPrint('[BackupService] Error restoring attachment ${attachment.attachmentId}: $e');
      }
    }
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
  static const List<String> _driveScopes = <String>[
    drive.DriveApi.driveFileScope,
    'https://www.googleapis.com/auth/drive.file',
  ];

  GoogleSignIn? _googleSignInInstance;
  GoogleSignInAccount? _cachedAccount;

  /// Get authenticated Google Drive API client
  Future<drive.DriveApi?> getDriveApi() async {
    try {
      debugPrint('[BackupService] Authenticating with Google Drive...');

      // Initialize GoogleSignIn instance if not already done
      _googleSignInInstance ??= GoogleSignIn.instance;

      // Initialize without scopes (v7.x doesn't accept scopes in initialize)
      await _googleSignInInstance!.initialize();

      // Try lightweight authentication first (if user already signed in before)
      // In v7.x, these methods return the account directly, no currentUser property
      var account = await _googleSignInInstance!.attemptLightweightAuthentication();

      // If lightweight auth failed, do full authentication
      account ??= await _googleSignInInstance!.authenticate();

      if (account == null) {
        debugPrint('[BackupService] User cancelled sign-in');
        return null;
      }

      _cachedAccount = account;
      debugPrint('[BackupService] Signed in as: ${account.email}');

      // Request authorization for Drive scopes using v7.x API
      debugPrint('[BackupService] Requesting authorization for Drive scopes...');
      final authorization = await account.authorizationClient.authorizationForScopes(_driveScopes);

      if (authorization == null) {
        debugPrint('[BackupService] ❌ Failed to get authorization for Drive scopes');
        throw Exception('Failed to get authorization for Drive scopes');
      }

      debugPrint('[BackupService] ✅ Got authorization for Drive scopes');

      // Get authenticated HTTP client using extension
      final authClient = authorization.authClient(scopes: _driveScopes);

      debugPrint('[BackupService] ✅ Got authenticated client');

      // Create and return Drive API instance
      final driveApi = drive.DriveApi(authClient);
      debugPrint('[BackupService] ✅ Google Drive API authenticated successfully');

      return driveApi;
    } catch (e, stackTrace) {
      debugPrint('[BackupService] ❌ Error getting Drive API: $e');
      debugPrint('[BackupService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Sign out from Google Drive
  Future<void> signOutFromGoogleDrive() async {
    try {
      if (_googleSignInInstance != null) {
        await _googleSignInInstance!.disconnect();
        _cachedAccount = null;
        debugPrint('[BackupService] Signed out from Google Drive');
      }
    } catch (e) {
      debugPrint('[BackupService] Error signing out from Google Drive: $e');
    }
  }

  /// Check if user is signed in to Google Drive
  Future<bool> isSignedInToGoogleDrive() async {
    try {
      return _cachedAccount != null;
    } catch (e) {
      debugPrint('[BackupService] Error checking Google Drive sign-in status: $e');
      return false;
    }
  }

  /// Get current Google Drive account email
  Future<String?> getGoogleDriveAccountEmail() async {
    try {
      return _cachedAccount?.email;
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

  /// List all backups from Google Drive
  Future<List<drive.File>> listBackupsFromGoogleDrive() async {
    try {
      debugPrint('[BackupService] Listing backups from Google Drive...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

      // Find backup folder
      final folderName = 'Zarq Messenger Backups';
      final folderQuery = "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final folderList = await driveApi.files.list(
        q: folderQuery,
        spaces: 'drive',
        $fields: 'files(id)',
      );

      if (folderList.files == null || folderList.files!.isEmpty) {
        debugPrint('[BackupService] No backup folder found');
        return [];
      }

      final folderId = folderList.files!.first.id;

      // List all backup files in folder
      final fileQuery = "'$folderId' in parents and trashed=false";
      final fileList = await driveApi.files.list(
        q: fileQuery,
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, size, createdTime, modifiedTime)',
      );

      debugPrint('[BackupService] Found ${fileList.files?.length ?? 0} backups');
      return fileList.files ?? [];
    } catch (e) {
      debugPrint('[BackupService] Error listing backups: $e');
      return [];
    }
  }

  /// Download backup from Google Drive
  Future<File?> downloadFromGoogleDrive(String fileId) async {
    try {
      debugPrint('[BackupService] Downloading backup from Google Drive...');

      final driveApi = await getDriveApi();
      if (driveApi == null) {
        throw Exception('Failed to authenticate with Google Drive');
      }

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

  /// Get auto-backup settings
  Future<AutoBackupSettings> getAutoBackupSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_autoBackupSettingsKey);

      if (jsonString == null) {
        return AutoBackupSettings(); // Return default settings
      }

      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      return AutoBackupSettings.fromJson(jsonData);
    } catch (e) {
      debugPrint('[BackupService] Error loading auto-backup settings: $e');
      return AutoBackupSettings();
    }
  }

  /// Save auto-backup settings
  Future<void> saveAutoBackupSettings(AutoBackupSettings settings) async {
    try {
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
}
