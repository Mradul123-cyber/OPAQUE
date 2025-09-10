import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class DeviceService {
  // Replace with your backend base URL (use http://10.0.2.2:8080 for Android emulator)
  static const String baseUrl = 'http://192.168.29.81:8080';

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
}
