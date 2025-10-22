import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Continuous magic particle animation for AI processing
class AIProcessingParticles extends StatefulWidget {
  final bool isProcessing;
  final Color color;

  const AIProcessingParticles({
    super.key,
    required this.isProcessing,
    this.color = const Color(0xFF667EEA),
  });

  @override
  State<AIProcessingParticles> createState() => _AIProcessingParticlesState();
}

class _AIProcessingParticlesState extends State<AIProcessingParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<MagicParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Create particles
    _generateParticles();
  }

  void _generateParticles() {
    _particles.clear();
    // Create 12 particles in a circular pattern
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * math.pi;
      _particles.add(MagicParticle(
        angle: angle,
        radius: 15.0 + _random.nextDouble() * 10,
        size: 3.0 + _random.nextDouble() * 3,
        speed: 0.8 + _random.nextDouble() * 0.4,
        delay: _random.nextDouble() * 0.5,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isProcessing) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(50, 50),
          painter: MagicParticlePainter(
            particles: _particles,
            progress: _controller.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class MagicParticle {
  final double angle;
  final double radius;
  final double size;
  final double speed;
  final double delay;

  MagicParticle({
    required this.angle,
    required this.radius,
    required this.size,
    required this.speed,
    required this.delay,
  });
}

class MagicParticlePainter extends CustomPainter {
  final List<MagicParticle> particles;
  final double progress;
  final Color color;

  MagicParticlePainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final particle in particles) {
      // Calculate particle progress with delay
      final particleProgress = ((progress - particle.delay) * particle.speed) % 1.0;

      // Fade in and out smoothly
      double opacity;
      if (particleProgress < 0.3) {
        opacity = particleProgress / 0.3;
      } else if (particleProgress > 0.7) {
        opacity = 1 - ((particleProgress - 0.7) / 0.3);
      } else {
        opacity = 1.0;
      }

      // Calculate position in circular motion
      final distance = particle.radius * particleProgress;
      final x = center.dx + math.cos(particle.angle) * distance;
      final y = center.dy + math.sin(particle.angle) * distance;

      // Draw sparkle
      final paint = Paint()
        ..color = color.withOpacity(opacity * 0.8)
        ..style = PaintingStyle.fill;

      // Draw star shape for magical effect
      _drawStar(canvas, Offset(x, y), particle.size, paint, progress * 2 * math.pi);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size, Paint paint, double rotation) {
    const numPoints = 4;
    final path = Path();

    for (int i = 0; i < numPoints * 2; i++) {
      final angle = (i * math.pi / numPoints) + rotation;
      final radius = (i.isEven ? size : size / 2);
      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MagicParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
