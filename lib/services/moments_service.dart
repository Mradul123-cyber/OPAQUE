import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/models/moment_model.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/device_service.dart';
import 'package:zarq_messenger/services/file_service.dart';
import 'package:zarq_messenger/app_config.dart';

class MomentsService {
  static const String _baseUrl = AppConfig.momentsBaseUrl;

  // ============================================
  // CREATE MOMENT
  // ============================================

  /// Creates a new moment (image or video)
  /// [mediaPath] - Path to the image or video file
  /// [mediaType] - 'image' or 'video'
  /// [visibility] - 'friends' or 'global'
  /// [caption] - Optional caption
  /// [friendsList] - List of friend UIDs (required for 'friends' visibility with E2EE)
  static Future<Map<String, dynamic>> createMoment({
    required File mediaFile,
    required String mediaType,
    required String visibility,
    String? caption,
    List<String>? friendsList,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/moments/create'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['media_type'] = mediaType;
      request.fields['visibility'] = visibility;
      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }

      // Store AES keys for local storage (if friends-only)
      String? aesKeyB64;
      String? aesIvB64;

      // Handle E2EE for friends-only moments
      if (visibility == 'friends' && friendsList != null && friendsList.isNotEmpty) {
        // Read media file
        final mediaBytes = await mediaFile.readAsBytes();

        // Encrypt media with AES-256-GCM
        final encryptionResult = FileService.encryptImageData(imageData: mediaBytes);
        final encryptedData = encryptionResult['encryptedData'] as Uint8List;
        final aesKey = encryptionResult['key'] as Uint8List;
        final aesIv = encryptionResult['iv'] as Uint8List;

        // Convert AES key and IV to base64
        aesKeyB64 = base64.encode(aesKey);
        aesIvB64 = base64.encode(aesIv);

        // Encrypt AES key for each friend using Signal Protocol
        List<Map<String, String>> encryptedKeys = [];

        for (String friendUid in friendsList) {
          try {
            // Get friend's device ID
            final deviceId = await DeviceService.getActiveDeviceId(friendUid);
            if (deviceId == null) continue;

            // Validate session before encrypting
            bool hasValidSession = await SignalService.isSessionValidForSending(
              recipientUid: friendUid,
              deviceId: deviceId,
            );

            String? encryptedAesKey;
            String? encryptedAesIv;

            if (!hasValidSession) {
              // Establish new session
              final prekeyBundle = await DeviceService.fetchPrekeyBundle(
                targetUid: friendUid,
                deviceId: deviceId,
              );
              if (prekeyBundle == null) continue;

              encryptedAesKey = await SignalService.encryptMessageWithSessionSetup(
                recipientUid: friendUid,
                plaintext: aesKeyB64,
                prekeyBundle: prekeyBundle,
                deviceId: deviceId,
              );

              encryptedAesIv = await SignalService.encryptMessageWithSessionSetup(
                recipientUid: friendUid,
                plaintext: aesIvB64,
                prekeyBundle: prekeyBundle,
                deviceId: deviceId,
              );
            } else {
              // Use existing session
              encryptedAesKey = await SignalService.encryptMessage(
                recipientUid: friendUid,
                plaintext: aesKeyB64,
                deviceId: deviceId,
              );

              encryptedAesIv = await SignalService.encryptMessage(
                recipientUid: friendUid,
                plaintext: aesIvB64,
                deviceId: deviceId,
              );
            }

            // Skip if encryption failed
            if (encryptedAesKey == null || encryptedAesIv == null) continue;

            encryptedKeys.add({
              'friend_id': friendUid,
              'encrypted_key': encryptedAesKey,
              'encrypted_iv': encryptedAesIv,
            });
          } catch (e) {
            print('[MomentsService] Failed to encrypt for friend $friendUid: $e');
            continue;
          }
        }

        // Add encrypted keys to request
        request.fields['encrypted_keys'] = jsonEncode(encryptedKeys);

        // Create temporary encrypted file
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/encrypted_moment_${DateTime.now().millisecondsSinceEpoch}');
        await tempFile.writeAsBytes(encryptedData);

        // Add encrypted file to request
        request.files.add(await http.MultipartFile.fromPath('media', tempFile.path));
      } else {
        // Global moment - no encryption
        request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('[MomentsService] Server response: $result');

        // Store AES keys locally for creator to decrypt their own moment
        // Try different possible paths for the moment ID
        String? momentId;
        if (result['moment'] != null && result['moment']['id'] != null) {
          momentId = result['moment']['id'] as String;
        } else if (result['id'] != null) {
          momentId = result['id'] as String;
        } else if (result['moment_id'] != null) {
          momentId = result['moment_id'] as String;
        }

        if (visibility == 'friends' &&
            aesKeyB64 != null &&
            aesIvB64 != null &&
            momentId != null) {
          print('[MomentsService] Saving local keys for moment: $momentId');
          print('[MomentsService] aesKeyB64 length: ${aesKeyB64.length}, aesIvB64 length: ${aesIvB64.length}');
          await _storeLocalMomentKeys(momentId, aesKeyB64, aesIvB64);
        } else {
          print('[MomentsService] NOT saving keys - visibility: $visibility, aesKeyB64: ${aesKeyB64 != null}, aesIvB64: ${aesIvB64 != null}, momentId: $momentId');
        }

        return result;
      } else {
        throw Exception('Failed to create moment: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error creating moment: $e');
      rethrow;
    }
  }

