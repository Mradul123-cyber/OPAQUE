import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'device_service.dart';

class SignalService {
  static const MethodChannel _channel = MethodChannel('com.zarq/signal');

  /// Test method to verify Signal method channel is working
  static Future<String?> ping() async {
    try {
      // print('=== SignalService.ping START ===');

      final result = await _channel.invokeMethod('ping');

      // print('Signal ping result: $result');
      // print('=== SignalService.ping END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.ping PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.ping error: $e');
      return null;
    }
  }

  /// Get the unique device ID for this installation
  static Future<int?> getDeviceId() async {
    try {
      // print('=== SignalService.getDeviceId START ===');

      final result = await _channel.invokeMethod('getDeviceId');

      // print('Device ID: $result');
      // print('=== SignalService.getDeviceId END ===');

      return result as int?;
    } on PlatformException catch (e) {
      // print('SignalService.getDeviceId PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.getDeviceId error: $e');
      return null;
    }
  }

  /// Get the Identity Key Pair private key for database encryption
  /// Returns base64 encoded 32-byte private key
  static Future<String?> getIdentityKeyPrivateKey() async {
    try {
      // print('=== SignalService.getIdentityKeyPrivateKey START ===');

      final result = await _channel.invokeMethod('getIdentityKeyPrivateKey');

      // print('Identity key private key retrieved for database encryption');
      // print('=== SignalService.getIdentityKeyPrivateKey END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.getIdentityKeyPrivateKey PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.getIdentityKeyPrivateKey error: $e');
      return null;
    }
  }

  /// Check if Signal Protocol keys have already been generated
  static Future<bool> hasKeys() async {
    try {
      // print('=== SignalService.hasKeys START ===');

      final result = await _channel.invokeMethod('hasKeys');

      // print('hasKeys result: $result');
      // print('=== SignalService.hasKeys END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.hasKeys PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.hasKeys error: $e');
      return false;
    }
  }

  /// Generate Signal Protocol key bundle (IdentityKey, SignedPreKey, OneTimePreKeys)
  static Future<Map<String, dynamic>?> generateKeyBundle() async {
    try {
      // print('=== SignalService.generateKeyBundle START ===');

      final result = await _channel.invokeMethod('generateKeyBundle');

      if (result != null) {
        final keyBundle = Map<String, dynamic>.from(result);
        // print('Key bundle generated successfully:');
        // print('- Identity Key: ${keyBundle['identity_key_b64']?.toString().substring(0, 20)}...');
        // print('- Registration ID: ${keyBundle['registration_id']}');
        // print('- Device ID: ${keyBundle['device_id']}'); // Now shows actual device ID
        // print('- Signed PreKey ID: ${keyBundle['signed_prekey_id']}');
        // print('- One-Time PreKeys count: ${(keyBundle['one_time_prekeys'] as List?)?.length ?? 0}');
        // print('=== SignalService.generateKeyBundle END ===');

        return keyBundle;
      } else {
        // print('Key bundle generation returned null');
        return null;
      }
    } on PlatformException catch (e) {
      // print('SignalService.generateKeyBundle PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.generateKeyBundle error: $e');
      return null;
    }
  }

  /// Get the current registration ID
  static Future<int?> getRegistrationId() async {
    try {
      // print('=== SignalService.getRegistrationId START ===');

      final result = await _channel.invokeMethod('getRegistrationId');

      // print('Registration ID: $result');
      // print('=== SignalService.getRegistrationId END ===');

      return result as int?;
    } on PlatformException catch (e) {
      // print('SignalService.getRegistrationId PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.getRegistrationId error: $e');
      return null;
    }
  }

  /// Clear all Signal Protocol keys (for logout/reset)
  static Future<bool> clearKeys() async {
    try {
      // print('=== SignalService.clearKeys START ===');

      final result = await _channel.invokeMethod('clearKeys');

      // print('Clear keys result: $result');
      // print('=== SignalService.clearKeys END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.clearKeys PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.clearKeys error: $e');
      return false;
    }
  }

