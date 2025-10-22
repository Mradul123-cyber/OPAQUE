import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:zarq_messenger/starfield_background.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'screens/phone_otp_verification_screen.dart';


class RegisterScreen extends StatefulWidget {
  final User user;
  final VoidCallback onRegistrationComplete;
  final String? displayName;
  final String? avatarUrl;
  final String? username;

  const RegisterScreen({
    super.key,
    required this.user,
    required this.onRegistrationComplete,
    this.displayName,
    this.avatarUrl,
    this.username,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isLoading = false;
  // Define the backend URL once to avoid repetition and potential typos.
  final String backendBaseUrl = 'https://api.zarqmessenger.com';

  // Phone number with country code (e.g., +919876543210)
  String _completePhoneNumber = '';
  bool _isPhoneValid = false;
  String? _phoneErrorMessage;

  // Username validation (for Google users)
  final _usernameController = TextEditingController();
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();

    // For Google users: Generate initial username from display name
    if (_isGoogleSignIn() && widget.displayName != null && widget.displayName!.isNotEmpty) {
      final suggestedUsername = _generateUsernameFromName(widget.displayName!);
      _usernameController.text = suggestedUsername;
      _checkUsernameAvailability(suggestedUsername);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool _isGoogleSignIn() {
    // Check if user signed in with Google
    for (var provider in widget.user.providerData) {
      if (provider.providerId == 'google.com') {
        return true;
      }
    }
    return false;
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
            _suggestAlternativeUsername(username);
          } else {
            _usernameError = null;
          }
        });
      } else {
        // print('[RegisterScreen] ❌ Username check failed: ${response.statusCode}');
        // print('[RegisterScreen] ❌ Response body: ${response.body}');
        setState(() {
          _isCheckingUsername = false;
          _usernameError = 'Unable to check username';
        });
      }
    } catch (e) {
      // print('[RegisterScreen] Error checking username: $e');
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
        // print('[RegisterScreen] Error suggesting username: $e');
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

  // Navigate to Phone OTP Verification
  void _proceedToOTPVerification() {
    if (_completePhoneNumber.isEmpty || !_isPhoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number.'), backgroundColor: Colors.red),
      );
      return;
    }

    // ✅ Validate username for Google users
    if (_isGoogleSignIn() && (_isUsernameAvailable != true || _usernameController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an available username.'), backgroundColor: Colors.red),
      );
      return;
    }

    // Navigate to OTP verification screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhoneOtpVerificationScreen(
          phoneNumber: _completePhoneNumber,
          user: widget.user,
          displayName: widget.displayName,
          avatarUrl: widget.avatarUrl,
          username: widget.username,
          onVerified: () {
            // After OTP is verified, complete registration
            Navigator.pop(context); // Pop OTP screen
            _completeRegistration();
          },
        ),
      ),
    );
  }

  Future<void> _completeRegistration() async {
    setState(() { _isLoading = true; });
    // print("[RegisterFlow] Starting registration completion for new user: ${widget.user.uid}");

    try {
      // --- Step 1: Create the user profile on the backend ---
      // print("[RegisterFlow] Step 1: Creating profile on backend...");
      // print("[RegisterFlow] Phone number with country code: $_completePhoneNumber");

      final token = await widget.user.getIdToken();
      final profileUrl = Uri.parse('$backendBaseUrl/profiles/create');

      // print("[RegisterFlow] 🔍 Received from ProfileSetup:");
      // print("[RegisterFlow]   - displayName from ProfileSetup: '${widget.displayName}'");
      // print("[RegisterFlow]   - Firebase user.displayName: '${widget.user.displayName}'");
      // print("[RegisterFlow]   - avatarUrl: '${widget.avatarUrl}'");

      // ✅ Determine username and displayName based on sign-in method
      String? usernameToUse;
      String? displayNameToUse;

      if (_isGoogleSignIn()) {
        // Google: username from RegisterScreen field, displayName from ProfileSetup
        usernameToUse = _usernameController.text.trim();
        displayNameToUse = widget.displayName;
      } else {
        // Email/Password: username from Firebase (SignupScreen), displayName from ProfileSetup or same as username
        usernameToUse = widget.user.displayName;  // Username from SignupScreen
        displayNameToUse = (widget.displayName != null && widget.displayName!.isNotEmpty)
          ? widget.displayName  // Use display name from ProfileSetup if provided
          : widget.user.displayName;  // Otherwise use username as display name
      }

      // print("[RegisterFlow]   - Final username: '$usernameToUse'");
      // print("[RegisterFlow]   - Final displayName: '$displayNameToUse'");

      final payload = {
        'phoneNumber': _completePhoneNumber,
        if (displayNameToUse != null && displayNameToUse.isNotEmpty) 'displayName': displayNameToUse,
        if (usernameToUse != null && usernameToUse.isNotEmpty) 'username': usernameToUse,
      };
      // print("[RegisterFlow] 📤 Sending payload to backend: ${json.encode(payload)}");
      final response = await http.post(
        profileUrl,
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: json.encode(payload),
      );

      if (!mounted) return;

      if (response.statusCode == 201) {
        // print("[RegisterFlow] -> Profile created successfully on backend.");

        // --- Step 2: Update avatar if provided ---
        if (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty) {
          // print("[RegisterFlow] Step 2: Updating avatar...");
          final avatarUrl = Uri.parse('$backendBaseUrl/profile/avatar/update');
          final avatarResponse = await http.post(
            avatarUrl,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: json.encode({'avatarUrl': widget.avatarUrl}),
          );
          if (avatarResponse.statusCode == 200) {
            // print("[RegisterFlow] -> Avatar updated successfully.");
          } else {
            // print("[RegisterFlow] WARNING: Avatar update failed: ${avatarResponse.statusCode}");
          }
        }

        // --- Step 3: Signal that registration is complete ---
        // print("[RegisterFlow] Profile creation complete. Calling onRegistrationComplete callback.");
        widget.onRegistrationComplete();

      } else {
        // print("[RegisterFlow] ERROR: Profile creation failed. Server response: ${response.statusCode} ${response.body}");

        // Parse error message and show inline error ONLY for phone number issues
        String errorMessage = response.body;
        if ((errorMessage.toLowerCase().contains('phone') || errorMessage.toLowerCase().contains('number')) &&
            (errorMessage.toLowerCase().contains('already') ||
             errorMessage.toLowerCase().contains('exist') ||
             errorMessage.toLowerCase().contains('registered') ||
             errorMessage.toLowerCase().contains('taken'))) {
          setState(() {
            _phoneErrorMessage = 'This number is already registered';
          });
        } else {
          // For username or other errors, still use SnackBar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Registration failed: $errorMessage'), backgroundColor: Colors.red),
            );
          }
        }
      }
    } catch (e) {
      // print("[RegisterFlow] ERROR: An exception occurred during registration. Error: $e");
      if (mounted) {
        String friendlyMessage = 'Registration failed. Please try again.';

        if (e.toString().toLowerCase().contains('network') ||
            e.toString().toLowerCase().contains('connection') ||
            e.toString().toLowerCase().contains('internet')) {
          friendlyMessage = 'No internet connection. Please check and try again.';
        } else if (e.toString().toLowerCase().contains('timeout')) {
          friendlyMessage = 'Connection timeout. Please try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyMessage), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
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
      setState(() { _isLoading = true; });
      try {
        // print("Cancelling registration, deleting Firebase user...");
        await widget.user.delete();

        // Navigate back to login screen after successful deletion
        if (mounted) {
          // print("User deleted successfully, navigating to login...");
          // Pop all routes and go back to login
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        // print("Error deleting user: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not cancel registration: $e'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() { _isLoading = false; });
        }
      }
    }
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

    // Responsive spacing
    final largeSpacing = screenHeight * 0.06; // ~48 on normal phones
    final mediumSpacing = screenHeight * 0.03; // ~24 on normal phones
    final smallSpacing = screenHeight * 0.02; // ~16 on normal phones
    final tinySpacing = screenHeight * 0.01; // ~8 on normal phones

    // Responsive padding for text fields
    final textFieldVerticalPadding = screenHeight * 0.018; // ~15 on normal phones
    final textFieldHorizontalPadding = screenWidth * 0.05; // ~20 on normal phones

    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              'Complete Registration',
              style: TextStyle(fontSize: subtitleFontSize.clamp(16.0, 20.0)),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.of(context).pop();
              },
              tooltip: 'Back to Profile Setup',
            ),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding.clamp(16.0, 48.0),
                  vertical: smallSpacing,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: IgnorePointer(
                    ignoring: _isLoading,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Welcome, ${widget.user.displayName ?? "New User"}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleFontSize.clamp(24.0, 36.0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: smallSpacing.clamp(12.0, 20.0)),
                        Text(
                          'Just one last step to secure your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            color: Colors.white70,
                          ),
                        ),
                        SizedBox(height: largeSpacing.clamp(32.0, 60.0)),

                        // ✅ Username field for Google users
                        if (_isGoogleSignIn()) ...[
                          Text(
                            'Choose your username:',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: subtitleFontSize.clamp(14.0, 18.0),
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: tinySpacing.clamp(8.0, 16.0)),
                          TextField(
                            controller: _usernameController,
                            maxLength: 30,
                            onChanged: _onUsernameChanged,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            ),
                            decoration: InputDecoration(
                              hintText: 'username',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: subtitleFontSize.clamp(14.0, 18.0),
                              ),
                              helperText: _usernameError ?? 'This will be your @username',
                              helperStyle: TextStyle(
                                color: _usernameError != null ? Colors.red : Colors.white54,
                                fontSize: bodyFontSize.clamp(12.0, 16.0),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                                horizontal: textFieldHorizontalPadding.clamp(16.0, 24.0),
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
                                    padding: EdgeInsets.all(tinySpacing.clamp(10.0, 14.0)),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : (_isUsernameAvailable == true
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : (_isUsernameAvailable == false
                                        ? const Icon(Icons.error, color: Colors.red)
                                        : null)),
                            ),
                          ),
                          SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        ],

                        // Modern phone number field with country picker
                        IntlPhoneField(
                          decoration: InputDecoration(
                            hintText: '9876543210',
                            hintStyle: TextStyle(
                              color: Colors.white38,
                              fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            ),
                            labelText: 'Phone Number',
                            labelStyle: TextStyle(
                              color: Colors.white70,
                              fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            ),
                            counterText: '',
                            contentPadding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              horizontal: textFieldHorizontalPadding.clamp(16.0, 24.0),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.3),
                          ),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                          ),
                          dropdownTextStyle: TextStyle(
                            color: Colors.white,
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                          ),
                          initialCountryCode: 'IN', // Default to India
                          showCountryFlag: true,
                          showDropdownIcon: true,
                          dropdownIconPosition: IconPosition.trailing,
                          flagsButtonPadding: EdgeInsets.only(
                            left: screenWidth * 0.03,
                          ),
                          onChanged: (phone) {
                            setState(() {
                              _completePhoneNumber = phone.completeNumber;
                              _isPhoneValid = phone.number.isNotEmpty;
                              // Clear error when user changes phone number
                              _phoneErrorMessage = null;
                            });
                            // print('[PhoneField] Complete number: ${phone.completeNumber}');
                            // print('[PhoneField] Country code: ${phone.countryCode}');
                            // print('[PhoneField] Number: ${phone.number}');
                          },
                          validator: (phone) {
                            if (phone == null || phone.number.isEmpty) {
                              return 'Phone number is required';
                            }
                            return null;
                          },
                        ),
                        // Show error message if phone number already registered
                        if (_phoneErrorMessage != null)
                          Padding(
                            padding: EdgeInsets.only(top: tinySpacing.clamp(6.0, 12.0)),
                            child: Text(
                              _phoneErrorMessage!,
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: bodyFontSize.clamp(12.0, 16.0),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          ElevatedButton(
                            onPressed: _proceedToOTPVerification,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              ),
                            ),
                            child: Text(
                              'Verify Phone & Continue',
                              style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                            ),
                          ),
                        TextButton(
                          onPressed: _isLoading ? null : _cancelRegistration,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(8.0, 14.0),
                            ),
                          ),
                          child: Text(
                            'Cancel and Go Back',
                            style: TextStyle(fontSize: bodyFontSize.clamp(12.0, 16.0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
