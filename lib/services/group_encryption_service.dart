import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'SignalService.dart';
import 'device_service.dart';
import 'package:zarq_messenger/app_config.dart';

class GroupEncryptionService {
  static const String baseUrl = '${AppConfig.baseUrl}';

  /// Distribute your sender key to the group
  /// Call this when:
  /// 1. You join a group
  /// 2. You create a group
  /// 3. A new member joins (to send them your key)
  static Future<bool> distributeSenderKey({
    required String groupId,
  }) async {
    try {
      // print('[GroupEncryption] Distributing sender key for group: $groupId');

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // print('[GroupEncryption] No user logged in');
        return false;
      }

      // Get device ID
      final deviceId = await SignalService.getDeviceId();
      if (deviceId == null) {
        // print('[GroupEncryption] Failed to get device ID');
        return false;
      }

      // Create sender key distribution message
      final senderKeyDistribution = await SignalService.createSenderKeyDistribution(
        groupId: groupId,
      );

      if (senderKeyDistribution == null) {
        // print('[GroupEncryption] Failed to create sender key distribution');
        return false;
      }

      // print('[GroupEncryption] Sender key created, length: ${senderKeyDistribution.length}');

      // Upload to backend
      final token = await user.getIdToken();
      final url = Uri.parse('$baseUrl/groups/$groupId/sender-keys/distribute');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'sender_key_distribution': senderKeyDistribution,
          'device_id': deviceId,
        }),
      );

      if (response.statusCode == 200) {
        // print('[GroupEncryption] ✅ Sender key distributed successfully');
        return true;
      } else {
        // print('[GroupEncryption] Failed to distribute sender key: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      // print('[GroupEncryption] Error distributing sender key: $e');
      return false;
    }
  }

  /// Fetch and process all sender keys from group members
  /// Call this before sending your first message or when a new member joins
  static Future<bool> fetchAndProcessGroupSenderKeys({
    required String groupId,
  }) async {
    try {
      // print('[GroupEncryption] Fetching sender keys for group: $groupId');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // print('[GroupEncryption] No user logged in');
        return false;
      }

      final token = await user.getIdToken();
      final url = Uri.parse('$baseUrl/groups/$groupId/sender-keys');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> senderKeys = json.decode(response.body);
        int successCount = 0;
        int eligibleKeys = 0;

        for (var key in senderKeys) {
          final senderUid = key['sender_uid'] as String?;
          final deviceId = key['device_id'] is int
              ? key['device_id'] as int
              : int.tryParse(key['device_id']?.toString() ?? '');
          final distribution = key['sender_key_distribution'] as String?;

          if (senderUid == null || deviceId == null || distribution == null) {
            continue;
          }

          // Skip our own sender key if returned by backend
          if (senderUid == user.uid) {
            continue;
          }

          eligibleKeys++;

          final success = await SignalService.processSenderKeyDistribution(
            senderUid: senderUid,
            senderDeviceId: deviceId,
            groupId: groupId,
            distributionMessage: distribution,
          );

          if (success) {
            successCount++;
          } else {
            debugPrint('[GroupEncryption] ⚠️ Could not process sender key from $senderUid:$deviceId');
          }
        }

        debugPrint('[GroupEncryption] Processed $successCount/$eligibleKeys sender keys for group $groupId');
        return true;
      } else {
        debugPrint('[GroupEncryption] Failed to fetch sender keys: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[GroupEncryption] Error fetching sender keys: $e');
      return false;
    }
  }

  /// Setup group encryption for a conversation
  /// This distributes your key and fetches others' keys
  static Future<bool> setupGroupEncryption({
    required String groupId,
  }) async {
    try {
      // Step 1: Distribute our sender key (allows sending encrypted messages to the group)
      final distributed = await distributeSenderKey(groupId: groupId);
      if (!distributed) {
        debugPrint('[GroupEncryption] ❌ Failed to distribute our sender key');
        return false;
      }

      // Step 2: Fetch and process other members' sender keys (allows decrypting their messages)
      // Even if some members are offline or haven't published keys yet, our sending setup is ready.
      await fetchAndProcessGroupSenderKeys(groupId: groupId);

      debugPrint('[GroupEncryption] ✅ Group encryption setup complete for group $groupId');
      return true;
    } catch (e) {
      debugPrint('[GroupEncryption] Error setting up group encryption: $e');
      return false;
    }
  }

  /// Rotate sender key for a group (e.g. after a member leaves or is removed).
  /// Clears existing sender keys for the group so Libsignal generates a completely
  /// fresh sender key, uploads it to backend, and fetches updated keys from remaining members.
  static Future<bool> rotateSenderKey({
    required String groupId,
  }) async {
    try {
      // Step 1: Clear local sender keys for this group
      // This wipes both our own old sender key (forcing Libsignal to generate a brand new key)
      // and old sender keys of other members (including any departed member).
      await clearGroupKeys(groupId: groupId);

      // Step 2: Create brand new sender key and upload to backend
      final distributed = await distributeSenderKey(groupId: groupId);
      if (!distributed) {
        return false;
      }

      // Step 3: Fetch and process fresh sender keys from all remaining members
      final processed = await fetchAndProcessGroupSenderKeys(groupId: groupId);
      return processed;
    } catch (e) {
      return false;
    }
  }

  /// Encrypt a message for a group
  static Future<String?> encryptGroupMessage({
    required String groupId,
    required String plaintext,
  }) async {
    try {
      // print('[GroupEncryption] Encrypting group message for: $groupId');

      final ciphertext = await SignalService.encryptGroupMessage(
        groupId: groupId,
        plaintext: plaintext,
      );

      if (ciphertext != null) {
        // print('[GroupEncryption] ✅ Group message encrypted');
      } else {
        // print('[GroupEncryption] ❌ Failed to encrypt group message');
      }

      return ciphertext;
    } catch (e) {
      // print('[GroupEncryption] Error encrypting group message: $e');
      return null;
    }
  }

  /// Decrypt a message from a group
  static Future<String?> decryptGroupMessage({
    required String senderUid,
    required int senderDeviceId,
    required String groupId,
    required String ciphertext,
  }) async {
    try {
      // print('[GroupEncryption] Decrypting group message from: $senderUid:$senderDeviceId');

      final plaintext = await SignalService.decryptGroupMessage(
        senderUid: senderUid,
        senderDeviceId: senderDeviceId,
        groupId: groupId,
        ciphertext: ciphertext,
      );

      if (plaintext != null) {
        // print('[GroupEncryption] ✅ Group message decrypted');
      } else {
        // print('[GroupEncryption] ❌ Failed to decrypt group message');
      }

      return plaintext;
    } catch (e) {
      // print('[GroupEncryption] Error decrypting group message: $e');
      return null;
    }
  }

  /// Clear all sender keys for a group (when leaving)
  static Future<bool> clearGroupKeys({
    required String groupId,
  }) async {
    try {
      // print('[GroupEncryption] Clearing group keys for: $groupId');

      final success = await SignalService.clearGroupSenderKeys(
        groupId: groupId,
      );

      if (success) {
        // print('[GroupEncryption] ✅ Group keys cleared');
      } else {
        // print('[GroupEncryption] ❌ Failed to clear group keys');
      }

      return success;
    } catch (e) {
      // print('[GroupEncryption] Error clearing group keys: $e');
      return false;
    }
  }
}
