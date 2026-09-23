import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import 'app_storage.dart';

class DeviceContactEntry {
  const DeviceContactEntry({
    required this.localName,
    required this.phoneNumber,
    required this.phoneHash,
    this.phoneDigits = '',
  });

  final String localName;
  final String phoneNumber;
  final String phoneHash;
  final String phoneDigits;

  Map<String, dynamic> toJson() => {
        'localName': localName,
        'phoneNumber': phoneNumber,
        'phoneHash': phoneHash,
        'phoneDigits': phoneDigits,
      };

  factory DeviceContactEntry.fromJson(Map<String, dynamic> json) =>
      DeviceContactEntry(
        localName: (json['localName'] as String?) ?? 'Unknown',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        phoneHash: (json['phoneHash'] as String?) ?? '',
        phoneDigits: (json['phoneDigits'] as String?) ??
            ((json['phoneNumber'] as String?) ?? '')
                .replaceAll(RegExp(r'[^0-9]'), ''),
      );
}

class OpaqueContactMatch {
  const OpaqueContactMatch({
    required this.username,
    this.displayName,
    this.localName,
    this.phoneNumber,
    this.avatarUrl,
    this.uid,
    this.phoneHash,
  });

  final String username;
  final String? displayName;
  final String? localName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? uid;
  final String? phoneHash;

  Map<String, dynamic> toJson() => {
        'username': username,
        'displayName': displayName,
        'localName': localName,
        'phoneNumber': phoneNumber,
        'avatarUrl': avatarUrl,
        'uid': uid,
        'phoneHash': phoneHash,
      };

  factory OpaqueContactMatch.fromJson(Map<String, dynamic> json) =>
      OpaqueContactMatch(
        username: (json['username'] as String?) ?? 'Unknown',
        displayName: json['displayName'] as String?,
        localName: json['localName'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        uid: json['uid'] as String?,
        phoneHash: json['phoneHash'] as String?,
      );
}

class IndexedContact {
  IndexedContact({
    required this.localName,
    required this.phoneNumber,
    required this.phoneHash,
    required this.phoneDigits,
    this.opaque,
  }) : localNameLower = localName.toLowerCase();

  final String localName;
  final String localNameLower;
  final String phoneNumber;
  final String phoneHash;
  final String phoneDigits;
  OpaqueContactMatch? opaque;

  bool get isOnOpaque => opaque != null;

  Map<String, dynamic> toJson() => {
        'localName': localName,
        'phoneNumber': phoneNumber,
        'phoneHash': phoneHash,
        'phoneDigits': phoneDigits,
        'opaque': opaque?.toJson(),
      };

  factory IndexedContact.fromJson(Map<String, dynamic> json) =>
      IndexedContact(
        localName: (json['localName'] as String?) ?? 'Unknown',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        phoneHash: (json['phoneHash'] as String?) ?? '',
        phoneDigits: (json['phoneDigits'] as String?) ??
            ((json['phoneNumber'] as String?) ?? '')
                .replaceAll(RegExp(r'[^0-9]'), ''),
        opaque: json['opaque'] != null
            ? OpaqueContactMatch.fromJson(
                Map<String, dynamic>.from(json['opaque']))
            : null,
      );
}

class ContactSearchHit {
  const ContactSearchHit({
    required this.localName,
    required this.phoneNumber,
    this.opaque,
  });

  final String localName;
  final String phoneNumber;
  final OpaqueContactMatch? opaque;
  bool get isOnOpaque => opaque != null;
}

/// High-performance contact service:
/// 1. Fast one-time sync without photo overhead.
/// 2. In-memory indexing (< 1ms search for both name & phone number).
/// 3. Zero network and zero native IPC during keystrokes.
class ContactMatchService with ChangeNotifier {
  ContactMatchService._();
  static final ContactMatchService instance = ContactMatchService._();

  static const int homeOpaqueContactLimit = 12;
  static const int searchFetchLimit = 40;
  static const String _rationaleAskedKey = 'opaque_contacts_rationale_asked';
  static const String _setupSkippedKey = 'opaque_contacts_setup_skipped_v1';

  List<OpaqueContactMatch> _opaqueMatches = [];
  List<DeviceContactEntry> _deviceContacts = [];
  List<IndexedContact> _indexedContacts = [];
  bool _syncing = false;
  bool _permissionDenied = false;
  bool _initialPrepareDone = false;
  bool _cacheLoaded = false;
  bool _setupSkipped = false;

