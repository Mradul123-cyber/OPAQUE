import 'package:flutter/material.dart';
import 'screens/opaque_auth_screen.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});
  @override
  Widget build(BuildContext context) => const OpaqueAuthScreen(register: true);
}
