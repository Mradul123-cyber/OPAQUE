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
      print('=== SignalService.initSession START ===');
      print('Recipient UID: $recipientUid');
      print('Bundle keys: ${prekeyBundle.keys.toList()}');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ERROR: No authenticated user for session init');
        throw Exception('No authenticated user');
      }

      print('Current user UID: ${currentUser.uid}');

      final result = await _channel.invokeMethod('initSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'bundleJson': jsonEncode(prekeyBundle),
      });

      print('initSession result: $result');

      // Immediately verify session was created
      final hasSessionAfter = await hasSession(recipientUid: recipientUid);
      print('Session verification after init: $hasSessionAfter');

      print('=== SignalService.initSession END ===');
      return result == true && hasSessionAfter;

    } on PlatformException catch (e) {
      print('SignalService.initSession PlatformException: ${e.code} - ${e.message}');
      print('Details: ${e.details}');
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
      print('=== SignalService.encryptMessage START ===');
      print('Recipient: $recipientUid, Message length: ${plaintext.length}');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ERROR: No authenticated user for encryption');
        throw Exception('No authenticated user');
      }

      // Verify session exists before encryption
      final hasSessionBefore = await hasSession(recipientUid: recipientUid);
      print('Session exists before encryption: $hasSessionBefore');

      if (!hasSessionBefore) {
        print('ERROR: No session exists for encryption');
        return null;
      }

      final result = await _channel.invokeMethod('encryptMessage', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'plaintext': plaintext,
        'recipientDeviceId': recipientDeviceId,
      });

      print('Encryption result length: ${result?.toString().length ?? 0}');
      print('=== SignalService.encryptMessage END ===');
      return result as String?;

    } on PlatformException catch (e) {
      print('SignalService.encryptMessage PlatformException: ${e.code} - ${e.message}');
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
      print('=== SignalService.decryptMessage START ===');
      print('Sender: $senderUid, Ciphertext length: ${ciphertextB64.length}');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ERROR: No authenticated user for decryption');
        throw Exception('No authenticated user');
      }

      final result = await _channel.invokeMethod('decryptMessage', {
        'myUid': currentUser.uid,
        'senderUid': senderUid,
        'ciphertextB64': ciphertextB64,
        'senderDeviceId': senderDeviceId,
      });

      print('Decryption result: ${result != null ? "SUCCESS" : "FAILED"}');
      print('=== SignalService.decryptMessage END ===');
      return result as String?;

    } on PlatformException catch (e) {
      print('SignalService.decryptMessage PlatformException: ${e.code} - ${e.message}');
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
      print('=== SignalService.hasSession CHECK ===');
      print('Checking session for: $recipientUid');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user for session check');
        return false;
      }

      final result = await _channel.invokeMethod('hasSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
      });

      print('hasSession result: $result');
      print('=== SignalService.hasSession END ===');
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
      print('=== SignalService.restoreSessionState START ===');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user for session restore');
        return false;
      }

      final result = await _channel.invokeMethod('restoreSessionState', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
      });

      print('restoreSessionState result: $result');
      print('=== SignalService.restoreSessionState END ===');
      return result == true;

    } catch (e) {
      print('SignalService.restoreSessionState error: $e');
      return false;
    }
  }

  /// Clear session for a specific recipient
  static Future<bool> clearSession({required String recipientUid}) async {
    try {
      print('=== SignalService.clearSession START ===');
      print('Clearing session with $recipientUid');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No current user for clearing session');
        return false;
      }

      final result = await _channel.invokeMethod('clearSession', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'clearAll': false,
      });

      print('Clear session result: $result');
      print('=== SignalService.clearSession END ===');
      return result == true;

    } catch (e) {
      print('SignalService.clearSession error: $e');
      return false;
    }
  }

  /// Clear all sessions for logout
  static Future<bool> clearAllSessions() async {
    try {
      print('=== SignalService.clearAllSessions START ===');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user for clearing all sessions');
        return false;
      }

      final result = await _channel.invokeMethod('clearSession', {
        'myUid': currentUser.uid,
        'clearAll': true,
      });

      print('Clear all sessions result: $result');
      print('=== SignalService.clearAllSessions END ===');
      return result == true;

    } catch (e) {
      print('SignalService.clearAllSessions error: $e');
      return false;
    }
  }

  /// Capture session context before encryption
  static Future<String?> captureSessionContext({
    required String recipientUid,
    int recipientDeviceId = 1,
  }) async {
    try {
      print('=== SignalService.captureSessionContext START ===');
      print('Capturing context for: $recipientUid');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ERROR: No authenticated user for session context capture');
        throw Exception('No authenticated user');
      }

      // Verify session exists before capture
      final hasSessionBefore = await hasSession(recipientUid: recipientUid);
      print('Session exists before capture: $hasSessionBefore');

      if (!hasSessionBefore) {
        print('ERROR: Cannot capture context - no session exists');
        return null;
      }

      final result = await _channel.invokeMethod('captureSessionContext', {
        'myUid': currentUser.uid,
        'recipientUid': recipientUid,
        'recipientDeviceId': recipientDeviceId,
      });

      print('Session context capture result: ${result != null ? "SUCCESS (${result.toString().length} chars)" : "FAILED"}');
      print('=== SignalService.captureSessionContext END ===');
      return result as String?;

    } on PlatformException catch (e) {
      print('SignalService.captureSessionContext PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('SignalService.captureSessionContext error: $e');
      return null;
    }
  }

  /// Apply session context before decryption
  static Future<bool> applySessionContext({
    required String senderUid,
    required String sessionContextB64,
    int senderDeviceId = 1,
  }) async {
    try {
      print('=== SignalService.applySessionContext START ===');
      print('Applying context from: $senderUid');
      print('Context length: ${sessionContextB64.length}');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('ERROR: No authenticated user for session context apply');
        throw Exception('No authenticated user');
      }

      final result = await _channel.invokeMethod('applySessionContext', {
        'myUid': currentUser.uid,
        'senderUid': senderUid,
        'sessionContextB64': sessionContextB64,
        'senderDeviceId': senderDeviceId,
      });

      print('Session context apply result: $result');
      print('=== SignalService.applySessionContext END ===');
      return result == true;

    } on PlatformException catch (e) {
      print('SignalService.applySessionContext PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('SignalService.applySessionContext error: $e');
      return false;
    }
  }
}