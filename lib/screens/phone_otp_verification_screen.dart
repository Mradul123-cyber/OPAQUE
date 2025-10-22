import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../starfield_background.dart';

class PhoneOtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final User user;
  final String? displayName;
  final String? avatarUrl;
  final String? username;
  final VoidCallback onVerified;

  const PhoneOtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.user,
    required this.displayName,
    required this.avatarUrl,
    required this.username,
    required this.onVerified,
  });

  @override
  State<PhoneOtpVerificationScreen> createState() => _PhoneOtpVerificationScreenState();
}

class _PhoneOtpVerificationScreenState extends State<PhoneOtpVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String? _verificationId;
  int? _resendToken;
  int _countdown = 60;
  Timer? _timer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sendOTP();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOTP() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (happens on some Android devices)
          await _verifyCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.message ?? 'Verification failed';
          });
          _showSnackbar(_errorMessage!, isError: true);
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
          });
          _startCountdown();
          _showSnackbar('OTP sent to ${widget.phoneNumber}');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
          });
        },
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      _showSnackbar('Failed to send OTP: $e', isError: true);
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpControllers.map((c) => c.text).join();

    if (otp.length != 6) {
      _showSnackbar('Please enter the complete OTP', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      await _verifyCredential(credential);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid OTP';
      });
      _showSnackbar('Invalid OTP. Please try again.', isError: true);

      // Clear OTP fields
      for (var controller in _otpControllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _verifyCredential(PhoneAuthCredential credential) async {
    try {
      // Link phone credential to existing user
      await widget.user.updatePhoneNumber(credential);

      setState(() {
        _isLoading = false;
      });

      _showSnackbar('Phone number verified successfully!');

      // Wait a moment then proceed
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        widget.onVerified();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed';
      });
      _showSnackbar('Verification failed: ${e.toString()}', isError: true);
    }
  }

  Future<void> _resendOTP() async {
    if (_isResending || _countdown > 0) return;

    setState(() {
      _isResending = true;
    });

    await _sendOTP();

    setState(() {
      _isResending = false;
    });
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final titleSize = (screenWidth * 0.07).clamp(24.0, 32.0);
    final subtitleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final bodySize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final otpBoxSize = (screenWidth * 0.12).clamp(45.0, 60.0);
    final spacing1 = (screenHeight * 0.03).clamp(20.0, 30.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 20.0);

    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text('Verify Phone Number', style: TextStyle(fontSize: subtitleSize.clamp(16.0, 20.0))),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all((screenWidth * 0.05).clamp(16.0, 24.0)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Phone icon
                    Container(
                      padding: EdgeInsets.all(spacing2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
                      ),
                      child: Icon(
                        Icons.phone_android,
                        size: (screenWidth * 0.15).clamp(50.0, 70.0),
                        color: Colors.cyanAccent,
                      ),
                    ),
                    SizedBox(height: spacing1),

                    // Title
                    Text(
                      'Enter Verification Code',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing2),

                    // Subtitle
                    Text(
                      'We sent a 6-digit code to',
                      style: TextStyle(fontSize: bodySize, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: (screenHeight * 0.01).clamp(6.0, 10.0)),
                    Text(
                      widget.phoneNumber,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing1),

                    // OTP Input boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        return Container(
                          width: otpBoxSize,
                          height: otpBoxSize,
                          margin: EdgeInsets.symmetric(horizontal: (screenWidth * 0.01).clamp(4.0, 8.0)),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _errorMessage != null
                                  ? Colors.red
                                  : _otpControllers[index].text.isNotEmpty
                                      ? Colors.cyanAccent
                                      : Colors.white30,
                              width: 2,
                            ),
                          ),
                          child: TextField(
                            controller: _otpControllers[index],
                            focusNode: _focusNodes[index],
                            enabled: !_isLoading,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: TextStyle(
                              fontSize: subtitleSize,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _errorMessage = null;
                              });

                              if (value.isNotEmpty && index < 5) {
                                _focusNodes[index + 1].requestFocus();
                              } else if (value.isEmpty && index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }

                              // Auto-verify when all 6 digits entered
                              if (index == 5 && value.isNotEmpty) {
                                _verifyOTP();
                              }
                            },
                          ),
                        );
                      }),
                    ),

                    if (_errorMessage != null) ...[
                      SizedBox(height: spacing2),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: bodySize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    SizedBox(height: spacing1),

                    // Verify button
                    if (_isLoading)
                      const CircularProgressIndicator(color: Colors.cyanAccent)
                    else
                      ElevatedButton(
                        onPressed: _verifyOTP,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(
                            horizontal: (screenWidth * 0.1).clamp(40.0, 60.0),
                            vertical: (screenHeight * 0.018).clamp(12.0, 18.0),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: subtitleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    SizedBox(height: spacing2),

                    // Resend OTP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Didn't receive the code? ",
                          style: TextStyle(fontSize: bodySize, color: Colors.white70),
                        ),
                        if (_countdown > 0)
                          Text(
                            'Resend in $_countdown s',
                            style: TextStyle(fontSize: bodySize, color: Colors.white54),
                          )
                        else
                          TextButton(
                            onPressed: _isResending ? null : _resendOTP,
                            child: Text(
                              _isResending ? 'Sending...' : 'Resend',
                              style: TextStyle(
                                fontSize: bodySize,
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
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
