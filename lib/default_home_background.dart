// lib/default_home_background.dart
import 'package:flutter/material.dart';

/// Simple, clean white background like WhatsApp
class DefaultHomeBackground extends StatelessWidget {
  final Widget child;

  const DefaultHomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white, // Pure white like WhatsApp
      child: child,
    );
  }
}
