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
    final path = join(dbPath, filePath);

    try {
      print("[DatabaseService] Attempting to open encrypted database...");
      return await openDatabase(
        path,
        version: 5, // Incremented version to trigger schema update
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      );
    } catch (e) {
      print("[DatabaseService] FAILED to open database, likely due to corruption.");
      print("[DatabaseService] Deleting corrupted database and creating a new one. Error: $e");

      await deleteDatabase(path);

      return await openDatabase(
        path,
        version: 5, // Use new version number
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
    print("[DatabaseService] All tables created successfully.");
  }

  // Handle database upgrades - drop and recreate table
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

    print("[DatabaseService] Database schema upgraded to v$newVersion.");
  }

  // --- Data Access Methods ---

  Future<void> insertMessage(Message message) async {
    final db = database;
    final json = message.toJson();

    // Remove keys that don't exist in the message table
    json.remove('senderKeyId');
    json.remove('recipientKeyId');

    await db.insert('messages', json, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMessage(int id) async {
    final db = database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Message>> getMessages(int conversationId) async {
    final db = database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => Message.fromJson(json)).toList();
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
    final result = await db.query(
      'messages',
      where: 'conversationId = ? AND status = ?',
      whereArgs: [conversationId, status.toString().split('.').last],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => Message.fromJson(json)).toList();
  }

  Future<List<Message>> getAllUndeliveredMessages(String currentUserUid) async {
    final db = database;

    // Simple query - get all messages where user is NOT the sender and status is 'sent'
    final result = await db.query(
      'messages',
      where: 'senderUid != ? AND status = ?',
      whereArgs: [currentUserUid, 'sent'],
      orderBy: 'timestamp DESC',
    );

    return result.map((json) => Message.fromJson(json)).toList();
  }

  Future<List<Message>> getUndeliveredMessagesInConversation(int conversationId, String currentUserUid) async {
    final db = database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ? AND senderUid != ? AND status = ?',
      whereArgs: [conversationId, currentUserUid, 'sent'],
      orderBy: 'timestamp ASC',
    );
    return result.map((json) => Message.fromJson(json)).toList();
  }


}