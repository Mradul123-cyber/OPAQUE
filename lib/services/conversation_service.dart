import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

import '../home_screen.dart';
import 'database_service.dart';

class ConversationService {
  final String _baseUrl = 'http://192.168.29.81:8080';
  
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
      );

      if (response.statusCode == 200) {
        // print('[ConversationService] === RAW BACKEND RESPONSE ===');
        // print('[ConversationService] Response body: ${response.body}');
        // print('[ConversationService] === END RAW RESPONSE ===');

        final List<dynamic> convosFromServer = json.decode(response.body);

        // Parse conversations first
        final baseConversations = convosFromServer
            .map((data) => ConversationInfo.fromJson(data))
            .toList();

        // Add unread status to each
        final conversationsWithUnread = <ConversationInfo>[];
        for (final convo in baseConversations) {
          final hasUnread = await dbService.hasUnreadMessages(
              convo.conversationId,
              user.uid
          );

          conversationsWithUnread.add(ConversationInfo(
            conversationId: convo.conversationId,
            chatTitle: convo.chatTitle,
            isGroup: convo.isGroup,
            creatorUid: convo.creatorUid,
            avatarUrl: convo.avatarUrl,
            partnerUid: convo.partnerUid,
            hasUnreadMessages: hasUnread,
          ));
        }

        return conversationsWithUnread;
      } else {
        throw Exception('Failed to load conversations: ${response.body}');
      }
    } on FirebaseAuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      throw Exception('An error occurred: $e');
    }
  }
}
