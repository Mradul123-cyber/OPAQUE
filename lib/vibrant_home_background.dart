// lib/vibrant_home_background.dart
import 'package:flutter/material.dart';

class VibrantHomeBackground extends StatelessWidget {
  final Widget child;
  const VibrantHomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3a0ca3), // Cosmic Purple
            Color(0xFF4cc9f0), // Cyan
            Color(0xFF7209b7), // Another Purple
          ],
        ),
      ),
      child: child,
    );
  }
}
