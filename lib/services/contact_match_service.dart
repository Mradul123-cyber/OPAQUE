import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import 'app_storage.dart';

/// A phone contact that may or may not be on Opaque.
class DeviceContactEntry {
  const DeviceContactEntry({
    required this.localName,
    required this.phoneNumber,
    required this.phoneHash,
  });

  final String localName;
  final String phoneNumber;
  final String phoneHash;
}

/// An Opaque user matched from the device address book.
class OpaqueContactMatch {
  const OpaqueContactMatch({
    required this.username,
    this.displayName,
    this.localName,
    this.phoneNumber,
    this.avatarUrl,
    this.uid,
  });

  final String username;
  final String? displayName;
  final String? localName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? uid;

  Map<String, dynamic> toJson() => {
        'username': username,
        'displayName': displayName,
        'localName': localName,
        'phoneNumber': phoneNumber,
        'avatarUrl': avatarUrl,
        'uid': uid,
      };

  factory OpaqueContactMatch.fromJson(Map<String, dynamic> json) =>
      OpaqueContactMatch(
        username: (json['username'] as String?) ?? 'Unknown',
        displayName: json['displayName'] as String?,
        localName: json['localName'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        uid: json['uid'] as String?,
      );
}

/// Shared contact sync + name resolution for Home and Friends.
class ContactMatchService with ChangeNotifier {
  ContactMatchService._();
  static final ContactMatchService instance = ContactMatchService._();

  static const int homeOpaqueContactLimit = 12;
  static const Duration _cacheTtl = Duration(hours: 12);

  List<OpaqueContactMatch> _opaqueMatches = [];
  List<DeviceContactEntry> _deviceContacts = [];
  DateTime? _lastSyncAt;
  bool _syncing = false;
  bool _permissionDenied = false;

  List<OpaqueContactMatch> get opaqueMatches =>
      List.unmodifiable(_opaqueMatches);
  List<DeviceContactEntry> get deviceContacts =>
      List.unmodifiable(_deviceContacts);
  bool get isSyncing => _syncing;
  bool get permissionDenied => _permissionDenied;
  bool get hasSynced => _lastSyncAt != null || _opaqueMatches.isNotEmpty;

  String get _cacheKey {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        AppStorage.cachedUid ??
        'anon';
    return 'opaque_contact_matches_$uid';
  }

  String get _phoneMapKey {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        AppStorage.cachedUid ??
        'anon';
    return 'contact_phone_mapping_$uid';
  }

  /// Resolve a person title: local contact → display name → username.
  /// When [preferLocal] is false: display name → local contact → username.
  static String resolveName({
    required bool preferLocal,
    String? localName,
    String? displayName,
    required String username,
  }) {
    final local = localName?.trim();
    final display = displayName?.trim();
    if (preferLocal) {
      if (local != null && local.isNotEmpty) return local;
      if (display != null && display.isNotEmpty) return display;
      return username;
    }
    if (display != null && display.isNotEmpty) return display;
    if (local != null && local.isNotEmpty) return local;
    return username;
  }

