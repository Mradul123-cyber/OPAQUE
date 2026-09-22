import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../widgets/opaque_design.dart';

enum SecurityPinMode {
  setup,
  change,
  disable,
  verify,
}

class SecurityPinScreen extends StatefulWidget {
  final SecurityPinMode mode;
  final VoidCallback? onSuccess;

  const SecurityPinScreen({
    super.key,
    required this.mode,
    this.onSuccess,
  });

  @override
  State<SecurityPinScreen> createState() => _SecurityPinScreenState();
}

class _SecurityPinScreenState extends State<SecurityPinScreen> {
  String _currentStep = 'enter'; // 'enter', 'confirm', 'verify_current', 'enter_new', 'confirm_new'
  String _enteredPin = '';
  String _firstPin = '';
  String _currentPin = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    switch (widget.mode) {
      case SecurityPinMode.setup:
        _currentStep = 'enter';
        break;
      case SecurityPinMode.change:
        _currentStep = 'verify_current';
        break;
      case SecurityPinMode.disable:
        _currentStep = 'verify_current';
        break;
      case SecurityPinMode.verify:
        _currentStep = 'enter';
        break;
    }
  }

  String get _titleText {
    switch (widget.mode) {
      case SecurityPinMode.setup:
        return _currentStep == 'confirm' ? 'Confirm your PIN' : 'Set up 6-Digit PIN';
      case SecurityPinMode.change:
        if (_currentStep == 'verify_current') return 'Enter Current PIN';
        if (_currentStep == 'confirm_new') return 'Confirm New PIN';
        return 'Enter New PIN';
      case SecurityPinMode.disable:
        return 'Turn Off 2FA';
      case SecurityPinMode.verify:
        return 'Two-Step Verification';
    }
  }

  String get _subtitleText {
    switch (widget.mode) {
      case SecurityPinMode.setup:
        return _currentStep == 'confirm'
            ? 'Re-enter your 6-digit PIN to confirm.'
            : 'Enter a 6-digit PIN. You will need it to register your account on a new phone.';
      case SecurityPinMode.change:
        if (_currentStep == 'verify_current') return 'Enter your current 6-digit PIN to continue.';
        if (_currentStep == 'confirm_new') return 'Re-enter your new PIN to confirm.';
        return 'Choose a new 6-digit PIN.';
      case SecurityPinMode.disable:
        return 'Enter your 6-digit PIN to disable Two-Step Verification.';
      case SecurityPinMode.verify:
        return 'Your account is protected with a Security PIN. Enter your 6-digit PIN to continue.';
    }
  }

  void _onDigitPressed(String digit) {
    if (_isLoading || _enteredPin.length >= 6) return;
    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 6) {
      _handlePinComplete();
    }
  }

  void _onBackspacePressed() {
    if (_isLoading || _enteredPin.isEmpty) return;
    setState(() {
      _errorMessage = null;
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _handlePinComplete() async {
    final pin = _enteredPin;

    if (widget.mode == SecurityPinMode.setup) {
      if (_currentStep == 'enter') {
        setState(() {
          _firstPin = pin;
          _enteredPin = '';
          _currentStep = 'confirm';
        });
      } else if (_currentStep == 'confirm') {
        if (pin != _firstPin) {
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _enteredPin = '';
            _currentStep = 'enter';
          });
          return;
        }
        await _savePinToBackend(enabled: true, newPin: pin);
      }
    } else if (widget.mode == SecurityPinMode.change) {
      if (_currentStep == 'verify_current') {
        setState(() {
          _currentPin = pin;
          _enteredPin = '';
          _currentStep = 'enter_new';
        });
      } else if (_currentStep == 'enter_new') {
        setState(() {
          _firstPin = pin;
          _enteredPin = '';
          _currentStep = 'confirm_new';
        });
      } else if (_currentStep == 'confirm_new') {
        if (pin != _firstPin) {
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _enteredPin = '';
            _currentStep = 'enter_new';
          });
          return;
        }
        await _savePinToBackend(enabled: true, newPin: pin, currentPin: _currentPin);
      }
    } else if (widget.mode == SecurityPinMode.disable) {
      await _savePinToBackend(enabled: false, currentPin: pin);
    } else if (widget.mode == SecurityPinMode.verify) {
      await _verifyPinWithBackend(pin);
    }
  }

  Future<void> _savePinToBackend({
    required bool enabled,
    String? newPin,
    String? currentPin,
  }) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      final body = <String, dynamic>{
        'enabled': enabled,
      };
      if (newPin != null) body['pin'] = newPin;
      if (currentPin != null) body['current_pin'] = currentPin;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/v1/auth/2fa/setup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (mounted) {
          widget.onSuccess?.call();
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? data['error'] ?? 'Failed to update PIN';
          _enteredPin = '';
          if (widget.mode == SecurityPinMode.change) {
            _currentStep = 'verify_current';
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please try again.';
        _enteredPin = '';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyPinWithBackend(String pin) async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/v1/auth/2fa/verify'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'pin': pin}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['valid'] == true) {
        if (mounted) {
          widget.onSuccess?.call();
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? data['error'] ?? 'Incorrect PIN';
          _enteredPin = '';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please try again.';
        _enteredPin = '';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.mode != SecurityPinMode.verify
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new, size: 18, color: c.ink),
                onPressed: () => Navigator.pop(context, false),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            // Lock icon badge
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.soft,
                border: Border.all(color: c.line, width: 1.5),
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 26,
                color: c.blue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _titleText,
              style: c.text(20, bold: true),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _subtitleText,
                style: c.text(12, muted: true).copyWith(height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),

            // 6 PIN dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? c.blue : Colors.transparent,
                    border: Border.all(
                      color: isFilled ? c.blue : c.line,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: c.text(12).copyWith(color: const Color(0xFFBF6974)),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            if (_isLoading) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.blue),
              ),
            ],

            const Spacer(flex: 2),

            // Numeric Keypad
            _buildKeypad(c),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(OpaqueColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['1', '2', '3'].map((d) => _buildKeypadButton(d, c)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['4', '5', '6'].map((d) => _buildKeypadButton(d, c)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['7', '8', '9'].map((d) => _buildKeypadButton(d, c)).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 68, height: 68),
              _buildKeypadButton('0', c),
              SizedBox(
                width: 68,
                height: 68,
                child: InkWell(
                  borderRadius: BorderRadius.circular(34),
                  onTap: _onBackspacePressed,
                  child: Center(
                    child: Icon(Icons.backspace_outlined, size: 22, color: c.ink),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String digit, OpaqueColors c) {
    return SizedBox(
      width: 68,
      height: 68,
      child: InkWell(
        borderRadius: BorderRadius.circular(34),
        onTap: () => _onDigitPressed(digit),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.soft,
            border: Border.all(color: c.line, width: 1),
          ),
          child: Center(
            child: Text(
              digit,
              style: c.text(22, bold: true),
            ),
          ),
        ),
      ),
    );
  }
}
