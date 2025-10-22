import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

import '../home_screen.dart';
import 'database_service.dart';

class ConversationService {
  final String _baseUrl = 'https://api.zarqmessenger.com';
  
  // Fetches the list of conversations for the currently logged-in user.
  Future<List<ConversationInfo>> fetchConversations() async {
    final dbService = DatabaseService.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return [];
    }

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('$_baseUrl/conversations');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10)); // Add timeout for faster offline detection

      if (response.statusCode == 200) {
        // print('[ConversationService] === RAW BACKEND RESPONSE ===');
        // print('[ConversationService] Response body: ${response.body}');
        // print('[ConversationService] === END RAW RESPONSE ===');

        final List<dynamic> convosFromServer = json.decode(response.body);

        // Parse conversations first
        final baseConversations = convosFromServer
            .map((data) => ConversationInfo.fromJson(data))
            .toList();

        // Add unread status, count, and last message timestamp to each
        final conversationsWithMetadata = <ConversationInfo>[];
        for (final convo in baseConversations) {
          final unreadCount = await dbService.getUnreadMessageCount(
              convo.conversationId,
              user.uid
          );
          final lastMessageTimestamp = await dbService.getLastMessageTimestamp(
              convo.conversationId
          );

          conversationsWithMetadata.add(ConversationInfo(
            conversationId: convo.conversationId,
            chatTitle: convo.chatTitle,
            isGroup: convo.isGroup,
            creatorUid: convo.creatorUid,
            avatarUrl: convo.avatarUrl,
            partnerUid: convo.partnerUid,
            hasUnreadMessages: unreadCount > 0,
            unreadCount: unreadCount,
            lastMessageTimestamp: lastMessageTimestamp,
          ));
        }

        // Sort by last message timestamp (newest first)
        conversationsWithMetadata.sort((a, b) {
          // Conversations with no messages go to bottom
          if (a.lastMessageTimestamp == null && b.lastMessageTimestamp == null) return 0;
          if (a.lastMessageTimestamp == null) return 1;
          if (b.lastMessageTimestamp == null) return -1;
          // Sort descending (newest first)
          return b.lastMessageTimestamp!.compareTo(a.lastMessageTimestamp!);
        });

        return conversationsWithMetadata;
      } else {
        throw Exception('Failed to load conversations: ${response.body}');
      }
    } on FirebaseAuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      // 🚀 OFFLINE MODE: If API fails, build conversation list from local database
      print('[ConversationService] ⚠️ API failed: $e - Using offline mode');
      return await _buildConversationsFromLocalDatabase();
    }
  }

  /// Build conversation list from local database (offline mode)
  /// This allows the app to work without internet
  Future<List<ConversationInfo>> _buildConversationsFromLocalDatabase() async {
    try {
      print('[ConversationService] 📱 Building conversation list from local database...');

      final dbService = DatabaseService.instance;
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return [];

      // Get all conversations that have messages in local database
      final db = dbService.database;

      // Query distinct conversation IDs from messages table
      final result = await db.rawQuery('''
        SELECT DISTINCT
          m.conversationId,
          MAX(m.timestamp) as lastMessageTime
        FROM messages m
        LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
        WHERE dm.message_id IS NULL
        GROUP BY m.conversationId
        ORDER BY lastMessageTime DESC
      ''', [user.uid]);

      final conversations = <ConversationInfo>[];

      for (final row in result) {
        final conversationId = row['conversationId'] as int;

        // Get unread count
        final unreadCount = await dbService.getUnreadMessageCount(conversationId, user.uid);

        // Get last message timestamp
        final lastMessageTimestamp = await dbService.getLastMessageTimestamp(conversationId);

        // Get ALL messages to find the OTHER person's name (not your own)
        final allMessages = await dbService.getMessages(conversationId, limit: 50);

        if (allMessages.isNotEmpty) {
          // Find first message from someone OTHER than current user
          String? chatTitle;
          String? partnerUid;

          // Look through messages to find the other person
          for (final message in allMessages) {
            if (message.senderUid != user.uid && message.senderUid != null) {
              // Found a message from the other person!
              chatTitle = message.username;
              partnerUid = message.senderUid;
              break;
            }
          }

          // Fallback: If all messages are from current user (unlikely), use first message username
          if (chatTitle == null) {
            chatTitle = allMessages.first.username;
          }

          conversations.add(ConversationInfo(
            conversationId: conversationId,
            chatTitle: chatTitle ?? 'Unknown', // Fallback to "Unknown"
            isGroup: false, // Can't determine from local DB, assume 1-on-1
            creatorUid: null,
            avatarUrl: null, // No avatar in offline mode
            partnerUid: partnerUid,
            hasUnreadMessages: unreadCount > 0,
            unreadCount: unreadCount,
            lastMessageTimestamp: lastMessageTimestamp,
          ));
        }
      }

      print('[ConversationService] ✅ Built ${conversations.length} conversations from local database');
      return conversations;

    } catch (e) {
      print('[ConversationService] ❌ Error building offline conversations: $e');
      return [];
    }
  }
}