  Future<void> loadCachedMatches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final list = decoded['matches'] as List? ?? const [];
      final syncedAt = decoded['syncedAt'] as String?;
      _opaqueMatches = list
          .whereType<Map>()
          .map((e) => OpaqueContactMatch.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _lastSyncAt = syncedAt != null ? DateTime.tryParse(syncedAt) : null;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistMatches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
          'matches': _opaqueMatches.map((m) => m.toJson()).toList(),
        }),
      );

      // Keep legacy username → phone map for call / find-friends callers.
      final phoneMap = <String, String>{};
      for (final match in _opaqueMatches) {
        if (match.phoneNumber != null && match.phoneNumber!.isNotEmpty) {
          phoneMap[match.username] = match.phoneNumber!;
        }
      }
      await prefs.setString(_phoneMapKey, jsonEncode(phoneMap));
      await prefs.setString('contact_phone_mapping', jsonEncode(phoneMap));
    } catch (_) {}
  }

  OpaqueContactMatch? matchForUsername(String username) {
    for (final m in _opaqueMatches) {
      if (m.username == username) return m;
    }
    return null;
  }

  OpaqueContactMatch? matchForUid(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    for (final m in _opaqueMatches) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  /// Apply matches produced by Friends contact scan (avoids a second full sync).
  void applyMatches({
    required List<OpaqueContactMatch> matches,
    required List<DeviceContactEntry> deviceContacts,
  }) {
    final sorted = [...matches]..sort((a, b) {
          final aHas = (a.localName?.isNotEmpty ?? false) ? 0 : 1;
          final bHas = (b.localName?.isNotEmpty ?? false) ? 0 : 1;
          if (aHas != bHas) return aHas - bHas;
          return (a.localName ?? a.username)
              .toLowerCase()
              .compareTo((b.localName ?? b.username).toLowerCase());
        });
    _opaqueMatches = sorted;
    _deviceContacts = deviceContacts;
    _lastSyncAt = DateTime.now();
    _permissionDenied = false;
    unawaited(_persistMatches());
    notifyListeners();
  }

  String titleFor({
    required bool preferLocal,
    String? username,
    String? displayName,
    String? partnerUid,
    String? fallback,
  }) {
    final match = matchForUid(partnerUid) ??
        (username != null ? matchForUsername(username) : null);
    return resolveName(
      preferLocal: preferLocal,
      localName: match?.localName,
      displayName: match?.displayName ?? displayName,
      username: username ?? match?.username ?? fallback ?? 'Unknown',
    );
  }

  /// Opaque contacts for the home list (no existing chat partner).
  List<OpaqueContactMatch> homeSuggestions({
    required Set<String> existingPartnerUids,
    required Set<String> existingUsernames,
    int limit = homeOpaqueContactLimit,
  }) {
    final out = <OpaqueContactMatch>[];
    for (final match in _opaqueMatches) {
      if (match.uid != null && existingPartnerUids.contains(match.uid)) {
        continue;
      }
      if (existingUsernames.contains(match.username.toLowerCase())) continue;
      out.add(match);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Device contacts that are not on Opaque (for invite search).
  List<DeviceContactEntry> inviteCandidates({String query = ''}) {
    final opaquePhones = {
      for (final m in _opaqueMatches)
        if (m.phoneNumber != null) _digitsOnly(m.phoneNumber!),
    };
    final q = query.trim().toLowerCase();
    final qDigits = _digitsOnly(query);
    final seen = <String>{};
    final out = <DeviceContactEntry>[];
    for (final c in _deviceContacts) {
      final digits = _digitsOnly(c.phoneNumber);
      if (opaquePhones.contains(digits)) continue;
      if (!seen.add(digits)) continue;
      if (q.isNotEmpty) {
        final nameHit = c.localName.toLowerCase().contains(q);
        final phoneHit = qDigits.isNotEmpty && digits.contains(qDigits);
        if (!nameHit && !phoneHit) continue;
      }
      out.add(c);
    }
    return out;
  }

  /// Request permission if needed, then sync. Safe to call from Home on launch.
  Future<bool> ensureSynced({bool force = false}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    if (_syncing) return _opaqueMatches.isNotEmpty;

    await loadCachedMatches();
    final cacheFresh = _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < _cacheTtl &&
        !force;
    if (cacheFresh && _opaqueMatches.isNotEmpty && _deviceContacts.isNotEmpty) {
      return true;
    }

    final status = await Permission.contacts.status;
    if (!status.isGranted) {
      final requested = await Permission.contacts.request();
      if (!requested.isGranted) {
        _permissionDenied = true;
        notifyListeners();
        return _opaqueMatches.isNotEmpty;
      }
    }
    _permissionDenied = false;
    return syncContacts(force: force);
  }

  Future<bool> syncContacts({bool force = false}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    if (_syncing) return false;
    _syncing = true;
    notifyListeners();

    try {
      final permission = await Permission.contacts.status;
      if (!permission.isGranted) {
        _permissionDenied = true;
        return false;
      }
      _permissionDenied = false;

      final contactsWithoutProps = await FlutterContacts.getContacts(
        withProperties: false,
      ).timeout(const Duration(seconds: 10));

      final contacts = <Contact>[];
      const batchSize = 2000;
      for (var i = 0; i < contactsWithoutProps.length; i += batchSize) {
        final end = (i + batchSize < contactsWithoutProps.length)
            ? i + batchSize
            : contactsWithoutProps.length;
        final batch = contactsWithoutProps.sublist(i, end);
        final results = await Future.wait(
          batch.map((c) => FlutterContacts.getContact(c.id)),
          eagerError: false,
        );
        for (final full in results) {
          if (full != null) contacts.add(full);
        }
      }

      final hashed = <String>[];
      final hashToPhone = <String, String>{};
      final hashToLocalName = <String, String>{};
      final device = <DeviceContactEntry>[];

      for (final contact in contacts) {
        final localName = contact.displayName.trim().isEmpty
            ? 'Unknown'
            : contact.displayName.trim();
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized == null) continue;
          final hash = sha256.convert(utf8.encode(normalized)).toString();
          hashed.add(hash);
          hashToPhone[hash] = normalized;
          hashToLocalName[hash] = localName;
          device.add(DeviceContactEntry(
            localName: localName,
            phoneNumber: normalized,
            phoneHash: hash,
          ));
        }
      }

      _deviceContacts = device;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || hashed.isEmpty) {
        _opaqueMatches = [];
        _lastSyncAt = DateTime.now();
        await _persistMatches();
        return false;
      }

      final token = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/friends/find'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(hashed),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _opaqueMatches.isNotEmpty;
      }

      final decoded = jsonDecode(response.body);
      final foundUsers = decoded is List ? decoded : const [];
      final matches = <OpaqueContactMatch>[];

      for (final data in foundUsers) {
        if (data is String) {
          matches.add(OpaqueContactMatch(username: data));
          continue;
        }
        if (data is! Map) continue;
        final map = Map<String, dynamic>.from(data);
        final phoneHash = map['phoneHash'] as String?;
        final phone = phoneHash != null
            ? hashToPhone[phoneHash]
            : (map['phoneNumber'] ?? map['phone_number']) as String?;
        final localName = phoneHash != null ? hashToLocalName[phoneHash] : null;
        matches.add(
          OpaqueContactMatch(
            username: (map['username'] as String?) ?? 'Unknown',
            displayName:
                (map['displayName'] ?? map['display_name']) as String?,
            localName: localName,
            phoneNumber: phone,
            avatarUrl: (map['avatarUrl'] ??
                    map['avatar_url'] ??
                    map['profile_picture_url'] ??
                    map['avatar'])
                as String?,
            uid: (map['uid'] ?? map['user_uid'] ?? map['userId']) as String?,
          ),
        );
      }

      // Prefer entries that have a local address-book name.
      matches.sort((a, b) {
        final aHas = (a.localName?.isNotEmpty ?? false) ? 0 : 1;
        final bHas = (b.localName?.isNotEmpty ?? false) ? 0 : 1;
        if (aHas != bHas) return aHas - bHas;
        return (a.localName ?? a.username)
            .toLowerCase()
            .compareTo((b.localName ?? b.username).toLowerCase());
      });

      _opaqueMatches = matches;
      _lastSyncAt = DateTime.now();
      await _persistMatches();
      return true;
    } catch (e) {
      debugPrint('[ContactMatchService] sync failed: $e');
      return _opaqueMatches.isNotEmpty;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  static String? _normalizePhone(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return null;
    if (!cleaned.startsWith('+')) {
      if (cleaned.length == 10 && cleaned.startsWith(RegExp(r'[6-9]'))) {
        cleaned = '+91$cleaned';
      } else if (cleaned.startsWith('91') && cleaned.length == 12) {
        cleaned = '+$cleaned';
      } else if (cleaned.startsWith('0') && cleaned.length == 11) {
        cleaned = '+91${cleaned.substring(1)}';
      }
    }
    return cleaned;
  }

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
