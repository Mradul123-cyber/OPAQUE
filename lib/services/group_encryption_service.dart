import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'SignalService.dart';
import 'device_service.dart';

class GroupEncryptionService {
  static const String baseUrl = 'https://api.zarqmessenger.com';

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
        // print('[GroupEncryption] Received ${senderKeys.length} sender keys');

        int successCount = 0;
        for (var key in senderKeys) {
          final senderUid = key['sender_uid'] as String;
          final deviceId = key['device_id'] as int;
          final distribution = key['sender_key_distribution'] as String;

          // print('[GroupEncryption] Processing sender key from: $senderUid:$deviceId');

          final success = await SignalService.processSenderKeyDistribution(
            senderUid: senderUid,
            senderDeviceId: deviceId,
            groupId: groupId,
            distributionMessage: distribution,
          );

          if (success) {
            successCount++;
            // print('[GroupEncryption] ✅ Processed sender key from $senderUid:$deviceId');
          } else {
            // print('[GroupEncryption] ❌ Failed to process sender key from $senderUid:$deviceId');
          }
        }

        // print('[GroupEncryption] Processed $successCount/${senderKeys.length} sender keys');
        return successCount == senderKeys.length;
      } else {
        // print('[GroupEncryption] Failed to fetch sender keys: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      // print('[GroupEncryption] Error fetching sender keys: $e');
      return false;
    }
  }

  /// Setup group encryption for a conversation
  /// This distributes your key and fetches others' keys
  static Future<bool> setupGroupEncryption({
    required String groupId,
  }) async {
    try {
      // print('[GroupEncryption] 🔐 Setting up group encryption for: $groupId');

      // Step 1: Distribute our sender key
      final distributed = await distributeSenderKey(groupId: groupId);
      if (!distributed) {
        // print('[GroupEncryption] Failed to distribute sender key');
        return false;
      }

      // Step 2: Fetch and process all other members' sender keys
      final processed = await fetchAndProcessGroupSenderKeys(groupId: groupId);
      if (!processed) {
        // print('[GroupEncryption] Failed to process all sender keys');
        return false;
      }

      // print('[GroupEncryption] ✅ Group encryption setup complete for group $groupId');
      return true;
    } catch (e) {
      // print('[GroupEncryption] Error setting up group encryption: $e');
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
