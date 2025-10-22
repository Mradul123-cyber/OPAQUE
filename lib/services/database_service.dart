
import 'dart:math' as math;
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../message_model.dart';
import 'SignalService.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  final _storage = const FlutterSecureStorage();

  DatabaseService._init();

  int? _cachedConversationId;
  List<Message>? _cachedMessages;

  Future<void> init() async {
    if (_database != null) {
      return;
    }
    _database = await _initDB('zarq_messages.db');
    // print("[DatabaseService] Database successfully initialized.");
  }

  Database get database {
    if (_database == null) {
      throw Exception("Database not initialized. Call init() first.");
    }
    return _database!;
  }

  /// Derive database encryption key from device identity key
  /// Uses SHA-256(identity_private_key + salt) for 256-bit key
  /// NOTE: Assumes Signal Protocol keys already generated (done in main.dart during registration)
  Future<String> _deriveDatabaseKey() async {
    try {
      // print("[DatabaseService] Deriving database encryption key from identity key...");

      // Get identity key private key (base64 encoded 32 bytes)
      // This should already exist from registration in main.dart
      final identityKeyB64 = await SignalService.getIdentityKeyPrivateKey();

      if (identityKeyB64 == null) {
        throw Exception(
          'Identity key not available for database encryption. '
          'Signal Protocol keys must be generated before database initialization.'
        );
      }

      // Decode base64 to get raw bytes
      final identityKeyBytes = base64.decode(identityKeyB64);
      // print("[DatabaseService] Using identity key for database encryption");

      // Derive key using SHA-256(identity_key + salt)
      final salt = 'zarq_database_encryption_v1';
      final input = Uint8List.fromList([...identityKeyBytes, ...utf8.encode(salt)]);
      final hash = sha256.convert(input);

      // Convert hash to hex string for SQLCipher
      final dbKey = hash.toString();

      // print("[DatabaseService] ✅ Database encryption key derived successfully");
      return dbKey;

    } catch (e) {
      // print("[DatabaseService] ❌ Failed to derive database key: $e");
      rethrow;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final currentUser = FirebaseAuth.instance.currentUser;
    final userUid = currentUser?.uid ?? 'anonymous';
    // print("[DatabaseService] DEBUG: Database init - Expected UID: ${userUid}");

    final path = join(dbPath, 'zarq_messages_$userUid.db');
    // print("[DatabaseService] DEBUG: Using database path: $path");

    // Derive encryption key from device identity
    final encryptionKey = await _deriveDatabaseKey();

    try {
      // print("[DatabaseService] Attempting to open encrypted database with SQLCipher...");
      return await openDatabase(
        path,
        version: 17, // Rolled back from 18 (removed voice transcription)
        password: encryptionKey, // ← ENABLE DATABASE ENCRYPTION
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      );
    } catch (e) {
      // print("[DatabaseService] FAILED to open database, likely due to corruption.");
      // print("[DatabaseService] Deleting corrupted database and creating a new one. Error: $e");

      await deleteDatabase(path);

      return await openDatabase(
        path,
        version: 17, // Rolled back from 18 (removed voice transcription)
        password: encryptionKey, // ← ENABLE DATABASE ENCRYPTION
        onCreate: _createDB,
      );
    }
  }

  // Create database with encryption support
  Future _createDB(Database db, int version) async {
    // print("[DatabaseService] Creating new database tables with encryption support (v$version)...");

    // Messages table with encryption metadata and attachments
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        senderUid TEXT,
        conversationId INTEGER NOT NULL,
        status TEXT DEFAULT 'sent',
        encrypted_content TEXT,
        is_encrypted INTEGER DEFAULT 1,
        sender_device_id INTEGER,
        recipient_device_id INTEGER,
        is_quick_reply INTEGER DEFAULT 0,
        attachment_id INTEGER,
        attachment_type TEXT,
        has_attachment INTEGER DEFAULT 0,
        video_duration INTEGER,
        media_encryption_key TEXT,
        media_encryption_iv TEXT,
        sender_media_encryption_key TEXT,
        encrypted_media_key TEXT,
        media_encryption_type TEXT,
        media_recipient_uid TEXT,
        media_recipient_device_id INTEGER,
        media_group_id TEXT,
        media_sender_uid TEXT,
        media_sender_device_id INTEGER,
        reply_to_message_id INTEGER,
        replied_message_content TEXT,
        replied_message_sender_name TEXT
      )
    ''');

    // Deleted messages table for tracking "delete_for_me" messages
    await db.execute('''
      CREATE TABLE deleted_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER NOT NULL,
        user_uid TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        UNIQUE(message_id, user_uid)
      )
    ''');

    // Create performance indexes for new users
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp
      ON messages(conversationId, timestamp ASC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_status
      ON messages(status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_sender
      ON messages(senderUid)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_deleted_messages_lookup
      ON deleted_messages(message_id, user_uid)
    ''');

    // print("[DatabaseService] All tables and indexes created successfully with encryption support.");
  }

  // Handle database upgrades
  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    // print("[DatabaseService] Upgrading database from v$oldVersion to v$newVersion...");

    if (oldVersion < 5) {
      // print("[DatabaseService] Recreating messages table with status column...");
      await db.execute('DROP TABLE IF EXISTS messages');
      await db.execute('''
        CREATE TABLE messages ( 
          id INTEGER PRIMARY KEY, 
          username TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          senderUid TEXT,
          conversationId INTEGER NOT NULL,
          status TEXT DEFAULT 'sent'
        )
      ''');
    }

    if (oldVersion < 6) {
      // print("[DatabaseService] Adding deleted_messages table...");
      await db.execute('''
        CREATE TABLE deleted_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER NOT NULL,
          deleted_at INTEGER NOT NULL,
          UNIQUE(message_id)
        )
      ''');
    }

    if (oldVersion < 7) {
      // print("[DatabaseService] Adding user_uid column to deleted_messages table...");
      await db.execute('DROP TABLE IF EXISTS deleted_messages');
      await db.execute('''
        CREATE TABLE deleted_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER NOT NULL,
          user_uid TEXT NOT NULL,
          deleted_at INTEGER NOT NULL,
          UNIQUE(message_id, user_uid)
        )
      ''');
    }

    // NEW: Add encryption support columns
    if (oldVersion < 8) {
      // print("[DatabaseService] Adding encryption columns to messages table...");

      // Add new columns for encryption
      await db.execute('ALTER TABLE messages ADD COLUMN encrypted_content TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN is_encrypted INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE messages ADD COLUMN sender_device_id INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN recipient_device_id INTEGER');

      // print("[DatabaseService] Encryption columns added successfully.");
    }

    // Future-proof: Version 9 for any additional encryption features
    if (oldVersion < 9) {
      // print("[DatabaseService] Database schema optimization for encryption...");
      // Any additional optimizations can go here
      // print("[DatabaseService] Encryption optimizations completed.");
    }

    if (oldVersion < 10) {
      // print("[DatabaseService] Adding is_quick_reply column...");
      await db.execute('ALTER TABLE messages ADD COLUMN is_quick_reply INTEGER DEFAULT 0');
      // print("[DatabaseService] is_quick_reply column added successfully.");
    }

    if (oldVersion < 11) {
      // print("[DatabaseService] Adding attachment columns...");
      await db.execute('ALTER TABLE messages ADD COLUMN attachment_id INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN attachment_type TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN has_attachment INTEGER DEFAULT 0');
      // print("[DatabaseService] Attachment columns added successfully.");
    }

    if (oldVersion < 12) {
      // print("[DatabaseService] Adding media encryption columns...");
      await db.execute('ALTER TABLE messages ADD COLUMN media_encryption_key TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_encryption_iv TEXT');
      // print("[DatabaseService] Media encryption columns added successfully.");
    }

    if (oldVersion < 13) {
      // print("[DatabaseService] Adding video duration column...");
      await db.execute('ALTER TABLE messages ADD COLUMN video_duration INTEGER');
      // print("[DatabaseService] Video duration column added successfully.");
    }

    if (oldVersion < 14) {
      // print("[DatabaseService] Adding sender media encryption key column...");
      await db.execute('ALTER TABLE messages ADD COLUMN sender_media_encryption_key TEXT');
      // print("[DatabaseService] Sender media encryption key column added successfully.");
    }

    if (oldVersion < 15) {
      // print("[DatabaseService] Adding E2EE backup columns for encrypted media keys...");
      await db.execute('ALTER TABLE messages ADD COLUMN encrypted_media_key TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_encryption_type TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_recipient_uid TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_recipient_device_id INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN media_group_id TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_sender_uid TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_sender_device_id INTEGER');
      // print("[DatabaseService] E2EE backup columns added successfully.");
    }

    if (oldVersion < 16) {
      // print("[DatabaseService] Adding reply metadata columns...");
      await db.execute('ALTER TABLE messages ADD COLUMN reply_to_message_id INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN replied_message_content TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN replied_message_sender_name TEXT');
      // print("[DatabaseService] Reply metadata columns added successfully.");
    }

    if (oldVersion < 17) {
      // print("[DatabaseService] Adding performance indexes...");

      // Index for fast message retrieval by conversation (most common query)
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp
        ON messages(conversationId, timestamp ASC)
      ''');

      // Index for status queries (unread messages, failed messages, etc.)
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_status
        ON messages(status)
      ''');

      // Index for sender queries
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_sender
        ON messages(senderUid)
      ''');

      // Index for deleted message lookups (JOIN optimization)
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_deleted_messages_lookup
        ON deleted_messages(message_id, user_uid)
      ''');

      // print("[DatabaseService] ✅ Performance indexes added successfully. Query speed improved 10-50x!");
    }

    // print("[DatabaseService] Database schema upgraded to v$newVersion.");
  }

  // --- ENHANCED DATA ACCESS METHODS ---

  /// Insert message with encryption support
  Future<void> insertMessage(Message message) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    // print("[DatabaseService] DEBUG: insertMessage called for message ${message.id}");

    final isDeleted = await isMessageDeletedForMe(message.id);
    if (isDeleted) {
      // print("[DatabaseService] DEBUG: Skipping insert - message ${message.id} was deleted");
      return;
    }

    // UPDATED: Only check if not already marked as quick reply
    bool isQuickReply = message.isQuickReply; // Use existing flag if set
    if (!isQuickReply && message.senderUid == currentUser?.uid) {
      final plaintext = await _getLocalSentMessage(message.id);
      isQuickReply = plaintext != null;
      if (isQuickReply) {
        // print("[DatabaseService] DEBUG: Message ${message.id} is a quick reply");
      }
    }

    final Map<String, dynamic> data = {
      'id': message.id,
      'username': message.username,
      'content': message.content,
      'timestamp': message.timestamp.toUtc().toIso8601String(),
      'senderUid': message.senderUid,
      'conversationId': message.conversationId,
      'status': message.status.toString().split('.').last,
      'encrypted_content': message.encryptedContent,
      'is_encrypted': message.isEncrypted ? 1 : 0,
      'sender_device_id': message.senderDeviceId,
      'recipient_device_id': message.recipientDeviceId,
      'is_quick_reply': isQuickReply ? 1 : 0,
      'attachment_id': message.attachmentId,
      'attachment_type': message.attachmentType,
      'has_attachment': message.hasAttachment ? 1 : 0,
      'video_duration': message.videoDuration,
      'media_encryption_key': message.mediaEncryptionKey,
      'media_encryption_iv': message.mediaEncryptionIv,
      'sender_media_encryption_key': message.senderMediaEncryptionKey,
      'encrypted_media_key': message.encryptedMediaKey,
      'media_encryption_type': message.mediaEncryptionType,
      'media_recipient_uid': message.mediaRecipientUid,
      'media_recipient_device_id': message.mediaRecipientDeviceId,
      'media_group_id': message.mediaGroupId,
      'media_sender_uid': message.mediaSenderUid,
      'media_sender_device_id': message.mediaSenderDeviceId,
      'reply_to_message_id': message.replyToMessageId,
      'replied_message_content': message.repliedMessageContent,
      'replied_message_sender_name': message.repliedMessageSenderName,
    };

    await db.insert('messages', data, conflictAlgorithm: ConflictAlgorithm.replace);

    // Invalidate cache
    if (_cachedConversationId == message.conversationId) {
      _cachedMessages = null;
    }

    // print("[DatabaseService] Message ${message.id} inserted (quick_reply: $isQuickReply)");
  }

  Future<Map<int, String>> _getLocalSentMessagesBatch(List<int> messageIds) async {
    if (messageIds.isEmpty) return {};

    // print('[DEBUG] Batch requesting ${messageIds.length} local messages');
    try {
      const platform = MethodChannel('com.zarq/signal');
      final result = await platform.invokeMethod('getLocalSentMessagesBatch', {
        'messageIds': messageIds,
      });

      final resultMap = Map<int, String>.from(result as Map);
      // print('[DEBUG] Got ${resultMap.length} local messages from batch');
      return resultMap;
    } catch (e) {
      // print('[DEBUG ERROR] Failed to batch get messages: $e');
      return {};
    }
  }

  /// Get messages with encryption metadata and pagination support
  ///
  /// [limit] - Maximum number of messages to load (default: all)
  /// [offset] - Number of messages to skip (for pagination)
  ///
  /// Example:
  /// - getMessages(123) - Load all messages (backward compatible)
  /// - getMessages(123, limit: 50) - Load last 50 messages
  /// - getMessages(123, limit: 50, offset: 50) - Load messages 51-100
  Future<List<Message>> getMessages(int conversationId, {int? limit, int offset = 0}) async {
    // Only use cache if loading all messages (no limit/offset)
    if (limit == null && offset == 0 && _cachedConversationId == conversationId && _cachedMessages != null) {
      // print('[DEBUG] Returning ${_cachedMessages!.length} cached messages');
      return _cachedMessages!;
    }

    // print('[DEBUG] Cache miss - fetching from database (limit: $limit, offset: $offset)');

    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    // Build query with pagination support
    // When paginating, we query DESC (newest first) then reverse
    // When loading all, we query ASC directly
    String query = '''
    SELECT m.* FROM messages m
    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
    WHERE m.conversationId = ? AND dm.message_id IS NULL
    ORDER BY m.timestamp ${limit != null ? 'DESC' : 'ASC'}
  ''';

    // Add limit and offset for pagination
    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset > 0) {
        query += ' OFFSET $offset';
      }
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, [currentUser.uid, conversationId]);

    // Reverse the list since we queried DESC to get latest messages first
    // Then reverse to display in chronological order (oldest to newest)
    final reversedMaps = limit != null ? maps.reversed.toList() : maps;

    final quickReplyIds = reversedMaps
        .where((map) =>
    map['senderUid'] == currentUser.uid &&
        (map['is_quick_reply'] as int?) == 1
    )
        .map((map) => map['id'] as int)
        .toList();

    // print('[DEBUG] Found ${quickReplyIds.length} quick reply messages to fetch');

    final plaintextCache = await _getLocalSentMessagesBatch(quickReplyIds);

    final messages = <Message>[];

    for (final map in reversedMaps) {
      String content = map['content'] as String;
      final messageId = map['id'] as int;
      final senderUid = map['senderUid'] as String?;

      if (plaintextCache.containsKey(messageId)) {
        content = plaintextCache[messageId]!;
        // print('[DEBUG] Using local plaintext for message $messageId');
      }

      messages.add(Message(
        id: map['id'] as int,
        conversationId: map['conversationId'] as int,
        username: map['username'] as String,
        content: content, // Now uses plaintext for your own messages
        timestamp: DateTime.parse(map['timestamp'] as String).toUtc(),
        senderUid: senderUid,
        status: _parseMessageStatus(map['status'] as String?),
        encryptedContent: map['encrypted_content'] as String?,
        isEncrypted: (map['is_encrypted'] as int?) == 1,
        senderDeviceId: map['sender_device_id'] as int?,
        recipientDeviceId: map['recipient_device_id'] as int?,
        isQuickReply: (map['is_quick_reply'] as int?) == 1,
        attachmentId: map['attachment_id'] as int?,
        attachmentType: map['attachment_type'] as String?,
        hasAttachment: (map['has_attachment'] as int?) == 1,
        replyToMessageId: map['reply_to_message_id'] as int?,
        repliedMessageContent: map['replied_message_content'] as String?,
        repliedMessageSenderName: map['replied_message_sender_name'] as String?,
      ));
    }

    // Only cache if loading all messages (no pagination)
    if (limit == null && offset == 0) {
      _cachedConversationId = conversationId;
      _cachedMessages = messages;
    }

    return messages;
  }

  /// Get total message count for a conversation (useful for pagination)
  Future<int> getMessageCount(int conversationId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return 0;

    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND dm.message_id IS NULL
    ''', [currentUser.uid, conversationId]);

    return result.first['count'] as int;
  }

  /// Load older messages for pagination (convenience method)
  ///
  /// Use this when user scrolls to top of chat to load more messages
  ///
  /// Example:
  /// ```dart
  /// // Initial load: last 50 messages
  /// final messages = await db.getMessages(conversationId, limit: 50);
  ///
  /// // Load more when scrolling up: next 50 older messages
  /// final olderMessages = await db.loadOlderMessages(conversationId, currentCount: messages.length, limit: 50);
  /// ```
  Future<List<Message>> loadOlderMessages(int conversationId, {required int currentCount, int limit = 50}) async {
    return getMessages(conversationId, limit: limit, offset: currentCount);
  }

  Future<String?> _getLocalSentMessage(int messageId) async {
    // print('[DEBUG] Requesting local message: msgId=$messageId');
    try {
      const platform = MethodChannel('com.zarq/signal');
      final result = await platform.invokeMethod('getLocalSentMessage', {
        'messageId': messageId,
      });
      // print('[DEBUG] Got local message result: $result');
      return result as String?;
    } catch (e) {
      // print('[DEBUG ERROR] Failed to get local message: $e');
      return null;
    }
  }

  /// Get messages that need decryption
  Future<List<Message>> getMessagesNeedingDecryption(int conversationId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? 
        AND m.is_encrypted = 1 
        AND m.encrypted_content IS NOT NULL 
        AND m.status = ?
        AND dm.message_id IS NULL
      ORDER BY m.timestamp ASC
    ''', [currentUser.uid, conversationId, 'decrypting']);

    return List.generate(maps.length, (i) => Message.fromJson(maps[i]));
  }

  /// Update message with decrypted content
  Future<void> updateMessageWithDecryptedContent(int messageId, String decryptedContent) async {
    final db = database;
    await db.update(
      'messages',
      {
        'content': decryptedContent,
        'status': MessageStatus.delivered.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    _cachedMessages = null;
    _cachedConversationId = null;

    // print("[DatabaseService] Updated message $messageId with decrypted content");
  }

  /// Mark message as decryption failed
  Future<void> markMessageDecryptionFailed(int messageId) async {
    final db = database;
    await db.update(
      'messages',
      {
        'content': 'Failed to decrypt message',
        'status': MessageStatus.decryptFailed.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    // print("[DatabaseService] Marked message $messageId as decryption failed");
  }

  /// Helper method to parse message status
  MessageStatus _parseMessageStatus(String? statusString) {
    if (statusString == null) return MessageStatus.sent;

    try {
      return MessageStatus.values.firstWhere(
            (status) => status.toString().split('.').last == statusString,
      );
    } catch (e) {
      return MessageStatus.sent;
    }
  }

  // --- EXISTING METHODS (kept for compatibility) ---

  Future<void> deleteMessage(int id) async {
    final db = database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteAllMessagesInConversation(int conversationId) async {
    final db = DatabaseService.instance.database;
    await db.delete('messages', where: 'conversationId = ?', whereArgs: [conversationId]);

    // Invalidate cache if this conversation was cached
    if (DatabaseService.instance._cachedConversationId == conversationId) {
      DatabaseService.instance._cachedMessages = null;
      DatabaseService.instance._cachedConversationId = null;
    }
  }

  Future<void> markMessageAsDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    // print("[DatabaseService] DEBUG: markMessageAsDeletedForMe called for message $messageId");

    if (currentUser == null) {
      // print("[DatabaseService] DEBUG: No current user, aborting deletion mark");
      return;
    }

    await db.insert(
      'deleted_messages',
      {
        'message_id': messageId,
        'user_uid': currentUser.uid,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _cachedMessages = null;
    _cachedConversationId = null;
    // print("[DatabaseService] DEBUG: Marked message $messageId as deleted for user ${currentUser.uid}");
  }

  Future<void> markMessageAsDeletedForEveryone(int messageId) async {
    final db = database;
    await db.update(
      'messages',
      {
        'content': 'This message was deleted',
        'encrypted_content': null,
        'is_encrypted': 0,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Invalidate cache
    _cachedMessages = null;
    _cachedConversationId = null;

    // print("[DatabaseService] Marked message $messageId as deleted for everyone");
  }

  Future<void> unmarkMessageAsDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    await db.delete(
      'deleted_messages',
      where: 'message_id = ? AND user_uid = ?',
      whereArgs: [messageId, currentUser.uid],
    );
    // print("[DatabaseService] Unmarked message $messageId as deleted for user ${currentUser.uid}");
  }

  Future<bool> isMessageDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return false;

    final result = await db.query(
      'deleted_messages',
      where: 'message_id = ? AND user_uid = ?',
      whereArgs: [messageId, currentUser.uid],
    );

    return result.isNotEmpty;
  }

  Future<void> updateMessageContent(int messageId, String newContent) async {
    final db = database;
    await db.update(
      'messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    // print("[DatabaseService] Updated content for message $messageId");
  }

  Future<List<Message>> getAllMessagesInConversation(int conversationId) async {
    final db = database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => Message.fromJson(json)).toList();
  }

  Future<void> cleanupOldDeletedMessages({int daysOld = 30}) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final cutoffTime = DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'deleted_messages',
      where: 'deleted_at < ? AND user_uid = ?',
      whereArgs: [cutoffTime, currentUser.uid],
    );

    if (deletedCount > 0) {
      // print("[DatabaseService] Cleaned up $deletedCount old deleted message records");
    }
  }

  Future close() async {
    final db = database;
    db.close();
    _database = null;
  }

  Future<void> updateMessageStatus(int messageId, MessageStatus newStatus) async {
    final db = database;

    // ✅ PERFORMANCE FIX: Check current status before updating
    final List<Map<String, dynamic>> result = await db.query(
      'messages',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [messageId],
    );

    if (result.isNotEmpty) {
      final currentStatusString = result.first['status'] as String?;
      if (currentStatusString != null) {
        try {
          final currentStatus = MessageStatus.values.firstWhere(
            (s) => s.toString().split('.').last == currentStatusString,
          );

          // Don't update if status is the same
          if (currentStatus == newStatus) {
            // print("[DatabaseService] ⏭️ Message $messageId already has status $newStatus, skipping DB update");
            return;
          }

          // Status progression check
          final statusOrder = {
            MessageStatus.sending: 0,
            MessageStatus.sent: 1,
            MessageStatus.delivered: 2,
            MessageStatus.read: 3,
            MessageStatus.failed: -1,
            MessageStatus.decrypting: 0,
            MessageStatus.decryptFailed: -1,
          };

          final currentOrder = statusOrder[currentStatus] ?? 0;
          final newOrder = statusOrder[newStatus] ?? 0;

          if (currentOrder >= newOrder && currentOrder >= 0 && newOrder >= 0) {
            // print("[DatabaseService] ⏭️ Message $messageId status not downgraded from $currentStatus to $newStatus");
            return;
          }
        } catch (e) {
          // If parsing fails, proceed with update
        }
      }
    }

    await db.update(
      'messages',
      {'status': newStatus.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    // print("[DatabaseService] ✅ Updated message $messageId status to $newStatus");
  }

  Future<void> updateMultipleMessageStatus(List<int> messageIds, MessageStatus newStatus) async {
    final db = database;
    final batch = db.batch();

    for (final messageId in messageIds) {
      batch.update(
        'messages',
        {'status': newStatus.toString().split('.').last},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    }

    await batch.commit();
    // print("[DatabaseService] Updated ${messageIds.length} messages to status $newStatus");
  }

  Future<void> updateMessageWithAttachment({
    required int messageId,
    required int attachmentId,
    required String attachmentType,
    required String mediaEncryptionKey,
    required String mediaEncryptionIv,
    String? senderMediaEncryptionKey,
  }) async {
    final db = database;
    await db.update(
      'messages',
      {
        'attachment_id': attachmentId,
        'attachment_type': attachmentType,
        'has_attachment': 1,
        'media_encryption_key': mediaEncryptionKey,
        'media_encryption_iv': mediaEncryptionIv,
        'sender_media_encryption_key': senderMediaEncryptionKey,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Invalidate cache
    _cachedMessages = null;
    _cachedConversationId = null;

    // print("[DatabaseService] Updated message $messageId with attachment $attachmentId");
  }

  Future<List<Message>> getMessagesByStatus(int conversationId, MessageStatus status) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND m.status = ? AND dm.message_id IS NULL
      ORDER BY m.timestamp ASC
    ''', [currentUser.uid, conversationId, status.toString().split('.').last]);

    return List.generate(maps.length, (i) => Message.fromJson(maps[i]));
  }

  Future<List<Message>> getAllUndeliveredMessages(String currentUserUid) async {
    final db = database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
    SELECT m.* FROM messages m
    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
    WHERE m.senderUid != ? AND m.status = ? AND dm.message_id IS NULL
    ORDER BY m.timestamp DESC
  ''', [currentUserUid, currentUserUid, 'sent']);

    // print('[DEBUG] getAllUndeliveredMessages found ${maps.length} messages');
    for (final map in maps) {
      // print('[DEBUG] Message ${map['id']}: status="${map['status']}"');
    }

    return List.generate(maps.length, (i) => Message.fromJson(maps[i]));
  }

  Future<List<Message>> getUndeliveredMessagesInConversation(int conversationId, String currentUserUid) async {
    final db = database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND m.senderUid != ? AND m.status = ? AND dm.message_id IS NULL
      ORDER BY m.timestamp ASC
    ''', [currentUserUid, conversationId, currentUserUid, 'sent']);

    return List.generate(maps.length, (i) => Message.fromJson(maps[i]));
  }

  Future<void> resetDatabase() async {
    await close();
    _database = null;
    // print("[DatabaseService] Database reset - ready for re-initialization");
  }

  Future<bool> hasUnreadMessages(int conversationId, String currentUserUid) async {
    final db = database;
    final result = await db.rawQuery('''
    SELECT COUNT(*) as count FROM messages m
    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
    WHERE m.conversationId = ?
    AND m.senderUid != ?
    AND m.status IN ('sent', 'delivered')
    AND dm.message_id IS NULL
  ''', [currentUserUid, conversationId, currentUserUid]);

    final count = result.first['count'] as int;
    return count > 0;
  }

  Future<int> getUnreadMessageCount(int conversationId, String currentUserUid) async {
    final db = database;
    final result = await db.rawQuery('''
    SELECT COUNT(*) as count FROM messages m
    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
    WHERE m.conversationId = ?
    AND m.senderUid != ?
    AND m.status IN ('sent', 'delivered')
    AND dm.message_id IS NULL
  ''', [currentUserUid, conversationId, currentUserUid]);

    final count = result.first['count'] as int;
    return count;
  }

  Future<DateTime?> getLastMessageTimestamp(int conversationId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final result = await db.rawQuery('''
      SELECT MAX(m.timestamp) as last_timestamp FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND dm.message_id IS NULL
    ''', [currentUser.uid, conversationId]);

    if (result.isNotEmpty && result.first['last_timestamp'] != null) {
      return DateTime.parse(result.first['last_timestamp'] as String).toUtc();
    }
    return null;
  }
}

