// lib/dark_home_background.dart
import 'package:flutter/material.dart';

/// Simple solid dark mode background like standard apps
class DarkHomeBackground extends StatelessWidget {
  final Widget child;

  const DarkHomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212), // Standard dark mode background (Material Design)
      child: child,
    );
  }
}
