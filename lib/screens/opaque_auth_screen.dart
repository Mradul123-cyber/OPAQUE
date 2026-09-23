import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import 'security_pin_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../main.dart';
import '../services/google_auth_service.dart';
import '../services/opaque_auth_service.dart';
import '../services/contact_match_service.dart';
import '../widgets/opaque_auth_design.dart';

enum _Method { phone, email, google }

enum _Step { choose, details, verify, profile, contacts, resume }

class OpaqueAuthScreen extends StatefulWidget {
  const OpaqueAuthScreen({
    super.key,
    this.register = false,
    this.user,
    this.onComplete,
  });
  final bool register;
  final User? user;
  final VoidCallback? onComplete;
  @override
  State<OpaqueAuthScreen> createState() => _OpaqueAuthScreenState();
}

class _OpaqueAuthScreenState extends State<OpaqueAuthScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _username = TextEditingController();
  final _displayName = TextEditingController(),
      _code = TextEditingController(),
      _phoneController = TextEditingController();
  final _google = GoogleAuthService();
  _Method _method = _Method.phone;
  _Step _step = _Step.choose;
  ThemeMode _mode = ThemeMode.system;
  late bool _register;
  bool _busy = false,
      _obscure = true,
      _checking = false,
      _completingPhone = false,
      _emailSent = false,
      _profileCreated = false,
      _contactsPermissionPrompted = false;
  String _phone = '', _error = '', _countryIso = 'IN';
  String? _verificationId, _avatar, _registrationPassword, _pendingEmail;
  int? _resendToken;
  int _phoneAttempt = 0;
  DateTime? _resendAt;
  Timer? _tick, _emailPoll, _smsWatchdog;
  ConfirmationResult? _webConfirmation;
  User? get _user => FirebaseAuth.instance.currentUser;
  int get _remaining => _resendAt == null
      ? 0
      : (_resendAt!.difference(DateTime.now()).inSeconds + 1).clamp(0, 60);
  @override
  void initState() {
    super.initState();
    _register = widget.register;
    WidgetsBinding.instance.addObserver(this);
    _loadTheme();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _resendAt != null)
        setState(() {
          if (_remaining == 0) _resendAt = null;
        });
    });
    if (widget.user != null) {
      _step = _Step.resume;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _run(() => _routeAuthenticated(widget.user!)),
      );
    }
  }

  Future<void> _loadTheme() async {
    final value = (await SharedPreferences.getInstance()).getString(
      'opaque_auth_theme',
    );
    if (mounted)
      setState(
        () => _mode = value == 'light'
            ? ThemeMode.light
            : value == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system,
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _step == _Step.verify &&
        _method == _Method.email)
      _checkEmail(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _emailPoll?.cancel();
    _smsWatchdog?.cancel();
    _phoneAttempt++;
    for (final c in [
      _email,
      _password,
      _username,
      _displayName,
      _code,
      _phoneController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await action();
    } catch (e, st) {
      debugPrint('[AuthFlow] ❌ Exception in _run: $e');
      debugPrint('[AuthFlow] ❌ Stack trace: $st');
      if (mounted) setState(() => _error = OpaqueAuthService.errorMessage(e));
    } finally {
      if (mounted && !_completingPhone) setState(() => _busy = false);
    }
  }

  void _go(_Step step) {
    if (!mounted) return;
    debugPrint('[AuthFlow] 📍 _go -> $step (method: $_method, register: $_register, user: ${_user?.uid})');
    _emailPoll?.cancel();
    setState(() {
      _step = step;
      _error = '';
    });
    if (step == _Step.verify && _method == _Method.email)
      _emailPoll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkEmail(silent: true),
      );
    // System contacts permission belongs on this dedicated step only (not Home).
    if (step == _Step.contacts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _step != _Step.contacts) return;
        unawaited(_promptContactsPermissionOnStep());
      });
    }
  }

  Future<void> _promptContactsPermissionOnStep() async {
    if (_contactsPermissionPrompted) return;
    _contactsPermissionPrompted = true;
    await ContactMatchService.instance.requestPermissionForDedicatedSetup();
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    final user = _user;
    if (user == null || !mounted) return;
    _emailPoll?.cancel();
    try {
      await OpaqueAuthService.clearDraft(user);
    } catch (_) {
      /* A stale local draft cannot override an existing server profile. */
    }
    if (!mounted) return;

    // Check if 2FA (6-digit PIN) is enabled for this account
    try {
      final token = await user.getIdToken();
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/v1/auth/2fa/status'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['two_factor_enabled'] == true) {
          if (!mounted) return;
          final verified = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => SecurityPinScreen(
                mode: SecurityPinMode.verify,
                onSuccess: () => Navigator.of(context).pop(true),
              ),
            ),
          );
          if (verified != true) {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              setState(() {
                _busy = false;
                _error = 'Two-step verification required to sign in.';
              });
              _go(_Step.choose);
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[Auth] 2FA status check error: $e');
    }

    if (!mounted) return;
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
    OpaqueAuthService.interactive.value = false;
  }

  Future<void> _routeAuthenticated(User user) async {
    debugPrint('[AuthFlow] 🧭 _routeAuthenticated start. UID: ${user.uid}, email: "${user.email}", emailVerified: ${user.emailVerified}, providers: ${user.providerData.map((p) => p.providerId).toList()}');
    _go(_Step.resume);
    if (OpaqueAuthService.needsEmailVerification(user)) {
      debugPrint('[AuthFlow] 🧭 User needs email verification');
      _method = _Method.email;
      _email.text = user.email ?? '';
      _username.text = await OpaqueAuthService.pendingUsername(user) ?? '';
      _register = true;
      _go(_Step.verify);
      return;
    }
    final exists = await OpaqueAuthService.profileExists(user);
    debugPrint('[AuthFlow] 🧭 profileExists returned: $exists');
    if (exists) {
      if (user.photoURL != null && user.photoURL!.isNotEmpty) {
        unawaited(OpaqueAuthService.saveAvatar(user, user.photoURL!).catchError((_) {}));
      }
      await _continueToContactsOrFinish();
      return;
    }
    final pending = await OpaqueAuthService.pendingUsername(user);
    debugPrint('[AuthFlow] 🧭 pending username: "$pending"');
    _register = true;
    _method = user.providerData.any((p) => p.providerId == 'google.com')
        ? _Method.google
        : (user.phoneNumber ?? '').isNotEmpty
        ? _Method.phone
        : _Method.email;
    if (pending != null && pending.isNotEmpty) {
      _username.text = pending;
      debugPrint('[AuthFlow] 🧭 Routing to _Step.profile with username "$pending"');
      _go(_Step.profile);
    } else {
      if (_username.text.isEmpty) {
        final suggested = GoogleAuthService.generateUsernameFromEmail(
          user.email ?? user.displayName ?? '',
        );
        _username.text = suggested.length > 30
            ? suggested.substring(0, 30)
            : suggested;
        debugPrint('[AuthFlow] 🧭 Suggested username: "${_username.text}"');
      }
      debugPrint('[AuthFlow] 🧭 Routing to _Step.details');
      _go(_Step.details);
    }
  }

  Future<void> _select(_Method method) async {
    if (_busy) return;
    debugPrint('[AuthFlow] 🔘 _select method: $method, register: $_register');
    setState(() {
      _method = method;
      _error = '';
    });
    if (method == _Method.google)
      await _run(() async {
        debugPrint('[AuthFlow] 🔘 Google sign in initiated...');
        OpaqueAuthService.interactive.value = true;
        final result = await _google.signInWithGoogle();
        debugPrint('[AuthFlow] 🔘 Google sign in completed. user: ${result.user?.uid}, email: ${result.user?.email}');
        if (result.user != null && mounted) {
          if (_avatar == null && result.user!.photoURL != null && result.user!.photoURL!.isNotEmpty) {
            _avatar = result.user!.photoURL;
          }
          await _routeAuthenticated(result.user!);
        }
      });
    else
      _go(_Step.details);
  }

  String? _usernameValidator(String? value) =>
      RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Use 3–30 letters, numbers or underscores.';
  Future<void> _submitDetails() async {
    if (!(_form.currentState?.validate() ?? false)) {
      debugPrint('[AuthFlow] ⚠️ _submitDetails: form validation failed');
      return;
    }
    await _run(() async {
      final user = _user;
      debugPrint('[AuthFlow] 📝 _submitDetails called! method=$_method, register=$_register, email="${_email.text.trim()}", username="${_username.text.trim()}", existing currentUser=${user?.uid} (email: ${user?.email})');
      if (user != null) {
        debugPrint('[AuthFlow] 📝 currentUser already exists: ${user.uid}');
        if (OpaqueAuthService.needsEmailVerification(user)) {
          debugPrint('[AuthFlow] 📝 currentUser needs email verification');
          _go(_Step.verify);
          return;
        }
        await OpaqueAuthService.checkUsername(_username.text.trim());
        await OpaqueAuthService.saveUsername(user, _username.text.trim());
        _go(_Step.profile);
        return;
      }
      if (_register) {
        await OpaqueAuthService.checkUsername(_username.text.trim());
      }
      OpaqueAuthService.interactive.value = true;
      if (_method == _Method.phone) {
        await _sendPhone();
        return;
      }
      if (_register) {
        _registrationPassword = _password.text;
      }
      debugPrint('[AuthFlow] 🚀 Calling ${_register ? "createUserWithEmailAndPassword" : "signInWithEmailAndPassword"} for email="${_email.text.trim()}"');
      final credential = _register
          ? await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: _email.text.trim(),
              password: _password.text,
            )
          : await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: _email.text.trim(),
              password: _password.text,
            );
      _password.clear();
      debugPrint('[AuthFlow] ✅ Firebase Auth response: UID=${credential.user?.uid}, email="${credential.user?.email}", emailVerified=${credential.user?.emailVerified}');
      if (credential.user == null) throw StateError('Please sign in again.');
      if (_register) {
        await OpaqueAuthService.saveUsername(
          credential.user!,
          _username.text.trim(),
        );
        _go(_Step.verify);
        await _sendEmail();
      } else {
        await _routeAuthenticated(credential.user!);
      }
    });
  }

  Future<void> _sendPhone() async {
    final attempt = ++_phoneAttempt;
    _code.clear();
    if (kIsWeb) {
      _webConfirmation = await FirebaseAuth.instance.signInWithPhoneNumber(
        _phone,
      );
      if (!mounted || attempt != _phoneAttempt) return;
      setState(
        () => _resendAt = DateTime.now().add(const Duration(seconds: 60)),
      );
      _go(_Step.verify);
      return;
    }
    final sent = Completer<void>();
    void complete() {
      if (!sent.isCompleted) sent.complete();
    }

    _smsWatchdog?.cancel();
    _smsWatchdog = Timer(const Duration(seconds: 70), () {
      if (mounted && attempt == _phoneAttempt) {
        _phoneAttempt++;
        setState(
          () => _error = 'Phone verification timed out. Please try again.',
        );
      }
      complete();
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phone,
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (credential) async {
        if (!mounted || attempt != _phoneAttempt) return;
        _smsWatchdog?.cancel();
        complete();
        await _completePhone(credential);
      },
      verificationFailed: (error) {
        if (!mounted || attempt != _phoneAttempt) return;
        _smsWatchdog?.cancel();
        setState(() => _error = OpaqueAuthService.errorMessage(error));
        complete();
      },
      codeSent: (id, token) {
        if (!mounted || attempt != _phoneAttempt || _completingPhone) return;
        _smsWatchdog?.cancel();
        setState(() {
          _verificationId = id;
          _resendToken = token;
          _resendAt = DateTime.now().add(const Duration(seconds: 60));
        });
        _go(_Step.verify);
        complete();
      },
      codeAutoRetrievalTimeout: (id) {
        if (mounted && attempt == _phoneAttempt) _verificationId = id;
        complete();
      },
    );
    await sent.future;
  }

  Future<void> _completePhone(PhoneAuthCredential credential) async {
    if (_completingPhone || !mounted) return;
    _completingPhone = true;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      _phoneAttempt++;
      if (result.user == null) throw StateError('Please try signing in again.');
      if (_register && _username.text.trim().isNotEmpty)
        await OpaqueAuthService.saveUsername(
          result.user!,
          _username.text.trim(),
        );
      if (mounted) await _routeAuthenticated(result.user!);
    } catch (e) {
      if (mounted) setState(() => _error = OpaqueAuthService.errorMessage(e));
    } finally {
      _completingPhone = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!(_form.currentState?.validate() ?? false) || _busy) return;
    if (kIsWeb) {
      await _run(() async {
        if (_webConfirmation == null)
          throw StateError('Request a new verification code.');
        final result = await _webConfirmation!.confirm(_code.text.trim());
        if (result.user == null)
          throw StateError('Please try signing in again.');
        if (_register && _username.text.trim().isNotEmpty)
          await OpaqueAuthService.saveUsername(
            result.user!,
            _username.text.trim(),
          );
        if (mounted) await _routeAuthenticated(result.user!);
      });
    } else {
      if (_verificationId == null) {
        setState(() => _error = 'Request a new verification code.');
        return;
      }
      await _completePhone(
        PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: _code.text.trim(),
        ),
      );
    }
  }

  Future<void> _sendEmail() async {
    if (_remaining > 0) return;
    final user = _user;
    if (user == null) throw StateError('Please sign in again.');
    if (_pendingEmail != null) {
      await user.verifyBeforeUpdateEmail(_pendingEmail!);
    } else {
      await user.sendEmailVerification();
    }
    if (mounted)
      setState(() {
        _emailSent = true;
        _resendAt = DateTime.now().add(const Duration(seconds: 60));
      });
  }

  Future<void> _checkEmail({bool silent = false}) async {
    if (_checking || _busy || _step != _Step.verify || _method != _Method.email)
      return;
    _checking = true;
    debugPrint('[AuthFlow] ✉️ _checkEmail called (silent=$silent). Current user UID: ${_user?.uid}, email: "${_user?.email}", emailVerified: ${_user?.emailVerified}');
    try {
      await _user?.reload();
      if (!mounted || _step != _Step.verify) return;
      final user = _user;
      debugPrint('[AuthFlow] ✉️ After reload: UID: ${user?.uid}, emailVerified: ${user?.emailVerified}');
      if (user != null && user.emailVerified) {
        if (_pendingEmail != null) {
          _email.text = user.email ?? _pendingEmail!;
          _pendingEmail = null;
        }
        await user.getIdToken(true);
        debugPrint('[AuthFlow] ✉️ Email confirmed verified! Proceeding to _routeAuthenticated');
        await _run(() => _routeAuthenticated(user));
      } else if (!silent) {
        debugPrint('[AuthFlow] ✉️ Email not yet verified');
        setState(
          () => _error =
              'Your email is not verified yet. Open the link in your inbox, then try again.',
        );
      }
    } catch (e) {
      debugPrint('[AuthFlow] ❌ Exception in _checkEmail: $e');
      if (!silent && mounted)
        setState(() => _error = OpaqueAuthService.errorMessage(e));
    } finally {
      _checking = false;
    }
  }

  Future<void> _pickPhoto() async {
    await _run(() async {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (image == null || _user == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024)
        throw StateError('Choose a photo smaller than 10 MB.');
      final ref = FirebaseStorage.instance.ref(
        'avatars/${const Uuid().v4()}.jpg',
      );
      final uploaded = await ref.putData(
        bytes,
        SettableMetadata(
          contentType: image.mimeType ?? 'image/jpeg',
          cacheControl: 'public, max-age=31536000',
        ),
      );
      final url = await uploaded.ref.getDownloadURL();
      if (mounted) setState(() => _avatar = url);
    });
  }

  Future<void> _saveProfile({bool skip = false}) async {
    debugPrint('[AuthFlow] 🏁 _saveProfile called! skip=$skip, profileCreated=$_profileCreated, user UID=${_user?.uid}, email="${_user?.email}", emailVerified=${_user?.emailVerified}, username="${_username.text.trim()}", displayName="${_displayName.text.trim()}"');
    if (!skip && !(_form.currentState?.validate() ?? false)) {
      debugPrint('[AuthFlow] ⚠️ _saveProfile form validation failed');
      return;
    }
    await _run(() async {
      final user = _user;
      if (user == null) {
        debugPrint('[AuthFlow] ❌ _saveProfile: _user is null!');
        throw StateError('Please sign in again.');
      }
      try {
        if (!_profileCreated) {
          debugPrint('[AuthFlow] 🏁 Calling OpaqueAuthService.createProfile...');
          await OpaqueAuthService.createProfile(
            user,
            _username.text.trim(),
            skip ? '' : _displayName.text.trim(),
          );
          _profileCreated = true;
          debugPrint('[AuthFlow] 🏁 Profile creation flag set to true!');
        } else {
          debugPrint('[AuthFlow] ℹ️ _profileCreated was already true, skipping createProfile');
        }
        final avatarToSave = _avatar ?? user.photoURL;
        if (!skip && avatarToSave != null && avatarToSave.isNotEmpty) {
          debugPrint('[AuthFlow] 🏁 Saving avatar: $avatarToSave');
          await OpaqueAuthService.saveAvatar(user, avatarToSave);
        }
      } on AuthApiException catch (e) {
        debugPrint('[AuthFlow] ❌ Caught AuthApiException in _saveProfile: code="${e.code}", message="${e.message}"');
        if (e.code == 'username_taken' || e.code == 'invalid_username')
          _go(_Step.details);
        rethrow;
      }
      _registrationPassword = null;
      debugPrint('[AuthFlow] 🏁 _saveProfile success! Going to contacts setup...');
      if (!mounted) return;
      await _continueToContactsOrFinish();
    });
  }

  /// Dedicated contacts step (Allow / Skip) before entering the app.
  Future<void> _continueToContactsOrFinish() async {
    final contacts = ContactMatchService.instance;
    await contacts.loadCachedMatches();
    if (!mounted) return;
    if (contacts.needsDedicatedSetup) {
      _go(_Step.contacts);
    } else {
      await _finish();
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_user == null) {
      _phoneAttempt++;
      _resendToken = null;
      _email.clear();
      _password.clear();
      _username.clear();
      _displayName.clear();
      _go(_Step.choose);
      return;
    }

    if (_register && !_profileCreated) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => Theme(
          data: opaqueAuthTheme(_isDark),
          child: AlertDialog(
            title: const Text('Cancel registration?'),
            content: const Text(
              'If you cancel, your registration will be cancelled and your account will not be created. Any entered information will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Keep going'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Cancel registration'),
              ),
            ],
          ),
        ),
      );

      if (confirmed == true) {
        await _run(() async {
          final user = _user;
          if (user != null) {
            try {
              await OpaqueAuthService.clearDraft(user);
            } catch (e) {
              debugPrint('Error clearing draft: $e');
            }
            try {
              await user.delete();
            } catch (e) {
              debugPrint('Error deleting user during cancel: $e');
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
            }
          }
          _email.clear();
          _password.clear();
          _registrationPassword = null;
          _pendingEmail = null;
          _username.clear();
          _displayName.clear();
          _code.clear();
          _phoneController.clear();
          _avatar = null;
          _emailSent = false;
          _profileCreated = false;
          _phoneAttempt++;
          _verificationId = null;
          _resendToken = null;
          OpaqueAuthService.interactive.value = false;
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (_) => false,
          );
        });
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Theme(
        data: opaqueAuthTheme(_isDark),
        child: AlertDialog(
          title: const Text('Leave setup for now?'),
          content: const Text(
            'Your account is saved. Sign in again to finish setting up your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _run(() async {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
        OpaqueAuthService.interactive.value = false;
      });
    }
  }

  bool get _isDark =>
      _mode == ThemeMode.dark ||
      (_mode == ThemeMode.system &&
          MediaQuery.platformBrightnessOf(context) == Brightness.dark);
  Widget _heading(
    BuildContext context,
    String title,
    String subtitle, {
    String? kicker,
    IconData? symbol,
  }) {
    final c = AuthPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (symbol != null) ...[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(symbol, size: 24, color: c.ink),
          ),
          const SizedBox(height: 22),
        ],
        if (kicker != null) ...[
          Text(
            kicker,
            style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: c.muted),
          ),
          const SizedBox(height: 9),
        ],
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 29,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, height: 1.8, color: c.muted),
        ),
        const SizedBox(height: 27),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? hint,
    bool secret = false,
    bool optional = false,
    bool username = false,
    int? maxLength,
    TextInputType? keyboard,
  }) {
    final c = AuthPalette(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            enabled: !_busy,
            obscureText: secret && _obscure,
            maxLength: maxLength,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: !secret,
            cursorColor: c.typingColor,
            style: TextStyle(fontSize: 13, color: c.ink),
            autofillHints: secret
                ? [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ]
                : keyboard == TextInputType.emailAddress
                ? [AutofillHints.email]
                : username
                ? [AutofillHints.newUsername]
                : null,
            onChanged: secret ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              suffixIcon: secret
                  ? IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 17,
                        color: c.muted,
                      ),
                    )
                  : null,
            ),
            validator: (value) {
              if (username) return _usernameValidator(value);
              if (optional) return null;
              if ((value ?? '').isEmpty) return 'This field is required.';
              if (keyboard == TextInputType.emailAddress &&
                  !RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value!.trim()))
                return 'Enter a valid email address.';
              if (secret &&
                  _register &&
                  (value!.length < 8 ||
                      !RegExp(r'[A-Z]').hasMatch(value) ||
                      !RegExp(r'[a-z]').hasMatch(value) ||
                      !RegExp(r'[0-9]').hasMatch(value)))
                return 'Use 8+ characters with uppercase, lowercase and a number.';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _primary(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: FilledButton(
      onPressed: _busy ? null : action,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
  Widget _errorView(BuildContext context) => _error.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        height: 1.7,
        color: AuthPalette(context).muted,
      ),
    ),
  );
  Widget _choice(IconData icon, String text, _Method method) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton(
      onPressed: _busy ? null : () => _select(method),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 15),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
  List<Widget> _body(BuildContext context) {
    final c = AuthPalette(context);
    final authenticated = _user != null;
    if (_step == _Step.choose)
      return [
        _heading(
          context,
          _register
              ? 'Your conversations.\nYour way in.'
              : 'Good to have\nyou back.',
          _register
              ? 'Choose one way to create your account.'
              : 'Choose how you’d like to sign in.',
          kicker: 'WELCOME TO OPAQUE',
        ),
        const SizedBox(height: 7),
        _choice(
          Icons.phone_android_outlined,
          'Continue with phone',
          _Method.phone,
        ),
        _choice(
          Icons.mail_outline_rounded,
          'Continue with email',
          _Method.email,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: c.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'or',
                  style: TextStyle(fontSize: 10, color: c.muted),
                ),
              ),
              Expanded(child: Divider(color: c.line)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _select(_Method.google),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF252832),
            side: const BorderSide(color: Color(0xFFDADCE0)),
            minimumSize: const Size(double.infinity, 50),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: Row(
            children: [
              Image.asset('assets/google_logo.png', width: 19, height: 19),
              const SizedBox(width: 15),
              const Expanded(child: Text('Continue with Google')),
            ],
          ),
        ),
        _errorView(context),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        const SizedBox(height: 19),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _register ? 'Already have an account?' : 'New to Opaque?',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _error = '';
                    }),
              child: Text(_register ? 'Log in' : 'Create account'),
            ),
          ],
        ),
      ];
    if (_step == _Step.resume)
      return [
        _heading(
          context,
          'Getting things ready.',
          'Checking your account so you can continue where you left off.',
        ),
        if (_busy)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        _errorView(context),
        if (!_busy)
          _primary(
            'Try again',
            () => _run(() async {
              if (_user == null) {
                _go(_Step.choose);
              } else {
                await _routeAuthenticated(_user!);
              }
            }),
          ),
        if (!_busy && _user != null)
          Center(
            child: TextButton(onPressed: _leave, child: const Text('Sign out')),
          ),
      ];
    if (_step == _Step.details)
      return [
        _heading(
          context,
          authenticated
              ? 'Make your\nusername yours.'
              : _method == _Method.phone
              ? 'Start with\nyour number.'
              : _register
              ? 'Start with\nyour email.'
              : 'Welcome back.',
          authenticated
              ? 'Confirm your username or choose another before continuing.'
              : _method == _Method.phone
              ? 'We’ll send you a code to verify your number.'
              : _register
              ? 'Verify your email to start chatting securely.'
              : 'Enter your email and password to continue.',
          kicker: authenticated
              ? 'YOUR USERNAME'
              : _register
              ? 'CREATE YOUR ACCOUNT'
              : 'SIGN IN',
        ),
        if (authenticated && _method == _Method.google)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Image.asset('assets/google_logo.png', width: 19, height: 19),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    _user?.email ?? 'Google account connected',
                    style: TextStyle(fontSize: 12, color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        if (!authenticated && _method == _Method.phone) ...[
          const Text(
            'Phone number',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          IntlPhoneField(
            controller: _phoneController,
            enabled: !_busy,
            initialCountryCode: _countryIso,
            cursorColor: c.typingColor,
            style: TextStyle(fontSize: 13, color: c.ink),
            dropdownTextStyle: TextStyle(fontSize: 12, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Phone number',
              counterText: '',
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: c.typingColor, width: 1.5),
              ),
            ),
            onChanged: (phone) {
              _phone = phone.completeNumber;
              _resendToken = null;
            },
            onCountryChanged: (country) {
              _countryIso = country.code;
              _phone = '+${country.fullCountryCode}${_phoneController.text}';
              _resendToken = null;
            },
          ),
        ],
        if (!authenticated && _method == _Method.email) ...[
          _field(
            context,
            'Email address',
            _email,
            hint: 'you@example.com',
            keyboard: TextInputType.emailAddress,
          ),
          _field(
            context,
            'Password',
            _password,
            hint: _register
                ? 'Create a strong password'
                : 'Enter your password',
            secret: true,
          ),
          if (_register) ...[
            _strength(context),
            _hint(
              context,
              '8+ characters, with uppercase, lowercase and a number.',
            ),
          ],
        ],
        if (_register || authenticated) ...[
          _field(
            context,
            'Username',
            _username,
            hint: 'Choose your username',
            username: true,
            maxLength: 30,
          ),
          _hint(
            context,
            'Letters, numbers and underscores. Your username must be unique.',
          ),
        ],
        _errorView(context),
        _primary(
          authenticated
              ? 'Confirm username'
              : _method == _Method.phone
              ? 'Send verification code'
              : _register
              ? 'Create account'
              : 'Log in',
          _submitDetails,
        ),
      ];
    if (_step == _Step.verify && _method == _Method.phone)
      return [
        _heading(
          context,
          'Check your phone.',
          'Enter the six-digit code sent to\n$_phone',
          symbol: Icons.phone_android_outlined,
        ),
        const Text(
          'Verification code',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _code,
          enabled: !_busy,
          cursorColor: c.typingColor,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, letterSpacing: 10, color: c.ink),
          decoration: InputDecoration(
            hintText: '000000',
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: c.typingColor, width: 1.5),
            ),
          ),
          validator: (v) =>
              (v?.length ?? 0) == 6 ? null : 'Enter all six digits.',
        ),
        _errorView(context),
        _primary(
          _register ? 'Verify & continue' : 'Verify & log in',
          _verifyCode,
        ),
        Center(
          child: TextButton(
            onPressed: _busy || _remaining > 0 ? null : () => _run(_sendPhone),
            child: Text(
              _remaining > 0 ? 'Resend code in ${_remaining}s' : 'Resend code',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () {
                    _phoneAttempt++;
                    _verificationId = null;
                    _resendToken = null;
                    _go(_Step.details);
                  },
            child: const Text('Change phone number'),
          ),
        ),
      ];
    if (_step == _Step.verify)
      return [
        _heading(
          context,
          'Check your inbox.',
          'Open the verification link to confirm your email address.',
          symbol: Icons.mail_outline_rounded,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.soft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: c.line.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.dark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.mark_email_read_outlined,
                  size: 20,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pendingEmail != null
                          ? 'Verification link sent to (pending)'
                          : (_emailSent
                              ? 'Verification link sent to'
                              : 'Your email address'),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _pendingEmail ?? _user?.email ?? _email.text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy ? null : _changeEmail,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: c.ink,
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        _errorView(context),
        _primary('I’ve verified my email', () => _checkEmail()),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed:
                  _busy || _remaining > 0 ? null : () => _run(_sendEmail),
              icon: _remaining > 0
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.muted,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, size: 16, color: c.ink),
              label: Text(
                _remaining > 0
                    ? 'Resend email in ${_remaining}s'
                    : _emailSent
                    ? 'Resend verification email'
                    : 'Send verification email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _remaining > 0 ? c.muted : c.ink,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogCtx) => Theme(
                    data: opaqueAuthTheme(_isDark),
                    child: AlertDialog(
                      title: const Text('Can’t find the email?'),
                      content: const Text(
                        'Check your spam or junk folder, allow a few minutes for delivery, and check the address shown here. You can then resend the email.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: c.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Email not received?',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Text(
                '•',
                style: TextStyle(color: c.muted.withOpacity(0.4), fontSize: 12),
              ),
              TextButton(
                onPressed: _busy ? null : _leave,
                style: TextButton.styleFrom(
                  foregroundColor: c.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Cancel registration',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ];
    if (_step == _Step.contacts) return _contactsStep(context);
    return [
      _heading(
        context,
        'A little more you.',
        'Add a name and photo for your conversations.\nYou can always do this later.',
        kicker: 'OPTIONAL · MAKE IT PERSONAL',
      ),
      Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.soft,
                border: Border.all(color: c.ink, width: 1.5),
              ),
              child: _avatar == null
                  ? Icon(Icons.camera_alt_outlined, color: c.muted)
                  : ClipOval(
                      child: Image.network(
                        _avatar!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.person_outline, color: c.muted),
                      ),
                    ),
            ),
            Positioned(
              right: -4,
              bottom: -2,
              child: SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: 'Add profile photo',
                  onPressed: _busy ? null : _pickPhoto,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: c.ink,
                    foregroundColor: c.background,
                    side: BorderSide(color: c.background, width: 3),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),
      Center(
        child: Text(
          '@${_username.text}',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ),
      if (_avatar != null)
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _avatar = null),
            child: const Text('Remove photo'),
          ),
        ),
      _field(
        context,
        'Display name (optional)',
        _displayName,
        hint: 'What should friends call you?',
        optional: true,
        maxLength: 50,
      ),
      _hint(context, 'Your username is used when no display name is added.'),
      _errorView(context),
      if (_profileCreated && _error.isNotEmpty)
        _hint(
          context,
          'Your account is ready. Retry saving the photo or skip it below.',
        ),
      _primary('Continue', () => _saveProfile()),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => _saveProfile(skip: true),
          child: const Text('Skip for now'),
        ),
      ),
    ];
  }

  List<Widget> _contactsStep(BuildContext context) {
    final c = AuthPalette(context);
    final contacts = ContactMatchService.instance;
    return [
      _heading(
        context,
        'Find people you know',
        'Opaque will ask for contacts access so it can show friends already on the app in your chat list.\nNumbers are checked privately and never uploaded as a raw list.',
        kicker: 'OPTIONAL · CONTACTS',
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What we use contacts for',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Show a few people from your phone who are already on Opaque, and let you search contacts later.',
              style: TextStyle(fontSize: 12, height: 1.55, color: c.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _errorView(context),
      if (_contactsPermissionPrompted && contacts.permissionDenied)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Contacts access was not granted. You can continue and enable it later in Friends.',
            style: TextStyle(fontSize: 12, height: 1.45, color: c.muted),
          ),
        ),
      if (_busy)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Syncing contacts…',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      _primary(
        'Continue',
        () => _run(() async {
          if (!_contactsPermissionPrompted) {
            await _promptContactsPermissionOnStep();
          }
          if (!ContactMatchService.instance.permissionDenied) {
            await ContactMatchService.instance.prepareFromDedicatedSetupStep();
          } else {
            await ContactMatchService.instance.skipContactsSetup();
          }
          if (!mounted) return;
          await _finish();
        }),
      ),
      Center(
        child: TextButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await ContactMatchService.instance.skipContactsSetup();
                    await _finish();
                  }),
          child: const Text('Skip for now'),
        ),
      ),
    ];
  }

  Widget _strength(BuildContext context) {
    final c = AuthPalette(context);
    final value = _password.text;
    final score = [
      value.length >= 8,
      RegExp(r'[A-Z]').hasMatch(value),
      RegExp(r'[a-z]').hasMatch(value),
      RegExp(r'[0-9]').hasMatch(value),
    ].where((v) => v).length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
              decoration: BoxDecoration(
                color: i < score
                    ? (c.dark
                          ? const Color(0xFF9BBBA6)
                          : const Color(0xFF507864))
                    : c.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeEmail() async {
    final currentEmail = _pendingEmail ?? _user?.email ?? _email.text;
    final controller = TextEditingController(text: currentEmail);
    controller.selection = TextSelection.collapsed(offset: currentEmail.length);

    final focusNode = FocusNode();
    bool initialSelectPrevented = false;
    void collapseSelection() {
      if (!initialSelectPrevented &&
          controller.text.isNotEmpty &&
          controller.selection.baseOffset == 0 &&
          controller.selection.extentOffset == controller.text.length) {
        initialSelectPrevented = true;
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      }
    }
    controller.addListener(collapseSelection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode.requestFocus();
    });

    final address = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => Theme(
        data: opaqueAuthTheme(_isDark),
        child: AlertDialog(
          title: const Text('Change email address'),
          content: SingleChildScrollView(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'you@example.com'),
              onTap: () {
                if (!controller.selection.isCollapsed) {
                  controller.selection = TextSelection.collapsed(
                    offset: controller.selection.extentOffset,
                  );
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(controller.text.trim()),
              child: const Text('Send link'),
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      controller.removeListener(collapseSelection);
      controller.dispose();
      focusNode.dispose();
    });
    if (address == null || !mounted) return;

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    if (address.toLowerCase() == currentEmail.toLowerCase()) {
      setState(() => _error = 'That is already your current email address.');
      return;
    }

    await _run(() async {
      final user = _user;
      if (user == null) throw StateError('Please sign in again.');

      final pwd = _registrationPassword ??
          (_password.text.isNotEmpty ? _password.text : null);

      if (_register && !_profileCreated && pwd != null) {
        final username = _username.text.trim().isNotEmpty
            ? _username.text.trim()
            : (await OpaqueAuthService.pendingUsername(user) ?? '');

        // 1. Clear draft and delete the previous unverified user
        try {
          await OpaqueAuthService.clearDraft(user);
        } catch (e) {
          debugPrint('Error clearing draft: $e');
        }
        try {
          await user.delete();
        } catch (e) {
          debugPrint('Error deleting previous user: $e');
        }

        // 2. Register the new user with the new email in Firebase
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: address, password: pwd);
        final newUser = credential.user;
        if (newUser == null) throw StateError('Could not register with new email.');

        // 3. Save pending username for new user
        if (username.isNotEmpty) {
          await OpaqueAuthService.saveUsername(newUser, username);
        }

        // 4. Send verification email to the new address
        await newUser.sendEmailVerification();

        if (mounted) {
          setState(() {
            _email.text = address;
            _pendingEmail = null;
            _emailSent = true;
            _resendAt = DateTime.now().add(const Duration(seconds: 60));
            _error = 'Verification link sent to $address.';
          });
        }
        return;
      }

      // Fallback for already existing accounts
      await user.verifyBeforeUpdateEmail(address);
      if (mounted) {
        setState(() {
          _pendingEmail = address;
          _emailSent = true;
          _resendAt = DateTime.now().add(const Duration(seconds: 60));
          _error = 'Verification link sent to $address.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: opaqueAuthTheme(_isDark),
      child: Builder(
        builder: (context) {
          final c = AuthPalette(context);
          final steps = _method == _Method.google
              ? [_Step.details, _Step.profile, _Step.contacts]
              : [_Step.details, _Step.verify, _Step.profile, _Step.contacts];
          return PopScope(
            canPop: _step == _Step.choose && !_busy && _user == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && !_busy) {
                if (_step == _Step.verify &&
                    _method == _Method.phone &&
                    _user == null) {
                  _phoneAttempt++;
                  _go(_Step.details);
                } else {
                  _leave();
                }
              }
            },
            child: Scaffold(
              backgroundColor: c.background,
              appBar: AppBar(
                backgroundColor: c.background,
                foregroundColor: c.ink,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                toolbarHeight: 70,
                centerTitle: true,
                automaticallyImplyLeading: false,
                title: const AuthWordmark(),
                leading: _step == _Step.choose
                    ? null
                    : IconButton(
                        tooltip: (_register && !_profileCreated)
                            ? 'Cancel registration'
                            : (_user == null ? 'Back' : 'Leave setup'),
                        onPressed: _busy ? null : _leave,
                        icon: Icon(
                          _user == null
                              ? Icons.arrow_back_rounded
                              : Icons.close_rounded,
                          size: 20,
                        ),
                      ),
                actions: [
                  PopupMenuButton<ThemeMode>(
                    tooltip: 'Appearance',
                    initialValue: _mode,
                    icon: Icon(
                      Icons.brightness_6_outlined,
                      size: 19,
                      color: c.muted,
                    ),
                    onSelected: (mode) async {
                      setState(() => _mode = mode);
                      await (await SharedPreferences.getInstance()).setString(
                        'opaque_auth_theme',
                        mode.name,
                      );
                    },
                    itemBuilder: (_) => ThemeMode.values
                        .map(
                          (mode) => CheckedPopupMenuItem<ThemeMode>(
                            value: mode,
                            checked: _mode == mode,
                            child: Text(
                              mode == ThemeMode.system
                                  ? 'System'
                                  : mode == ThemeMode.light
                                  ? 'Light'
                                  : 'Dark',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            key: ValueKey(_step),
                            padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
                            child: AutofillGroup(
                              child: Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (_register && steps.contains(_step))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 28,
                                        ),
                                        child: Row(
                                          children: List.generate(
                                            steps.length,
                                            (i) => Expanded(
                                              child: Container(
                                                height: 3,
                                                margin: EdgeInsets.only(
                                                  right: i == steps.length - 1
                                                      ? 0
                                                      : 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                  color:
                                                      i <= steps.indexOf(_step)
                                                      ? c.ink
                                                      : c.line,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ..._body(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (MediaQuery.viewInsetsOf(context).bottom == 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 12,
                                  color: c.muted,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'A private place for your conversations.',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: c.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
