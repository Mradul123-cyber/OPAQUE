import 'widgets/notes_design.dart';
import 'widgets/backup_design.dart';
import 'widgets/opaque_toast.dart';
// lib/setting_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
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
      avatarUrl: json['avatarUrl'],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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
  bool _isFriendsListVisible = false;
  bool _isFriendsLoading = false;
  List<Friend> _friendsList = [];
  final _displayNameController = TextEditingController();
  String _avatarPrivacy = 'everyone';

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

      if (!mounted) return;

      bool changed = false;
      if (savedUsername != null && savedUsername.isNotEmpty && _username == null) {
        _username = savedUsername;
        _cachedUsername = savedUsername;
        changed = true;
      }
      if (savedDisplayName != null && savedDisplayName.isNotEmpty && _displayName == null) {
        _displayName = savedDisplayName;
        _cachedDisplayName = savedDisplayName;
        _displayNameController.text = savedDisplayName;
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

        final fetchedPrivacy = (data['avatar_privacy'] ?? data['avatarPrivacy']) as String?;
        if (fetchedPrivacy != null && fetchedPrivacy.isNotEmpty && _avatarPrivacy != fetchedPrivacy) {
          _avatarPrivacy = fetchedPrivacy;
          changed = true;
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
            await prefs.setString('cached_user_display_name', fetchedDisplayName);
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
      if (_avatarUrl != null && _avatarUrl!.contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(_avatarUrl!).delete();
        } catch (_) {}
      }

      // Generate opaque random UUID to completely hide Firebase UID from CDN URL
      final avatarId = const Uuid().v4();
      final storageRef = FirebaseStorage.instance.ref().child('avatars/$avatarId.jpg');
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
    try {
      final token = await _currentUser?.getIdToken();
      if (token == null) return;
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/profile/privacy/avatar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatarPrivacy': newSetting}),
      );
      if (response.statusCode == 200) {
        setState(() {
          _avatarPrivacy = newSetting;
        });
      }
    } catch (e) {
      if (mounted) {
        OpaqueToast.error(context, 'Failed to update privacy: $e');
      }
    }
  }

  void _showAvatarPrivacyDialog() {
    final c = NotesColors(context);
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
                    Icon(Icons.radio_button_unchecked, color: c.muted, size: 18),
                ],
              ),
            ),
          );
        }

        return NotesSheet(
          title: 'Profile photo privacy',
          description: 'Choose who can see your profile photo.',
          showIcon: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option('Everyone', 'Any user on Opaque can see your photo', 'everyone'),
              option('My Contacts', 'Only accepted friends can see your photo', 'contacts'),
              option('Nobody', 'No one can see your photo', 'nobody'),
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
        OpaqueToast.error(context, 'Failed to update display name: ${response.body}');
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

  Future<void> _showOpaqueProfile() async {
    _displayNameController.text =
        _displayName ?? _currentUser?.displayName ?? '';
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
          final c = NotesColors(ctx);
          Widget identity(IconData icon, String label, String value) =>
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
                          Text(value, style: c.text(12)),
                        ],
                      ),
                    ),
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
          return NotesSheet(
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
                                    backgroundColor: const Color(0xFF507FC3),
                                    foregroundColor: Colors.white,
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
                        style: c.text(11).copyWith(color: c.blue),
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
                ),
                identity(
                  Icons.mail_outline,
                  'ACCOUNT EMAIL',
                  _currentUser?.email ?? 'No email',
                ),
                const SizedBox(height: 17),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: c.muted),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Your email is shown here for your account reference.',
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
                  child: NotesButton(
                    label: saving ? 'Saving…' : 'Save changes',
                    primary: true,
                    onPressed: saving || photoBusy
                        ? null
                        : () async {
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
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setString('cached_user_display_name', name);
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
                          },
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

  Widget _opaqueAvatar(NotesColors c, double size) {
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
          final c = NotesColors(ctx);
          return NotesSheet(
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
                      child: NotesButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NotesButton(
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
    final c = NotesColors(context);
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
                        ? 'My contacts'
                        : 'Everyone',
                _showAvatarPrivacyDialog,
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
          final url = Uri.parse('${AppConfig.baseUrl}/v1/fcm/token');
          await http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'fcm_token': '', // Empty string to clear
              'device_id': 1,
            }),
          );
          // print('[SettingsScreen] FCM token cleared from backend');
        } catch (e) {
          // print("[SettingsScreen] Error clearing FCM token: $e");
          // Continue with logout even if this fails
        }
      }

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
        // print("[SettingsScreen] Database reset");
      } else {
        // Just reset in-memory state without clearing persistent data
        // print("[SettingsScreen] Keeping Signal Protocol keys and database");
        await SignalService.resetUserContext(); // Reset in-memory state only
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
                              OpaqueToast.error(context, 'Failed to delete account: $e');
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

        // Clear local data
        final signalResetSuccess = await SignalService.resetUserContext();
        if (!signalResetSuccess) {
          // print("Warning: Signal Protocol context reset failed");
        }

        final dbService = Provider.of<DatabaseService>(context, listen: false);
        await dbService.resetDatabase();

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
