import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'starfield_background.dart';
import 'profile_setup_screen.dart';
import 'register_screen.dart';
import 'main.dart';

class EmailVerificationScreen extends StatefulWidget {
  final User user;
  final String username;

  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.username,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  bool _isCheckingVerification = false;
  bool _canResendEmail = true;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Start checking for email verification every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkEmailVerified();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    if (_isCheckingVerification) return;

    setState(() {
      _isCheckingVerification = true;
    });

    try {
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        _timer?.cancel();

        if (mounted) {
          // Email verified, proceed to profile setup
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ProfileSetupScreen(
                user: user,
                onSetupComplete: (String? displayName, String? avatarUrl, String? username) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RegisterScreen(
                        user: user,
                        displayName: displayName,
                        avatarUrl: avatarUrl,
                        username: username,
                        onRegistrationComplete: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => AuthWrapper(user: user),
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
    } catch (e) {
      // print('[EmailVerification] Error checking verification: $e');
    }

    if (mounted) {
      setState(() {
        _isCheckingVerification = false;
      });
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResendEmail) return;

    try {
      await widget.user.sendEmailVerification();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent! Please check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );

        // Disable resend button for 60 seconds
        setState(() {
          _canResendEmail = false;
          _resendCountdown = 60;
        });

        // Countdown timer
        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_resendCountdown > 0) {
            setState(() {
              _resendCountdown--;
            });
          } else {
            setState(() {
              _canResendEmail = true;
            });
            timer.cancel();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send verification email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelSignup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Signup?'),
        content: const Text(
          'This will delete your account and you will have to sign up again. Are you sure?',
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
        await widget.user.delete();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not cancel signup: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Verify Email'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
          ),
          body: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 100,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Verify Your Email',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'We sent a verification email to:\n${widget.user.email}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Please check your inbox and click the verification link to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 48),
                    if (_isCheckingVerification)
                      const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Checking verification status...',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _checkEmailVerified,
                        icon: const Icon(Icons.refresh),
                        label: const Text('I\'ve Verified'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _canResendEmail ? _resendVerificationEmail : null,
                      child: Text(
                        _canResendEmail
                            ? 'Resend Verification Email'
                            : 'Resend in $_resendCountdown seconds',
                        style: TextStyle(
                          color: _canResendEmail ? Colors.blue : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cancelSignup,
                      child: const Text(
                        'Cancel and Go Back',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
