import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'dart:math';
import 'dart:typed_data';


import '../message_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  final _storage = const FlutterSecureStorage();

  DatabaseService._init();

  Future<void> init() async {
    if (_database != null) {
      return;
    }
    _database = await _initDB('zarq_messages.db');
    print("[DatabaseService] Database successfully initialized.");
  }

  Database get database {
    if (_database == null) {
      throw Exception("Database not initialized. Call init() first.");
    }
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final currentUser = FirebaseAuth.instance.currentUser;
    final userUid = currentUser?.uid ?? 'anonymous';
    print("[DatabaseService] DEBUG: Database init - Expected UID: ${userUid}");

    final path = join(dbPath, 'zarq_messages_$userUid.db');
    print("[DatabaseService] DEBUG: Using database path: $path");

    try {
      print("[DatabaseService] Attempting to open encrypted database...");
      return await openDatabase(
        path,
        version: 7, // Fixed version number
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      );
    } catch (e) {
      print("[DatabaseService] FAILED to open database, likely due to corruption.");
      print("[DatabaseService] Deleting corrupted database and creating a new one. Error: $e");

      await deleteDatabase(path);

      return await openDatabase(
        path,
        version: 7, // Fixed version number
        onCreate: _createDB,
      );
    }
  }

  // This method is called when the database is created for the first time.
  Future _createDB(Database db, int version) async {
    print("[DatabaseService] Creating new database tables with multi-user schema (v$version)...");

    // Messages table with status column
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

    print("[DatabaseService] All tables created successfully.");
  }

  // Handle database upgrades
  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    print("[DatabaseService] Upgrading database from v$oldVersion to v$newVersion...");

    if (oldVersion < 5) {
      print("[DatabaseService] Recreating messages table with status column...");

      // Drop existing table
      await db.execute('DROP TABLE IF EXISTS messages');

      // Create new table with status column
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

      print("[DatabaseService] Messages table recreated successfully.");
    }

    if (oldVersion < 6) {
      print("[DatabaseService] Adding deleted_messages table...");

      // Create deleted_messages table
      await db.execute('''
        CREATE TABLE deleted_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message_id INTEGER NOT NULL,
          deleted_at INTEGER NOT NULL,
          UNIQUE(message_id)
        )
      ''');

      print("[DatabaseService] Deleted messages table created successfully.");
    }

    if (oldVersion < 7) {
      print("[DatabaseService] Adding user_uid column to deleted_messages table...");

      // Drop and recreate the table with user_uid column
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

      print("[DatabaseService] deleted_messages table updated with user_uid column.");
    }

    print("[DatabaseService] Database schema upgraded to v$newVersion.");
  }

  // --- Data Access Methods ---

  Future<void> insertMessage(Message message) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    print("[DatabaseService] DEBUG: insertMessage called for message ${message.id}, current user: ${currentUser?.uid}");

    // Check if current user has deleted this message
    final isDeleted = await isMessageDeletedForMe(message.id);
    if (isDeleted) {
      print("[DatabaseService] DEBUG: Skipping insert - message ${message.id} was deleted by current user ${currentUser?.uid}");
      return;
    }

    print("[DatabaseService] DEBUG: Proceeding with insert for message ${message.id}");

    final json = message.toJson();
    json.remove('senderKeyId');
    json.remove('recipientKeyId');

    await db.insert('messages', json, conflictAlgorithm: ConflictAlgorithm.replace);
    print("[DatabaseService] DEBUG: Message ${message.id} inserted successfully");
  }

  // Hard delete - keep for backward compatibility but discourage use
  Future<void> deleteMessage(int id) async {
    final db = database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  // DELETION METHODS FOR NEW SYSTEM

  /// Mark message as deleted for the current user only
  Future<void> markMessageAsDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    print("[DatabaseService] DEBUG: markMessageAsDeletedForMe called for message $messageId, user: ${currentUser?.uid}");

    if (currentUser == null) {
      print("[DatabaseService] DEBUG: No current user, aborting deletion mark");
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

    print("[DatabaseService] DEBUG: Marked message $messageId as deleted for user ${currentUser.uid}");

    // Verify the insertion
    final verification = await db.query('deleted_messages', where: 'message_id = ? AND user_uid = ?', whereArgs: [messageId, currentUser.uid]);
    print("[DatabaseService] DEBUG: Verification - deletion record exists: ${verification.isNotEmpty}");
  }

  /// Update message content to show it was deleted for everyone
  Future<void> markMessageAsDeletedForEveryone(int messageId) async {
    final db = database;
    await db.update(
      'messages',
      {'content': 'This message was deleted'},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    print("[DatabaseService] Marked message $messageId as deleted for everyone");
  }

  /// Remove message from deleted_messages table (for undo functionality)
  Future<void> unmarkMessageAsDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    await db.delete(
      'deleted_messages',
      where: 'message_id = ? AND user_uid = ?',
      whereArgs: [messageId, currentUser.uid],
    );
    print("[DatabaseService] Unmarked message $messageId as deleted for user ${currentUser.uid}");
  }

  /// Check if a message is deleted for the current user
  Future<bool> isMessageDeletedForMe(int messageId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    print("[DatabaseService] DEBUG: isMessageDeletedForMe called for message $messageId, user: ${currentUser?.uid}");

    if (currentUser == null) {
      print("[DatabaseService] DEBUG: No current user, returning false");
      return false;
    }

    final result = await db.query(
      'deleted_messages',
      where: 'message_id = ? AND user_uid = ?',
      whereArgs: [messageId, currentUser.uid],
    );

    print("[DatabaseService] DEBUG: Query result for message $messageId: ${result.length} records found");
    if (result.isNotEmpty) {
      print("[DatabaseService] DEBUG: Deletion record: ${result.first}");
    }

    return result.isNotEmpty;
  }

  /// Get messages for a conversation, excluding those deleted for the current user
  Future<List<Message>> getMessages(int conversationId) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;

    print("[DatabaseService] CRITICAL DEBUG: getMessages called");
    print("[DatabaseService] CRITICAL DEBUG: conversationId=$conversationId, currentUser=${currentUser?.uid}");

    if (currentUser == null) return [];

    // Debug: Check deletion records first
    final deletionRecords = await db.query('deleted_messages', where: 'user_uid = ?', whereArgs: [currentUser.uid]);
    print("[DatabaseService] CRITICAL DEBUG: Found ${deletionRecords.length} deletion records for user ${currentUser.uid}:");
    for (final record in deletionRecords) {
      print("[DatabaseService] CRITICAL DEBUG: Deletion record: $record");
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
    SELECT m.* FROM messages m
    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
    WHERE m.conversationId = ? AND dm.message_id IS NULL
    ORDER BY m.timestamp ASC
  ''', [currentUser.uid, conversationId]);

    print("[DatabaseService] CRITICAL DEBUG: Query returned ${maps.length} messages after deletion filtering");
    for (final map in maps) {
      print("[DatabaseService] CRITICAL DEBUG: Message ${map['id']}: ${map['content']}");
    }

    return List.generate(maps.length, (i) {
      return Message.fromJson(maps[i]);
    });
  }

  Future<void> updateMessageContent(int messageId, String newContent) async {
    final db = database;
    await db.update(
      'messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    print("[DatabaseService] Updated content for message $messageId");
  }

  /// Get all messages for a conversation (including deleted ones) - for debugging
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

  /// Clean up old deleted message records (optional maintenance)
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
      print("[DatabaseService] Cleaned up $deletedCount old deleted message records for user ${currentUser.uid}");
    }
  }

  Future close() async {
    final db = database;
    db.close();
    _database = null;
  }

  /// Update the status of a specific message
  Future<void> updateMessageStatus(int messageId, MessageStatus newStatus) async {
    final db = database;
    await db.update(
      'messages',
      {'status': newStatus.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    print("[DatabaseService] Updated message $messageId status to $newStatus");
  }

  /// Update status for multiple messages (useful for "read all" scenarios)
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
    print("[DatabaseService] Updated ${messageIds.length} messages to status $newStatus");
  }

  /// Get all messages with a specific status (useful for finding undelivered messages)
  Future<List<Message>> getMessagesByStatus(int conversationId, MessageStatus status) async {
    final db = database;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    // Filter out deleted_for_me messages
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND m.status = ? AND dm.message_id IS NULL
      ORDER BY m.timestamp ASC
    ''', [currentUser.uid, conversationId, status.toString().split('.').last]);

    return List.generate(maps.length, (i) {
      return Message.fromJson(maps[i]);
    });
  }

  Future<List<Message>> getAllUndeliveredMessages(String currentUserUid) async {
    final db = database;

    // Get all messages where user is NOT the sender and status is 'sent'
    // Exclude messages deleted for the current user
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.senderUid != ? AND m.status = ? AND dm.message_id IS NULL
      ORDER BY m.timestamp DESC
    ''', [currentUserUid, currentUserUid, 'sent']);

    return List.generate(maps.length, (i) {
      return Message.fromJson(maps[i]);
    });
  }

  Future<List<Message>> getUndeliveredMessagesInConversation(int conversationId, String currentUserUid) async {
    final db = database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT m.* FROM messages m
      LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
      WHERE m.conversationId = ? AND m.senderUid != ? AND m.status = ? AND dm.message_id IS NULL
      ORDER BY m.timestamp ASC
    ''', [currentUserUid, conversationId, currentUserUid, 'sent']);

    return List.generate(maps.length, (i) {
      return Message.fromJson(maps[i]);
    });
  }

  Future<void> resetDatabase() async {
    await close();
    _database = null;
    print("[DatabaseService] Database reset - ready for re-initialization");
  }
}