  List<OpaqueContactMatch> get opaqueMatches =>
      List.unmodifiable(_opaqueMatches);
  List<DeviceContactEntry> get deviceContacts =>
      List.unmodifiable(_deviceContacts);
  List<IndexedContact> get indexedContacts =>
      List.unmodifiable(_indexedContacts);
  bool get isSyncing => _syncing;
  bool get permissionDenied => _permissionDenied;
  bool get hasPreparedOnce => _initialPrepareDone;
  bool get hasCachedData =>
      _indexedContacts.isNotEmpty ||
      _opaqueMatches.isNotEmpty ||
      _deviceContacts.isNotEmpty;

  /// True when auth should show the dedicated contacts Allow / Skip step.
  bool get needsDedicatedSetup {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    if (_setupSkipped) return false;
    if (_initialPrepareDone || hasCachedData) return false;
    return true;
  }

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ??
      AppStorage.cachedUid ??
      'anon';
  String get _cacheKey => 'opaque_contact_matches_v3_$_uid';
  String get _preparedKey => 'opaque_contacts_prepared_v3_$_uid';
  String get _phoneMapKey => 'contact_phone_mapping_$_uid';

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

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/contacts_cache_${_uid}.json');
  }

  Future<void> loadCachedMatches() async {
    if (_cacheLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _initialPrepareDone = prefs.getBool(_preparedKey) ?? false;
      _setupSkipped = prefs.getBool(_setupSkippedKey) ?? false;

      final file = await _getCacheFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _permissionDenied = decoded['permissionDenied'] == true;
            _opaqueMatches = (decoded['matches'] as List? ?? const [])
                .whereType<Map>()
                .map((e) =>
                    OpaqueContactMatch.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            _indexedContacts = (decoded['indexedContacts'] as List? ?? const [])
                .whereType<Map>()
                .map((e) =>
                    IndexedContact.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            _deviceContacts = (decoded['deviceContacts'] as List? ?? const [])
                .whereType<Map>()
                .map((e) =>
                    DeviceContactEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList();

            // Fallback: Populate indexedContacts from deviceContacts if needed
            if (_indexedContacts.isEmpty && _deviceContacts.isNotEmpty) {
              final matchByHash = {
                for (final m in _opaqueMatches)
                  if (m.phoneHash != null) m.phoneHash!: m
              };
              _indexedContacts = _deviceContacts
                  .map((d) => IndexedContact(
                        localName: d.localName,
                        phoneNumber: d.phoneNumber,
                        phoneHash: d.phoneHash,
                        phoneDigits: d.phoneDigits.isNotEmpty
                            ? d.phoneDigits
                            : _digitsOnly(d.phoneNumber),
                        opaque: matchByHash[d.phoneHash],
                      ))
                  .toList();
            }
          }
        }
      } else {
        // Fallback to SharedPreferences if file cache doesn't exist yet
        final raw = prefs.getString(_cacheKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _opaqueMatches = (decoded['matches'] as List? ?? const [])
                .whereType<Map>()
                .map((e) =>
                    OpaqueContactMatch.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            _deviceContacts = (decoded['deviceContacts'] as List? ?? const [])
                .whereType<Map>()
                .map((e) =>
                    DeviceContactEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            _permissionDenied = decoded['permissionDenied'] == true;
            _indexedContacts = _deviceContacts
                .map((d) => IndexedContact(
                      localName: d.localName,
                      phoneNumber: d.phoneNumber,
                      phoneHash: d.phoneHash,
                      phoneDigits: _digitsOnly(d.phoneNumber),
                    ))
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[ContactMatchService] cache load failed: $e');
    } finally {
      _cacheLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preparedKey, _initialPrepareDone);

      final file = await _getCacheFile();
      final data = {
        'permissionDenied': _permissionDenied,
        'preparedAt': DateTime.now().toUtc().toIso8601String(),
        'matches': _opaqueMatches.map((m) => m.toJson()).toList(),
        'indexedContacts': _indexedContacts.map((c) => c.toJson()).toList(),
        'deviceContacts': _deviceContacts.map((c) => c.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);

      // Lightweight mapping for fast username -> phone lookups
      final phoneMap = <String, String>{};
      for (final m in _opaqueMatches) {
        if (m.phoneNumber?.isNotEmpty == true) {
          phoneMap[m.username] = m.phoneNumber!;
        }
      }
      await prefs.setString(_phoneMapKey, jsonEncode(phoneMap));
      await prefs.setString('contact_phone_mapping', jsonEncode(phoneMap));
    } catch (e) {
      debugPrint('[ContactMatchService] persist failed: $e');
    }
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

  Future<bool> _hasAskedRationale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rationaleAskedKey) ?? false;
  }

  Future<void> _markRationaleAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rationaleAskedKey, true);
  }

  /// Login first-open: why-dialog, system permission, fast sync.
  Future<void> promptContactsOnFirstOpen(BuildContext context) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!context.mounted) return;