  /// Test method to verify prekey bundle placeholder (still unimplemented)
  static Future<Map<String, dynamic>?> testGetPreKeyBundle() async {
    try {
      // print('=== SignalService.testGetPreKeyBundle START ===');

      final result = await _channel.invokeMethod('getPreKeyBundle');

      // print('Get prekey bundle result: $result');
      // print('=== SignalService.testGetPreKeyBundle END ===');

      return result as Map<String, dynamic>?;
    } on PlatformException catch (e) {
      // print('SignalService.testGetPreKeyBundle PlatformException: ${e.code} - ${e.message}');
      // print('This is expected - method not implemented yet');
      return null;
    } catch (e) {
      // print('SignalService.testGetPreKeyBundle error: $e');
      return null;
    }
  }

  static Future<bool> establishSession({
    required String recipientUid,
    required Map<String, dynamic> prekeyBundle,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.establishSession START ===');
      // print('Establishing session with: $recipientUid');
      // print('Bundle contains: ${prekeyBundle.keys.toList()}');

      final params = <String, dynamic>{
        'recipientUid': recipientUid,
        'prekeyBundle': prekeyBundle,
      };

      // Only add deviceId if explicitly provided
      if (deviceId != null) {
        params['deviceId'] = deviceId;
      }

      final result = await _channel.invokeMethod('establishSession', params);

      // print('Session establishment result: $result');
      // print('=== SignalService.establishSession END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.establishSession PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.establishSession error: $e');
      return false;
    }
  }

