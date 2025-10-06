import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:zarq_messenger/starfield_background.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ProfileSetupScreen extends StatefulWidget {
  final User user;
  final Function(String? displayName, String? avatarUrl, String? username) onSetupComplete;

  const ProfileSetupScreen({
    super.key,
    required this.user,
    required this.onSetupComplete,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  String? _avatarUrl;
  bool _isUploading = false;
  File? _imageFile;
  Uint8List? _webImage;

  // Username validation
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameError;
  Timer? _debounce;
  bool _showUsernameField = false; // Track if username field should be shown (not used for Google users anymore)
  final String backendBaseUrl = 'http://192.168.29.81:8080';

  bool _isGoogleSignIn() {
    // Check if user signed in with Google
    for (var provider in widget.user.providerData) {
      if (provider.providerId == 'google.com') {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    // Debug: Check what Google provides
    // print('[ProfileSetup] Firebase User Info:');
    // print('[ProfileSetup]   - UID: ${widget.user.uid}');
    // print('[ProfileSetup]   - Email: ${widget.user.email}');
    // print('[ProfileSetup]   - Display Name: ${widget.user.displayName}');
    // print('[ProfileSetup]   - Photo URL: ${widget.user.photoURL}');
    // print('[ProfileSetup]   - Is Google Sign-In: ${_isGoogleSignIn()}');

    // Pre-fill with username/display name if available
    _displayNameController.text = widget.user.displayName ?? '';

    // ✅ NO username logic for email/password users - they already entered username in SignupScreen
    // ✅ NO username logic for Google users - they will enter username in RegisterScreen

    // Pre-fill avatar with Google photo URL if user signed in with Google
    if (widget.user.photoURL != null && widget.user.photoURL!.isNotEmpty) {
      _avatarUrl = widget.user.photoURL;
      // print('[ProfileSetup] ✅ Pre-filled avatar from Google');
    }

    if (_displayNameController.text.isNotEmpty) {
      // print('[ProfileSetup] ✅ Pre-filled display name: ${_displayNameController.text}');
    } else {
      // print('[ProfileSetup] ⚠️ Display name is empty - user will need to enter manually');
    }
  }

  String _generateUsernameFromName(String name) {
    // Remove special characters, spaces, convert to lowercase
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.isEmpty || username.length < 3) {
      setState(() {
        _isUsernameAvailable = false;
        _usernameError = 'Username must be at least 3 characters';
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    try {
      final token = await widget.user.getIdToken();
      final response = await http.post(
        Uri.parse('$backendBaseUrl/profiles/check-username'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'username': username}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final available = data['available'] == true;

        setState(() {
          _isUsernameAvailable = available;
          _isCheckingUsername = false;
          if (!available) {
            _usernameError = 'Username already taken';
            // Show username field for email/password users when username is taken
            // Google users will handle username in RegisterScreen
            if (!_isGoogleSignIn()) {
              _showUsernameField = true;
              _suggestAlternativeUsername(username);
            }
          } else {
            _usernameError = null;
          }
        });
      } else {
        setState(() {
          _isCheckingUsername = false;
          _usernameError = 'Unable to check username';
        });
      }
    } catch (e) {
      // print('[ProfileSetup] Error checking username: $e');
      setState(() {
        _isCheckingUsername = false;
        _usernameError = 'Error checking username';
      });
    }
  }

  void _suggestAlternativeUsername(String baseUsername) async {
    // Try appending numbers until we find an available one
    for (int i = 1; i <= 99; i++) {
      final suggested = '$baseUsername$i';
      try {
        final token = await widget.user.getIdToken();
        final response = await http.post(
          Uri.parse('$backendBaseUrl/profiles/check-username'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({'username': suggested}),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['available'] == true) {
            // Found available username
            setState(() {
              _usernameController.text = suggested;
              _isUsernameAvailable = true;
              _usernameError = null;
            });
            break;
          }
        }
      } catch (e) {
        break;
      }
    }
  }

  void _onUsernameChanged(String value) {
    // Cancel previous timer
    _debounce?.cancel();

    // Start new timer (wait 500ms after user stops typing)
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability(value);
    });
  }

  Future<void> _cancelRegistration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Registration?'),
        content: const Text(
          'This will delete your new account, and you will have to sign up again. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // print("[ProfileSetup] Cancelling registration, deleting Firebase user...");
        await widget.user.delete();
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not cancel registration: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
    );

    if (pickedFile == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'profile_pictures/${widget.user.uid}/avatar.jpg',
      );

      String downloadUrl;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        _webImage = bytes;
        final uploadTask = storageRef.putData(bytes);
        final snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        _imageFile = File(pickedFile.path);
        final uploadTask = storageRef.putFile(_imageFile!);
        final snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      setState(() {
        _avatarUrl = downloadUrl;
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar uploaded successfully!')),
      );
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload avatar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _continue() async {
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();

    // print('[ProfileSetup] Continue pressed:');
    // print('[ProfileSetup]   - Display Name: $displayName');
    // print('[ProfileSetup]   - Username: $username');
    // print('[ProfileSetup]   - Username Available: $_isUsernameAvailable');
    // print('[ProfileSetup]   - Is Google Sign-In: ${_isGoogleSignIn()}');

    widget.onSetupComplete(
      displayName.isNotEmpty ? displayName : null,
      _avatarUrl,
      username.isNotEmpty ? username : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive design
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive calculations
    final isSmallScreen = screenWidth < 360;
    final isTablet = screenWidth > 600;

    // Adaptive padding based on screen width
    final horizontalPadding = screenWidth * 0.08; // 8% of screen width
    final maxWidth = isTablet ? 500.0 : screenWidth * 0.9;

    // Responsive font sizes
    final titleFontSize = screenWidth * 0.07; // ~28 on normal phones
    final subtitleFontSize = screenWidth * 0.04; // ~16 on normal phones
    final bodyFontSize = screenWidth * 0.035; // ~14 on normal phones
    final buttonFontSize = screenWidth * 0.045; // ~18 on normal phones

    // Responsive spacing
    final largeSpacing = screenHeight * 0.06; // ~48 on normal phones
    final mediumSpacing = screenHeight * 0.05; // ~40 on normal phones
    final smallSpacing = screenHeight * 0.04; // ~32 on normal phones
    final tinySpacing = screenHeight * 0.03; // ~24 on normal phones
    final miniSpacing = screenHeight * 0.015; // ~12 on normal phones
    final microSpacing = screenHeight * 0.01; // ~8 on normal phones

    // Responsive sizes
    final avatarRadius = screenWidth * 0.15; // ~60 on normal phones
    final avatarIconSize = screenWidth * 0.15; // ~60 on normal phones
    final cameraIconSize = screenWidth * 0.05; // ~20 on normal phones
    final cameraButtonPadding = screenWidth * 0.02; // ~8 on normal phones

    // Responsive padding for text fields
    final textFieldVerticalPadding = screenHeight * 0.018; // ~15 on normal phones

    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'Setup Your Profile',
              style: TextStyle(fontSize: subtitleFontSize.clamp(16.0, 20.0)),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _cancelRegistration,
              tooltip: 'Cancel Registration',
            ),
            actions: [
              TextButton(
                onPressed: () => widget.onSetupComplete(null, null, null),
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: subtitleFontSize.clamp(14.0, 18.0),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding.clamp(16.0, 48.0),
                  vertical: microSpacing,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Personalize Your Profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize.clamp(24.0, 36.0),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: microSpacing.clamp(6.0, 12.0)),
                      Text(
                        'Add a photo and display name (optional)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: subtitleFontSize.clamp(14.0, 18.0),
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: largeSpacing.clamp(32.0, 60.0)),

                      // Avatar Section
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: avatarRadius.clamp(50.0, 80.0),
                              backgroundColor: Colors.grey[800],
                              backgroundImage: _avatarUrl != null
                                  ? NetworkImage(_avatarUrl!)
                                  : (_webImage != null
                                      ? MemoryImage(_webImage!)
                                      : null) as ImageProvider?,
                              child: _avatarUrl == null && _webImage == null
                                  ? Icon(
                                      Icons.person,
                                      size: avatarIconSize.clamp(50.0, 80.0),
                                      color: Colors.white54,
                                    )
                                  : null,
                            ),
                            if (_isUploading)
                              const Positioned.fill(
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickAndUploadAvatar,
                                child: Container(
                                  padding: EdgeInsets.all(cameraButtonPadding.clamp(6.0, 10.0)),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00ACC1),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: cameraIconSize.clamp(18.0, 24.0),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: mediumSpacing.clamp(30.0, 50.0)),

                      // Display Name Field
                      TextField(
                        controller: _displayNameController,
                        maxLength: 30,
                        onChanged: (value) {
                          // Only auto-generate username for Google users when display name changes
                          if (_isGoogleSignIn() && value.isNotEmpty) {
                            final suggestedUsername = _generateUsernameFromName(value);
                            _usernameController.text = suggestedUsername;
                            _onUsernameChanged(suggestedUsername);
                          }
                        },
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: subtitleFontSize.clamp(14.0, 18.0),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter Display Name',
                          hintStyle: TextStyle(
                            color: Colors.white54,
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                          ),
                          helperText: 'Maximum 30 characters',
                          helperStyle: TextStyle(
                            color: Colors.white54,
                            fontSize: bodyFontSize.clamp(12.0, 16.0),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                            horizontal: screenWidth * 0.04,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                          ),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                        ),
                      ),

                      // Username Field - Only shown for email/password users with duplicate names
                      if (_showUsernameField) ...[
                        SizedBox(height: tinySpacing.clamp(20.0, 30.0)),
                        Text(
                          'Someone already has that username. Please choose a different one:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: bodyFontSize.clamp(12.0, 16.0),
                            color: Colors.orange,
                          ),
                        ),
                        SizedBox(height: miniSpacing.clamp(10.0, 16.0)),
                        TextField(
                          controller: _usernameController,
                          maxLength: 30,
                          onChanged: _onUsernameChanged,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Choose Username',
                            hintStyle: TextStyle(
                              color: Colors.white54,
                              fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            ),
                            helperText: _usernameError ?? 'This will be your @username',
                            helperStyle: TextStyle(
                              color: _usernameError != null ? Colors.red : Colors.white54,
                              fontSize: bodyFontSize.clamp(12.0, 16.0),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              horizontal: screenWidth * 0.04,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide(
                                color: _isUsernameAvailable == true
                                  ? Colors.green
                                  : (_isUsernameAvailable == false ? Colors.red : Colors.white24),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide(
                                color: _isUsernameAvailable == true
                                  ? Colors.green
                                  : (_isUsernameAvailable == false ? Colors.red : Colors.white24),
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide(
                                color: _isUsernameAvailable == true
                                  ? Colors.green
                                  : (_isUsernameAvailable == false ? Colors.red : Colors.lightBlueAccent),
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.3),
                            suffixIcon: _isCheckingUsername
                              ? Padding(
                                  padding: EdgeInsets.all(miniSpacing.clamp(10.0, 14.0)),
                                  child: SizedBox(
                                    width: cameraIconSize.clamp(18.0, 24.0),
                                    height: cameraIconSize.clamp(18.0, 24.0),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : (_isUsernameAvailable == true
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: subtitleFontSize.clamp(20.0, 28.0),
                                    )
                                  : (_isUsernameAvailable == false
                                      ? Icon(
                                          Icons.error,
                                          color: Colors.red,
                                          size: subtitleFontSize.clamp(20.0, 28.0),
                                        )
                                      : null)),
                          ),
                        ),
                      ],
                      SizedBox(height: smallSpacing.clamp(24.0, 40.0)),

                      ElevatedButton(
                        onPressed: _showUsernameField
                          ? (_isUsernameAvailable == true ? _continue : null)
                          : _continue,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          backgroundColor: const Color(0xFF00ACC1),
                        ),
                        child: Text(
                          'Continue',
                          style: TextStyle(fontSize: buttonFontSize.clamp(16.0, 22.0)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
