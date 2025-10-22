import 'package:flutter/material.dart';
import 'dart:math' as math;

class ParticleAnimationWidget extends StatefulWidget {
  final Widget child;
  final bool isRemoving;
  final VoidCallback? onAnimationComplete;

  const ParticleAnimationWidget({
    super.key,
    required this.child,
    required this.isRemoving,
    this.onAnimationComplete,
  });

  @override
  State<ParticleAnimationWidget> createState() => _ParticleAnimationWidgetState();
}

class _ParticleAnimationWidgetState extends State<ParticleAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _scaleController;
  final List<Particle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Main animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Scale animation controller for smooth shrinking
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(ParticleAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRemoving && !oldWidget.isRemoving) {
      _startTelegramStyleAnimation();
    }
  }

  void _startTelegramStyleAnimation() {
    // Create more particles for smoother effect (Telegram uses ~40-50)
    _particles.clear();
    for (int i = 0; i < 50; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = _random.nextDouble() * 2.5 + 1.5;

      _particles.add(Particle(
        startX: 0.5, // Start from center
        startY: 0.5,
        velocityX: math.cos(angle) * speed,
        velocityY: math.sin(angle) * speed,
        size: _random.nextDouble() * 4 + 3,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 4,
      ));
    }

    // Start both animations
    _scaleController.forward(from: 0);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRemoving) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _scaleController]),
      builder: (context, child) {
        // Easing function for smooth animation (similar to Telegram)
        final easeOut = Curves.easeOutCubic.transform(_controller.value);
        final scale = 1.0 - Curves.easeInCubic.transform(_scaleController.value);

        return Stack(
          children: [
            // Shrinking and fading original widget
            Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: (1 - _controller.value * 1.2).clamp(0.0, 1.0),
                child: widget.child,
              ),
            ),
            // Particles explosion
            Positioned.fill(
              child: CustomPaint(
                painter: TelegramParticlePainter(
                  particles: _particles,
                  progress: easeOut,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class Particle {
  final double startX;
  final double startY;
  final double velocityX;
  final double velocityY;
  final double size;
  final double rotation;
  final double rotationSpeed;

  Particle({
    required this.startX,
    required this.startY,
    required this.velocityX,
    required this.velocityY,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class TelegramParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  TelegramParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      // Calculate position with acceleration (particles slow down over time)
      final deceleration = 1.0 - (progress * 0.3);
      final distance = progress * deceleration;

      final x = (particle.startX * size.width) +
                (particle.velocityX * distance * size.width * 0.15);
      final y = (particle.startY * size.height) +
                (particle.velocityY * distance * size.height * 0.15);

      // Fade out with smoother curve
      final opacity = (1 - progress * progress).clamp(0.0, 1.0);

      // Size reduction over time
      final currentSize = particle.size * (1 - progress * 0.4);

      // Rotation animation
      final currentRotation = particle.rotation + (particle.rotationSpeed * progress);

      final paint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.9)
        ..style = PaintingStyle.fill;

      // Draw rounded rectangles (like Telegram) instead of circles
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(currentRotation);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: currentSize * 1.5,
          height: currentSize,
        ),
        Radius.circular(currentSize * 0.5),
      );

      canvas.drawRRect(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(TelegramParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
