import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:zarq_messenger/app_config.dart';

class DeletionService {
  static const String baseUrl = '${AppConfig.baseUrl}';

  static Future<bool> deleteMessage({
    required int messageId,
    required String deletionType, // 'delete_for_me' or 'delete_for_everyone'
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // print('[DeletionService] ERROR: No authenticated user');
      return false;
    }

    try {
      final token = await user.getIdToken();
      // print('[DeletionService] Deleting message $messageId with type: $deletionType');

      final response = await http.delete(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'deletion_type': deletionType,
        }),
      );

      // print('[DeletionService] Response status: ${response.statusCode}');
      // print('[DeletionService] Response body: ${response.body}');

      if (response.statusCode == 200) {
        // print('[DeletionService] Delete successful for message $messageId');
        return true;
      } else {
        // print('[DeletionService] Delete failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      // print('[DeletionService] Exception deleting message: $e');
      return false;
    }
  }
}