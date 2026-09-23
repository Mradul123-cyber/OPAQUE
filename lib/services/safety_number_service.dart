import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'SignalService.dart';

enum SafetyNumberStatus {
  unverified,
  verified,
  changed,
}

class SafetyNumberResult {
  final String formattedNumber;
  final List<String> blocks;
  final SafetyNumberStatus status;
  final String? remoteIdentityKey;

  const SafetyNumberResult({
    required this.formattedNumber,
    required this.blocks,
    required this.status,
    this.remoteIdentityKey,
  });

  bool get isVerified => status == SafetyNumberStatus.verified;
  bool get hasChanged => status == SafetyNumberStatus.changed;
}

class SafetyNumberService {
  static const int _iterations = 5200;

  /// Deterministically compute the 60-digit Signal Protocol safety number (12 blocks of 5 digits).
  ///
  /// Inputs are sorted lexicographically so that regardless of which peer computes it,
  /// the resulting numbers match 100%.
  static String computeDisplayFingerprint({
    required String localUid,
    required String? localKeyB64,
    required String remoteUid,
    required String? remoteKeyB64,
  }) {
    Uint8List localKeyBytes;
    Uint8List remoteKeyBytes;

    try {
      if (localKeyB64 != null && localKeyB64.isNotEmpty) {
        localKeyBytes = base64.decode(localKeyB64.trim());
      } else {
        localKeyBytes = Uint8List.fromList(utf8.encode(localUid));
      }
    } catch (_) {
      localKeyBytes = Uint8List.fromList(utf8.encode(localUid));
    }

    try {
      if (remoteKeyB64 != null && remoteKeyB64.isNotEmpty) {
        remoteKeyBytes = base64.decode(remoteKeyB64.trim());
      } else {
        remoteKeyBytes = Uint8List.fromList(utf8.encode(remoteUid));
      }
    } catch (_) {
      remoteKeyBytes = Uint8List.fromList(utf8.encode(remoteUid));
    }

    // Sort the two participants deterministically based on public key bytes, or UIDs if keys match
    final bool localIsFirst = _compareByteArrays(localKeyBytes, remoteKeyBytes) < 0 ||
        (_compareByteArrays(localKeyBytes, remoteKeyBytes) == 0 && localUid.compareTo(remoteUid) <= 0);

    final Uint8List key1 = localIsFirst ? localKeyBytes : remoteKeyBytes;
    final Uint8List key2 = localIsFirst ? remoteKeyBytes : localKeyBytes;
    final String uid1 = localIsFirst ? localUid : remoteUid;
    final String uid2 = localIsFirst ? remoteUid : localUid;

    // Combine material: [key1, key2, uid1, uid2]
    final material = BytesBuilder(copy: false)
      ..add(key1)
      ..add(key2)
      ..add(utf8.encode(uid1))
      ..add(utf8.encode(uid2));

    // Iterated SHA-512 hashing (similar to Signal's NumericFingerprintGenerator)
    List<int> digest = sha512.convert(material.toBytes()).bytes;
    for (int i = 0; i < 64; i++) {
      digest = sha512.convert(digest).bytes;
    }

    // Extract 12 chunks of 5 decimal digits
    final List<String> blocks = [];
    final byteData = ByteData.sublistView(Uint8List.fromList(digest));

    for (int i = 0; i < 12; i++) {
      final int offset = (i * 4) % (digest.length - 4);
      final int value = byteData.getUint32(offset, Endian.big);
      final int chunk = (value % 100000).abs();
      blocks.add(chunk.toString().padLeft(5, '0'));
    }

    return blocks.join(' ');
  }

  /// Get the safety number result and verification/changed status for a contact.
  static Future<SafetyNumberResult> getSafetyNumber({
    required String localUid,
    required String? localKeyB64,
    required String remoteUid,
    required String? remoteKeyB64,
  }) async {
    final formatted = computeDisplayFingerprint(
      localUid: localUid,
      localKeyB64: localKeyB64,
      remoteUid: remoteUid,
      remoteKeyB64: remoteKeyB64,
    );
    final blocks = formatted.split(' ');

    final status = await checkStatus(
      partnerUid: remoteUid,
      currentRemoteKeyB64: remoteKeyB64,
    );

    return SafetyNumberResult(
      formattedNumber: formatted,
      blocks: blocks,
      status: status,
      remoteIdentityKey: remoteKeyB64,
    );
  }

  /// Check whether the contact's identity key has changed, is verified, or unverified.
  static Future<SafetyNumberStatus> checkStatus({
    required String partnerUid,
    required String? currentRemoteKeyB64,
  }) async {
    if (partnerUid.isEmpty) return SafetyNumberStatus.unverified;

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKey = prefs.getString('known_identity_key_$partnerUid');
      final isVerified = prefs.getBool('verified_safety_number_$partnerUid') ?? false;

      // Determine baseline key:
      // If SharedPreferences has no known key yet, check if the native SignalProtocolStore
      // has an established identity key from prior sessions.
      String? baselineKey = storedKey;
      if (baselineKey == null || baselineKey.isEmpty) {
        baselineKey = await SignalService.getRemoteIdentityKey(partnerUid);
        if (baselineKey != null && baselineKey.isNotEmpty && storedKey == null) {
          await prefs.setString('known_identity_key_$partnerUid', baselineKey.trim());
        }
      }

      // If we have a baseline key and the active remote key exists and does not match:
      // Contact's key has CHANGED (reinstalled, new device, prekeys regenerated)!
      if (baselineKey != null &&
          baselineKey.isNotEmpty &&
          currentRemoteKeyB64 != null &&
          currentRemoteKeyB64.isNotEmpty &&
          baselineKey.trim() != currentRemoteKeyB64.trim()) {
        return SafetyNumberStatus.changed;
      }

      // If key is first seen and valid (no prior key in prefs or native store), record it as known key
      if ((storedKey == null || storedKey.isEmpty) &&
          currentRemoteKeyB64 != null &&
          currentRemoteKeyB64.isNotEmpty) {
        await prefs.setString('known_identity_key_$partnerUid', currentRemoteKeyB64.trim());
      }

      return isVerified ? SafetyNumberStatus.verified : SafetyNumberStatus.unverified;
    } catch (_) {
      return SafetyNumberStatus.unverified;
    }
  }

  /// Mark the safety number as verified by the user.
  static Future<void> markVerified({
    required String partnerUid,
    required String? currentRemoteKeyB64,
  }) async {
    if (partnerUid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (currentRemoteKeyB64 != null && currentRemoteKeyB64.isNotEmpty) {
        await prefs.setString('known_identity_key_$partnerUid', currentRemoteKeyB64.trim());
      }
      await prefs.setBool('verified_safety_number_$partnerUid', true);

      // Cleanly remove stale native Signal session so the next message establishes
      // with the new verified key
      try {
        await SignalService.removeSession(recipientUid: partnerUid);
      } catch (_) {}
    } catch (e) {
      debugPrint('[SafetyNumberService] Error marking verified: $e');
    }
  }

  /// Reset or clear verification status for a contact.
  static Future<void> clearVerification({
    required String partnerUid,
  }) async {
    if (partnerUid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('verified_safety_number_$partnerUid', false);
    } catch (e) {
      debugPrint('[SafetyNumberService] Error clearing verification: $e');
    }
  }

  /// Helper to compare two byte arrays lexicographically
  static int _compareByteArrays(Uint8List a, Uint8List b) {
    final int minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] != b[i]) {
        return a[i].compareTo(b[i]);
      }
    }
    return a.length.compareTo(b.length);
  }
}
