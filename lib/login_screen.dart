import 'package:flutter/material.dart';
import 'screens/opaque_auth_screen.dart';

/// Entry auth screen. Contacts setup is a dedicated step inside OpaqueAuthScreen.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const OpaqueAuthScreen();
}
