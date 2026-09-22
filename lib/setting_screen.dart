import 'dart:async';
import 'widgets/opaque_design.dart';
import 'widgets/backup_design.dart';
import 'widgets/opaque_toast.dart';
import 'screens/security_pin_screen.dart';
// lib/setting_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import 'package:zarq_messenger/screens/backup_management_screen.dart';
import 'package:zarq_messenger/screens/style_screen.dart';
import 'package:zarq_messenger/screens/tutorial_screen.dart';
import 'profile_background.dart';
import 'login_screen.dart';
import 'about_screen.dart';
import 'package:provider/provider.dart';
import 'services/user_settings_provider.dart';
import 'services/websocket_service.dart';
import 'services/SignalService.dart';
import 'services/key_rotation_service.dart';
import 'services/database_service.dart';
import 'widgets/call_aware_screen.dart';
import 'services/overlay_permission_helper.dart';
import 'services/system_overlay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/app_config.dart';

class Friend {
  final String username;
  final String? avatarUrl;

  Friend({required this.username, this.avatarUrl});

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      username: json['username'] ?? 'Unknown',
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'] ?? json['profile_picture_url'] ?? json['avatar']) as String?,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  // Static in-memory cache across screen navigations in the current session
  static String? _cachedUid;
  static String? _cachedUsername;
  static String? _cachedDisplayName;

  // Active bottom sheet updater (if profile sheet is open during a background sync)
  void Function(void Function())? _profileSheetUpdater;

  late TextEditingController _nameController;
  bool _isUploading = false;
  String? _avatarUrl;
  String? _displayName;
  String? _username;
  bool _twoFactorEnabled = false;
  bool _isFriendsListVisible = false;
  bool _isFriendsLoading = false;
  List<Friend> _friendsList = [];
  final _displayNameController = TextEditingController();
  String _avatarPrivacy = 'everyone';
  String _messagingPrivacy = 'everyone';
  String _lastSeenPrivacy = 'everyone';
  String? _contactEmail;
  bool _contactEmailVerified = false;
  static String? _savedPendingPassword;

  /// Returns the account's primary email to display.
  /// 1. If user signed in with Google (or has google.com provider), return the Google email (always verified).
  /// 2. If user.email is verified, return user.email.
  /// 3. If contact_email is confirmed in backend, return contact_email.
  /// 4. If user.email is not null, return user.email.
  /// 5. Otherwise, check providerData for any provider with an email.
  String? get _activeVerifiedEmail {
    final user = _currentUser;
    if (user == null) return null;

    // 1. Google provider email is always verified by Google and cannot be lost
    for (final p in user.providerData) {
      if (p.providerId == 'google.com' &&
          p.email != null &&
          p.email!.isNotEmpty) {
        return p.email;
      }
    }

    // 2. Verified top-level email
    if (user.emailVerified && user.email != null && user.email!.isNotEmpty) {
      return user.email;
    }

    // 3. Confirmed backend contact email
    if (_contactEmailVerified &&
        _contactEmail != null &&
        _contactEmail!.isNotEmpty) {
      return _contactEmail;
    }

    // 4. Any top-level email on the Firebase user
    if (user.email != null && user.email!.isNotEmpty) {
      return user.email;
    }

    // 5. Any provider email
    for (final p in user.providerData) {
      if (p.email != null && p.email!.isNotEmpty) {
        return p.email;
      }
    }

    // 6. Backend contact email even if unverified flag hasn't synced
    if (_contactEmail != null && _contactEmail!.isNotEmpty) {
      return _contactEmail;
    }

    return null;
  }

  /// Returns any unverified email pending on the user's account.
  String? get _pendingUnverifiedEmail {
    final user = _currentUser;
    if (user == null) return null;

    final verified = _activeVerifiedEmail?.toLowerCase();

    if (!user.emailVerified &&
        user.email != null &&
        user.email!.isNotEmpty &&
        user.email!.toLowerCase() != verified) {
      return user.email;
    }

    for (final p in user.providerData) {
      if (p.providerId == 'password' &&
          p.email != null &&
          p.email!.isNotEmpty &&
          p.email!.toLowerCase() != verified) {
        return p.email;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _currentUser?.displayName ?? '',
    );
    _avatarUrl = _currentUser?.photoURL;

    // 1. Immediate in-memory cache population (0ms, no flicker)
    final uid = _currentUser?.uid;
    if (_cachedUid == uid && uid != null) {
      _username = _cachedUsername;
      _displayName = _cachedDisplayName ?? _currentUser?.displayName;
    } else {
      _cachedUid = uid;
      _cachedUsername = null;
      _cachedDisplayName = null;
      _username = null;
      _displayName = _currentUser?.displayName;
    }

    if (_displayName != null && _displayName!.isNotEmpty) {
      _displayNameController.text = _displayName!;
    }

    // 2. Load from persistent local storage (survives app restarts)
    _loadCachedProfile();

    // 3. Silent background revalidation with backend (Stale-While-Revalidate)
    _fetchProfileData();
  }

  /// Load profile from local SharedPreferences without blocking UI
  Future<void> _loadCachedProfile() async {
    try {
      final uid = _currentUser?.uid;
      if (uid == null) return;

      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString('cached_user_uid');
      if (savedUid != uid) return;

      final savedUsername = prefs.getString('cached_user_username');
      final savedDisplayName = prefs.getString('cached_user_display_name');
      final saved2fa = prefs.getBool('cached_user_2fa_enabled');

      if (!mounted) return;

      bool changed = false;
      if (savedUsername != null &&
          savedUsername.isNotEmpty &&
          _username == null) {
        _username = savedUsername;
        _cachedUsername = savedUsername;
        changed = true;
      }
      if (savedDisplayName != null &&
          savedDisplayName.isNotEmpty &&
          _displayName == null) {
        _displayName = savedDisplayName;
        _cachedDisplayName = savedDisplayName;
        _displayNameController.text = savedDisplayName;
        changed = true;
      }
      if (saved2fa != null && _twoFactorEnabled != saved2fa) {
        _twoFactorEnabled = saved2fa;
        changed = true;
      }
      final savedAvatarPrivacy = prefs.getString('cached_user_avatar_privacy');
      if (savedAvatarPrivacy != null && savedAvatarPrivacy.isNotEmpty && _avatarPrivacy != savedAvatarPrivacy) {
        _avatarPrivacy = savedAvatarPrivacy;
        changed = true;
      }
      final savedMessagingPrivacy = prefs.getString('cached_user_messaging_privacy');
      if (savedMessagingPrivacy != null && savedMessagingPrivacy.isNotEmpty && _messagingPrivacy != savedMessagingPrivacy) {
        _messagingPrivacy = savedMessagingPrivacy;
        changed = true;
      }
      final savedLastSeenPrivacy = prefs.getString('cached_user_last_seen_privacy');
      if (savedLastSeenPrivacy != null && savedLastSeenPrivacy.isNotEmpty && _lastSeenPrivacy != savedLastSeenPrivacy) {
        _lastSeenPrivacy = savedLastSeenPrivacy;
        changed = true;
      }

      if (changed && mounted) {
        setState(() {});
        _profileSheetUpdater?.call(() {});
      }
    } catch (_) {}
  }

  /// Silent background fetch to ensure local state stays in sync with backend
  Future<void> _fetchProfileData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/profiles/me'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final fetchedDisplayName = data['display_name'] as String?;
        final fetchedUsername = data['username'] as String?;
        final fetchedTwoFactor = data['two_factor_enabled'] as bool? ?? false;

        bool changed = false;

        if (fetchedUsername != null && fetchedUsername.isNotEmpty) {
          if (_username != fetchedUsername) {
            _username = fetchedUsername;
            changed = true;
          }
          _cachedUsername = fetchedUsername;
        }

        if (fetchedDisplayName != null && fetchedDisplayName.isNotEmpty) {
          if (_displayName != fetchedDisplayName) {
            _displayName = fetchedDisplayName;
            _displayNameController.text = fetchedDisplayName;
            changed = true;
          }
          _cachedDisplayName = fetchedDisplayName;
        }

        if (_twoFactorEnabled != fetchedTwoFactor) {
          _twoFactorEnabled = fetchedTwoFactor;
          changed = true;
        }

        final fetchedContactEmail = data['contact_email'] as String?;
        final fetchedContactEmailVerified =
            data['contact_email_verified'] as bool? ?? false;
        if (_contactEmail != fetchedContactEmail) {
          _contactEmail = fetchedContactEmail?.isEmpty == true
              ? null
              : fetchedContactEmail;
          changed = true;
        }
        if (_contactEmailVerified != fetchedContactEmailVerified) {
          _contactEmailVerified = fetchedContactEmailVerified;
          changed = true;
        }

        final fetchedPrivacy =
            (data['avatar_privacy'] ?? data['avatarPrivacy']) as String?;
        if (fetchedPrivacy != null &&
            fetchedPrivacy.isNotEmpty &&
            _avatarPrivacy != fetchedPrivacy) {
          _avatarPrivacy = fetchedPrivacy;
          changed = true;
        }

        final fetchedMsgPrivacy = data['message_privacy'] as String?;
        if (fetchedMsgPrivacy != null &&
            fetchedMsgPrivacy.isNotEmpty &&
            _messagingPrivacy != fetchedMsgPrivacy) {
          _messagingPrivacy = fetchedMsgPrivacy;
          changed = true;
        }

        final fetchedLsPrivacy = data['last_seen_privacy'] as String?;
        if (fetchedLsPrivacy != null &&
            fetchedLsPrivacy.isNotEmpty &&
            _lastSeenPrivacy != fetchedLsPrivacy) {
          _lastSeenPrivacy = fetchedLsPrivacy;
          changed = true;
        }

        final fetchedAvatar =
            (data['avatarUrl'] ?? data['profile_picture_url'] ?? data['avatar_url'] ?? data['avatar']) as String?;
        if (fetchedAvatar != null && fetchedAvatar.isNotEmpty) {
          if (_avatarUrl != fetchedAvatar) {
            _avatarUrl = fetchedAvatar;
            changed = true;
          }
          if (user.photoURL == null || user.photoURL!.isEmpty) {
            unawaited(user.updatePhotoURL(fetchedAvatar).catchError((_) {}));
          }
        } else if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          _avatarUrl = user.photoURL;
          changed = true;
          unawaited(_updateAvatarUrlInBackend(user.photoURL!).catchError((_) {}));
        }

        final uid = user.uid;
        _cachedUid = uid;