  // ============================================
  // GET MOMENTS FEEDS
  // ============================================

  /// Get friends' moments (E2EE encrypted)
  static Future<List<MomentModel>> getFriendsMoments({int limit = 20, int offset = 0}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      final response = await http.get(
        Uri.parse('$_baseUrl/moments/friends?limit=$limit&offset=$offset'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[MomentsService] Friends moments response: $data');
        final momentsJson = data['moments'] as List;
        if (momentsJson.isNotEmpty) {
          print('[MomentsService] First moment: ${momentsJson[0]}');
        }
        return momentsJson.map((json) => MomentModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch friends moments: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error fetching friends moments: $e');
      rethrow;
    }
  }

  /// Get global moments (public, no encryption)
  static Future<List<MomentModel>> getGlobalMoments({int limit = 20, int offset = 0}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      final response = await http.get(
        Uri.parse('$_baseUrl/moments/global?limit=$limit&offset=$offset'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final momentsJson = data['moments'] as List;
        return momentsJson.map((json) => MomentModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch global moments: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error fetching global moments: $e');
      rethrow;
    }
  }

  // ============================================
  // MOMENT VIEWS
  // ============================================

  /// Mark a moment as viewed
  static Future<void> markMomentAsViewed(String momentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      final response = await http.post(
        Uri.parse('$_baseUrl/moments/$momentId/view'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark moment as viewed: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error marking moment as viewed: $e');
      rethrow;
    }
  }

  /// Get list of viewers for a moment (owner only)
  static Future<List<MomentViewer>> getMomentViewers(String momentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      final response = await http.get(
        Uri.parse('$_baseUrl/moments/$momentId/viewers'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final viewersJson = data['viewers'] as List;
        return viewersJson.map((json) => MomentViewer.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch viewers: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error fetching viewers: $e');
      rethrow;
    }
  }

  // ============================================
  // MOMENT DELETION
  // ============================================

  /// Delete a moment (owner only)
  static Future<void> deleteMoment(String momentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      if (token == null) throw Exception('No auth token');

      final response = await http.delete(
        Uri.parse('$_baseUrl/moments/$momentId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete moment: ${response.body}');
      }
    } catch (e) {
      print('[MomentsService] Error deleting moment: $e');
      rethrow;
    }
  }

  // ============================================
  // DECRYPTION HELPERS
  // ============================================

  /// Decrypt an encrypted moment media (for friends-only moments)
  static Future<Uint8List?> decryptMomentMedia({
    required String momentId,
    required String encryptedMediaUrl,
    required String encryptedMediaKey,
    required String encryptedMediaIv,
    required String creatorUid,
  }) async {
    try {
      print('[MomentsService] Starting decryption for moment: $momentId, creator: $creatorUid');

      // Download encrypted media
      print('[MomentsService] Downloading encrypted media from: $encryptedMediaUrl');
      final response = await http.get(Uri.parse(encryptedMediaUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download encrypted media: HTTP ${response.statusCode}');
      }
      final encryptedData = response.bodyBytes;
      print('[MomentsService] Downloaded ${encryptedData.length} bytes of encrypted data');

      String? aesKeyB64;
      String? aesIvB64;

      // Check if this is the creator's own moment - use local keys
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == creatorUid) {
        print('[MomentsService] This is creator\'s own moment, checking local storage...');
        final localKeys = await _getLocalMomentKeys(momentId);
        if (localKeys != null) {
          aesKeyB64 = localKeys['key'];
          aesIvB64 = localKeys['iv'];
          print('[MomentsService] Found local keys for own moment!');
        } else {
          print('[MomentsService] No local keys found for own moment');
        }
      }

      // If no local keys, decrypt using Signal Protocol
      if (aesKeyB64 == null || aesIvB64 == null) {
        print('[MomentsService] Using Signal Protocol decryption...');

        // Get creator's device ID
        print('[MomentsService] Fetching device ID for creator: $creatorUid');
        final creatorDeviceId = await DeviceService.getActiveDeviceId(creatorUid);
        if (creatorDeviceId == null) {
          throw Exception('Could not find creator device ID for $creatorUid');
        }
        print('[MomentsService] Creator device ID: $creatorDeviceId');

        // Decrypt AES key and IV using Signal Protocol
        print('[MomentsService] Decrypting AES key...');
        aesKeyB64 = await SignalService.decryptMessage(
          senderUid: creatorUid,
          ciphertextB64: encryptedMediaKey,
          deviceId: creatorDeviceId,
        );

        print('[MomentsService] Decrypting AES IV...');
        aesIvB64 = await SignalService.decryptMessage(
          senderUid: creatorUid,
          ciphertextB64: encryptedMediaIv,
          deviceId: creatorDeviceId,
        );
      }

      if (aesKeyB64 == null || aesIvB64 == null) {
        throw Exception('Failed to decrypt AES keys (key=$aesKeyB64, iv=$aesIvB64)');
      }
      print('[MomentsService] Successfully obtained AES key and IV');

      final aesKey = base64.decode(aesKeyB64);
      final aesIv = base64.decode(aesIvB64);
      print('[MomentsService] AES key length: ${aesKey.length}, IV length: ${aesIv.length}');

      // Decrypt media data
      print('[MomentsService] Decrypting media data...');
      final decryptedData = FileService.decryptImageData(
        encryptedData: encryptedData,
        key: aesKey,
        iv: aesIv,
      );

      if (decryptedData == null) {
        throw Exception('FileService.decryptImageData returned null');
      }

      print('[MomentsService] Successfully decrypted ${decryptedData.length} bytes of media data');
      return decryptedData;
    } catch (e, stackTrace) {
      print('[MomentsService] Error decrypting moment media: $e');
      print('[MomentsService] Stack trace: $stackTrace');
      return null;
    }
  }

  // ============================================
  // LOCAL KEY STORAGE (for creator's own moments)
  // ============================================

  /// Store AES keys locally for a moment (so creator can decrypt their own encrypted moment)
  static Future<void> _storeLocalMomentKeys(String momentId, String aesKeyB64, String aesIvB64) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'moment_key_${user.uid}_$momentId';
      final data = jsonEncode({
        'key': aesKeyB64,
        'iv': aesIvB64,
      });
      await prefs.setString(key, data);
      print('[MomentsService] Stored local keys for moment: $momentId');
    } catch (e) {
      print('[MomentsService] Error storing local moment keys: $e');
    }
  }

  /// Retrieve locally stored AES keys for a moment
  static Future<Map<String, String>?> _getLocalMomentKeys(String momentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final prefs = await SharedPreferences.getInstance();
      final key = 'moment_key_${user.uid}_$momentId';
      final data = prefs.getString(key);
      if (data == null) return null;

      final decoded = jsonDecode(data) as Map<String, dynamic>;
      return {
        'key': decoded['key'] as String,
        'iv': decoded['iv'] as String,
      };
    } catch (e) {
      print('[MomentsService] Error retrieving local moment keys: $e');
      return null;
    }
  }
}
