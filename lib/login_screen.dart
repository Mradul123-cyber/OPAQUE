import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart'; // Import main.dart to get access to AuthGate
import 'signup_screen.dart';
import 'starfield_background.dart';
import 'email_verification_screen.dart';
import 'app_config.dart';
import 'services/google_auth_service.dart';
import 'widgets/google_sign_in_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isPasswordVisible = false;
  final GoogleAuthService _googleAuthService = GoogleAuthService();

  Future<void> _loginWithFirebaseEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Validate fields
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Basic email format validation
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );


      // Check if email is verified (only if email verification is enabled)
      if (ENABLE_EMAIL_VERIFICATION && userCredential.user != null && !userCredential.user!.emailVerified) {
        // print("[Login Screen] -> Email not verified, redirecting to verification screen");
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(
                user: userCredential.user!,
                username: userCredential.user!.displayName ?? 'User',
              ),
            ),
          );
        }
        return;
      }

      // Email verified or verification disabled, proceed to app
      if (mounted) {
        // This forces the app to re-evaluate the auth state from the top.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }
    } on FirebaseAuthException catch (e) {
      // print("[Login Screen] -> FIREBASE ERROR: ${e.code} - ${e.message}");

      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email. Please sign up first.';
          break;
        case 'wrong-password':
          errorMessage = 'Wrong password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your connection.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password.';
          break;
        default:
          errorMessage = 'Login failed. Please try again.';
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
      // print("[Login Screen] -> UNKNOWN ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An unexpected error occurred. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    // Only set loading to false if there was an error.
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      // print("[Login Screen] Starting Google Sign-In...");

      // Sign in with Google
      final UserCredential userCredential = await _googleAuthService.signInWithGoogle();
      final User? user = userCredential.user;

      if (user == null) {
        throw Exception('Failed to get user from Google Sign-In');
      }

      // print("[Login Screen] -> SUCCESS: Google Sign-In successful for ${user.email}");

      // Google users don't need email verification - already verified by Google
      // Google automatically sets emailVerified = true, so we skip verification
      if (mounted) {
        // Navigate to AuthGate which will check if profile exists
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }

    } on FirebaseAuthException catch (e) {
      // print("[Login Screen] -> FIREBASE GOOGLE ERROR: ${e.code} - ${e.message}");

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
      // print("[Login Screen] -> GOOGLE SIGN IN ERROR: $e");

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
            title: Text(
              'Zarq Messenger Login',
              style: TextStyle(fontSize: subtitleFontSize.clamp(16.0, 20.0)),
            ),
            centerTitle: true,
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
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: titleFontSize.clamp(28.0, 40.0),
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: tinySpacing.clamp(6.0, 12.0)),
                        Text(
                          'Sign in to continue',
                          style: TextStyle(
                            fontSize: subtitleFontSize.clamp(14.0, 18.0),
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: largeSpacing.clamp(32.0, 60.0)),

                        // Google Sign-In Button (Works for both Web and Mobile)
                        GoogleSignInButton(
                          onPressed: _signInWithGoogle,
                          isLoading: _isGoogleLoading,
                          text: 'Sign in with Google',
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
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                          decoration: InputDecoration(
                            hintText: 'Email',
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
                          style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                          decoration: InputDecoration(
                            hintText: 'Password',
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
                        SizedBox(height: mediumSpacing.clamp(20.0, 32.0)),
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          ElevatedButton(
                            onPressed: _loginWithFirebaseEmail,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: textFieldVerticalPadding.clamp(12.0, 18.0),
                              ),
                            ),
                            child: Text(
                              'Log In with Email',
                              style: TextStyle(fontSize: subtitleFontSize.clamp(14.0, 18.0)),
                            ),
                          ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignUpScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: textFieldVerticalPadding.clamp(8.0, 14.0),
                            ),
                          ),
                          child: Text(
                            "Don't have an account? Sign Up",
                            style: TextStyle(fontSize: bodyFontSize.clamp(12.0, 16.0)),
                          ),
                        ),
                        SizedBox(height: mediumSpacing.clamp(24.0, 40.0)),
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