    try {
      final status = await Permission.contacts.status;
      if (status.isGranted || status.isLimited) {
        await _markRationaleAsked();
        unawaited(syncContacts());
        return;
      }
      if (await _hasAskedRationale()) return;
      if (status.isPermanentlyDenied) {
        await _markRationaleAsked();
        _permissionDenied = true;
        return;
      }

      final continueToSystem = await _showContactsRationaleDialog(context);
      await _markRationaleAsked();
      if (continueToSystem != true) {
        _permissionDenied = true;
        notifyListeners();
        return;
      }
      if (!context.mounted) return;

      final result = await Permission.contacts.request();
      final granted = result.isGranted || result.isLimited;
      _permissionDenied = !granted;
      notifyListeners();
      if (granted) {
        unawaited(syncContacts());
      }
    } catch (e) {
      debugPrint('[ContactMatchService] first-open prompt failed: $e');
      await _markRationaleAsked();
    }
  }

  Future<bool?> _showContactsRationaleDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF19202A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF303947)),
          ),
          title: const Text(
            'Find people you know',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE0E6EF),
            ),
          ),
          content: const Text(
            'Opaque uses your contacts to show friends who are already on the app in your chat list, so you can message them quickly.\n\n'
            'Your phone numbers are checked privately (hashed) and are never uploaded as a raw contact list.\n\n'
            'You can skip this and still use Opaque. People you know just will not appear automatically.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              height: 1.55,
              color: Color(0xFF9CA8BB),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Not now',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Color(0xFF9CA8BB),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8AAFE4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Fast bulk sync:
  /// Single native IPC read -> local indexing -> background batch match with server.
  Future<bool> syncContacts({bool force = false}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
    if (_syncing) return hasCachedData;

    await loadCachedMatches();

    final status = await Permission.contacts.status;
    if (!(status.isGranted || status.isLimited)) {
      _permissionDenied = true;
      notifyListeners();
      return hasCachedData;
    }

    _syncing = true;
    _permissionDenied = false;
    notifyListeners();

    try {
      // 1. Fetch contacts in a single fast platform query (no photo/thumbnail/account overhead)
      final listed = await FlutterContacts.getContacts(
        withProperties: true,
        withThumbnail: false,
        withPhoto: false,
        withAccounts: false,
        withGroups: false,
        sorted: false,
      ).timeout(const Duration(seconds: 15));

      if (listed.isEmpty) {
        _indexedContacts = [];
        _opaqueMatches = [];
        _deviceContacts = [];
        _initialPrepareDone = true;
        await _persist();
        return true;
      }

      // 2. Normalize and hash all contacts in a single CPU pass
      final newIndexed = <IndexedContact>[];
      final deviceList = <DeviceContactEntry>[];
      final hashed = <String>[];
      final hashToContacts = <String, List<IndexedContact>>{};
      final seenDigits = <String>{};

      // Preserve existing server matches if offline
      final existingMatchesByHash = <String, OpaqueContactMatch>{};
      for (final m in _opaqueMatches) {
        if (m.phoneHash != null) {
          existingMatchesByHash[m.phoneHash!] = m;
        }
      }

      for (final c in listed) {
        final localName =
            c.displayName.trim().isEmpty ? 'Unknown' : c.displayName.trim();
        for (final p in c.phones) {
          final normalized = _normalizePhone(p.number);
          if (normalized == null) continue;
          final digits = _digitsOnly(normalized);
          if (digits.length < 5 || !seenDigits.add(digits)) continue;

          final hash = sha256.convert(utf8.encode(normalized)).toString();
          final contact = IndexedContact(
            localName: localName,
            phoneNumber: normalized,
            phoneHash: hash,
            phoneDigits: digits,
            opaque: existingMatchesByHash[hash],
          );
          newIndexed.add(contact);
          deviceList.add(DeviceContactEntry(
            localName: localName,
            phoneNumber: normalized,
            phoneHash: hash,
            phoneDigits: digits,
          ));
          hashed.add(hash);
          hashToContacts.putIfAbsent(hash, () => []).add(contact);
        }
      }

      _indexedContacts = newIndexed;
      _deviceContacts = deviceList;
      _initialPrepareDone = true;

      // Persist local address book immediately so search works right now
      await _persist();
      notifyListeners();

      // 3. Batch match with server in background if authenticated
      if (FirebaseAuth.instance.currentUser != null && hashed.isNotEmpty) {
        final matches = await _batchMatchHashes(hashed, hashToContacts);
        if (matches.isNotEmpty) {
          _opaqueMatches = matches;
          for (final m in matches) {
            if (m.phoneHash != null && hashToContacts.containsKey(m.phoneHash)) {
              for (final c in hashToContacts[m.phoneHash]!) {
                c.opaque = m;
              }
            }
          }
          await _persist();
          notifyListeners();
        }
      }
      return true;
    } catch (e, st) {
      debugPrint('[ContactMatchService] sync failed: $e\n$st');
      return hasCachedData;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Backward-compatible alias for gradual prepare
  Future<void> prepareHomeSampleGradually() async {
    await syncContacts();
  }

  /// After login: match cached sample phones against Opaque without re-reading phonebook.
  Future<void> rematchCachedAfterAuth() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_indexedContacts.isEmpty && _deviceContacts.isEmpty) return;

    final hashed = <String>[];
    final hashToContacts = <String, List<IndexedContact>>{};
    for (final c in _indexedContacts) {
      if (c.phoneHash.isEmpty) continue;
      hashed.add(c.phoneHash);
      hashToContacts.putIfAbsent(c.phoneHash, () => []).add(c);
    }
    if (hashed.isEmpty) return;

    final matches = await _batchMatchHashes(hashed, hashToContacts);
    if (matches.isNotEmpty) {
      _opaqueMatches = matches;
      for (final m in matches) {
        if (m.phoneHash != null && hashToContacts.containsKey(m.phoneHash)) {
          for (final c in hashToContacts[m.phoneHash]!) {
            c.opaque = m;
          }
        }
      }
      await _persist();
      notifyListeners();
    }
  }

  /// Auth contacts step: show system permission dialog only.
  Future<bool> requestPermissionForDedicatedSetup() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _permissionDenied = false;
      notifyListeners();
      return true;
    }

    await loadCachedMatches();
    await _markRationaleAsked();

    try {
      var status = await Permission.contacts.status;
      if (status.isGranted || status.isLimited) {
        _permissionDenied = false;
        notifyListeners();
        return true;
      }
      if (status.isPermanentlyDenied) {
        _permissionDenied = true;
        notifyListeners();
        return false;
      }

      status = await Permission.contacts.request();
      final granted = status.isGranted || status.isLimited;
      _permissionDenied = !granted;
      notifyListeners();
      return granted;
    } catch (e) {
      debugPrint('[ContactMatchService] permission request failed: $e');
      _permissionDenied = true;
      notifyListeners();
      return false;
    }
  }

  /// Auth contacts step: run fast full sync upon permission.
  Future<bool> prepareFromDedicatedSetupStep() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _initialPrepareDone = true;
      await _persist();
      return true;
    }

    await loadCachedMatches();
    await _markRationaleAsked();

    try {
      var status = await Permission.contacts.status;
      if (!(status.isGranted || status.isLimited)) {
        if (status.isPermanentlyDenied) {
          _permissionDenied = true;
          _initialPrepareDone = true;
          await _persist();
          notifyListeners();
          return false;
        }
        status = await Permission.contacts.request();
      }

      final granted = status.isGranted || status.isLimited;
      _permissionDenied = !granted;
      if (!granted) {
        _initialPrepareDone = true;
        await _persist();
        notifyListeners();
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_setupSkippedKey, false);
      _setupSkipped = false;

      await syncContacts();
      return hasCachedData || _initialPrepareDone;
    } catch (e) {
      debugPrint('[ContactMatchService] dedicated setup failed: $e');
      _initialPrepareDone = true;
      await _persist();
      notifyListeners();
      return false;
    }
  }

  /// Auth contacts step: user chose Skip.
  Future<void> skipContactsSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupSkippedKey, true);
    _setupSkipped = true;
    _initialPrepareDone = true;
    await _markRationaleAsked();
    await _persist();
    notifyListeners();
  }

  /// Registration: fast sync.
  Future<bool> prepareAtRegistration() async {
    await loadCachedMatches();
    if (hasCachedData) return true;
    final status = await Permission.contacts.status;
    if (status.isGranted || status.isLimited) {
      return syncContacts();
    }
    _permissionDenied = true;
    _initialPrepareDone = true;
    await _persist();
    notifyListeners();
    return false;
  }

  Future<bool> refreshLimitedSample() async {
    return syncContacts(force: true);
  }

  Future<bool> ensureSynced({bool force = false}) async {
    await loadCachedMatches();
    if (!force && (_initialPrepareDone || hasCachedData)) return hasCachedData;
    return syncContacts(force: force);
  }

  /// Instant local in-memory search for both local contact names and phone numbers.
  /// Execution time is < 1ms; 0 network calls and 0 platform channel IPC.
  List<ContactSearchHit> searchContacts(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];

    final q = query.toLowerCase();
    final qDigits = _digitsOnly(query);
    final hits = <ContactSearchHit>[];
    final seen = <String>{};

    for (final contact in _indexedContacts) {
      bool matched = false;

      // 1. Local contact name match
      if (contact.localNameLower.contains(q)) {
        matched = true;
      }
      // 2. Phone number digits match
      else if (qDigits.length >= 2 && contact.phoneDigits.contains(qDigits)) {
        matched = true;
      }
      // 3. Opaque username or display name match
      else if (contact.opaque != null) {
        final u = contact.opaque!.username.toLowerCase();
        final d = (contact.opaque!.displayName ?? '').toLowerCase();
        if (u.contains(q) || d.contains(q)) {
          matched = true;
        }
      }

      if (matched) {
        final key = contact.opaque != null
            ? 'u:${contact.opaque!.username.toLowerCase()}'
            : 'p:${contact.phoneDigits}';
        if (seen.add(key)) {
          hits.add(ContactSearchHit(
            localName: contact.localName,
            phoneNumber: contact.phoneNumber,
            opaque: contact.opaque,
          ));
        }
      }
      if (hits.length >= searchFetchLimit) break;
    }

    // Sort: Opaque users first, then exact/prefix match, then alphabetical
    hits.sort((a, b) {
      if (a.isOnOpaque != b.isOnOpaque) {
        return a.isOnOpaque ? -1 : 1;
      }
      final an = a.localName.toLowerCase();
      final bn = b.localName.toLowerCase();
      final aExact = an == q ? 0 : (an.startsWith(q) ? 1 : 2);
      final bExact = bn == q ? 0 : (bn.startsWith(q) ? 1 : 2);
      if (aExact != bExact) return aExact - bExact;
      return an.compareTo(bn);
    });

    return hits;
  }

  /// Backward-compatible search method
  Future<List<ContactSearchHit>> searchByLocalName(String rawQuery) async {
    return searchContacts(rawQuery);
  }

  /// Background batch server matching
  Future<List<OpaqueContactMatch>> _batchMatchHashes(
    List<String> hashed,
    Map<String, List<IndexedContact>> hashToContacts,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || hashed.isEmpty) return const [];

    final allMatches = <OpaqueContactMatch>[];
    const chunkSize = 500;

    for (var i = 0; i < hashed.length; i += chunkSize) {
      final chunk = hashed.sublist(i, math.min(i + chunkSize, hashed.length));
      try {
        final token = await user.getIdToken();
        final response = await http
            .post(
              Uri.parse('${AppConfig.baseUrl}/friends/find'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(chunk),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(response.body);
        final foundUsers = decoded is List ? decoded : const [];

        for (final data in foundUsers) {
          if (data is String) {
            allMatches.add(OpaqueContactMatch(username: data));
            continue;
          }
          if (data is! Map) continue;
          final map = Map<String, dynamic>.from(data);
          final phoneHash = map['phoneHash'] as String?;
          final matchedContacts =
              phoneHash != null ? hashToContacts[phoneHash] : null;
          final localName = matchedContacts?.isNotEmpty == true
              ? matchedContacts!.first.localName
              : null;
          final phone = matchedContacts?.isNotEmpty == true
              ? matchedContacts!.first.phoneNumber
              : (map['phoneNumber'] ?? map['phone_number']) as String?;

          allMatches.add(
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
              phoneHash: phoneHash,
            ),
          );
        }
      } catch (e) {
        debugPrint('[ContactMatchService] batch match chunk failed: $e');
      }
    }
    return allMatches;
  }

  void applyMatches({
    required List<OpaqueContactMatch> matches,
    required List<DeviceContactEntry> deviceContacts,
  }) {
    _opaqueMatches = matches;
    _deviceContacts = deviceContacts;
    final matchByHash = {
      for (final m in matches)
        if (m.phoneHash != null) m.phoneHash!: m
    };
    _indexedContacts = deviceContacts
        .map((d) => IndexedContact(
              localName: d.localName,
              phoneNumber: d.phoneNumber,
              phoneHash: d.phoneHash,
              phoneDigits: d.phoneDigits.isNotEmpty
                  ? d.phoneDigits
                  : _digitsOnly(d.phoneNumber),
              opaque: matchByHash[d.phoneHash],
            ))
        .toList();
    _initialPrepareDone = true;
    _permissionDenied = false;
    _cacheLoaded = true;
    unawaited(_persist());
    notifyListeners();
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
