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
import 'package:provider/provider.dart';
// import 'package:provider/provider.dart'; // No longer needed for now
// import 'package:zarq_messenger_frontend/services/key_management_service.dart'; // No longer needed for now

import 'profile_background.dart';
import 'login_screen.dart';

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
  bool _isFriendsListVisible = false;
  bool _isFriendsLoading = false;
  List<Friend> _friendsList = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _currentUser?.displayName ?? '',
    );
    _avatarUrl = _currentUser?.photoURL;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      Uri.parse('http://192.168.29.81:8080/profile/avatar/update'),
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

      final url = Uri.parse('http://192.168.29.81:8080/friends/list');
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

  // --- TODO: The Backup/Restore feature is temporarily disabled. ---
  // This code is commented out because it was designed for the old key system.
  // It needs to be updated to back up and restore the new Signal Protocol Identity Key.
  /*
  Future<void> _triggerBackup() async {
    // ... old backup logic ...
  }

  Future<void> _triggerRestore() async {
    // ... old restore logic ...
  }

  Future<void> _triggerDeleteBackup() async {
    // ... old delete backup logic ...
  }
  */

  Future<String?> _askForPassword({
    required String title,
    required String hint,
  }) async {
    String? password;
    await showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                password = controller.text;
                Navigator.pop(ctx);
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
    return password;
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0a1128).withOpacity(0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.cyanAccent.withOpacity(0.5)),
          ),
          title: const Text(
            'Edit Display Name',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter your new name",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: _updateDisplayName,
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.cyanAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _currentUser?.displayName?.isNotEmpty == true
        ? _currentUser!.displayName![0].toUpperCase()
        : '?';
    final bool currentUserHasImage =
        _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return ProfileBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Profile'),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20.0),
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
                              CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.black.withOpacity(0.3),
                                backgroundImage: currentUserHasImage
                                    ? NetworkImage(_avatarUrl!)
                                    : null,
                                child: !currentUserHasImage
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          fontSize: 60,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      )
                                    : null,
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
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF0a1128),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentUser?.displayName ?? 'No Name',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: _showEditNameDialog,
                            ),
                          ],
                        ),
                        Text(
                          _currentUser?.email ?? 'No Email',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 20),

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
                        const SizedBox(height: 20),
                        _buildFriendsListSection(),
                        const SizedBox(height: 15),

                        // In settings_screen.dart -> _SettingsScreenState -> build()
                        _buildActionButton(
                          icon: Icons.logout,
                          text: 'Logout',
                          onTap: () async {
                            // --- THIS IS THE NEW LOGIC ---
                            // 1. Get the KeyManagementService

                            // 2. Sign out from Firebase
                            await FirebaseAuth.instance.signOut();

                            // 3. Navigate back to the login screen
                            if (mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                                (route) => false,
                              );
                            }
                            // -----------------------------
                          },
                          color: Colors.redAccent,
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
    );
  }

  Widget _buildFriendsListSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: _toggleFriendsList,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.cyanAccent),
                  const SizedBox(width: 12),
                  const Text(
                    "My Friends",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_friendsList.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _friendsList.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Icon(
                    _isFriendsListVisible
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.white70,
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
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.cyanAccent,
                      ),
                    ),
                  )
                : _friendsList.isEmpty && _isFriendsListVisible
                ? const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(
                      child: Text(
                        "You haven't added any friends yet.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
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
                          leading: CircleAvatar(
                            backgroundColor: hasImage
                                ? Colors.transparent
                                : color,
                            backgroundImage: hasImage
                                ? NetworkImage(friend.avatarUrl!)
                                : null,
                            child: hasImage
                                ? null
                                : Text(
                                    initial,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                          ),
                          title: Text(
                            friend.username,
                            style: const TextStyle(color: Colors.white),
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
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.black87),
      label: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        shadowColor: color,
        elevation: 8,
      ),
    );
  }
}
