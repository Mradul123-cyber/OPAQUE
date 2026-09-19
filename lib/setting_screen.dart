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
import 'package:zarq_messenger/screens/backup_management_screen.dart';
import 'package:zarq_messenger/screens/style_screen.dart';
import 'package:zarq_messenger/screens/tutorial_screen.dart';
import 'package:zarq_messenger/screens/premium_plans_screen.dart';
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

  late TextEditingController _nameController;
  bool _isUploading = false;
  String? _avatarUrl;
  String? _displayName;
  String? _username;
  bool _isFriendsListVisible = false;
  bool _isFriendsLoading = false;
  List<Friend> _friendsList = [];
  final _displayNameController = TextEditingController();



  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _currentUser?.displayName ?? '',
    );
    _avatarUrl = _currentUser?.photoURL;
    _fetchProfileData();
  }

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
        setState(() {
          _displayName = data['display_name'];
          _username = data['username'];
          _displayNameController.text = _displayName ?? '';
        });
      }
    } catch (e) {
      // print('Error fetching profile data: $e');
    }
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
      imageQuality: 70,
      maxWidth: 800,
    );
    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final userId = _currentUser!.uid;
      final storageRef = FirebaseStorage.instance.ref().child(
        'profile_pictures/$userId/avatar.jpg',
      );

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        final uploadTask = storageRef.putData(bytes);
        final snapshot = await uploadTask.whenComplete(() => {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        await _updateAvatarUrlInBackend(downloadUrl);
        await _currentUser!.updatePhotoURL(downloadUrl);
        if (mounted) setState(() => _avatarUrl = downloadUrl);
      } else {
        final file = File(pickedFile.path);
        final uploadTask = storageRef.putFile(file);
        final snapshot = await uploadTask.whenComplete(() => {});
        final downloadUrl = await snapshot.ref.getDownloadURL();
        await _updateAvatarUrlInBackend(downloadUrl);
        await _currentUser!.updatePhotoURL(downloadUrl);
        if (mounted) setState(() => _avatarUrl = downloadUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching friends: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Display name updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {});
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update name: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateUserDisplayName() async {
    final newDisplayName = _displayNameController.text.trim();
    if (newDisplayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display name cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
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
        setState(() {
          _displayName = newDisplayName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Display name updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update display name: ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating display name: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: dialogTextSize),
              helperText: 'Maximum 30 characters',
              helperStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: dialogTextSize * 0.9),
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
                style: TextStyle(color: Colors.white70, fontSize: dialogTextSize),
              ),
            ),
            TextButton(
              onPressed: _updateUserDisplayName,
              child: Text(
                'Save',
                style: TextStyle(color: Colors.cyanAccent, fontSize: dialogTextSize),
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
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: dialogTextSize),
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
                style: TextStyle(color: Colors.white70, fontSize: dialogTextSize),
              ),
            ),
            TextButton(
              onPressed: _updateDisplayName,
              child: Text(
                'Save',
                style: TextStyle(color: Colors.cyanAccent, fontSize: dialogTextSize),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final outerPadding = (screenWidth * 0.05).clamp(16.0, 24.0);
    final containerPadding = (screenWidth * 0.06).clamp(20.0, 28.0);
    final borderRadius1 = (screenWidth * 0.05).clamp(16.0, 24.0);
    final avatarRadius = (screenWidth * 0.15).clamp(50.0, 70.0);
    final avatarTextSize = (screenWidth * 0.15).clamp(50.0, 70.0);
    final displayNameSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final usernameSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final sectionTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize1 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize2 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final spacing1 = (screenHeight * 0.025).clamp(16.0, 24.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 20.0);
    final spacing3 = (screenHeight * 0.0125).clamp(8.0, 12.0);

    final initial = _currentUser?.displayName?.isNotEmpty == true
        ? _currentUser!.displayName![0].toUpperCase()
        : '?';
    final bool currentUserHasImage =
        _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return CallAwareScreen(
      screenName: 'SettingsScreen',
      child: ProfileBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text('Profile', style: TextStyle(fontSize: displayNameSize * 0.8)),
            centerTitle: true,
          ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: outerPadding,
                right: outerPadding,
                top: outerPadding,
                bottom: MediaQuery.of(context).padding.bottom + outerPadding,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius1),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    padding: EdgeInsets.all(containerPadding),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(borderRadius1),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              currentUserHasImage
                                  ? CachedNetworkImage(
                                      imageUrl: _avatarUrl!,
                                      imageBuilder: (context, imageProvider) => CircleAvatar(
                                        radius: avatarRadius,
                                        backgroundImage: imageProvider,
                                        backgroundColor: Colors.black.withOpacity(0.3),
                                      ),
                                      placeholder: (context, url) => CircleAvatar(
                                        radius: avatarRadius,
                                        backgroundColor: Colors.black.withOpacity(0.3),
                                        child: const CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => CircleAvatar(
                                        radius: avatarRadius,
                                        backgroundColor: Colors.black.withOpacity(0.3),
                                        child: Text(
                                          initial,
                                          style: TextStyle(
                                            fontSize: avatarTextSize,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                    )
                                  : CircleAvatar(
                                      radius: avatarRadius,
                                      backgroundColor: Colors.black.withOpacity(0.3),
                                      child: Text(
                                        initial,
                                        style: TextStyle(
                                          fontSize: avatarTextSize,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ),
                              if (_isUploading)
                                const CircularProgressIndicator(
                                  color: Colors.cyanAccent,
                                ),
                              if (!_isUploading)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: EdgeInsets.all(spacing3 * 0.75),
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF0a1128),
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      color: Colors.black,
                                      size: iconSize2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacing1),
                        // Display Name (from database)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _displayName ?? _currentUser?.displayName ?? 'No Display Name',
                                style: TextStyle(
                                  fontSize: displayNameSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                color: Colors.white70,
                                size: iconSize2,
                              ),
                              onPressed: _showEditDisplayNameDialog,
                            ),
                          ],
                        ),
                        SizedBox(height: spacing2),
                        // Username (unique identifier)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: spacing2, vertical: spacing3),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(borderRadius1 * 0.6),
                            border: Border.all(
                              color: Colors.green[200]!,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.alternate_email, color: Colors.green[700], size: iconSize2),
                              SizedBox(width: spacing3),
                              Text(
                                _username ?? 'Loading...',
                                style: TextStyle(
                                  fontSize: usernameSize,
                                  color: Colors.green[900],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacing3),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: spacing2, vertical: spacing3),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(borderRadius1 * 0.6),
                            border: Border.all(
                              color: Colors.red[200]!,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.email, color: Colors.red[700], size: iconSize2),
                              SizedBox(width: spacing3),
                              Expanded(
                                child: Text(
                                  _currentUser?.email ?? 'No Email',
                                  style: TextStyle(
                                    fontSize: usernameSize,
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacing1),

                        // --- TODO: Backup/Restore Buttons are commented out ---
                        // These buttons are disabled until the backup logic is updated
                        // to support the new Signal Protocol Identity Key.
                        /* _buildActionButton(
                          icon: Icons.cloud_upload,
                          text: 'Backup Encryption Key',
                          onTap: _triggerBackup,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(height: 10),
                        _buildActionButton(
                          icon: Icons.cloud_download,
                          text: 'Restore Encryption Key',
                          onTap: _triggerRestore,
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(height: 10),
                        _buildActionButton(
                          icon: Icons.delete_forever,
                          text: 'Delete Key Backup',
                          onTap: _triggerDeleteBackup,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 30),
                        */
                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),
                        _buildFriendsListSection(
                          sectionTitleSize: sectionTitleSize,
                          iconSize1: iconSize1,
                          bodyTextSize: bodyTextSize,
                          spacing1: spacing1,
                          spacing2: spacing2,
                          spacing3: spacing3,
                          borderRadius1: borderRadius1,
                        ),
                        SizedBox(height: spacing2 * 0.75),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 NEW CUSTOMIZATION SECTION 🚨
                        _buildStyleSection(
                          sectionTitleSize: sectionTitleSize,
                          iconSize1: iconSize1,
                          bodyTextSize: bodyTextSize,
                          spacing2: spacing2,
                          spacing3: spacing3,
                          borderRadius1: borderRadius1,
                        ),
                        SizedBox(height: spacing1),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 PREMIUM SECTION 🚨
                        _buildPremiumSection(
                          sectionTitleSize: sectionTitleSize,
                          iconSize1: iconSize1,
                          bodyTextSize: bodyTextSize,
                          spacing2: spacing2,
                          spacing3: spacing3,
                          borderRadius1: borderRadius1,
                        ),
                        SizedBox(height: spacing1),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 BACKUP SECTION 🚨
                        _buildBackupSection(
                          sectionTitleSize: sectionTitleSize,
                          iconSize1: iconSize1,
                          bodyTextSize: bodyTextSize,
                          spacing2: spacing2,
                          spacing3: spacing3,
                          borderRadius1: borderRadius1,
                        ),
                        SizedBox(height: spacing1),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 CALL SETTINGS SECTION 🚨
                        _buildCallSettingsSection(
                          sectionTitleSize: sectionTitleSize,
                          usernameSize: usernameSize,
                          spacing2: spacing2,
                          spacing3: spacing3,
                        ),
                        SizedBox(height: spacing1),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 ABOUT SECTION 🚨
                        _buildAboutSection(
                          sectionTitleSize: sectionTitleSize,
                          iconSize1: iconSize1,
                          bodyTextSize: bodyTextSize,
                          spacing2: spacing2,
                          spacing3: spacing3,
                          borderRadius1: borderRadius1,
                        ),
                        SizedBox(height: spacing1),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // 🚨 DELETE ACCOUNT SECTION 🚨
                        // TODO: Delete Account - Disabled temporarily due to cascade issues
                        // Needs proper strategy for handling user data deletion without affecting other users
                        // _buildActionButton(
                        //   icon: Icons.delete_forever_outlined,
                        //   text: 'Delete Account',
                        //   onTap: () => _showDeleteAccountDialog(context),
                        //   color: Colors.red.shade700,
                        //   buttonHeight: (screenHeight * 0.065).clamp(45.0, 60.0),
                        //   borderRadius: borderRadius1 * 0.75,
                        // ),
                        //
                        // SizedBox(height: spacing2),

                        const Divider(color: Colors.white30),
                        SizedBox(height: spacing1),

                        // Logout (keeps data)
                        _buildActionButton(
                          icon: Icons.logout,
                          text: 'Logout',
                          onTap: () => _showLogoutDialog(context),
                          color: Colors.orange,
                          buttonHeight: (screenHeight * 0.065).clamp(45.0, 60.0),
                          borderRadius: borderRadius1 * 0.75,
                        ),

                        SizedBox(height: spacing2),

                        // Logout & Clear All Data
                        _buildActionButton(
                          icon: Icons.delete_forever,
                          text: 'Logout & Clear All Data',
                          onTap: () => _showLogoutWithClearDataDialog(context),
                          color: Colors.redAccent,
                          buttonHeight: (screenHeight * 0.065).clamp(45.0, 60.0),
                          borderRadius: borderRadius1 * 0.75,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      )
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
              Icon(Icons.info_outline, color: Colors.cyanAccent, size: iconSize1),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Create, restore, and manage your encrypted backups',
                  style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
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
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToBackupManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BackupManagementScreen(),
      ),
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
                  style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
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
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToStyle() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const StyleScreen(),
      ),
    );
  }

  Widget _buildPremiumSection({
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
          "Premium Subscription",
          style: TextStyle(
            color: Colors.white,
            fontSize: sectionTitleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // TODO: PREMIUM - DISABLED FOR NOW (TEST MODE)
        // Uncomment the section below when switching to Razorpay LIVE mode
        // and comment out the "Coming Soon" section

        /* ==================== ENABLE THIS WHEN GOING LIVE ====================
        // Info about premium
        Container(
          padding: EdgeInsets.all(spacing3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFF59E0B).withOpacity(0.2),
                const Color(0xFF8B5CF6).withOpacity(0.2),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(borderRadius1 * 0.4),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.workspace_premium, color: const Color(0xFFF59E0B), size: iconSize1),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Unlock unlimited AI power and premium features',
                  style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Upgrade to Premium Button
        _buildActionButton(
          icon: Icons.star,
          text: 'Upgrade to Premium',
          onTap: _navigateToPremium,
          color: const Color(0xFFF59E0B),
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
        ==================== END LIVE VERSION ==================== */

        // ==================== TEMPORARY: COMING SOON (TEST MODE) ====================
        // Info about premium - Coming Soon
        Container(
          padding: EdgeInsets.all(spacing3),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(borderRadius1 * 0.4),
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock, color: Colors.grey, size: iconSize1),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Premium features launching soon with live payments',
                  style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing2 * 0.75),

        // Upgrade to Premium Button - Disabled (Coming Soon)
        _buildDisabledActionButton(
          icon: Icons.lock,
          text: 'Coming Soon',
          color: Colors.grey,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
        // ==================== END COMING SOON VERSION ====================
      ],
    );
  }

  void _navigateToPremium() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PremiumPlansScreen(),
      ),
    );
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
              Icon(Icons.info_outline, color: Colors.cyanAccent, size: iconSize1),
              SizedBox(width: spacing3),
              Expanded(
                child: Text(
                  'Learn how Zarq works, version info, and legal',
                  style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
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
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
        SizedBox(height: spacing2 * 0.75),

        // About Button
        _buildActionButton(
          icon: Icons.info,
          text: 'About',
          onTap: _navigateToAbout,
          color: Colors.cyanAccent,
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: borderRadius1 * 0.75,
        ),
      ],
    );
  }

  void _navigateToTutorial() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TutorialScreen(),
      ),
    );
  }

  void _navigateToAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AboutScreen(),
      ),
    );
  }

  // Show dialog for simple logout (keeps data)
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      websocketService.disconnect();

      // 5. Firebase logout (always)
      await FirebaseAuth.instance.signOut();
      // print("[SettingsScreen] Firebase logout completed");

    } catch (e) {
      // print('[SettingsScreen] Error during logout: $e');
      // Continue with navigation even if some cleanup fails
    }

    // 6. Navigate back to the login screen
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false,
      );
    }
  }

  // Show delete account dialog with strong confirmation
  void _showDeleteAccountDialog(BuildContext context) {
    final TextEditingController confirmationController = TextEditingController();
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
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
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmationController,
                      enabled: !isDeleting,
                      style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2),
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
                          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
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
                  onPressed: isDeleting ? null : () {
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
                  onPressed: (isDeleting || confirmationController.text != confirmationText)
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete account: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (confirmationController.text == confirmationText && !isDeleting)
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Delete Forever', style: TextStyle(fontSize: 16)),
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
        final websocketService = Provider.of<WebSocketService>(context, listen: false);
        websocketService.disconnect();

        // Sign out from Firebase
        await FirebaseAuth.instance.signOut();

        // Navigate to login screen
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
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
          style: TextStyle(
            color: Colors.white70,
            fontSize: usernameSize,
          ),
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
          buttonHeight: (MediaQuery.of(context).size.height * 0.065).clamp(45.0, 60.0),
          borderRadius: (MediaQuery.of(context).size.width * 0.05).clamp(16.0, 24.0) * 0.75,
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
              padding: EdgeInsets.symmetric(horizontal: spacing2, vertical: spacing3),
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
                        borderRadius: BorderRadius.circular(borderRadius1 * 0.5),
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
                        style: TextStyle(color: Colors.white70, fontSize: bodyTextSize),
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.25),
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
                                  imageBuilder: (context, imageProvider) => CircleAvatar(
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
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => CircleAvatar(
                                    backgroundColor: color,
                                    child: Text(
                                      initial,
                                      style: const TextStyle(color: Colors.white),
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
                            style: TextStyle(color: Colors.white, fontSize: bodyTextSize),
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
    final iconSize = (MediaQuery.of(context).size.width * 0.05).clamp(18.0, 24.0);
    final textSize = (MediaQuery.of(context).size.width * 0.04).clamp(14.0, 18.0);

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
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
    final iconSize = (MediaQuery.of(context).size.width * 0.05).clamp(18.0, 24.0);
    final textSize = (MediaQuery.of(context).size.width * 0.04).clamp(14.0, 18.0);

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
        elevation: 0,
      ),
    );
  }
}
