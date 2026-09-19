import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/main.dart';
import 'starfield_background.dart';
import "register_screen.dart";
import "profile_setup_screen.dart";
import "email_verification_screen.dart";
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'app_config.dart';
import 'services/google_auth_service.dart';
import 'widgets/google_sign_in_button.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  String _status = "Waiting...";
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isPasswordVisible = false;
  final String backendBaseUrl = '${AppConfig.baseUrl}';
  String _passwordStrength = '';
  Color _passwordStrengthColor = Colors.transparent;
  final GoogleAuthService _googleAuthService = GoogleAuthService();

  void _checkPasswordStrength(String password) {
    if (password.isEmpty) {
      setState(() {
        _passwordStrength = '';
        _passwordStrengthColor = Colors.transparent;
      });
      return;
    }

    int strength = 0;

    // Check length
    if (password.length >= 8) strength++;
    if (password.length >= 12) strength++;

    // Check for lowercase
    if (password.contains(RegExp(r'[a-z]'))) strength++;

    // Check for uppercase
    if (password.contains(RegExp(r'[A-Z]'))) strength++;

    // Check for numbers
    if (password.contains(RegExp(r'[0-9]'))) strength++;

    // Check for special characters
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength++;

    setState(() {
      if (strength <= 2) {
        _passwordStrength = 'Weak';
        _passwordStrengthColor = Colors.red;
      } else if (strength <= 4) {
        _passwordStrength = 'Moderate';
        _passwordStrengthColor = Colors.orange;
      } else {
        _passwordStrength = 'Strong';
        _passwordStrengthColor = Colors.green;
      }
    });
  }

  Future<bool> _checkUsernameAvailability(String username) async {
    try {
      final url = Uri.parse('$backendBaseUrl/profiles/check-username');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['available'] ?? false;
      }
      return false;
    } catch (e) {
      // print('[SignUp] Error checking username availability: $e');
      return false;
    }
  }

  Future<void> _signUp() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate username format: no leading/trailing spaces, no consecutive spaces
    if (username != _usernameController.text.trim() || username.contains(RegExp(r'\s{2,}'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username cannot have leading/trailing spaces or multiple consecutive spaces'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate password strength (must be at least Moderate)
    if (_passwordStrength == 'Weak' || _passwordStrength.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password is too weak. Please use at least 8 characters with uppercase, lowercase, and numbers.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Check if username is available before creating Firebase account
      // print('[SignUp] Checking username availability for: $username');
      final isAvailable = await _checkUsernameAvailability(username);

      if (!isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Username is already taken. Please choose a different username.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // print('[SignUp] Username is available, proceeding with account creation');
      // Step 1: Create the user in Firebase.
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: password,
          );

      // Step 2: Update their display name.
      if (userCredential.user != null) {
        await userCredential.user!.updateDisplayName(username);

        // Step 3: Send email verification (if enabled)
        if (ENABLE_EMAIL_VERIFICATION) {
          await userCredential.user!.sendEmailVerification();
          // print('[SignUp] Verification email sent to ${userCredential.user!.email}');
        }
      }

      if (mounted) {
        if (ENABLE_EMAIL_VERIFICATION) {
          // Show email verification screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(
                user: userCredential.user!,
                username: username,
              ),
            ),
          );
        } else {
          // Skip email verification, go directly to profile setup
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ProfileSetupScreen(
                user: userCredential.user!,
                onSetupComplete: (String? displayName, String? avatarUrl, String? username) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RegisterScreen(
                        user: userCredential.user!,
                        displayName: displayName,
                        avatarUrl: avatarUrl,
                        username: username,
                        onRegistrationComplete: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => AuthWrapper(user: userCredential.user!),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
      return;

    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String friendlyMessage;
        switch (e.code) {
          case 'email-already-in-use':
            friendlyMessage = 'This email is already registered. Please login instead.';
            break;
          case 'weak-password':
            friendlyMessage = 'Password is too weak. Please use a stronger password.';
            break;
          case 'invalid-email':
            friendlyMessage = 'Invalid email address.';
            break;
          case 'network-request-failed':
            friendlyMessage = 'No internet connection. Please check and try again.';
            break;
          default:
            friendlyMessage = 'Sign up failed. Please try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String friendlyMessage = 'Something went wrong. Please try again.';

        if (e.toString().toLowerCase().contains('network') ||
            e.toString().toLowerCase().contains('connection')) {
          friendlyMessage = 'No internet connection. Please check and try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      // print("[SignUp Screen] Starting Google Sign-In...");

      // Sign up/in with Google (Google handles both)
      final UserCredential userCredential = await _googleAuthService.signInWithGoogle();
      final User? user = userCredential.user;

      if (user == null) {
        throw Exception('Failed to get user from Google Sign-In');
      }

      // print("[SignUp Screen] -> SUCCESS: Google Sign-In successful for ${user.email}");

      // Google users don't need email verification - already verified by Google
      // Google automatically sets emailVerified = true, so we skip verification
      if (mounted) {
        // Navigate to AuthGate which will check if profile exists
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }

    } on FirebaseAuthException catch (e) {
      // print("[SignUp Screen] -> FIREBASE GOOGLE ERROR: ${e.code} - ${e.message}");

      String errorMessage;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          errorMessage = 'This email is already registered with a different sign-in method. Please use email/password login.';
          break;
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          errorMessage = 'Sign-in cancelled.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your connection.';
          break;
        default:
          errorMessage = 'Google Sign-In failed. Please try again.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // print("[SignUp Screen] -> GOOGLE SIGN IN ERROR: $e");

      if (mounted) {
        String errorMessage = 'Google Sign-In failed. Please try again.';

        if (e.toString().contains('cancelled')) {
          errorMessage = 'Sign-in cancelled.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
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
    final titleFontSize = screenWidth * 0.08; // 8% of width, ~32 on normal phones
    final subtitleFontSize = screenWidth * 0.04; // ~16 on normal phones
    final bodyFontSize = screenWidth * 0.035; // ~14 on normal phones

    // Responsive spacing
    final largeSpacing = screenHeight * 0.06; // ~48 on normal phones
    final mediumSpacing = screenHeight * 0.03; // ~24 on normal phones
    final smallSpacing = screenHeight * 0.02; // ~16 on normal phones
    final tinySpacing = screenHeight * 0.01; // ~8 on normal phones

    // Responsive padding for text fields
    final textFieldVerticalPadding = screenHeight * 0.018; // ~15 on normal phones

    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Sign Up'),
            backgroundColor: Colors.transparent,
            elevation: 0,
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
                          'Join Zarq',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleFontSize.clamp(28.0, 40.0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: tinySpacing.clamp(6.0, 12.0)),
                        Text(
                          'Create your account',
                          style: TextStyle(
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: largeSpacing.clamp(32.0, 60.0)),

                        // Google Sign-In Button (Works for both Web and Mobile)
                        GoogleSignInButton(
                          onPressed: _signUpWithGoogle,
                          isLoading: _isGoogleLoading,
                          text: 'Continue with Google',
                        ),

                        SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white38, thickness: 1)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontWeight: FontWeight.w500,
                                  fontSize: bodyFontSize.clamp(12.0, 16.0),
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: Colors.white38, thickness: 1)),
                          ],
                        ),
                        SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        TextField(
                          controller: _usernameController,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'^\s')), // No leading space
                            TextInputFormatter.withFunction((oldValue, newValue) {
                              // Prevent multiple consecutive spaces
                              if (newValue.text.contains(RegExp(r'\s{2,}'))) {
                                return oldValue;
                              }
                              return newValue;
                            }),
                          ],
                          style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                          decoration: InputDecoration(
                            hintText: 'Choose a Username',
                            hintStyle: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
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
                        SizedBox(height: smallSpacing.clamp(12.0, 20.0)),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                          decoration: InputDecoration(
                            hintText: 'Enter your Email',
                            hintStyle: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
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
                        SizedBox(height: smallSpacing.clamp(12.0, 20.0)),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          onChanged: _checkPasswordStrength,
                          style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                          decoration: InputDecoration(
                            hintText: 'Choose a Password',
                            hintStyle: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              horizontal: screenWidth * 0.04,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.3),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.white70,
                                size: subtitleFontSize.clamp(18.0, 24.0),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                        ),
                        if (_passwordStrength.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: tinySpacing.clamp(6.0, 10.0)),
                            child: Text(
                              'Password Strength: $_passwordStrength',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _passwordStrengthColor,
                                fontWeight: FontWeight.bold,
                                fontSize: bodyFontSize.clamp(12.0, 16.0),
                              ),
                            ),
                          ),
                        SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          ElevatedButton(
                            onPressed: _signUp,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              ),
                            ),
                            child: Text(
                              'Sign Up',
                              style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(8.0, 14.0),
                            ),
                          ),
                          child: Text(
                            'Already have an account? Log In',
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
