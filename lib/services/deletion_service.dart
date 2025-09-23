import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class DeletionService {
  static const String baseUrl = 'http://192.168.29.81:8080';

  static Future<bool> deleteMessage({
    required int messageId,
    required String deletionType, // 'delete_for_me' or 'delete_for_everyone'
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final token = await user.getIdToken();
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

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting message: $e');
      return false;
    }
  }
}