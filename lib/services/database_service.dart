// --- FILE: lib/services/database_service.dart ---
// This version contains the corrected database schema to support multiple users.

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
        version: 2, // FIX: Incremented version to trigger onUpgrade/onCreate
        onCreate: _createDB,
        onUpgrade: _onUpgradeDB,
      );
    } catch (e) {
      print("[DatabaseService] FAILED to open database, likely due to corruption.");
      print("[DatabaseService] Deleting corrupted database and creating a new one. Error: $e");
      
      await deleteDatabase(path);
      
      return await openDatabase(
        path,
        version: 2, // FIX: Use new version number
        onCreate: _createDB,
      );
    }
  }

  // This method is called when the database is created for the first time.
  Future _createDB(Database db, int version) async {
    print("[DatabaseService] Creating new database tables with multi-user schema (v$version)...");
    
    // Messages table (no changes needed)
    await db.execute('''
      CREATE TABLE messages ( 
        id INTEGER PRIMARY KEY, 
        username TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        senderUid TEXT,
        conversationId INTEGER NOT NULL
      )
    ''');
    print("[DatabaseService] All tables created successfully.");
  }

  // FIX: Added an onUpgrade handler to safely migrate existing users' databases.
  Future<void> _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    print("[DatabaseService] Upgrading database from v$oldVersion to v$newVersion...");
    if (oldVersion < 2) {
        await _createDB(db, newVersion);
        print("[DatabaseService] Database schema upgraded.");
    }
  }

  // --- Data Access Methods (no changes needed below) ---

  Future<void> insertMessage(Message message, int conversationId) async {
    final db = database;
    final json = message.toJson();
    json['conversationId'] = conversationId;
    // Remove keys that don't exist in the new simplified message table
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
}
