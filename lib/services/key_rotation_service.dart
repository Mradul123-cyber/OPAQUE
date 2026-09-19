import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/device_service.dart';
import 'package:zarq_messenger/app_config.dart';

class KeyRotationService {
  static Timer? _rotationTimer;

  static const String baseUrl = '${AppConfig.baseUrl}';


  static Future<Map<String, String>> _getAuthHeaders() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final idToken = await user.getIdToken(true);
      return {
        'Authorization': 'Bearer $idToken',
        'Accept': 'application/json',
      };
    } catch (e) {
      // print('[KeyRotation] Error getting auth headers: $e');
      throw Exception('Failed to get auth headers: $e');
    }
  }

  static Future<void> checkThresholdAfterKeyConsumption({
    required String currentUserUid,
    required int deviceId,
  }) async {
    try {
      // print('[KeyRotation] Checking threshold for user: $currentUserUid, device: $deviceId');

      // Fixed URL to match Go handler
      final response = await http.get(
        Uri.parse('$baseUrl/v1/prekeys/count/$currentUserUid/$deviceId'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final remainingKeys = data['remaining'] as int? ?? 100;

        // print('[KeyRotation] Current available keys: $remainingKeys');

        if (remainingKeys < 20) {
          // print('[KeyRotation] THRESHOLD REACHED! Triggering immediate rotation');
          await _performKeyRotation();
        } else {
          // print('[KeyRotation] Keys sufficient ($remainingKeys), no rotation needed');
        }
      } else {
        // print('[KeyRotation] Failed to get key count: ${response.statusCode}');
      }
    } catch (e) {
      // print('[KeyRotation] Error checking threshold: $e');
    }
  }


  static void startBackgroundRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(Duration(days: 7), (_) {
      _performKeyRotation();
    });
  }

  static void stopBackgroundRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
  }

  static Future<void> _performKeyRotation() async {
    try {
      // print('[KeyRotation] Starting background key rotation...');

      // Check if rotation needed
      final stats = await SignalService.getEncryptionStats();
      if (stats?['needs_signed_prekey_rotation'] == true) {
        await _rotateSigned();
      }

      // Replenish prekeys if low
      await _replenishPreKeys();

      // print('[KeyRotation] Background key rotation completed');
    } catch (e) {
      // print('[KeyRotation] Error during background rotation: $e');
    }
  }


  static Future<void> _rotateSigned() async {
    try {
      // print('[KeyRotation] Rotating signed prekey...');

      // Rotate signed prekey locally
      final rotationSuccess = await SignalService.rotateSignedPreKey();
      if (!rotationSuccess) {
        // print('[KeyRotation] Local signed prekey rotation failed');
        return;
      }
      // print('[KeyRotation] ✓ Local signed prekey rotation successful');

      // Get device ID and new key bundle info
      final deviceId = await SignalService.getDeviceId();

      final signedPreKeyData = await SignalService.getCurrentSignedPreKey();

      if (deviceId != null && signedPreKeyData != null) {

        // Prepare signed prekey data for upload

        // Check if the data looks valid
        final pubKey = signedPreKeyData['public_key_b64']?.toString() ?? '';
        final signature = signedPreKeyData['signature_b64']?.toString() ?? '';


        if (pubKey.length < 40 || signature.length < 40) {
          // print('[KeyRotation] ✗ Invalid key data - too short');
          return;
        }

        // Upload to backend
        try {
          final uploadSuccess = await DeviceService.uploadRotatedKeys(
            deviceId: deviceId,
            signedPreKey: signedPreKeyData,
          );

          if (uploadSuccess) {
            // print('[KeyRotation] ✓ Signed prekey uploaded successfully');
          } else {
            // print('[KeyRotation] ✗ Backend returned false for signed prekey upload');
          }
        } catch (uploadError) {
          // print('[KeyRotation] ✗ Exception during upload: $uploadError');
        }
      } else {
        // print('[KeyRotation] ✗ Missing data: deviceId=$deviceId, keyBundle=${signedPreKeyData != null}');
      }
    } catch (e) {
      // print('[KeyRotation] Error rotating signed prekey: $e');
    }
  }

  static Future<void> _replenishPreKeys() async {
    try {
      // print('[KeyRotation] Checking one-time prekey count...');

      // Generate additional prekeys
      final newPreKeys = await SignalService.generateAdditionalPreKeys(count:100);
      if (newPreKeys.isEmpty) {
        // print('[KeyRotation] No new prekeys generated');
        return;
      }

      // Get device ID
      final deviceId = await SignalService.getDeviceId();
      if (deviceId == null) {
        // print('[KeyRotation] Could not get device ID for prekey upload');
        return;
      }

      // Upload new prekeys to backend
      final uploadSuccess = await DeviceService.uploadRotatedKeys(
        deviceId: deviceId,
        oneTimePreKeys: newPreKeys,
      );

      if (uploadSuccess) {
        // print('[KeyRotation] ${newPreKeys.length} new prekeys uploaded successfully');
      } else {
        // print('[KeyRotation] Failed to upload new prekeys');
      }
    } catch (e) {
      // print('[KeyRotation] Error replenishing prekeys: $e');
    }
  }

  // ============ GROUP SENDER KEY ROTATION ============

  /// Check and perform periodic rotation if needed (30 days or 10000 messages)
  static Future<Map<String, dynamic>> checkPeriodicRotation({required int groupId}) async {
    try {
      // print('[KeyRotation] 🔍 Checking periodic rotation for group $groupId...');

      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/groups/$groupId/check-rotation'),
        headers: {...headers, 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rotated = data['rotated'] as bool? ?? false;

        if (rotated) {
          // print('[KeyRotation] 🔄 Periodic rotation triggered: ${data['reason']}');
        } else {
          // print('[KeyRotation] ✅ No rotation needed (${data['days_since_rotation']} days, ${data['messages_since_rotation']} messages)');
        }

        return data;
      } else {
        // print('[KeyRotation] ❌ Check rotation failed: ${response.statusCode}');
        return {'rotated': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      // print('[KeyRotation] ❌ Error checking periodic rotation: $e');
      return {'rotated': false, 'error': e.toString()};
    }
  }
}