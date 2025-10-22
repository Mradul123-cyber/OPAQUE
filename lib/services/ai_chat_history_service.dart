import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'SignalService.dart';

class AIChatHistoryService {
  static final AIChatHistoryService instance = AIChatHistoryService._init();
  static Database? _database;

  AIChatHistoryService._init();

  Future<void> init() async {
    if (_database != null) return;
    _database = await _initDB('zarq_ai_chats.db');
  }

  Database get database {
    if (_database == null) {
      throw Exception("AI Chat database not initialized. Call init() first.");
    }
    return _database!;
  }

  Future<String> _deriveDatabaseKey() async {
    try {
      final identityKeyB64 = await SignalService.getIdentityKeyPrivateKey();
      if (identityKeyB64 == null) {
        throw Exception('Identity key not available for AI chat encryption');
      }

      final identityKeyBytes = base64.decode(identityKeyB64);
      final salt = 'zarq_ai_chat_encryption_v1';
      final input = Uint8List.fromList([...identityKeyBytes, ...utf8.encode(salt)]);
      final hash = sha256.convert(input);

      return hash.toString();
    } catch (e) {
      rethrow;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final currentUser = FirebaseAuth.instance.currentUser;
    final userUid = currentUser?.uid ?? 'anonymous';
    final path = join(dbPath, 'zarq_ai_chats_$userUid.db');

    final encryptionKey = await _deriveDatabaseKey();

    try {
      return await openDatabase(
        path,
        version: 1,
        password: encryptionKey,
        onCreate: _createDB,
      );
    } catch (e) {
      await deleteDatabase(path);
      return await openDatabase(
        path,
        version: 1,
        password: encryptionKey,
        onCreate: _createDB,
      );
    }
  }

  Future _createDB(Database db, int version) async {
    // Conversations table (chat sessions)
    await db.execute('''
      CREATE TABLE ai_conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_terminal_mode INTEGER DEFAULT 1,
        is_on_device_mode INTEGER DEFAULT 1
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        is_user INTEGER NOT NULL,
        is_on_device INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES ai_conversations (id) ON DELETE CASCADE
      )
    ''');
  }

  // Create new conversation
  Future<int> createConversation({
    required String title,
    required bool isTerminalMode,
    required bool isOnDeviceMode,
  }) async {
    final db = database;
    final now = DateTime.now().toUtc().toIso8601String();

    final id = await db.insert('ai_conversations', {
      'title': title,
      'created_at': now,
      'updated_at': now,
      'is_terminal_mode': isTerminalMode ? 1 : 0,
      'is_on_device_mode': isOnDeviceMode ? 1 : 0,
    });

    return id;
  }

  // Save message
  Future<void> saveMessage({
    required int conversationId,
    required String content,
    required bool isUser,
    required bool isOnDevice,
  }) async {
    final db = database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('ai_messages', {
      'conversation_id': conversationId,
      'content': content,
      'is_user': isUser ? 1 : 0,
      'is_on_device': isOnDevice ? 1 : 0,
      'timestamp': now,
    });

    // Update conversation updated_at
    await db.update(
      'ai_conversations',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  // Get all conversations (for sidebar)
  Future<List<AIConversation>> getAllConversations() async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ai_conversations',
      orderBy: 'updated_at DESC',
    );

    return maps.map((map) => AIConversation.fromJson(map)).toList();
  }

  // Get messages for a conversation
  Future<List<AIMessageData>> getMessages(int conversationId) async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ai_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => AIMessageData.fromJson(map)).toList();
  }

  // Update conversation title
  Future<void> updateConversationTitle(int conversationId, String newTitle) async {
    final db = database;
    await db.update(
      'ai_conversations',
      {'title': newTitle},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  // Delete conversation
  Future<void> deleteConversation(int conversationId) async {
    final db = database;
    await db.delete(
      'ai_conversations',
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    // Messages will be deleted automatically due to CASCADE
  }

  // Get last active conversation
  Future<AIConversation?> getLastConversation() async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ai_conversations',
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return AIConversation.fromJson(maps.first);
  }

  Future<void> close() async {
    final db = database;
    await db.close();
    _database = null;
  }
}

// AI Conversation model
class AIConversation {
  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isTerminalMode;
  final bool isOnDeviceMode;

  AIConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.isTerminalMode,
    required this.isOnDeviceMode,
  });

  factory AIConversation.fromJson(Map<String, dynamic> json) {
    return AIConversation(
      id: json['id'] as int,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isTerminalMode: (json['is_terminal_mode'] as int) == 1,
      isOnDeviceMode: (json['is_on_device_mode'] as int) == 1,
    );
  }
}

// AI Message model
class AIMessageData {
  final int id;
  final int conversationId;
  final String content;
  final bool isUser;
  final bool isOnDevice;
  final DateTime timestamp;

  AIMessageData({
    required this.id,
    required this.conversationId,
    required this.content,
    required this.isUser,
    required this.isOnDevice,
    required this.timestamp,
  });

  factory AIMessageData.fromJson(Map<String, dynamic> json) {
    return AIMessageData(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int,
      content: json['content'] as String,
      isUser: (json['is_user'] as int) == 1,
      isOnDevice: (json['is_on_device'] as int) == 1,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
