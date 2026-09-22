import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_storage.dart';

import '../home_screen.dart';
import 'database_service.dart';
import 'package:zarq_messenger/app_config.dart';

class ConversationService {
  final String _baseUrl = '${AppConfig.baseUrl}';

  // Fetches the list of conversations for the currently logged-in user.
  Future<List<ConversationInfo>> fetchConversations() async {
    final dbService = DatabaseService.instance;
    await dbService.init();

    if (Firebase.apps.isEmpty) {
      try {
        await AppStorage.firebaseInitFuture;
      } catch (_) {}
    }
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }

    final uid = user?.uid ?? AppStorage.cachedUid;
    if (uid == null) {
      return [];
    }

    if (user != null) {
      try {
        final token = await user.getIdToken();
        final url = Uri.parse('$_baseUrl/conversations');

        final response = await http
            .get(
              url,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            )
            .timeout(
              const Duration(seconds: 10),
            );

        if (response.statusCode == 200) {
          final List<dynamic> convosFromServer = json.decode(response.body);

          // Parse conversations first
          final baseConversations = convosFromServer
              .map((data) => ConversationInfo.fromJson(data))
              .toList();

          // Add unread status, count, and last message to each (in parallel)
          final conversationsWithMetadata = await Future.wait(
            baseConversations.map((convo) async {
              final unreadFuture = dbService.getUnreadMessageCount(
                convo.conversationId,
                uid,
              );
              final lastMsgFuture = dbService.getLastMessage(convo.conversationId);
              final unreadCount = await unreadFuture;
              final lastMsg = await lastMsgFuture;

              return ConversationInfo(
                conversationId: convo.conversationId,
                chatTitle: convo.chatTitle,
                isGroup: convo.isGroup,
                creatorUid: convo.creatorUid,
                avatarUrl: convo.avatarUrl,
                partnerUid: convo.partnerUid,
                isFriend: convo.isFriend,
                hasUnreadMessages: unreadCount > 0,
                unreadCount: unreadCount,
                lastMessageTimestamp: lastMsg?.timestamp,
                lastMessage: lastMsg?.content,
              );
            }),
          );

          // Sort by last message timestamp (newest first)
          conversationsWithMetadata.sort((a, b) {
            if (a.lastMessageTimestamp == null && b.lastMessageTimestamp == null)
              return 0;
            if (a.lastMessageTimestamp == null) return 1;
            if (b.lastMessageTimestamp == null) return -1;
            return b.lastMessageTimestamp!.compareTo(a.lastMessageTimestamp!);
          });

          return conversationsWithMetadata;
        } else {
          print('[ConversationService] ⚠️ Failed to load conversations (${response.statusCode}) - Using offline mode');
          return await _buildConversationsFromLocalDatabase();
        }
      } on FirebaseAuthException catch (e) {
        print('[ConversationService] ⚠️ Auth exception: $e - Using offline mode');
        return await _buildConversationsFromLocalDatabase();
      } catch (e) {
        print('[ConversationService] ⚠️ API failed: $e - Using offline mode');
        return await _buildConversationsFromLocalDatabase();
      }
    } else {
      print('[ConversationService] ⚠️ No active Firebase session yet - using local database');
      return await _buildConversationsFromLocalDatabase();
    }
  }

  Future<List<ConversationInfo>> _buildConversationsFromLocalDatabase() async {
    try {
      final dbService = DatabaseService.instance;
      await dbService.init();

      final uid = FirebaseAuth.instance.currentUser?.uid ?? AppStorage.cachedUid;
      if (uid == null) return [];

      final db = dbService.database;
      final result = await db.rawQuery(
        '''
        SELECT DISTINCT m.conversationId
        FROM messages m
        LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
        WHERE dm.message_id IS NULL
      ''',
        [uid],
      );

      final conversations = <ConversationInfo>[];

      for (final row in result) {
        final conversationId = row['conversationId'] as int;
        final unreadCount = await dbService.getUnreadMessageCount(
          conversationId,
          uid,
        );
        final lastMsg = await dbService.getLastMessage(conversationId);
        final allMessages = await dbService.getMessages(
          conversationId,
          limit: 50,
        );

        if (allMessages.isNotEmpty) {
          String? chatTitle;
          String? partnerUid;

          for (final message in allMessages) {
            if (message.senderUid != uid && message.senderUid != null) {
              chatTitle = message.username;
              partnerUid = message.senderUid;
              break;
            }
          }

          if (chatTitle == null) {
            chatTitle = allMessages.first.username;
          }

          conversations.add(
            ConversationInfo(
              conversationId: conversationId,
              chatTitle: chatTitle ?? 'Unknown',
              isGroup: false,
              partnerUid: partnerUid,
              hasUnreadMessages: unreadCount > 0,
              unreadCount: unreadCount,
              lastMessageTimestamp: lastMsg?.timestamp,
              lastMessage: lastMsg?.content,
            ),
          );
        }
      }

      conversations.sort((a, b) {
        if (a.lastMessageTimestamp == null && b.lastMessageTimestamp == null)
          return 0;
        if (a.lastMessageTimestamp == null) return 1;
        if (b.lastMessageTimestamp == null) return -1;
        return b.lastMessageTimestamp!.compareTo(a.lastMessageTimestamp!);
      });

      return conversations;
    } catch (e) {
      print('[ConversationService] ❌ Error building offline conversations: $e');
      return [];
    }
  }
}
