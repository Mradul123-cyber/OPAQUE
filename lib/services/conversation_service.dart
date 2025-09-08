import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

import '../home_screen.dart';

class ConversationService {
  final String _baseUrl = 'http://192.168.29.81:8080';
  
  // Fetches the list of conversations for the currently logged-in user.
  Future<List<ConversationInfo>> fetchConversations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // If no user is logged in, return an empty list.
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
        // Successfully fetched data.
        final List<dynamic> convosFromServer = json.decode(response.body);
        return convosFromServer
            .map((data) => ConversationInfo.fromJson(data))
            .toList();
      } else {
        // If the server returns an error, throw an exception to be caught by the UI.
        throw Exception('Failed to load conversations: ${response.body}');
      }
    } on FirebaseAuthException catch (e) {
      // Handle potential errors from getting the token.
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      // Handle other errors like network issues.
      throw Exception('An error occurred: $e');
    }
  }
}