  /// Upload rotated keys to backend without full re-registration
  static Future<bool> uploadRotatedKeys({
    required int deviceId,
    Map<String, dynamic>? signedPreKey,
    List<Map<String, dynamic>>? oneTimePreKeys,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final idToken = await user.getIdToken(true);
      final uri = Uri.parse('${DeviceService.baseUrl}/v1/prekeys/update');

      final body = <String, dynamic>{
        'device_id': deviceId,
      };

      if (signedPreKey != null) body['signed_prekey'] = signedPreKey;
      if (oneTimePreKeys != null) body['one_time_prekeys'] = oneTimePreKeys;

      final resp = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(body),
      );

      return resp.statusCode == 200;
    } catch (e) {
      // print('uploadRotatedKeys error: $e');
      return false;
    }
  }

  /// Check if we have a session with a specific user
  static Future<bool> hasSession({
    required String recipientUid,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.hasSession START ===');
      // print('Checking session with: $recipientUid${deviceId != null ? ':$deviceId' : ''}');

      final params = <String, dynamic>{
        'recipientUid': recipientUid,
      };

      // Only add deviceId if explicitly provided
      if (deviceId != null) {
        params['deviceId'] = deviceId;
      }

      final result = await _channel.invokeMethod('hasSession', params);

      // print('hasSession result: $result');
      // print('=== SignalService.hasSession END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.hasSession PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.hasSession error: $e');
      return false;
    }
  }

  static Future<bool> resetUserContext() async {
    try {
      // print('=== SignalService.resetUserContext START ===');

      final result = await _channel.invokeMethod('resetUserContext');

      // print('Reset user context result: $result');
      // print('=== SignalService.resetUserContext END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.resetUserContext PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.resetUserContext error: $e');
      return false;
    }
  }

  /// Remove session with a user (for testing)
  static Future<bool> removeSession({
    required String recipientUid,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.removeSession START ===');
      // print('Removing session with: $recipientUid${deviceId != null ? ':$deviceId' : ''}');

      final params = <String, dynamic>{
        'recipientUid': recipientUid,
      };

      // Only add deviceId if explicitly provided
      if (deviceId != null) {
        params['deviceId'] = deviceId;
      }

      final result = await _channel.invokeMethod('removeSession', params);

      // print('removeSession result: $result');
      // print('=== SignalService.removeSession END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.removeSession PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.removeSession error: $e');
      return false;
    }
  }

  static Future<bool> isSessionValidForSending({
    required String recipientUid,
    required int deviceId,
  }) async {
    try {
      final result = await _channel.invokeMethod('isSessionValidForSending', {
        'recipientUid': recipientUid,
        'deviceId': deviceId,
      });
      return result as bool? ?? false;
    } catch (e) {
      // print('SignalService.isSessionValidForSending error: $e');
      return false;
    }
  }

  /// Reset session when decryption fails due to identity key change
  /// This forces session re-establishment on next send
  static Future<void> resetSessionDueToDecryptionFailure({
    required String senderUid,
    required int senderDeviceId,
  }) async {
    try {
      // print('🔄 SignalService: Resetting stale session for $senderUid:$senderDeviceId');
      await _channel.invokeMethod('resetSessionDueToDecryptionFailure', {
        'senderUid': senderUid,
        'senderDeviceId': senderDeviceId,
      });
      // print('✅ Session reset successful - will re-establish on next message');
    } catch (e) {
      // print('SignalService.resetSessionDueToDecryptionFailure error: $e');
    }
  }

  /// Encrypt a plaintext message for a recipient
  static Future<String?> encryptMessage({
    required String recipientUid,
    required String plaintext,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.encryptMessage START ===');
      // print('Encrypting for: $recipientUid');
      // print('Plaintext length: ${plaintext.length}');

      final params = <String, dynamic>{
        'recipientUid': recipientUid,
        'plaintext': plaintext,
      };

      // Only add deviceId if explicitly provided
      if (deviceId != null) {
        params['deviceId'] = deviceId;
      }

      final result = await _channel.invokeMethod('encryptMessage', params);

      if (result != null) {
        // print('Encryption successful, ciphertext length: ${result.toString().length}');
      } else {
        // print('Encryption failed - null result');
      }
      // print('=== SignalService.encryptMessage END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.encryptMessage PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.encryptMessage error: $e');
      return null;
    }
  }


  /// Decrypt a received message from a sender
  static Future<String?> decryptMessage({
    required String senderUid,
    required String ciphertextB64,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.decryptMessage START ===');
      // print('Decrypting from: $senderUid');
      // print('Ciphertext length: ${ciphertextB64.length}');

      final params = <String, dynamic>{
        'senderUid': senderUid,
        'ciphertextB64': ciphertextB64,
      };

      // FIX: Use correct parameter name that matches MainActivity
      if (deviceId != null) {
        params['senderDeviceId'] = deviceId;  // ✅ FIXED: was 'deviceId', now 'senderDeviceId'
      } else {
        // Throw error if deviceId is not provided for decryption
        throw Exception('Device ID is required for message decryption');
      }

      final result = await _channel.invokeMethod('decryptMessage', params);

      if (result != null) {
        // print('Decryption successful, plaintext length: ${result.toString().length}');
      } else {
        // print('Decryption failed - null result');
      }
      // print('=== SignalService.decryptMessage END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.decryptMessage PlatformException: ${e.code} - ${e.message}');
      // print('SignalService.decryptMessage PlatformException details: $e');
      return null;
    } catch (e, stackTrace) {
      // print('SignalService.decryptMessage error: $e');
      // print('SignalService.decryptMessage stackTrace: $stackTrace');
      return null;
    }
  }
  /// Encrypt message with automatic session establishment if needed
  static Future<String?> encryptMessageWithSessionSetup({
    required String recipientUid,
    required String plaintext,
    Map<String, dynamic>? prekeyBundle,
    int? deviceId, // Made nullable - will use actual device ID if not provided
  }) async {
    try {
      // print('=== SignalService.encryptMessageWithSessionSetup START ===');
      // print('Recipient: $recipientUid');
      // print('Has prekey bundle: ${prekeyBundle != null}');

      final params = <String, dynamic>{
        'recipientUid': recipientUid,
        'plaintext': plaintext,
        'prekeyBundle': prekeyBundle,
      };

      // Only add deviceId if explicitly provided
      if (deviceId != null) {
        params['deviceId'] = deviceId;
      }

      final result = await _channel.invokeMethod('encryptMessageWithSessionSetup', params);

      // print('Encrypt with session setup result: ${result != null ? "SUCCESS" : "FAILED"}');
      // print('=== SignalService.encryptMessageWithSessionSetup END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.encryptMessageWithSessionSetup PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.encryptMessageWithSessionSetup error: $e');
      return null;
    }
  }

  /// Get encryption statistics and status
  static Future<Map<String, dynamic>?> getEncryptionStats() async {
    try {
      // print('=== SignalService.getEncryptionStats START ===');

      final result = await _channel.invokeMethod('getEncryptionStats');

      if (result != null) {
        final stats = Map<String, dynamic>.from(result);
        // print('Encryption stats retrieved: ${stats.keys.toList()}');
        // print('=== SignalService.getEncryptionStats END ===');
        return stats;
      } else {
        // print('Failed to get encryption stats');
        return null;
      }
    } on PlatformException catch (e) {
      // print('SignalService.getEncryptionStats PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.getEncryptionStats error: $e');
      return null;
    }
  }

  /// Rotate signed prekey for forward secrecy
  static Future<bool> rotateSignedPreKey() async {
    try {
      // print('=== SignalService.rotateSignedPreKey START ===');

      final result = await _channel.invokeMethod('rotateSignedPreKey');

      // print('Rotate signed prekey result: $result');
      // print('=== SignalService.rotateSignedPreKey END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.rotateSignedPreKey PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.rotateSignedPreKey error: $e');
      return false;
    }
  }

  /// Generate additional one-time prekeys
  static Future<List<Map<String, dynamic>>> generateAdditionalPreKeys({int count = 100}) async {
    try {
      // print('=== SignalService.generateAdditionalPreKeys START ===');
      // print('Generating $count additional prekeys...');

      final result = await _channel.invokeMethod('generateAdditionalPreKeys', {
        'count': count,
      });

      if (result != null && result is List) {
        final preKeys = result.map((item) => Map<String, dynamic>.from(item)).toList();
        // print('Generated ${preKeys.length} additional prekeys');
        // print('=== SignalService.generateAdditionalPreKeys END ===');
        return preKeys;
      } else {
        // print('Failed to generate additional prekeys');
        return [];
      }
    } on PlatformException catch (e) {
      // print('SignalService.generateAdditionalPreKeys PlatformException: ${e.code} - ${e.message}');
      return [];
    } catch (e) {
      // print('SignalService.generateAdditionalPreKeys error: $e');
      return [];
    }
  }

  /// Perform security audit of the Signal Protocol setup
  static Future<Map<String, dynamic>?> performSecurityAudit() async {
    try {
      // print('=== SignalService.performSecurityAudit START ===');

      final result = await _channel.invokeMethod('performSecurityAudit');

      if (result != null) {
        final audit = Map<String, dynamic>.from(result);
        // print('Security audit completed: ${audit['security_level']}');
        // print('Security score: ${audit['security_score']}/100');
        // print('=== SignalService.performSecurityAudit END ===');
        return audit;
      } else {
        // print('Failed to perform security audit');
        return null;
      }
    } on PlatformException catch (e) {
      // print('SignalService.performSecurityAudit PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.performSecurityAudit error: $e');
      return null;
    }
  }

  /// Get the current signed prekey data for upload
  static Future<Map<String, dynamic>?> getCurrentSignedPreKey() async {
    try {
      final result = await _channel.invokeMethod('getCurrentSignedPreKey');
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      // print('getCurrentSignedPreKey error: $e');
      return null;
    }
  }

  // ========== GROUP ENCRYPTION METHODS (Sender Keys Protocol) ==========

  /// Create a sender key distribution message for a group
  /// This should be called when:
  /// 1. You first join a group
  /// 2. A new member joins (send them your key)
  /// 3. You rotate your key (after member leaves)
  ///
  /// Returns base64-encoded distribution message to send to all group members
  static Future<String?> createSenderKeyDistribution({
    required String groupId,
  }) async {
    try {
      // print('=== SignalService.createSenderKeyDistribution START ===');
      // print('Creating sender key distribution for group: $groupId');

      final result = await _channel.invokeMethod('createSenderKeyDistribution', {
        'groupId': groupId,
      });

      if (result != null) {
        // print('Sender key distribution created, length: ${result.toString().length}');
      } else {
        // print('Failed to create sender key distribution');
      }
      // print('=== SignalService.createSenderKeyDistribution END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.createSenderKeyDistribution PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.createSenderKeyDistribution error: $e');
      return null;
    }
  }

  /// Process a sender key distribution message from another group member
  /// This stores their sender key so you can decrypt their messages
  ///
  /// Call this when you receive a distribution message from another member
  static Future<bool> processSenderKeyDistribution({
    required String senderUid,
    required int senderDeviceId,
    required String groupId,
    required String distributionMessage,
  }) async {
    try {
      // print('=== SignalService.processSenderKeyDistribution START ===');
      // print('Processing sender key from: $senderUid:$senderDeviceId for group: $groupId');

      final result = await _channel.invokeMethod('processSenderKeyDistribution', {
        'senderUid': senderUid,
        'senderDeviceId': senderDeviceId,
        'groupId': groupId,
        'distributionMessage': distributionMessage,
      });

      // print('Sender key distribution processed: ${result == true}');
      // print('=== SignalService.processSenderKeyDistribution END ===');

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.processSenderKeyDistribution PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.processSenderKeyDistribution error: $e');
      return false;
    }
  }

  /// Encrypt a message for a group using Sender Keys
  /// Much more efficient than encrypting individually for each member
  ///
  /// Returns base64-encoded ciphertext
  static Future<String?> encryptGroupMessage({
    required String groupId,
    required String plaintext,
  }) async {
    try {
      // print('=== SignalService.encryptGroupMessage START ===');
      // print('Encrypting group message for group: $groupId');
      // print('Plaintext length: ${plaintext.length}');

      final result = await _channel.invokeMethod('encryptGroupMessage', {
        'groupId': groupId,
        'plaintext': plaintext,
      });

      if (result != null) {
        // print('Group message encrypted, ciphertext length: ${result.toString().length}');
      } else {
        // print('Failed to encrypt group message');
      }
      // print('=== SignalService.encryptGroupMessage END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.encryptGroupMessage PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.encryptGroupMessage error: $e');
      return null;
    }
  }

  /// Decrypt a group message using Sender Keys
  ///
  /// Returns decrypted plaintext message
  static Future<String?> decryptGroupMessage({
    required String senderUid,
    required int senderDeviceId,
    required String groupId,
    required String ciphertext,
  }) async {
    try {
      // print('=== SignalService.decryptGroupMessage START ===');
      // print('Decrypting group message from: $senderUid:$senderDeviceId in group: $groupId');

      final result = await _channel.invokeMethod('decryptGroupMessage', {
        'senderUid': senderUid,
        'senderDeviceId': senderDeviceId,
        'groupId': groupId,
        'ciphertext': ciphertext,
      });

      if (result != null) {
        // print('Group message decrypted, plaintext length: ${result.toString().length}');
      } else {
        // print('Failed to decrypt group message - may not have sender key yet');
      }
      // print('=== SignalService.decryptGroupMessage END ===');

      return result as String?;
    } on PlatformException catch (e) {
      // print('SignalService.decryptGroupMessage PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // print('SignalService.decryptGroupMessage error: $e');
      return null;
    }
  }

  /// Clear all sender keys for a group (when leaving or group deleted)
  static Future<bool> clearGroupSenderKeys({
    required String groupId,
  }) async {
    try {
      // print('SignalService.clearGroupSenderKeys for group: $groupId');

      final result = await _channel.invokeMethod('clearGroupSenderKeys', {
        'groupId': groupId,
      });

      return result == true;
    } on PlatformException catch (e) {
      // print('SignalService.clearGroupSenderKeys PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      // print('SignalService.clearGroupSenderKeys error: $e');
      return false;
    }
  }
}