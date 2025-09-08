import 'dart:math';
import 'package:flutter/material.dart';

class Star {
  Offset position;
  double size;
  double opacity;
  double brightness;
  double flickerSpeed;
  Star(this.position, this.size, this.opacity, this.brightness, this.flickerSpeed);
}

class StarfieldPainter extends CustomPainter {
  final List<Star> stars;
  final double time;

  // We'll use two Paint objects: one for the core and one for the glow
  final Paint _starPaint = Paint()..color = Colors.white;
  final Paint _glowPaint = Paint()..color = Colors.white;

  StarfieldPainter({required this.stars, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final flicker = 0.5 + 0.5 * sin(time * star.flickerSpeed);
      final currentOpacity = star.opacity * flicker;

      // 1. Draw the soft glow first
      final glowRadius = star.size * 2 * star.brightness;
      if (glowRadius > 0) {
        _glowPaint.color = Colors.white.withOpacity(currentOpacity * 0.25); // Glow is faint
        _glowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
        canvas.drawCircle(star.position, star.size, _glowPaint);
      }

      // 2. Draw the bright, solid star core on top
      _starPaint.color = Colors.white.withOpacity(currentOpacity);
      canvas.drawCircle(star.position, star.size, _starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return oldDelegate.time != time; // Repaint on every frame for animation
  }
}