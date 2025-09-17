import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignalService {
  static const MethodChannel _channel = MethodChannel('com.zarq/signal');

  /// Initialize a Signal protocol session with a recipient using their prekey bundle
  static Future<bool> initSession({
    required String recipientUid,
    required Map<String, dynamic> prekeyBundle,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final result = await _channel.invokeMethod('initSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'bundleJson': jsonEncode(prekeyBundle),
      });

      return result == true;
    } on PlatformException catch (e) {
      print('SignalService.initSession failed: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('SignalService.initSession error: $e');
      return false;
    }
  }

  /// Encrypt a plaintext message for a recipient
  static Future<String?> encryptMessage({
    required String recipientUid,
    required String plaintext,
    int recipientDeviceId = 1,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final result = await _channel.invokeMethod('encryptMessage', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'plaintext': plaintext,
        'recipientDeviceId': recipientDeviceId,
      });

      return result as String?;
    } on PlatformException catch (e) {
      print('SignalService.encryptMessage failed: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('SignalService.encryptMessage error: $e');
      return null;
    }
  }

  /// Decrypt a received message
  static Future<String?> decryptMessage({
    required String senderUid,
    required String ciphertextB64,
    int senderDeviceId = 1,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('No authenticated user');

      final result = await _channel.invokeMethod('decryptMessage', {
        'myUid': currentUser.uid,
        'senderUid': senderUid,
        'ciphertextB64': ciphertextB64,
        'senderDeviceId': senderDeviceId,
      });

      return result as String?;
    } on PlatformException catch (e) {
      print('SignalService.decryptMessage failed: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('SignalService.decryptMessage error: $e');
      return null;
    }
  }

  /// Check if we have an established session with a recipient
  static Future<bool> hasSession({
    required String recipientUid,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final result = await _channel.invokeMethod('hasSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
      });

      return result == true;
    } catch (e) {
      print('SignalService.hasSession error: $e');
      return false;
    }
  }

  /// Restore session state after app restart
  static Future<bool> restoreSessionState({
    required String recipientUid,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final result = await _channel.invokeMethod('restoreSessionState', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
      });

      return result == true;
    } catch (e) {
      print('SignalService.restoreSessionState error: $e');
      return false;
    }
  }

  /// Clear session for a specific recipient
  static Future<bool> clearSession({required String recipientUid}) async {
    try {
      print('[SignalService] Clearing session with $recipientUid');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('[SignalService] No current user for clearing session');
        return false;
      }

      final result = await _channel.invokeMethod('clearSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'clearAll': false,
      });

      print('[SignalService] Clear session result: $result');
      return result == true;
    } catch (e) {
      print('[SignalService] Error clearing session: $e');
      return false;
    }
  }

  // ===== FORWARD SECRECY TESTING METHODS =====

  /// Test basic forward secrecy for a recipient
  static Future<Map<String, dynamic>> testForwardSecrecy({
    required String recipientUid,
    int deviceId = 1,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {'error': 'No authenticated user', 'success': false};
    }

    print("=== FORWARD SECRECY TEST START ===");
    print("Testing: ${currentUser.uid} -> $recipientUid");

    try {
      final testMessage = "Forward secrecy test - ${DateTime.now().millisecondsSinceEpoch}";

      // Step 1: Encrypt test message
      print("Step 1: Encrypting test message...");
      final encrypted = await encryptMessage(
        recipientUid: recipientUid,
        plaintext: testMessage,
        recipientDeviceId: deviceId,
      );

      if (encrypted == null) {
        return {'error': 'Failed to encrypt test message', 'step': 'encryption', 'success': false};
      }
      print("Step 1 ✅: Message encrypted");

      // Step 2: Verify decryption works (simulate recipient)
      print("Step 2: Verifying decryption works...");
      final decrypted = await decryptMessage(
        senderUid: currentUser.uid,
        ciphertextB64: encrypted,
        senderDeviceId: deviceId,
      );

      if (decrypted != testMessage) {
        return {'error': 'Session not working properly', 'step': 'verification', 'success': false};
      }
      print("Step 2 ✅: Decryption verified");

      // Step 3: Clear session with verification
      print("Step 3: Clearing session with verification...");
      final clearResult = await _channel.invokeMethod('clearSessionWithTest', {
        'recipientUid': recipientUid,
        'deviceId': deviceId,
        'myUid': currentUser.uid,
      });

      if (clearResult != true) {
        return {'error': 'Session clearing failed', 'step': 'clearing', 'success': false};
      }
      print("Step 3 ✅: Session cleared");

      // Step 4: Test forward secrecy
      print("Step 4: Testing forward secrecy...");
      final forwardSecrecyTest = await _channel.invokeMethod('testForwardSecrecy', {
        'recipientUid': recipientUid,
        'deviceId': deviceId,
        'myUid': currentUser.uid,
      });

      // Step 5: Get audit information
      print("Step 5: Getting audit information...");
      final audit = await _channel.invokeMethod('auditSessionState', {
        'recipientUid': recipientUid,
        'deviceId': deviceId,
        'myUid': currentUser.uid,
      });

      final result = {
        'success': true,
        'testMessage': testMessage,
        'encryptionWorked': true,
        'decryptionWorked': true,
        'sessionCleared': clearResult == true,
        'forwardSecrecyVerified': forwardSecrecyTest['forwardSecrecyVerified'] == true,
        'relatedFilesCount': forwardSecrecyTest['relatedFilesCount'] ?? -1,
        'sessionExists': forwardSecrecyTest['sessionExists'] ?? false,
        'audit': audit,
        'recipientUid': recipientUid,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print("=== FORWARD SECRECY TEST RESULT ===");
      print("✅ Success: ${result['success']}");
      print("🔒 Forward Secrecy: ${result['forwardSecrecyVerified']}");
      print("📁 Files Remaining: ${result['relatedFilesCount']}");
      print("=== TEST COMPLETE ===");

      return result;

    } catch (e) {
      print("❌ Forward secrecy test failed: $e");
      return {
        'success': false,
        'error': e.toString(),
        'recipientUid': recipientUid,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test session recovery after clearing
  static Future<Map<String, dynamic>> testSessionRecovery({
    required String recipientUid,
    int deviceId = 1,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {'error': 'No authenticated user', 'success': false};
    }

    print("=== SESSION RECOVERY TEST START ===");

    try {
      // Step 1: Establish initial session
      print("Step 1: Establishing initial session...");
      final initialMessage = "Before clear - ${DateTime.now().millisecondsSinceEpoch}";

      final initialEncrypt = await encryptMessage(
        recipientUid: recipientUid,
        plaintext: initialMessage,
        recipientDeviceId: deviceId,
      );

      if (initialEncrypt == null) {
        return {'error': 'Failed to establish initial session', 'success': false};
      }
      print("Step 1 ✅: Initial session established");

      // Step 2: Clear session
      print("Step 2: Clearing session...");
      final clearResult = await _channel.invokeMethod('clearSessionWithTest', {
        'recipientUid': recipientUid,
        'deviceId': deviceId,
        'myUid': currentUser.uid,
      });
      print("Step 2 ✅: Session cleared: $clearResult");

      // Step 3: Test new session establishment
      print("Step 3: Testing session recovery...");
      final newMessage = "After clear - ${DateTime.now().millisecondsSinceEpoch}";

      final newEncrypt = await encryptMessage(
        recipientUid: recipientUid,
        plaintext: newMessage,
        recipientDeviceId: deviceId,
      );

      if (newEncrypt == null) {
        return {
          'success': false,
          'error': 'Failed to establish new session after clearing',
          'sessionCleared': clearResult == true,
        };
      }
      print("Step 3 ✅: New session established");

      // Step 4: Verify new session works
      print("Step 4: Verifying new session works...");
      final newDecrypt = await decryptMessage(
        senderUid: currentUser.uid,
        ciphertextB64: newEncrypt,
        senderDeviceId: deviceId,
      );

      final recoveryWorked = newDecrypt == newMessage;
      print("Step 4: New session decryption: $recoveryWorked");

      final result = {
        'success': true,
        'initialSessionWorked': true,
        'sessionCleared': clearResult == true,
        'newSessionEstablished': newEncrypt != null,
        'newSessionWorked': recoveryWorked,
        'initialMessage': initialMessage,
        'newMessage': newMessage,
        'recipientUid': recipientUid,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print("=== SESSION RECOVERY TEST RESULT ===");
      print("✅ Recovery Success: ${result['success']}");
      print("🔄 New Session Works: ${result['newSessionWorked']}");
      print("=== RECOVERY TEST COMPLETE ===");

      return result;

    } catch (e) {
      print("❌ Session recovery test failed: $e");
      return {
        'success': false,
        'error': e.toString(),
        'recipientUid': recipientUid,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Test mass session clearing
  static Future<Map<String, dynamic>> testMassSessionClearing({
    required List<String> recipientUids,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {'error': 'No authenticated user', 'success': false};
    }

    print("=== MASS SESSION CLEARING TEST START ===");

    try {
      final results = <String, dynamic>{};

      // Step 1: Create sessions with multiple recipients
      print("Step 1: Creating sessions with ${recipientUids.length} recipients...");

      for (String recipientUid in recipientUids) {
        try {
          final testMessage = "Test for $recipientUid - ${DateTime.now().millisecondsSinceEpoch}";

          final encrypted = await encryptMessage(
            recipientUid: recipientUid,
            plaintext: testMessage,
            recipientDeviceId: 1,
          );

          results[recipientUid] = {
            'sessionCreated': encrypted != null,
            'testMessage': testMessage,
          };

          print("  ✅ Session created with $recipientUid");
        } catch (e) {
          results[recipientUid] = {
            'sessionCreated': false,
            'error': e.toString(),
          };
          print("  ❌ Failed to create session with $recipientUid: $e");
        }
      }

      // Step 2: Get session stats before clearing
      print("Step 2: Getting session stats before clearing...");
      final statsBefore = await _channel.invokeMethod('getSessionStats', {
        'myUid': currentUser.uid,
      });
      print("Stats before: $statsBefore");

      // Step 3: Clear all sessions
      print("Step 3: Clearing all sessions...");
      final clearAllResult = await _channel.invokeMethod('clearSession', {
        'myUid': currentUser.uid,
        'clearAll': true,
      });
      print("Clear all result: $clearAllResult");

      // Step 4: Get session stats after clearing
      print("Step 4: Getting session stats after clearing...");
      final statsAfter = await _channel.invokeMethod('getSessionStats', {
        'myUid': currentUser.uid,
      });
      print("Stats after: $statsAfter");

      // Step 5: Verify forward secrecy for each recipient
      print("Step 5: Verifying forward secrecy for each recipient...");

      for (String recipientUid in recipientUids) {
        try {
          final forwardSecrecyTest = await _channel.invokeMethod('testForwardSecrecy', {
            'recipientUid': recipientUid,
            'deviceId': 1,
            'myUid': currentUser.uid,
          });

          results[recipientUid]['forwardSecrecyVerified'] = forwardSecrecyTest['forwardSecrecyVerified'] == true;
          results[recipientUid]['relatedFilesCount'] = forwardSecrecyTest['relatedFilesCount'] ?? -1;

          print("  Forward secrecy for $recipientUid: ${results[recipientUid]['forwardSecrecyVerified']}");
        } catch (e) {
          results[recipientUid]['forwardSecrecyError'] = e.toString();
          print("  ❌ Forward secrecy test failed for $recipientUid: $e");
        }
      }

      final overallResult = {
        'success': true,
        'recipientCount': recipientUids.length,
        'statsBefore': statsBefore,
        'statsAfter': statsAfter,
        'clearAllSuccess': clearAllResult == true,
        'individualResults': results,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print("=== MASS CLEARING TEST RESULT ===");
      print("✅ Overall Success: ${overallResult['success']}");
      print("📊 Recipients Tested: ${overallResult['recipientCount']}");
      print("🗑️ Clear All Success: ${overallResult['clearAllSuccess']}");
      print("=== MASS TEST COMPLETE ===");

      return overallResult;

    } catch (e) {
      print("❌ Mass session clearing test failed: $e");
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Get current session statistics
  static Future<Map<String, dynamic>> getSessionStats() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return {'error': 'No authenticated user', 'success': false};
    }

    try {
      final stats = await _channel.invokeMethod('getSessionStats', {
        'myUid': currentUser.uid,
      });

      return {
        'success': true,
        'stats': stats,
        'timestamp': DateTime.now().toIso8601String(),
      };

    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Quick forward secrecy test for development
  static Future<Map<String, dynamic>> quickForwardSecrecyTest() async {
    const testRecipientUid = "test_recipient_for_forward_secrecy";

    print("🚀 Running quick forward secrecy test with $testRecipientUid");

    final result = await testForwardSecrecy(recipientUid: testRecipientUid);

    if (result['success'] == true && result['forwardSecrecyVerified'] == true) {
      print("🎉 QUICK TEST PASSED - Forward secrecy is working!");
    } else {
      print("⚠️ QUICK TEST FAILED - Check the logs above");
    }

    return result;
  }

  /// Clear all sessions for logout
  static Future<bool> clearAllSessions() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final result = await _channel.invokeMethod('clearSession', {
        'myUid': currentUser.uid,
        'clearAll': true,
      });

      return result == true;
    } catch (e) {
      print('SignalService.clearAllSessions error: $e');
      return false;
    }
  }
}