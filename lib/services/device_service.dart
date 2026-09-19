import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/app_config.dart';

class DeviceService {
  // Replace with your backend base URL (use http://10.0.2.2:8080 for Android emulator)
  static const String baseUrl = '${AppConfig.baseUrl}';

  /// Register device + keys with the backend.
  /// - deviceId: integer device id (1 for first device)
  /// - deviceName, platform, pushToken: metadata
  /// - identityKeyB64, signedPreKeyB64, signatureB64, oneTimePreKeys: base64 strings
  static Future<Map<String, dynamic>> registerDevice({
    required int deviceId,
    required String deviceName,
    required String platform,
    required String pushToken,
    required String identityKeyB64,
    required int registrationId,
    required int signedPreKeyId,
    required String signedPreKeyB64,
    required String signedPreKeySignatureB64,
    required List<Map<String, dynamic>> oneTimePreKeys, // [{ "key_id":1, "public_key_b64":"..." }, ...]
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final idToken = await user.getIdToken(true);

    final uri = Uri.parse('$baseUrl/v1/devices/register');

    final body = {
      // server uses authenticated UID; we don't send firebase_uid intentionally
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      'push_token': pushToken,
      'identity_key_b64': identityKeyB64,
      'registration_id': registrationId,
      'signed_prekey': {
        'key_id': signedPreKeyId,
        'public_key_b64': signedPreKeyB64,
        'signature_b64': signedPreKeySignatureB64,
      },
      'one_time_prekeys': oneTimePreKeys,
    };

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Device registration failed: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data;
  }

  static Future<Map<String, dynamic>?> fetchPrekeyBundle({
    required String targetUid,
    required int deviceId,
    String baseUrl = baseUrl, // uses your DeviceService.baseUrl constant
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final idToken = await user.getIdToken(true);

    final uri = Uri.parse('$baseUrl/v1/prekey_bundle?uid=$targetUid&device_id=$deviceId');

    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data;
    } else if (resp.statusCode == 404) {
      // no bundle / user not found
      return null;
    } else {
      // propagate other errors with helpful message
      throw Exception('fetchPrekeyBundle failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Send an encrypted message to a conversation.
  /// For testing we send a dummy base64 ciphertext. Replace contentB64 with real ciphertext later.
  static Future<Map<String, dynamic>> sendMessage({
    required int conversationId,
    required String contentB64,
    String? sessionContext, // Add this parameter
    int? replyToMessageId, // Reply-to message ID
    String baseUrl = baseUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final idToken = await user.getIdToken(true);

    final requestBody = {
      'conversation_id': conversationId,
      'content_b64': contentB64,
      'message_type': 'chat',
    };

    // print("HTTP DEBUG: Request body content_b64 length: ${contentB64.length}");
    // print("HTTP DEBUG: Request body first 20: ${contentB64.substring(0, min(20, contentB64.length))}");

    // Add session context if provided
    if (sessionContext != null) {
      requestBody['session_context_b64'] = sessionContext;
    }

    // Add reply_to_message_id if provided
    if (replyToMessageId != null) {
      requestBody['replyToMessageId'] = replyToMessageId;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/v1/messages/send'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  static Future<bool> uploadRotatedKeys({
    required int deviceId,
    Map<String, dynamic>? signedPreKey,
    List<Map<String, dynamic>>? oneTimePreKeys,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final idToken = await user.getIdToken(true);
      final uri = Uri.parse('$baseUrl/v1/prekeys/update');

      final body = <String, dynamic>{
        'device_id': deviceId,
      };

      if (signedPreKey != null) body['signed_prekey'] = signedPreKey;
      if (oneTimePreKeys != null) body['one_time_prekeys'] = oneTimePreKeys;

      // print('[Upload] Request URL: $uri');
      // print('[Upload] Request body: ${jsonEncode(body)}');

      final resp = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(body),
      );

      // print('[Upload] Response status: ${resp.statusCode}');
      // print('[Upload] Response body: ${resp.body}');

      return resp.statusCode == 200;
    } catch (e) {
      // print('[Upload] Error: $e');
      return false;
    }
  }

  static Future<int?> getActiveDeviceId(String userUid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final idToken = await user.getIdToken(true);
      final uri = Uri.parse('$baseUrl/v1/users/$userUid/device');

      final resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Accept': 'application/json',
        },
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['device_id'] as int?;
      } else if (resp.statusCode == 404) {
        // print('DeviceService: User $userUid has no registered device');
        return null;
      } else {
        throw Exception('Failed to get device ID: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      // print('DeviceService.getActiveDeviceId error: $e');
      return null;
    }
  }

}