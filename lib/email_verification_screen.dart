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
  bool _isManualChecking = false;
  bool _canResendEmail = true;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Start checking for email verification every 5 seconds (silently in background)
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkEmailVerifiedSilently();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Silent background check (doesn't show loading UI)
  Future<void> _checkEmailVerifiedSilently() async {
    try {
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        _timer?.cancel();
        _proceedToNextScreen(user);
      }
    } catch (e) {
      // Silently fail, will retry in 5 seconds
    }
  }

  // Manual check (shows loading UI when user clicks button)
  Future<void> _checkEmailVerifiedManually() async {
    if (_isManualChecking) return;

    setState(() {
      _isManualChecking = true;
    });

    try {
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        _timer?.cancel();
        _proceedToNextScreen(user);
      } else {
        // Not verified yet
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Email not verified yet. Please check your inbox.'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking verification: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isManualChecking = false;
      });
    }
  }

  void _proceedToNextScreen(User user) {
    if (mounted) {
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

  Future<void> _resendVerificationEmail() async {
    if (!_canResendEmail) return;

    try {
      await widget.user.sendEmailVerification();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Verification email sent! Please check your inbox.'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Failed to send email: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showEmailHelpDialog(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.mail_outline,
              color: Colors.cyanAccent,
              size: (screenWidth * 0.06).clamp(20.0, 28.0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Email Not Received?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (screenWidth * 0.045).clamp(16.0, 20.0),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Try these steps:',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: (screenWidth * 0.038).clamp(14.0, 17.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: (screenWidth * 0.03).clamp(10.0, 14.0)),
              _buildHelpStep(
                '1',
                'Check Spam/Junk Folder',
                'The email might be in your spam or junk folder',
                screenWidth,
              ),
              SizedBox(height: (screenWidth * 0.025).clamp(8.0, 12.0)),
              _buildHelpStep(
                '2',
                'Wait a Few Minutes',
                'Email delivery can take 1-5 minutes',
                screenWidth,
              ),
              SizedBox(height: (screenWidth * 0.025).clamp(8.0, 12.0)),
              _buildHelpStep(
                '3',
                'Check Email Address',
                'Make sure ${widget.user.email} is correct',
                screenWidth,
              ),
              SizedBox(height: (screenWidth * 0.025).clamp(8.0, 12.0)),
              _buildHelpStep(
                '4',
                'Add to Safe Senders',
                'Add noreply@zarq-messenger.com to your contacts',
                screenWidth,
              ),
              SizedBox(height: (screenWidth * 0.03).clamp(10.0, 14.0)),
              Container(
                padding: EdgeInsets.all((screenWidth * 0.03).clamp(10.0, 14.0)),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: (screenWidth * 0.045).clamp(16.0, 20.0),
                    ),
                    SizedBox(width: (screenWidth * 0.02).clamp(8.0, 12.0)),
                    Expanded(
                      child: Text(
                        'Still no email? Click "Resend" button above',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: (screenWidth * 0.03).clamp(11.0, 14.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: (screenWidth * 0.038).clamp(14.0, 17.0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String title, String description, double screenWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: (screenWidth * 0.07).clamp(24.0, 32.0),
          height: (screenWidth * 0.07).clamp(24.0, 32.0),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.cyanAccent),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(width: (screenWidth * 0.03).clamp(10.0, 14.0)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: (screenWidth * 0.01).clamp(4.0, 6.0)),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: (screenWidth * 0.03).clamp(11.0, 14.0),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _cancelSignup() async {
    final screenWidth = MediaQuery.of(context).size.width;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 10),
            Text(
              'Cancel Signup?',
              style: TextStyle(
                color: Colors.white,
                fontSize: (screenWidth * 0.045).clamp(16.0, 20.0),
              ),
            ),
          ],
        ),
        content: Text(
          'This will delete your account and you will have to sign up again. Are you sure?',
          style: TextStyle(
            color: Colors.white70,
            fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'No, Keep Account',
              style: TextStyle(
                color: Colors.white70,
                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Yes, Cancel Signup',
              style: TextStyle(
                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
              ),
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
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Could not cancel: ${e.toString()}'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final titleSize = (screenWidth * 0.07).clamp(24.0, 32.0);
    final subtitleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final iconSize = (screenWidth * 0.2).clamp(70.0, 100.0);
    final spacing1 = (screenHeight * 0.03).clamp(20.0, 30.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 20.0);
    final spacing3 = (screenHeight * 0.01).clamp(6.0, 10.0);

    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('Verify Email', style: TextStyle(fontSize: subtitleSize.clamp(16.0, 20.0))),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all((screenWidth * 0.05).clamp(16.0, 24.0)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Email icon with modern styling
                    Container(
                      padding: EdgeInsets.all(spacing2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.mark_email_unread_outlined,
                        size: iconSize,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    SizedBox(height: spacing1),

                    // Title
                    Text(
                      'Verify Your Email',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: spacing2),

                    // Email address
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: (screenWidth * 0.04).clamp(12.0, 20.0),
                        vertical: spacing3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        widget.user.email ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: subtitleSize,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing1),

                    // Instructions
                    Container(
                      padding: EdgeInsets.all(spacing2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white70,
                            size: (screenWidth * 0.06).clamp(20.0, 28.0),
                          ),
                          SizedBox(height: spacing3),
                          Text(
                            'We sent a verification link to your email.\nPlease check your inbox (and spam folder) and click the link to verify your account.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: bodySize,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing1 * 1.5),

                    // Verify button or loading
                    if (_isManualChecking)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: Colors.cyanAccent),
                          SizedBox(height: spacing2),
                          Text(
                            'Checking verification...',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: bodySize,
                            ),
                          ),
                        ],
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _checkEmailVerifiedManually,
                        icon: const Icon(Icons.verified_user),
                        label: Text(
                          'I\'ve Verified My Email',
                          style: TextStyle(fontSize: subtitleSize),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(
                            horizontal: (screenWidth * 0.08).clamp(30.0, 50.0),
                            vertical: (screenHeight * 0.018).clamp(12.0, 18.0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),

                    SizedBox(height: spacing2),

                    // Resend button
                    OutlinedButton.icon(
                      onPressed: _canResendEmail ? _resendVerificationEmail : null,
                      icon: Icon(
                        Icons.email,
                        size: (screenWidth * 0.045).clamp(16.0, 20.0),
                      ),
                      label: Text(
                        _canResendEmail
                            ? 'Resend Verification Email'
                            : 'Resend in $_resendCountdown s',
                        style: TextStyle(fontSize: bodySize),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _canResendEmail ? Colors.cyanAccent : Colors.grey,
                        side: BorderSide(
                          color: _canResendEmail
                              ? Colors.cyanAccent
                              : Colors.grey.withOpacity(0.3),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: (screenWidth * 0.06).clamp(20.0, 40.0),
                          vertical: (screenHeight * 0.015).clamp(10.0, 16.0),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),

                    SizedBox(height: spacing1),

                    // Auto-check indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: spacing3),
                        Text(
                          'Auto-checking every 5 seconds',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: (screenWidth * 0.03).clamp(11.0, 14.0),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: spacing2),

                    // Email not received help
                    TextButton.icon(
                      onPressed: () => _showEmailHelpDialog(context),
                      icon: Icon(
                        Icons.help_outline,
                        size: (screenWidth * 0.04).clamp(14.0, 18.0),
                        color: Colors.white60,
                      ),
                      label: Text(
                        'Email not received?',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: (screenWidth * 0.03).clamp(11.0, 14.0),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),

                    SizedBox(height: spacing3),

                    // Cancel button
                    TextButton(
                      onPressed: _cancelSignup,
                      child: Text(
                        'Cancel and Go Back',
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: bodySize,
                        ),
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