        // Persist to local storage for offline reliability
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_user_uid', uid);
          if (fetchedUsername != null && fetchedUsername.isNotEmpty) {
            await prefs.setString('cached_user_username', fetchedUsername);
          }
          if (fetchedDisplayName != null && fetchedDisplayName.isNotEmpty) {
            await prefs.setString(
              'cached_user_display_name',
              fetchedDisplayName,
            );
          }
          await prefs.setBool('cached_user_2fa_enabled', fetchedTwoFactor);
          if (_avatarPrivacy.isNotEmpty) {
            await prefs.setString('cached_user_avatar_privacy', _avatarPrivacy);
          }
          if (_messagingPrivacy.isNotEmpty) {
            await prefs.setString('cached_user_messaging_privacy', _messagingPrivacy);
          }
          if (_lastSeenPrivacy.isNotEmpty) {
            await prefs.setString('cached_user_last_seen_privacy', _lastSeenPrivacy);
          }
        } catch (_) {}

        if (mounted && changed) {
          setState(() {});
          _profileSheetUpdater?.call(() {});
        }
      }
    } catch (e) {
      // Silent error: Keep existing cached profile intact without showing placeholders
    }
  }

  /// Clear in-memory and persistent profile cache (e.g. on logout/delete account)
  static Future<void> _clearProfileCache() async {
    _cachedUid = null;
    _cachedUsername = null;
    _cachedDisplayName = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_user_uid');
      await prefs.remove('cached_user_username');
      await prefs.remove('cached_user_display_name');
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    if (_isUploading) return;

    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      // Delete old avatar from Firebase Storage if replacing
      if (_avatarUrl != null &&
          _avatarUrl!.contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(_avatarUrl!).delete();
        } catch (_) {}
      }

      // Generate opaque random UUID to completely hide Firebase UID from CDN URL
      final avatarId = const Uuid().v4();
      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/$avatarId.jpg',
      );
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      );

      String downloadUrl;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        final uploadTask = storageRef.putData(bytes, metadata);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        final file = File(pickedFile.path);
        final uploadTask = storageRef.putFile(file, metadata);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      await _updateAvatarUrlInBackend(downloadUrl);
      await _currentUser!.updatePhotoURL(downloadUrl);
      if (mounted) setState(() => _avatarUrl = downloadUrl);
    } catch (e) {
      if (mounted) {
        OpaqueToast.error(context, 'Failed to upload image: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _updateAvatarUrlInBackend(String url) async {
    final token = await _currentUser?.getIdToken();
    if (token == null) throw Exception("User not authenticated");

    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/profile/avatar/update'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'avatarUrl': url}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update avatar in backend: ${response.body}');
    }
  }

  Future<void> _updateAvatarPrivacy(String newSetting) async {
    if (_avatarPrivacy == newSetting) return;
    final previous = _avatarPrivacy;
    setState(() {
      _avatarPrivacy = newSetting;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_avatar_privacy', newSetting);
      final token = await _currentUser?.getIdToken();
      if (token == null) {
        if (mounted) {
          setState(() => _avatarPrivacy = previous);
          await prefs.setString('cached_user_avatar_privacy', previous);
        }
        return;
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/profile/privacy/avatar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatarPrivacy': newSetting}),
      );
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _avatarPrivacy = previous);
          await prefs.setString('cached_user_avatar_privacy', previous);
          OpaqueToast.error(context, 'Failed to update privacy');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _avatarPrivacy = previous);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_avatar_privacy', previous);
        OpaqueToast.error(context, 'Failed to update privacy: $e');
      }
    }
  }

  Future<void> _updateMessagingPrivacy(String newSetting) async {
    if (_messagingPrivacy == newSetting) return;
    final previous = _messagingPrivacy;
    setState(() {
      _messagingPrivacy = newSetting;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_messaging_privacy', newSetting);
      final token = await _currentUser?.getIdToken();
      if (token == null) {
        if (mounted) {
          setState(() => _messagingPrivacy = previous);
          await prefs.setString('cached_user_messaging_privacy', previous);
        }
        return;
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/profile/privacy/message'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'messagingPrivacy': newSetting}),
      );
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _messagingPrivacy = previous);
          await prefs.setString('cached_user_messaging_privacy', previous);
          OpaqueToast.error(context, 'Failed to update messaging privacy');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messagingPrivacy = previous);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_messaging_privacy', previous);
        OpaqueToast.error(context, 'Failed to update: $e');
      }
    }
  }

  Future<void> _updateLastSeenPrivacy(String newSetting) async {
    if (_lastSeenPrivacy == newSetting) return;
    final previous = _lastSeenPrivacy;
    setState(() {
      _lastSeenPrivacy = newSetting;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_last_seen_privacy', newSetting);
      final token = await _currentUser?.getIdToken();
      if (token == null) {
        if (mounted) {
          setState(() => _lastSeenPrivacy = previous);
          await prefs.setString('cached_user_last_seen_privacy', previous);
        }
        return;
      }
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/profile/privacy/lastseen'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'lastSeenPrivacy': newSetting}),
      );
      if (response.statusCode != 200) {
        if (mounted) {
          setState(() => _lastSeenPrivacy = previous);
          await prefs.setString('cached_user_last_seen_privacy', previous);
          OpaqueToast.error(context, 'Failed to update last seen privacy');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastSeenPrivacy = previous);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_last_seen_privacy', previous);
        OpaqueToast.error(context, 'Failed to update: $e');
      }
    }
  }

  void _showAvatarPrivacyDialog() {
    final c = OpaqueColors(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget option(String title, String subtitle, String value) {
          final isSelected = _avatarPrivacy == value;
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              _updateAvatarPrivacy(value);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: c.text(13, bold: isSelected)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: c.text(10, muted: true)),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: c.ink, size: 18)
                  else
                    Icon(
                      Icons.radio_button_unchecked,
                      color: c.muted,
                      size: 18,
                    ),
                ],
              ),
            ),
          );
        }

        return OpaqueSheet(
          title: 'Profile photo privacy',
          description: 'Choose who can see your profile photo.',
          showIcon: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                'Everyone',
                'Any user on Opaque can see your photo',
                'everyone',
              ),
              option(
                'Friends only',
                'Only accepted friends can see your photo',
                'contacts',
              ),
              option('Nobody', 'No one can see your photo', 'nobody'),
            ],
          ),
        );
      },
    );
  }

  void _showMessagingPrivacyDialog() {
    final c = OpaqueColors(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget option(String title, String subtitle, String value) {
          final isSelected = _messagingPrivacy == value;
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              _updateMessagingPrivacy(value);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: c.text(13, bold: isSelected)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: c.text(10, muted: true)),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: c.ink, size: 18)
                  else
                    Icon(Icons.radio_button_unchecked, color: c.muted, size: 18),
                ],
              ),
            ),
          );
        }

        return OpaqueSheet(
          title: 'Who can message you',
          description: 'Control who can start new conversations with you.',
          showIcon: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option('Everyone', 'Any Opaque user can message you', 'everyone'),
              option('Friends only', 'Only your friends can start a new chat', 'friends'),
              option('Nobody', 'No one can initiate a new conversation with you', 'nobody'),
            ],
          ),
        );
      },
    );
  }

  void _showLastSeenPrivacyDialog() {
    final c = OpaqueColors(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget option(String title, String subtitle, String value) {
          final isSelected = _lastSeenPrivacy == value;
          return InkWell(
            onTap: () {
              Navigator.pop(ctx);
              _updateLastSeenPrivacy(value);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: c.text(13, bold: isSelected)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: c.text(10, muted: true)),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: c.ink, size: 18)
                  else
                    Icon(Icons.radio_button_unchecked, color: c.muted, size: 18),
                ],
              ),
            ),
          );
        }

        return OpaqueSheet(
          title: 'Last seen & online',
          description: 'Choose who can see when you were last active.',
          showIcon: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option('Everyone', 'Any user can see your last seen', 'everyone'),
              option('Friends only', 'Only your friends see your last seen', 'friends'),
              option('Nobody', 'No one can see your last seen or online status', 'nobody'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchFriendsList() async {
    if (!mounted) return;
    setState(() => _isFriendsLoading = true);

    try {
      final token = await _currentUser?.getIdToken();
      if (token == null) throw Exception("Not authenticated");

      final url = Uri.parse('${AppConfig.baseUrl}/friends/list');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mounted) {
        if (response.statusCode == 200) {
          final List<dynamic> friendsFromServer = json.decode(response.body);
          setState(() {
            _friendsList = friendsFromServer
                .map((data) => Friend.fromJson(data))
                .toList();
          });
        } else {
          throw Exception('Failed to load friends list: ${response.body}');
        }
      }
    } catch (e) {
      if (mounted) {
        OpaqueToast.error(context, 'Error fetching friends: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isFriendsLoading = false);
      }
    }
  }

  void _toggleFriendsList() {
    setState(() {
      _isFriendsListVisible = !_isFriendsListVisible;
      if (_isFriendsListVisible && _friendsList.isEmpty) {
        _fetchFriendsList();
      }
    });
  }

  Future<void> _updateDisplayName() async {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty && newName != _currentUser?.displayName) {
      try {
        await _currentUser?.updateDisplayName(newName);
        if (mounted) {
          setState(() {});
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          OpaqueToast.error(context, 'Failed to update name: $e');
        }
      }
    }
  }

  Future<void> _updateUserDisplayName() async {
    final newDisplayName = _displayNameController.text.trim();
    if (newDisplayName.isEmpty) {
      OpaqueToast.error(context, 'Display name cannot be empty');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/profile/displayname/update'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'displayName': newDisplayName}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        _cachedDisplayName = newDisplayName;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_user_display_name', newDisplayName);
        } catch (_) {}
        setState(() {
          _displayName = newDisplayName;
        });
        Navigator.of(context).pop();
      } else {
        OpaqueToast.error(
          context,
          'Failed to update display name: ${response.body}',
        );
      }
    } catch (e) {
      if (mounted) {
        OpaqueToast.error(context, 'Error updating display name: $e');
      }
    }
  }

  void _showEditDisplayNameDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final dialogTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final borderRadius = (screenWidth * 0.04).clamp(12.0, 18.0);

    _displayNameController.text = _displayName ?? '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0a1128).withOpacity(0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
          ),
          title: Text(
            'Edit Display Name',
            style: TextStyle(color: Colors.white, fontSize: dialogTitleSize),
          ),
          content: TextField(
            controller: _displayNameController,
            autofocus: true,
            maxLength: 30,
            style: TextStyle(color: Colors.white, fontSize: dialogTextSize),
            decoration: InputDecoration(
              hintText: "Enter display name",
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: dialogTextSize,
              ),
              helperText: 'Maximum 30 characters',
              helperStyle: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: dialogTextSize * 0.9,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.cyanAccent.withOpacity(0.5),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: dialogTextSize,
                ),
              ),
            ),
            TextButton(
              onPressed: _updateUserDisplayName,
              child: Text(
                'Save',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: dialogTextSize,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ================== BACKUP METHODS ==================

  void _showEditNameDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final dialogTextSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final borderRadius = (screenWidth * 0.04).clamp(12.0, 18.0);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0a1128).withOpacity(0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
          ),
          title: Text(
            'Edit Display Name',
            style: TextStyle(color: Colors.white, fontSize: dialogTitleSize),
          ),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            style: TextStyle(color: Colors.white, fontSize: dialogTextSize),
            decoration: InputDecoration(
              hintText: "Enter your new name",
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: dialogTextSize,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.cyanAccent.withOpacity(0.5),
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyanAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: dialogTextSize,
                ),
              ),
            ),
            TextButton(
              onPressed: _updateDisplayName,
              child: Text(
                'Save',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: dialogTextSize,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditUsernameDialog(OpaqueColors c) async {
    final controller = TextEditingController(text: _username ?? '');
    bool checking = false;
    bool saving = false;
    String? statusText;
    bool isAvailable = false;
    Timer? debounceTimer;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          void checkAvailability(String val) {
            final trimmed = val.trim();
            debounceTimer?.cancel();
            if (trimmed.isEmpty) {
              setModalState(() {
                statusText = null;
                isAvailable = false;
                checking = false;
              });
              return;
            }
            if (trimmed == _username) {
              setModalState(() {
                statusText = 'This is your current username';
                isAvailable = false;
                checking = false;
              });
              return;
            }
            if (trimmed.length < 3) {
              setModalState(() {
                statusText = 'Username must be at least 3 characters';
                isAvailable = false;
                checking = false;
              });
              return;
            }
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
              setModalState(() {
                statusText = 'Only letters, numbers, and underscores allowed';
                isAvailable = false;
                checking = false;
              });
              return;
            }

            setModalState(() {
              checking = true;
              statusText = 'Checking availability…';
            });

            debounceTimer = Timer(const Duration(milliseconds: 400), () async {
              try {
                final response = await http.post(
                  Uri.parse('${AppConfig.baseUrl}/profiles/check-username'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'username': trimmed}),
                );
                if (!modalCtx.mounted) return;
                if (response.statusCode == 200) {
                  final body = jsonDecode(response.body);
                  setModalState(() {
                    checking = false;
                    isAvailable = body['available'] == true;
                    statusText = isAvailable
                        ? 'Username is available'
                        : (body['reason'] ?? 'Username is already taken');
                  });
                } else {
                  setModalState(() {
                    checking = false;
                    isAvailable = false;
                    statusText = 'Could not verify username';
                  });
                }
              } catch (_) {
                if (modalCtx.mounted) {
                  setModalState(() {
                    checking = false;
                    isAvailable = false;
                    statusText = 'Network error checking username';
                  });
                }
              }
            });
          }

          Future<void> saveUsername() async {
            final trimmed = controller.text.trim();
            if (!isAvailable || trimmed.isEmpty) return;
            setModalState(() => saving = true);
            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) throw Exception('Not authenticated');
              final token = await user.getIdToken();
              final resp = await http.post(
                Uri.parse('${AppConfig.baseUrl}/profile/username/update'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'username': trimmed}),
              );
              if (resp.statusCode == 200) {
                _username = trimmed;
                _cachedUsername = trimmed;
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('cached_user_username', trimmed);
                } catch (_) {}
                if (mounted) setState(() {});
                _profileSheetUpdater?.call(() {});
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                if (mounted) {
                  OpaqueToast.show(context, 'Username updated to @$trimmed');
                }
              } else {
                final errBody = jsonDecode(resp.body);
                setModalState(() {
                  saving = false;
                  statusText = errBody['message'] ?? 'Failed to update username';
                });
              }
            } catch (e) {
              setModalState(() {
                saving = false;
                statusText = 'Failed to update username. Please try again.';
              });
            }
          }

          return OpaqueSheet(
            title: 'Change username',
            description: 'Choose a unique username for your account.',
            showIcon: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  enabled: !saving,
                  autofocus: true,
                  style: c.text(14),
                  decoration: c.field('new_username').copyWith(
                        prefixText: '@',
                        prefixStyle: c
                            .text(14, bold: true)
                            .copyWith(color: c.dark ? Colors.white : Colors.black),
                      ),
                  onChanged: checkAvailability,
                ),
                const SizedBox(height: 8),
                if (statusText != null)
                  Row(
                    children: [
                      if (checking)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(c.muted),
                          ),
                        )
                      else
                        Icon(
                          isAvailable
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 13,
                          color: isAvailable
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFBF6974),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          statusText!,
                          style: c.text(10).copyWith(
                                color: isAvailable
                                    ? const Color(0xFF22C55E)
                                    : (checking
                                        ? c.muted
                                        : const Color(0xFFBF6974)),
                              ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OpaqueButton(
                    label: saving ? 'Saving…' : 'Save username',
                    primary: true,
                    onPressed: saving || !isAvailable ? null : saveUsername,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChangePhoneDialog(OpaqueColors c) async {
    final phoneController = TextEditingController();
    final otpController = TextEditingController();
    bool sendingCode = false;
    bool verifying = false;
    String? verificationId;
    int? resendToken;
    String? error;
    bool codeSent = false;
    String completePhoneNumber = '';
    String countryIso = 'IN';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          Future<void> sendCode() async {
            String phone = completePhoneNumber.trim();
            if (phone.isEmpty) {
              final text = phoneController.text.trim();
              if (text.isNotEmpty) {
                phone = text.startsWith('+') ? text : '+$text';
              }
            }
            if (phone.isEmpty || phone.length < 8) {
              setModalState(() => error =
                  'Please enter a valid phone number with country code');
              return;
            }

            final user = FirebaseAuth.instance.currentUser;
            if (user?.phoneNumber != null && user!.phoneNumber == phone) {
              setModalState(() => error =
                  'This phone number is already linked to your account.');
              return;
            }

            setModalState(() {
              sendingCode = true;
              error = null;
            });

            // Step 1 check: Check if phone number is already registered before sending SMS code
            try {
              final tok = user != null ? await user.getIdToken() : null;
              final checkRes = await http.post(
                Uri.parse('${AppConfig.baseUrl}/profiles/check-phone'),
                headers: {
                  if (tok != null) 'Authorization': 'Bearer $tok',
                  'Content-Type': 'application/json',
                },
                body: json.encode({'phone': phone}),
              );
              if (checkRes.statusCode == 200) {
                final data = json.decode(checkRes.body);
                if (data['available'] == false) {
                  setModalState(() {
                    sendingCode = false;
                    error = data['reason'] ??
                        'This phone number is already registered to another account.';
                  });
                  return;
                }
              }
            } catch (e) {
              debugPrint('[Settings] check-phone error: $e');
            }

            try {
              await FirebaseAuth.instance.verifyPhoneNumber(
                phoneNumber: phone,
                timeout: const Duration(seconds: 60),
                forceResendingToken: resendToken,
                verificationCompleted:
                    (PhoneAuthCredential credential) async {
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      if (user.phoneNumber != null &&
                          user.phoneNumber!.isNotEmpty) {
                        await user.updatePhoneNumber(credential);
                      } else {
                        await user.linkWithCredential(credential);
                      }
                      final token = await user.getIdToken(true);
                      await http.post(
                        Uri.parse('${AppConfig.baseUrl}/profile/phone/update'),
                        headers: {'Authorization': 'Bearer $token'},
                      );
                      if (mounted) setState(() {});
                      _profileSheetUpdater?.call(() {});
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      if (mounted) {
                        OpaqueToast.show(
                            context, 'Phone number updated successfully');
                      }
                    }
                  } catch (e) {
                    if (modalCtx.mounted) {
                      setModalState(() => error = e.toString());
                    }
                  }
                },
                verificationFailed: (FirebaseAuthException e) {
                  if (modalCtx.mounted) {
                    setModalState(() {
                      sendingCode = false;
                      error = e.message ?? 'Verification failed';
                    });
                  }
                },
                codeSent: (String id, int? token) {
                  if (modalCtx.mounted) {
                    setModalState(() {
                      verificationId = id;
                      resendToken = token;
                      codeSent = true;
                      sendingCode = false;
                      error = null;
                    });
                  }
                },
                codeAutoRetrievalTimeout: (String id) {
                  verificationId = id;
                },
              );
            } catch (e) {
              if (modalCtx.mounted) {
                setModalState(() {
                  sendingCode = false;
                  error = 'Could not send verification code: $e';
                });
              }
            }
          }

          Future<void> verifyOtp() async {
            final otp = otpController.text.trim();
            if (otp.length != 6) {
              setModalState(
                  () => error = 'Enter the 6-digit verification code');
              return;
            }
            if (verificationId == null) {
              setModalState(
                  () => error = 'Session expired. Please request a new code.');
              return;
            }
            setModalState(() {
              verifying = true;
              error = null;
            });
            try {
              final credential = PhoneAuthProvider.credential(
                verificationId: verificationId!,
                smsCode: otp,
              );
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) throw Exception('User not authenticated');

              if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
                await user.updatePhoneNumber(credential);
              } else {
                await user.linkWithCredential(credential);
              }

              final token = await user.getIdToken(true);
              await http.post(
                Uri.parse('${AppConfig.baseUrl}/profile/phone/update'),
                headers: {'Authorization': 'Bearer $token'},
              );

              if (mounted) setState(() {});
              _profileSheetUpdater?.call(() {});
              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              if (mounted) {
                OpaqueToast.show(context, 'Phone number updated successfully');
              }
            } on FirebaseAuthException catch (e) {
              setModalState(() {
                verifying = false;
                if (e.code == 'credential-already-in-use') {
                  error =
                      'This phone number is already linked to another account.';
                } else if (e.code == 'invalid-verification-code') {
                  error = 'Invalid 6-digit code. Please try again.';
                } else {
                  error = e.message ?? 'Verification failed';
                }
              });
            } catch (e) {
              setModalState(() {
                verifying = false;
                error = 'Failed to link phone number. Please try again.';
              });
            }
          }

          return PopScope(
            canPop: !sendingCode && !verifying,
            child: OpaqueSheet(
              title: codeSent
                  ? 'Verify phone number'
                  : (_currentUser?.phoneNumber != null &&
                          _currentUser!.phoneNumber!.isNotEmpty
                      ? 'Change phone number'
                      : 'Link phone number'),
              description: codeSent
                  ? 'Enter the 6-digit code sent to ${completePhoneNumber.isNotEmpty ? completePhoneNumber : 'your phone'}.'
                  : (_currentUser?.phoneNumber != null &&
                          _currentUser!.phoneNumber!.isNotEmpty
                      ? 'Current phone: ${_currentUser!.phoneNumber}'
                      : 'Select your country and enter your phone number.'),
              showIcon: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!codeSent) ...[
                    Theme(
                      data: Theme.of(sheetCtx).copyWith(
                        dialogTheme: DialogThemeData(
                          backgroundColor: c.surface,
                          surfaceTintColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: c.line, width: 1),
                          ),
                        ),
                      ),
                      child: IntlPhoneField(
                        controller: phoneController,
                        enabled: !sendingCode,
                        initialCountryCode: countryIso,
                        style: c.text(14),
                        dropdownTextStyle: c.text(13, bold: true),
                        dropdownIcon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: c.muted,
                        ),
                        cursorColor: c.dark ? Colors.white : Colors.black,
                        showCountryFlag: true,
                        showDropdownIcon: true,
                        dropdownIconPosition: IconPosition.trailing,
                        flagsButtonMargin: const EdgeInsets.only(
                          left: 6,
                          right: 10,
                          top: 4,
                          bottom: 4,
                        ),
                        flagsButtonPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        dropdownDecoration: BoxDecoration(
                          color: c.dark
                              ? const Color(0xFF283241)
                              : const Color(0xFFE9EBEF),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: c.dark
                                ? const Color(0xFF384556)
                                : const Color(0xFFD5D8DF),
                            width: 1,
                          ),
                        ),
                        pickerDialogStyle: PickerDialogStyle(
                          backgroundColor: c.surface,
                          padding: const EdgeInsets.all(16),
                          searchFieldPadding:
                              const EdgeInsets.only(bottom: 12),
                          searchFieldCursorColor:
                              c.dark ? Colors.white : Colors.black,
                          searchFieldInputDecoration: InputDecoration(
                            hintText: 'Search country name or code…',
                            hintStyle: c.text(12, muted: true),
                            prefixIcon:
                                Icon(Icons.search, size: 18, color: c.muted),
                            filled: true,
                            fillColor: c.soft,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: c.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: c.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF22C55E),
                                width: 1.5,
                              ),
                            ),
                          ),
                          countryNameStyle: c.text(13),
                          countryCodeStyle: c.text(12, bold: true).copyWith(
                                color: c.dark
                                    ? const Color(0xFF8BB5F8)
                                    : const Color(0xFF1A73E8),
                              ),
                          listTileDivider: Divider(height: 1, color: c.line),
                          listTilePadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                        ),
                        decoration: c.field('Phone number').copyWith(
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                        onChanged: (phone) {
                          completePhoneNumber = phone.completeNumber;
                          if (error != null) {
                            setModalState(() => error = null);
                          }
                        },
                        onCountryChanged: (country) {
                          countryIso = country.code;
                          completePhoneNumber =
                              '+${country.fullCountryCode}${phoneController.text.trim()}';
                          if (error != null) {
                            setModalState(() => error = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select your country from the dropdown and enter your phone number.',
                      style: c.text(10, muted: true).copyWith(height: 1.4),
                    ),
                    if (sendingCode) ...[
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: c.dark
                              ? const Color(0xFF283241)
                              : const Color(0xFFE2E5E9),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22C55E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Sending verification code…',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OpaqueButton(
                          label: 'Send verification code',
                          primary: true,
                          onPressed: sendCode,
                        ),
                      ),
                    ],
                  ] else ...[
                    TextField(
                      controller: otpController,
                      enabled: !verifying,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: c
                          .text(18, bold: true)
                          .copyWith(letterSpacing: 8),
                      textAlign: TextAlign.center,
                      decoration:
                          c.field('000000').copyWith(counterText: ''),
                    ),
                    if (verifying) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: c.dark
                              ? const Color(0xFF283241)
                              : const Color(0xFFE2E5E9),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22C55E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Verifying code…',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OpaqueButton(
                          label: 'Verify & update',
                          primary: true,
                          onPressed: verifyOtp,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: sendingCode || verifying ? null : sendCode,
                        child: Text(
                          'Resend code',
                          style: c.text(11, bold: true).copyWith(
                                color: c.dark ? Colors.white : Colors.black,
                              ),
                        ),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: c
                          .text(11)
                          .copyWith(color: const Color(0xFFBF6974)),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChangeGoogleAccountDialog(OpaqueColors c) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await user.reload();
    } catch (_) {}

    final currentEmail =
        _activeVerifiedEmail ?? user.email ?? 'Current Google Account';
    bool busy = false;
    String busyStatus = 'Opening Google…';
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          String cleanError(dynamic e, String fallback) {
            if (e is FirebaseAuthException) {
              switch (e.code) {
                case 'credential-already-in-use':
                  return 'This Google account is already linked to another Opaque user.';
                case 'requires-recent-login':
                  return 'For your security, please sign out and sign back in, then try again.';
                case 'network-request-failed':
                  return 'Network error. Please check your internet connection.';
                default:
                  final msg = e.message;
                  if (msg != null && msg.isNotEmpty) {
                    return msg.replaceAll(RegExp(r'\[.*?\]\s*'), '');
                  }
                  return fallback;
              }
            }
            final s = e.toString().replaceAll(RegExp(r'\[.*?\]\s*'), '');
            if (s.contains('credential-already-in-use')) {
              return 'This Google account is already linked to another Opaque user.';
            }
            if (s.contains('requires-recent-login')) {
              return 'For your security, please sign out and sign back in, then try again.';
            }
            return fallback;
          }

          Future<void> switchGoogleAccount() async {
            setModalState(() {
              busy = true;
              busyStatus = 'Opening Google Sign-In…';
              error = null;
            });

            try {
              final googleSignIn = GoogleSignIn.instance;
              await googleSignIn.initialize();
              await googleSignIn.signOut();

              GoogleSignInAccount googleUser;
              try {
                googleUser = await googleSignIn.authenticate();
              } on GoogleSignInException catch (gErr) {
                if (gErr.code.name == 'canceled') {
                  setModalState(() => busy = false);
                  return;
                }
                setModalState(() {
                  busy = false;
                  error = 'Google Sign-In failed (${gErr.code.name}).';
                });
                return;
              } catch (authErr) {
                final s = authErr.toString();
                if (s.contains('canceled') || s.contains('cancelled')) {
                  setModalState(() => busy = false);
                  return;
                }
                rethrow;
              }

              final authentication = googleUser.authentication;
              final idToken = authentication.idToken;
              if (idToken == null) {
                setModalState(() {
                  busy = false;
                  error = 'Failed to get authentication token from Google.';
                });
                return;
              }

              final newEmail = googleUser.email.trim();
              if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
                setModalState(() {
                  busy = false;
                  error =
                      'You selected the Google account that is already active ($newEmail).';
                });
                return;
              }

              setModalState(() {
                busyStatus = 'Verifying account…';
              });

              // 1. Check if email is already in use in Firebase Auth
              try {
                final methods = await FirebaseAuth.instance
                    .fetchSignInMethodsForEmail(newEmail);
                if (methods.isNotEmpty) {
                  setModalState(() {
                    busy = false;
                    error =
                        'This Google account ($newEmail) is already linked to another user.';
                  });
                  return;
                }
              } catch (e) {
                debugPrint('[Settings] fetchSignInMethodsForEmail: $e');
              }

              // 2. Check backend database availability
              try {
                final tok = await user.getIdToken();
                final checkRes = await http.post(
                  Uri.parse('${AppConfig.baseUrl}/profiles/check-email'),
                  headers: {
                    'Authorization': 'Bearer $tok',
                    'Content-Type': 'application/json',
                  },
                  body: json.encode({'email': newEmail}),
                );
                if (checkRes.statusCode == 200) {
                  final data = json.decode(checkRes.body);
                  if (data['available'] == false) {
                    setModalState(() {
                      busy = false;
                      error = data['reason'] ??
                          'This Google account ($newEmail) is already registered to another user.';
                    });
                    return;
                  }
                }
              } catch (e) {
                debugPrint('[Settings] check-email error: $e');
              }

              setModalState(() {
                busyStatus = 'Updating Google account…';
              });

              // 3. Prepare new Google credential
              final newCred = GoogleAuthProvider.credential(idToken: idToken);

              // 4. Test linkWithCredential BEFORE unlinking!
              // If newCred is already in use by another user in Firebase, Firebase will throw
              // 'credential-already-in-use' immediately, keeping our current account 100% safe!
              bool needSwap = false;
              try {
                await user.linkWithCredential(newCred);
              } on FirebaseAuthException catch (linkCheckErr) {
                if (linkCheckErr.code == 'provider-already-linked') {
                  // Expected: new credential is valid, but current Google provider is still attached.
                  needSwap = true;
                } else {
                  // It's 'credential-already-in-use' or another error: current account stays 100% safe!
                  rethrow;
                }
              }

              if (needSwap) {
                // To replace the existing Google provider without leaving the account orphaned:
                // a. Link a temporary bridge credential so the account always has an active provider
                final bridgeEmail = 'bridge_${user.uid}@internal.opaque';
                final bridgePwd =
                    'Bridge_${DateTime.now().millisecondsSinceEpoch}_Secret!';
                final bridgeCred = EmailAuthProvider.credential(
                  email: bridgeEmail,
                  password: bridgePwd,
                );
                await user.linkWithCredential(bridgeCred);

                // b. Unlink the old google.com provider
                try {
                  await user.unlink('google.com');
                } catch (unlinkErr) {
                  debugPrint('[Settings] unlink old google error: $unlinkErr');
                }

                // c. Link the new Google credential
                try {
                  await user.linkWithCredential(newCred);
                } catch (swapErr) {
                  debugPrint('[Settings] link new Google error: $swapErr');
                  rethrow;
                } finally {
                  // d. Always clean up the temporary bridge credential
                  try {
                    await user.unlink('password');
                  } catch (_) {}
                }
              }

              setModalState(() {
                busyStatus = 'Finalizing profile…';
              });

              // 5. Update backend contact_email
              try {
                final tok = await user.getIdToken(true);
                await http.post(
                  Uri.parse(
                      '${AppConfig.baseUrl}/profile/contact-email/confirm'),
                  headers: {
                    'Authorization': 'Bearer $tok',
                    'Content-Type': 'application/json',
                  },
                  body: json.encode({'contact_email': newEmail}),
                );
              } catch (e) {
                debugPrint('[Settings] update contact-email error: $e');
              }

              // 6. Seamlessly refresh the session with the new Google credential
              // Updating the primary email server-side invalidates old session tokens.
              // Re-signing in with the new Google credential immediately establishes a fresh,
              // valid session so the user is NEVER signed out or kicked to the login screen.
              try {
                await FirebaseAuth.instance.signInWithCredential(newCred);
              } catch (signErr) {
                debugPrint('[Settings] refresh session note: $signErr');
                try {
                  await user.reload();
                } catch (_) {}
              }

              // 7. Update local state
              if (mounted) {
                setState(() {
                  _contactEmail = newEmail;
                  _contactEmailVerified = true;
                });
                _profileSheetUpdater?.call(() {});
              }

              setModalState(() => busy = false);
              Navigator.pop(sheetCtx);
              OpaqueToast.show(
                context,
                'Google account updated to $newEmail',
              );
            } catch (e) {
              setModalState(() {
                busy = false;
                error = cleanError(
                    e, 'Could not switch Google account. Please try again.');
              });
            }
          }

          return PopScope(
            canPop: !busy,
            child: OpaqueSheet(
              title: 'Change Google account',
              description: 'Switch to a different Google account for your profile.',
              showIcon: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.soft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_circle_outlined,
                                color: Color(0xFF4285F4), size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                currentEmail,
                                style: c.text(13, bold: true),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Select another Google account to link to this profile. Your messages, contacts, encryption keys, and settings will remain completely safe and untouched.',
                          style: c.text(11, muted: true).copyWith(height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: c.dark
                            ? const Color(0xFF283241)
                            : const Color(0xFFE2E5E9),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF22C55E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              busyStatus,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OpaqueButton(
                        label: 'Choose Google Account',
                        primary: true,
                        onPressed: switchGoogleAccount,
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: c
                          .text(11)
                          .copyWith(color: const Color(0xFFBF6974), height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showChangeEmailDialog(OpaqueColors c) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Refresh user state only if no email change is pending (to avoid token revocation logout)
    if (_pendingUnverifiedEmail == null) {
      try {
        await user.reload();
      } catch (_) {}
    }

    final verifiedEmail = _activeVerifiedEmail;
    String? pendingEmail = _pendingUnverifiedEmail;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool busy = false;
    String? error;
    String? successMessage;
    // If user already has an unverified email on their account, start in pending state
    bool isPending = pendingEmail != null && pendingEmail.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          String cleanError(dynamic e, String fallback) {
            if (e is FirebaseAuthException) {
              switch (e.code) {
                case 'requires-recent-login':
                  return 'Security check: For your safety, please sign out and sign back in, then try again.';
                case 'email-already-in-use':
                case 'credential-already-in-use':
                  return 'This email address is already registered to another account.';
                case 'weak-password':
                  return 'Password is too weak. Please use at least 8 characters.';
                case 'invalid-email':
                  return 'The email address is badly formatted.';
                case 'wrong-password':
                case 'invalid-credential':
                  return 'Incorrect password. Please enter your account password.';
                case 'network-request-failed':
                  return 'Network error. Please check your internet connection.';
                case 'too-many-requests':
                  return 'Too many attempts. Please wait a moment before trying again.';
                default:
                  final msg = e.message;
                  if (msg != null && msg.isNotEmpty) {
                    return msg.replaceAll(RegExp(r'\[.*?\]\s*'), '');
                  }
                  return fallback;
              }
            }
            final s = e.toString().replaceAll(RegExp(r'\[.*?\]\s*'), '');
            if (s.contains('requires-recent-login')) {
              return 'Security check: For your safety, please sign out and sign back in, then try again.';
            }
            if (s.startsWith('Exception: ')) {
              return s.substring(11);
            }
            return fallback;
          }

          // ── Check if user clicked the email verification link ─────────────
          Future<void> checkVerification() async {
            setModalState(() {
              busy = true;
              error = null;
              successMessage = null;
            });
            try {
              final targetEmail =
                  (pendingEmail ?? emailController.text.trim()).toLowerCase();
              final pwd = passwordController.text.trim().isNotEmpty
                  ? passwordController.text.trim()
                  : _savedPendingPassword;

              User? freshUser;
              bool isVerified = false;

              if (pwd == null || pwd.isEmpty) {
                setModalState(() {
                  busy = false;
                  error =
                      'Please enter your account password below to confirm verification.';
                });
                return;
              }

              // First try re-authenticating the current user with targetEmail and password.
              // This refreshes the session in-place without triggering an auth-state switch.
              try {
                final cred = EmailAuthProvider.credential(
                  email: targetEmail,
                  password: pwd,
                );
                final authRes = await user.reauthenticateWithCredential(cred);
                freshUser = authRes.user ?? FirebaseAuth.instance.currentUser;
                isVerified = freshUser != null && freshUser.emailVerified;
              } on FirebaseAuthException catch (authErr) {
                if (authErr.code == 'user-not-found' ||
                    authErr.code == 'invalid-credential' ||
                    authErr.code == 'wrong-password') {
                  setModalState(() {
                    busy = false;
                    error =
                        'We have not detected your verification yet.\n'
                        'Please open your inbox for $targetEmail, tap the confirmation link, then tap here.';
                  });
                  return;
                }
                // If reauthenticate fails because refresh token was already revoked,
                // sign in directly with targetEmail and password to mint fresh tokens.
                try {
                  final cred =
                      await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: targetEmail,
                    password: pwd,
                  );
                  freshUser = cred.user;
                  isVerified = freshUser != null && freshUser.emailVerified;
                } on FirebaseAuthException catch (signInErr) {
                  if (signInErr.code == 'user-not-found' ||
                      signInErr.code == 'invalid-credential' ||
                      signInErr.code == 'wrong-password') {
                    setModalState(() {
                      busy = false;
                      error =
                          'We have not detected your verification yet.\n'
                          'Please open your inbox for $targetEmail, tap the confirmation link, then tap here.';
                    });
                    return;
                  }
                  debugPrint('[Settings] direct signIn note: $signInErr');
                }
              }

              if (!isVerified || freshUser == null) {
                setModalState(() {
                  busy = false;
                  error =
                      'We have not detected your verification yet.\n'
                      'Please open your inbox for $targetEmail, tap the confirmation link, then tap here.';
                });
                return;
              }

              // Verification confirmed! Update backend contact_email
              try {
                final tok = await freshUser.getIdToken(true);
                await http.post(
                  Uri.parse(
                      '${AppConfig.baseUrl}/profile/contact-email/confirm'),
                  headers: {
                    'Authorization': 'Bearer $tok',
                    'Content-Type': 'application/json',
                  },
                  body: json.encode({'contact_email': targetEmail}),
                );
              } catch (_) {}

              _savedPendingPassword = null;
              if (mounted) {
                setState(() {
                  _contactEmail = targetEmail;
                  _contactEmailVerified = true;
                });
                _profileSheetUpdater?.call(() {});
              }

              setModalState(() {
                busy = false;
                isPending = false;
                pendingEmail = null;
                successMessage =
                    '$targetEmail is now your verified account email!';
              });
            } catch (e) {
              setModalState(() {
                busy = false;
                error = cleanError(e,
                    'Could not complete verification. Please click the link in your email and try again.');
              });
            }
          }

          // ── Resend the confirmation email ────────────────────────────────
          Future<void> resendEmail() async {
            setModalState(() {
              busy = true;
              error = null;
            });
            try {
              final target =
                  pendingEmail ?? emailController.text.trim();
              try {
                await user.verifyBeforeUpdateEmail(target);
              } catch (_) {
                await user.sendEmailVerification();
              }
              setModalState(() => busy = false);
              if (mounted) {
                OpaqueToast.show(context, 'Verification link resent to $target');
              }
            } catch (e) {
              setModalState(() {
                busy = false;
                error = cleanError(e,
                    'Could not resend verification email. Please wait a moment and try again.');
              });
            }
          }

          // ── Cancel pending change & revert to verified email ──────────────
          Future<void> cancelPendingChange() async {
            setModalState(() {
              busy = true;
              error = null;
            });
            try {
              _savedPendingPassword = null;
              // Remove unconfirmed contact email in backend if any
              try {
                final tok = await user.getIdToken();
                await http.delete(
                  Uri.parse('${AppConfig.baseUrl}/profile/contact-email'),
                  headers: {'Authorization': 'Bearer $tok'},
                );
              } catch (_) {}

              if (mounted) {
                setState(() {
                  _contactEmail = null;
                  _contactEmailVerified = false;
                });
                _profileSheetUpdater?.call(() {});
              }

              Navigator.pop(sheetCtx);
              OpaqueToast.show(
                context,
                'Email change cancelled. Kept ${verifiedEmail ?? 'previous email'}.',
              );
            } catch (e) {
              setModalState(() {
                busy = false;
                error = cleanError(
                    e, 'Could not cancel change. Please try again.');
              });
            }
          }

          // ── Send verification link to new email ──────────────────────────
          Future<void> sendVerificationLink() async {
            final newEmail = emailController.text.trim();
            final pwd = passwordController.text;

            if (newEmail.isEmpty ||
                !newEmail.contains('@') ||
                !newEmail.contains('.')) {
              setModalState(
                  () => error = 'Please enter a valid email address');
              return;
            }
            if (verifiedEmail != null &&
                newEmail.toLowerCase() == verifiedEmail.toLowerCase()) {
              setModalState(
                  () => error = 'This is already your current email');
              return;
            }

            if (pwd.isEmpty) {
              setModalState(
                  () => error = 'Please enter your current account password');
              return;
            }

            setModalState(() {
              busy = true;
              error = null;
            });

            // 1. Check if email is already registered in Firebase Auth
            try {
              final methods = await FirebaseAuth.instance
                  .fetchSignInMethodsForEmail(newEmail);
              if (methods.isNotEmpty) {
                setModalState(() {
                  busy = false;
                  error =
                      'This email address is already in use by another account.';
                });
                return;
              }
            } catch (e) {
              debugPrint('[Settings] fetchSignInMethodsForEmail: $e');
            }

            // 2. Check if email is registered in backend database
            try {
              final tok = await user.getIdToken();
              final checkRes = await http.post(
                Uri.parse('${AppConfig.baseUrl}/profiles/check-email'),
                headers: {
                  'Authorization': 'Bearer $tok',
                  'Content-Type': 'application/json',
                },
                body: json.encode({'email': newEmail}),
              );
              if (checkRes.statusCode == 200) {
                final data = json.decode(checkRes.body);
                if (data['available'] == false) {
                  setModalState(() {
                    busy = false;
                    error = data['reason'] ??
                        'This email address is already registered to another account.';
                  });
                  return;
                }
              }
            } catch (e) {
              debugPrint('[Settings] backend check-email: $e');
            }

            try {
              // Reauthenticate first to confirm current password
              try {
                final cred = EmailAuthProvider.credential(
                  email: user.email ?? verifiedEmail ?? '',
                  password: pwd,
                );
                await user.reauthenticateWithCredential(cred);
              } on FirebaseAuthException catch (e) {
                setModalState(() {
                  busy = false;
                  error = (e.code == 'wrong-password' ||
                          e.code == 'invalid-credential')
                      ? 'Incorrect password. Please enter your account password.'
                      : (e.message ?? 'Password verification failed.');
                });
                return;
              }

              // Authorized! Send verification link without changing email yet
              await user.verifyBeforeUpdateEmail(newEmail);

              pendingEmail = newEmail;
              _savedPendingPassword = pwd;
              setModalState(() {
                busy = false;
                isPending = true;
              });
            } catch (e) {
              setModalState(() {
                busy = false;
                error = cleanError(e,
                    'Could not send verification email. Please check your connection and try again.');
              });
            }
          }

          // ── Sheet Title & Description ─────────────────────────────────────
          String title;
          String description;
          if (successMessage != null) {
            title = 'Email verified';
            description = 'Your account email has been updated.';
          } else if (isPending) {
            title = 'Email verification pending';
            description =
                'We sent a confirmation link to ${pendingEmail ?? ''}.';
          } else {
            title = 'Change account email';
            description = verifiedEmail != null
                ? 'Current verified email: $verifiedEmail'
                : 'Enter your new email and account password.';
          }

          return PopScope(
            canPop: !busy,
            child: OpaqueSheet(
              title: title,
              description: description,
              showIcon: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 1. Success State ─────────────────────────────────────────
                  if (successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF22C55E), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Color(0xFF22C55E), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              successMessage!,
                              style: c.text(12).copyWith(height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OpaqueButton(
                        label: 'Done',
                        primary: true,
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ),

                  // ── 2. Pending Verification State ────────────────────────────
                  ] else if (isPending) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.mark_email_unread_outlined,
                                  color: Color(0xFFEAB308), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pendingEmail ?? '',
                                  style: c.text(13, bold: true),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (verifiedEmail != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Active account email: $verifiedEmail',
                              style: c.text(10, muted: true),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Open your email inbox (including Spam) and tap the confirmation link, then tap "I\'ve verified it".',
                            style: c.text(11, muted: true).copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    if (_savedPendingPassword == null || _savedPendingPassword!.isEmpty) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        enabled: !busy,
                        obscureText: true,
                        style: c.text(14),
                        decoration: c.field('Account password to confirm'),
                      ),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: c.dark
                              ? const Color(0xFF283241)
                              : const Color(0xFFE2E5E9),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22C55E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Checking verification…',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OpaqueButton(
                          label: 'I\'ve verified it ✓',
                          primary: true,
                          onPressed: checkVerification,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OpaqueButton(
                        label: 'Resend verification link',
                        primary: false,
                        onPressed: busy ? null : resendEmail,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: busy ? null : cancelPendingChange,
                        child: Text(
                          'Cancel change (revert to ${verifiedEmail ?? 'previous'})',
                          style: c.text(11, bold: true).copyWith(
                                color: const Color(0xFFBF6974),
                              ),
                        ),
                      ),
                    ),

                  // ── 3. Normal Entry State ────────────────────────────────────
                  ] else ...[
                    TextField(
                      controller: emailController,
                      enabled: !busy,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      style: c.text(14),
                      decoration: c.field('New email address'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      enabled: !busy,
                      obscureText: true,
                      style: c.text(14),
                      decoration: c.field('Current account password'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your current account password to authorize this change.',
                      style: c.text(10, muted: true).copyWith(height: 1.4),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: c.dark
                              ? const Color(0xFF283241)
                              : const Color(0xFFE2E5E9),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22C55E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Sending link…',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OpaqueButton(
                          label: 'Send verification link',
                          primary: true,
                          onPressed: sendVerificationLink,
                        ),
                      ),
                    ],
                  ],

                  // ── Error notice ─────────────────────────────────────────────
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: c
                          .text(11)
                          .copyWith(color: const Color(0xFFBF6974), height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTwoFactorOptions() {
    final c = OpaqueColors(context);
    if (!_twoFactorEnabled) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SecurityPinScreen(
            mode: SecurityPinMode.setup,
            onSuccess: () {
              if (mounted) {
                setState(() => _twoFactorEnabled = true);
                _profileSheetUpdater?.call(() {});
                OpaqueToast.show(
                    context, 'Two-Step Verification activated');
              }
            },
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => OpaqueSheet(
        title: 'Two-step verification',
        description:
            'Your account is protected with a 6-digit security PIN.',
        showIcon: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SecurityPinScreen(
                      mode: SecurityPinMode.change,
                      onSuccess: () {
                        if (mounted) {
                          OpaqueToast.show(
                              context, 'PIN changed successfully');
                        }
                      },
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.password_outlined,
                        size: 18, color: c.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Change PIN',
                              style: c.text(13, bold: true)),
                          const SizedBox(height: 3),
                          Text('Update your 6-digit security PIN',
                              style: c.text(10, muted: true)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 15, color: c.muted),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SecurityPinScreen(
                      mode: SecurityPinMode.disable,
                      onSuccess: () {
                        if (mounted) {
                          setState(() => _twoFactorEnabled = false);
                          _profileSheetUpdater?.call(() {});
                          OpaqueToast.show(context,
                              'Two-step verification turned off');
                        }
                      },
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.lock_open_outlined,
                        size: 18, color: Color(0xFFBF6974)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Turn off two-step verification',
                            style: c
                                .text(13, bold: true)
                                .copyWith(color: const Color(0xFFBF6974)),
                          ),
                          const SizedBox(height: 3),
                          Text(
                              'Removes the PIN requirement when logging in',
                              style: c.text(10, muted: true)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 15, color: c.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _showOpaqueProfile() async {
    final initialName =
        (_displayName ?? _currentUser?.displayName ?? '').trim();
    _displayNameController.text = initialName;
    bool saving = false;
    bool photoBusy = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          _profileSheetUpdater = updateSheet;
          final c = OpaqueColors(ctx);
          Widget identity(
            IconData icon,
            String label,
            String value, {
            String? subtitle,
            Widget? actionWidget,
          }) =>
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: c.muted),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: c
                                .text(9, muted: true)
                                .copyWith(letterSpacing: 1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: c.text(12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: c.text(10).copyWith(
                                color: const Color(0xFFEAB308),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (actionWidget != null)
                      actionWidget
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.soft,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('Locked', style: c.text(9, muted: true)),
                      ),
                  ],
                ),
              );
          Widget profileActionButton(String label, VoidCallback onTap) {
            final textColor = c.dark ? Colors.white : Colors.black;
            final bgColor =
                c.dark ? const Color(0xFF283241) : const Color(0xFFE9EBEF);
            final borderColor =
                c.dark ? const Color(0xFF384556) : const Color(0xFFD5D8DF);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            );
          }

          final isGoogleUser = _currentUser?.providerData
                  .any((p) => p.providerId == 'google.com') ??
              false;
          final currentName = _displayNameController.text.trim();
          final bool isNameChanged =
              currentName.isNotEmpty && currentName != initialName;

          return OpaqueSheet(
            title: 'Your profile',
            description: 'How you appear to your friends.',
            showIcon: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: Stack(
                          children: [
                            Center(child: _opaqueAvatar(c, 78)),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Change profile photo',
                                  style: IconButton.styleFrom(
                                    backgroundColor: c.dark
                                        ? const Color(0xFF283241)
                                        : const Color(0xFFE9EBEF),
                                    foregroundColor:
                                        c.dark ? Colors.white : Colors.black,
                                    side: BorderSide(
                                      color: c.surface,
                                      width: 3,
                                    ),
                                  ),
                                  icon: Icon(
                                    photoBusy
                                        ? Icons.hourglass_empty
                                        : Icons.camera_alt_outlined,
                                    size: 13,
                                    color: c.dark ? Colors.white : Colors.black,
                                  ),
                                  onPressed: saving || photoBusy
                                      ? null
                                      : () async {
                                          updateSheet(() => photoBusy = true);
                                          await _pickAndUploadImage();
                                          if (ctx.mounted)
                                            updateSheet(
                                              () => photoBusy = false,
                                            );
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        _displayNameController.text.trim().isEmpty
                            ? _displayName ?? 'Your name'
                            : _displayNameController.text.trim(),
                        style: c.text(17, bold: true),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${_username ?? '…'}',
                        style: c.text(11, muted: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 23),
                Divider(height: 1, color: c.line),
                const SizedBox(height: 20),
                Text(
                  'DISPLAY NAME',
                  style: c.text(9, muted: true).copyWith(letterSpacing: 1.1),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _displayNameController,
                  enabled: !saving,
                  style: c.text(14),
                  decoration: c.field('Your display name'),
                  onChanged: (_) => updateSheet(() => error = null),
                ),
                const SizedBox(height: 6),
                Text(
                  'The name your friends see in conversations.',
                  style: c.text(10, muted: true),
                ),
                const SizedBox(height: 20),
                identity(
                  Icons.alternate_email,
                  'USERNAME',
                  '@${_username ?? '…'}',
                  actionWidget: profileActionButton(
                    'Edit',
                    () => _showEditUsernameDialog(c),
                  ),
                ),
                identity(
                  Icons.phone_outlined,
                  'PHONE NUMBER',
                  (_currentUser?.phoneNumber != null &&
                          _currentUser!.phoneNumber!.isNotEmpty)
                      ? _currentUser!.phoneNumber!
                      : 'Not linked',
                  actionWidget: profileActionButton(
                    (_currentUser?.phoneNumber != null &&
                            _currentUser!.phoneNumber!.isNotEmpty)
                        ? 'Change'
                        : '+ Link',
                    () => _showChangePhoneDialog(c),
                  ),
                ),
                identity(
                  Icons.mail_outline,
                  'ACCOUNT EMAIL',
                  _activeVerifiedEmail ?? 'Not linked',
                  subtitle: isGoogleUser
                      ? 'Signed in with Google'
                      : (_pendingUnverifiedEmail != null
                          ? 'Verification pending: $_pendingUnverifiedEmail'
                          : null),
                  actionWidget: profileActionButton(
                    'Change',
                    () => isGoogleUser
                        ? _showChangeGoogleAccountDialog(c)
                        : _showChangeEmailDialog(c),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 13, color: c.muted),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Credentials can be linked or updated with verification.',
                        style: c.text(10, muted: true).copyWith(height: 1.7),
                      ),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: c
                          .text(11)
                          .copyWith(color: const Color(0xFFBF6974)),
                    ),
                  ),
                 const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OpaqueButton(
                    label: saving ? 'Saving…' : 'Save changes',
                    primary: isNameChanged,
                    onPressed: isNameChanged && !saving && !photoBusy
                        ? () async {
                            final name = _displayNameController.text.trim();
                            if (name.isEmpty) {
                              updateSheet(
                                () => error = 'Display name cannot be empty.',
                              );
                              return;
                            }
                            updateSheet(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user == null)
                                throw StateError('Sign in required');
                              final token = await user.getIdToken();
                              final response = await http.post(
                                Uri.parse(
                                  '${AppConfig.baseUrl}/profile/displayname/update',
                                ),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'Authorization': 'Bearer $token',
                                },
                                body: json.encode({'displayName': name}),
                              );
                              if (response.statusCode != 200)
                                throw StateError('Update failed');
                              _cachedDisplayName = name;
                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                  'cached_user_display_name',
                                  name,
                                );
                              } catch (_) {}
                              if (mounted) setState(() => _displayName = name);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (_) {
                              if (ctx.mounted)
                                updateSheet(
                                  () => error =
                                      'Could not save your name. Please try again.',
                                );
                            } finally {
                              if (ctx.mounted)
                                updateSheet(() => saving = false);
                            }
                          }
                        : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    _profileSheetUpdater = null;
  }

  Widget _opaqueAvatar(OpaqueColors c, double size) {
    final name = _displayName ?? _currentUser?.displayName ?? '';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();
    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: c.text(size > 50 ? 25 : 16),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.soft,
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: ClipOval(
          child: _avatarUrl?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: _avatarUrl!,
                  memCacheWidth: 150,
                  memCacheHeight: 150,
                  maxWidthDiskCache: 300,
                  maxHeightDiskCache: 300,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => fallback,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }

  Future<void> _opaqueLogout(bool clearData) async {
    bool acknowledged = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          final c = OpaqueColors(ctx);
          return OpaqueSheet(
            title: clearData ? 'Clear local data & log out?' : 'Log out?',
            description: clearData
                ? 'This removes the app’s saved data from this device.'
                : 'Your local data will stay on this device.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clearData
                      ? 'Make sure you have a usable backup before continuing. This does not delete your Opaque account.'
                      : 'You’ll return to the sign-in screen. Choose “Log out & clear local data” instead if you want to remove this device’s saved data.',
                  style: c.text(12, muted: true).copyWith(height: 1.8),
                ),
                if (clearData) ...[
                  TextButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const BackupManagementScreen(),
                      ),
                    ),
                    child: Text(
                      'Review Backup & Restore',
                      style: c.text(12).copyWith(color: c.blue),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF507FC3),
                    value: acknowledged,
                    onChanged: (v) =>
                        updateSheet(() => acknowledged = v ?? false),
                    title: Text(
                      'I understand that local messages and saved data will be removed.',
                      style: c.text(11),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OpaqueButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OpaqueButton(
                        label: clearData ? 'Clear & log out' : 'Log out',
                        primary: true,
                        danger: clearData,
                        onPressed: clearData && !acknowledged
                            ? null
                            : () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted && confirmed == true)
      await _performLogout(clearData: clearData);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final c = OpaqueColors(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 3),
      child: Text(
        text,
        style: c.text(9, muted: true).copyWith(letterSpacing: 1.3),
      ),
    );
    Widget row(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback action, {
      bool danger = false,
    }) => InkWell(
      onTap: action,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: c.muted),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: c
                        .text(12)
                        .copyWith(
                          color: danger ? const Color(0xFFBF6974) : c.ink,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: c.text(10, muted: true).copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 15, color: c.muted),
          ],
        ),
      ),
    );
    return CallAwareScreen(
      screenName: 'SettingsScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: const BackupHeader(),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            children: [
              Text(
                'Settings',
                style: c.text(22, bold: true).copyWith(letterSpacing: -.6),
              ),
              const SizedBox(height: 5),
              Text(
                'Your account, privacy and preferences.',
                style: c.text(12, muted: true),
              ),
              InkWell(
                onTap: _showOpaqueProfile,
                child: Container(
                  padding: const EdgeInsets.only(top: 23, bottom: 21),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      _opaqueAvatar(c, 48),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName ??
                                  _currentUser?.displayName ??
                                  'Your profile',
                              style: c.text(15, bold: true),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${_username ?? '…'}',
                              style: c.text(11, muted: true),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 15, color: c.muted),
                    ],
                  ),
                ),
              ),
              label('PREFERENCES'),
              row(
                Icons.palette_outlined,
                'Style',
                'Theme, message shapes and call layout',
                _navigateToStyle,
              ),
              row(
                Icons.picture_in_picture_alt_outlined,
                'Floating call overlay',
                'Manage display-over-other-apps permission',
                () => OverlayPermissionHelper.requestPermission(context),
              ),
              label('PRIVACY'),
              row(
                Icons.lock_outline,
                'Profile photo privacy',
                _avatarPrivacy == 'nobody'
                    ? 'Nobody'
                    : _avatarPrivacy == 'contacts'
                    ? 'Friends only'
                    : 'Everyone',
                _showAvatarPrivacyDialog,
              ),
              row(
                Icons.message_outlined,
                'Who can message you',
                _messagingPrivacy == 'nobody'
                    ? 'Nobody'
                    : _messagingPrivacy == 'friends'
                    ? 'Friends only'
                    : 'Everyone',
                _showMessagingPrivacyDialog,
              ),
              row(
                Icons.access_time_outlined,
                'Last seen & online',
                _lastSeenPrivacy == 'nobody'
                    ? 'Nobody'
                    : _lastSeenPrivacy == 'friends'
                    ? 'Friends only'
                    : 'Everyone',
                _showLastSeenPrivacyDialog,
              ),
              label('SECURITY'),
              row(
                Icons.shield_outlined,
                'Two-step verification',
                _twoFactorEnabled ? 'Active (6-digit PIN)' : 'Off',
                _showTwoFactorOptions,
              ),
              label('BACKUP & RESTORE'),
              row(
                Icons.folder_outlined,
                'Backup & restore',
                'Keep a copy of your conversations',
                _navigateToBackupManagement,
              ),
              label('HELP'),
              row(
                Icons.menu_book_outlined,
                'How Opaque works',
                'A quick guide to getting started',
                _navigateToTutorial,
              ),
              row(
                Icons.info_outline,
                'About Opaque',
                'Learn more about the app',
                _navigateToAbout,
              ),
              label('ACCOUNT'),
              row(
                Icons.logout,
                'Log out',
                'Keep your local data on this device',
                () => _opaqueLogout(false),
              ),
              row(
                Icons.delete_outline,
                'Log out & clear local data',
                'Remove local data from this device',
                () => _opaqueLogout(true),
                danger: true,
              ),
              const SizedBox(height: 10),
              Text(
                'Clearing data affects this device. It does not delete your account.',
                style: c.text(10, muted: true).copyWith(height: 1.7),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 25, bottom: 6),
                child: Text(
                  'PRIVATE CONVERSATIONS. PROTECTED BY DESIGN.',
                  textAlign: TextAlign.center,
                  style: c
                      .text(9, muted: true)
                      .copyWith(letterSpacing: .6, height: 1.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupSection({
    required double sectionTitleSize,
    required double iconSize1,
    required double bodyTextSize,
    required double spacing2,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Backup & Restore",
          style: TextStyle(
            color: Colors.white,
            fontSize: sectionTitleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing3 * 1.25),

        // Info about backup management
        Container(
          padding: EdgeInsets.all(spacing3),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(borderRadius1 * 0.4),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.cyanAccent,
                size: iconSize1,
              ),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Create, restore, and manage your encrypted backups',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: bodyTextSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Manage Backups Button
        _buildActionButton(
          icon: Icons.backup,
          text: 'Manage Backups',
          onTap: _navigateToBackupManagement,
          color: Colors.blueAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(
            45.0,
            60.0,
          ),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToBackupManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BackupManagementScreen()),
    );
  }

  Widget _buildStyleSection({
    required double sectionTitleSize,
    required double iconSize1,
    required double bodyTextSize,
    required double spacing2,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Appearance Settings",
          style: TextStyle(
            color: Colors.white,
            fontSize: sectionTitleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Info about customization
        Container(
          padding: EdgeInsets.all(spacing3),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(borderRadius1 * 0.4),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.palette, color: Colors.cyanAccent, size: iconSize1),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Personalize your app appearance and UI',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: bodyTextSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Customization Button
        _buildActionButton(
          icon: Icons.palette,
          text: 'Style',
          onTap: _navigateToStyle,
          color: Colors.purpleAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(
            45.0,
            60.0,
          ),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToStyle() {
    Navigator.pop(context, 'open_style');
  }

  Widget _buildAboutSection({
    required double sectionTitleSize,
    required double iconSize1,
    required double bodyTextSize,
    required double spacing2,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "About Zarq Messenger",
          style: TextStyle(
            color: Colors.white,
            fontSize: sectionTitleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Info about the app
        Container(
          padding: EdgeInsets.all(spacing3),
          decoration: BoxDecoration(
            color: Colors.cyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(borderRadius1 * 0.4),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.cyanAccent,
                size: iconSize1,
              ),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Learn how Zarq works, version info, and legal',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: bodyTextSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // How Zarq Works Button
        _buildActionButton(
          icon: Icons.school_outlined,
          text: 'How Zarq Works',
          onTap: _navigateToTutorial,
          color: Colors.purpleAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(
            45.0,
            60.0,
          ),
          borderRadius: borderRadius1 * 0.75,
        ),
        SizedBox(height: spacing2 * 0.75),

        // About Button
        _buildActionButton(
          icon: Icons.info,
          text: 'About',
          onTap: _navigateToAbout,
          color: Colors.cyanAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(
            45.0,
            60.0,
          ),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToTutorial() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TutorialScreen()),
    );
  }

  void _navigateToAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AboutScreen()),
    );
  }

  // Show dialog for simple logout (keeps data)
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.orange),
              SizedBox(width: 10),
              Text('Logout', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'You will be logged out but your messages will stay on this phone.\n\nYou can login again anytime to see your messages.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout(clearData: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  // Show dialog for logout with data clear
  void _showLogoutWithClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Clear All Data?', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            '⚠️ All your messages will be deleted from this phone.\n\nYou won\'t be able to see them again!\n\nUse this if:\n• You share this phone with others\n• You want to start fresh\n• You\'re switching to a new phone',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout(clearData: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete & Logout'),
            ),
          ],
        );
      },
    );
  }

  // Perform logout with optional data clearing
  Future<void> _performLogout({required bool clearData}) async {
    // print("[SettingsScreen] Logout triggered (clearData: $clearData)");

    try {
      // 1. Clear FCM token from backend (so no more notifications)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          final deviceId = await SignalService.getDeviceId();
          if (deviceId != null && deviceId > 0) {
            final url = Uri.parse('${AppConfig.baseUrl}/v1/fcm/token');
            await http.post(
              url,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'fcm_token': '', // Empty string to clear
                'device_id': deviceId,
              }),
            );
            // print('[SettingsScreen] FCM token cleared from backend');
          }
        } catch (e) {
          // print("[SettingsScreen] Error clearing FCM token: $e");
          // Continue with logout even if this fails
        }
      }

      KeyRotationService.resetState();
      SignalService.invalidateCachedDeviceId();

      if (clearData) {
        // 2. Reset Signal Protocol user context (only if clearing data)
        // print("[SettingsScreen] Resetting Signal Protocol user context...");
        final signalResetSuccess = await SignalService.resetUserContext();
        if (signalResetSuccess) {
          // print("[SettingsScreen] Signal Protocol context reset successfully");
        } else {
          // print("[SettingsScreen] Warning: Signal Protocol context reset failed");
        }

        // 3. Reset database (only if clearing data)
        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.resetDatabase();
        final prefs = await SharedPreferences.getInstance();
        if (user != null) {
          await prefs.remove('user_${user.uid}_initialized');
        }
        // print("[SettingsScreen] Database reset");
      } else {
        // Just reset in-memory state without clearing persistent data
        // print("[SettingsScreen] Keeping Signal Protocol keys and database");
        await SignalService.resetUserContext(); // Reset in-memory state only
        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.close();
      }

      // 4. Disconnect WebSocket (always)
      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      websocketService.disconnect();

      // 5. Clear cached profile data
      await _clearProfileCache();

      // 6. Firebase logout (always)
      await FirebaseAuth.instance.signOut();
      // print("[SettingsScreen] Firebase logout completed");
    } catch (e) {
      // print('[SettingsScreen] Error during logout: $e');
      // Continue with navigation even if some cleanup fails
    }

    // 6. Navigate back to the login screen
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // Show delete account dialog with strong confirmation
  void _showDeleteAccountDialog(BuildContext context) {
    final TextEditingController confirmationController =
        TextEditingController();
    const String confirmationText = "DELETE";
    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 32,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete Account?',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ WARNING: This action is PERMANENT and IRREVERSIBLE!',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your account and ALL data will be permanently deleted:',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• All messages (cannot be recovered)\n'
                      '• All photos and videos\n'
                      '• All conversations\n'
                      '• All friends and contacts\n'
                      '• All call history\n'
                      '• Your profile and account',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'To confirm, type DELETE below:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmationController,
                      enabled: !isDeleting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type DELETE',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: Colors.black45,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.redAccent),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.redAccent,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {}); // Rebuild to update button state
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () {
                          confirmationController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDeleting ? Colors.grey : Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      (isDeleting ||
                          confirmationController.text != confirmationText)
                      ? null
                      : () async {
                          setState(() {
                            isDeleting = true;
                          });

                          try {
                            await _deleteAccount();
                            confirmationController.dispose();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } catch (e) {
                            setState(() {
                              isDeleting = false;
                            });
                            if (dialogContext.mounted) {
                              OpaqueToast.error(
                                context,
                                'Failed to delete account: $e',
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        (confirmationController.text == confirmationText &&
                            !isDeleting)
                        ? Colors.redAccent
                        : Colors.grey[800],
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[800],
                    disabledForegroundColor: Colors.grey[600],
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Delete Forever',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Delete account from backend
  Future<void> _deleteAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      final token = await user.getIdToken();

      // Call backend delete account endpoint
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/v1/user/account/delete'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        // Account deleted successfully from backend

        KeyRotationService.resetState();
        SignalService.invalidateCachedDeviceId();

        // Clear local data
        final signalResetSuccess = await SignalService.resetUserContext();
        if (!signalResetSuccess) {
          // print("Warning: Signal Protocol context reset failed");
        }

        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.resetDatabase();

        // Clear initialized flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('user_${user.uid}_initialized');

        // Disconnect WebSocket
        final websocketService = Provider.of<WebSocketService>(
          context,
          listen: false,
        );
        websocketService.disconnect();

        // Clear cached profile data
        await _clearProfileCache();

        // Sign out from Firebase
        await FirebaseAuth.instance.signOut();

        // Navigate to login screen
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        throw Exception('Failed to delete account: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting account: $e');
    }
  }

  Widget _buildCallSettingsSection({
    required double sectionTitleSize,
    required double usernameSize,
    required double spacing2,
    required double spacing3,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Call Settings",
          style: TextStyle(
            color: Colors.white,
            fontSize: sectionTitleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing3 * 1.25),
        Text(
          "Configure call overlay and permissions",
          style: TextStyle(color: Colors.white70, fontSize: usernameSize),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Overlay Permission Button
        _buildActionButton(
          icon: Icons.window,
          text: 'Enable Floating Call Overlay',
          onTap: () async {
            await OverlayPermissionHelper.requestPermission(context);
          },
          color: Colors.tealAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(
            45.0,
            60.0,
          ),
          borderRadius:
              (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 24.0) *
              0.75,
        ),
      ],
    );
  }

  Widget _buildFriendsListSection({
    required double sectionTitleSize,
    required double iconSize1,
    required double bodyTextSize,
    required double spacing1,
    required double spacing2,
    required double spacing3,
    required double borderRadius1,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(borderRadius1 * 0.75),
          child: InkWell(
            onTap: _toggleFriendsList,
            borderRadius: BorderRadius.circular(borderRadius1 * 0.75),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing2,
                vertical: spacing3,
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.cyanAccent, size: iconSize1),
                  SizedBox(width: spacing3),
                  Text(
                    "My Friends",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: sectionTitleSize * 0.85,
                    ),
                  ),
                  const Spacer(),
                  if (_friendsList.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing3,
                        vertical: spacing3 * 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(
                          borderRadius1 * 0.5,
                        ),
                      ),
                      child: Text(
                        _friendsList.length.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: bodyTextSize,
                        ),
                      ),
                    ),
                  Icon(
                    _isFriendsListVisible
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.white70,
                    size: iconSize1,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: SizedBox(
            height: _isFriendsListVisible ? null : 0,
            child: _isFriendsLoading
                ? Padding(
                    padding: EdgeInsets.all(spacing1),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.cyanAccent,
                      ),
                    ),
                  )
                : _friendsList.isEmpty && _isFriendsListVisible
                ? Padding(
                    padding: EdgeInsets.all(spacing1),
                    child: Center(
                      child: Text(
                        "You haven't added any friends yet.",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: bodyTextSize,
                        ),
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.25,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _friendsList.length,
                      itemBuilder: (context, index) {
                        final friend = _friendsList[index];
                        final hasImage =
                            friend.avatarUrl != null &&
                            friend.avatarUrl!.isNotEmpty;
                        final initial = friend.username.isNotEmpty
                            ? friend.username[0].toUpperCase()
                            : '?';
                        final color = Color(
                          friend.username.hashCode,
                        ).withOpacity(1.0);
                        return ListTile(
                          leading: hasImage
                              ? CachedNetworkImage(
                                  imageUrl: friend.avatarUrl!,
                                  memCacheWidth: 120,
                                  memCacheHeight: 120,
                                  maxWidthDiskCache: 250,
                                  maxHeightDiskCache: 250,
                                  imageBuilder: (context, imageProvider) =>
                                      CircleAvatar(
                                        backgroundImage: imageProvider,
                                        backgroundColor: Colors.transparent,
                                      ),
                                  placeholder: (context, url) => CircleAvatar(
                                    backgroundColor: color,
                                    child: SizedBox(
                                      width: iconSize1,
                                      height: iconSize1,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      CircleAvatar(
                                        backgroundColor: color,
                                        child: Text(
                                          initial,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                )
                              : CircleAvatar(
                                  backgroundColor: color,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                          title: Text(
                            friend.username,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: bodyTextSize,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    required Color color,
    required double buttonHeight,
    required double borderRadius,
  }) {
    final iconSize = (MediaQuery.of(context).size.width * 0.05).clamp(
      18.0,
      24.0,
    );
    final textSize = (MediaQuery.of(context).size.width * 0.04).clamp(
      14.0,
      18.0,
    );

    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.black87, size: iconSize),
      label: Text(
        text,
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: textSize,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: Size(double.infinity, buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        shadowColor: color,
        elevation: 8,
      ),
    );
  }

  Widget _buildDisabledActionButton({
    required IconData icon,
    required String text,
    required Color color,
    required double buttonHeight,
    required double borderRadius,
  }) {
    final iconSize = (MediaQuery.of(context).size.width * 0.05).clamp(
      18.0,
      24.0,
    );
    final textSize = (MediaQuery.of(context).size.width * 0.04).clamp(
      14.0,
      18.0,
    );

    return ElevatedButton.icon(
      onPressed: null, // Disabled
      icon: Icon(icon, color: Colors.white54, size: iconSize),
      label: Text(
        text,
        style: TextStyle(
          color: Colors.white54,
          fontWeight: FontWeight.bold,
          fontSize: textSize,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.3),
        disabledBackgroundColor: color.withOpacity(0.3),
        minimumSize: Size(double.infinity, buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        elevation: 0,
      ),
    );
  }
}
