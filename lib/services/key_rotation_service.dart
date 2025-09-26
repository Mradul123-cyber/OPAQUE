import 'dart:async';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/device_service.dart';

class KeyRotationService {
  static Timer? _rotationTimer;

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
      print('[KeyRotation] Starting background key rotation...');

      // Check if rotation needed
      final stats = await SignalService.getEncryptionStats();
      if (stats?['needs_signed_prekey_rotation'] == true) {
        await _rotateSigned();
      }

      // Replenish prekeys if low
      await _replenishPreKeys();

      print('[KeyRotation] Background key rotation completed');
    } catch (e) {
      print('[KeyRotation] Error during background rotation: $e');
    }
  }

  static Future<void> _rotateSigned() async {
    try {
      print('[KeyRotation] Rotating signed prekey...');

      // Rotate signed prekey locally
      final rotationSuccess = await SignalService.rotateSignedPreKey();
      if (!rotationSuccess) {
        print('[KeyRotation] Local signed prekey rotation failed');
        return;
      }

      // Get device ID and new key bundle info
      final deviceId = await SignalService.getDeviceId();
      final keyBundle = await SignalService.generateKeyBundle();

      if (deviceId != null && keyBundle != null) {
        // Prepare signed prekey data for upload
        final signedPreKeyData = {
          'key_id': keyBundle['signed_prekey_id'],
          'public_key_b64': keyBundle['signed_prekey_b64'],
          'signature_b64': keyBundle['signed_prekey_signature_b64'],
        };

        // Upload to backend
        final uploadSuccess = await DeviceService.uploadRotatedKeys(
          deviceId: deviceId,
          signedPreKey: signedPreKeyData,
        );

        if (uploadSuccess) {
          print('[KeyRotation] Signed prekey uploaded successfully');
        } else {
          print('[KeyRotation] Failed to upload rotated signed prekey');
        }
      }
    } catch (e) {
      print('[KeyRotation] Error rotating signed prekey: $e');
    }
  }

  static Future<void> _replenishPreKeys() async {
    try {
      print('[KeyRotation] Checking one-time prekey count...');

      // Generate additional prekeys
      final newPreKeys = await SignalService.generateAdditionalPreKeys(count:100);
      if (newPreKeys.isEmpty) {
        print('[KeyRotation] No new prekeys generated');
        return;
      }

      // Get device ID
      final deviceId = await SignalService.getDeviceId();
      if (deviceId == null) {
        print('[KeyRotation] Could not get device ID for prekey upload');
        return;
      }

      // Upload new prekeys to backend
      final uploadSuccess = await DeviceService.uploadRotatedKeys(
        deviceId: deviceId,
        oneTimePreKeys: newPreKeys,
      );

      if (uploadSuccess) {
        print('[KeyRotation] ${newPreKeys.length} new prekeys uploaded successfully');
      } else {
        print('[KeyRotation] Failed to upload new prekeys');
      }
    } catch (e) {
      print('[KeyRotation] Error replenishing prekeys: $e');
    }
  }
}