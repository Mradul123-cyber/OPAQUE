import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Widget that shows encryption/decryption animation with crossed chains
class EncryptionAnimationWidget extends StatefulWidget {
  final Widget child;
  final bool isDecrypting; // true for receiver, false for sender
  final VoidCallback? onAnimationComplete;

  const EncryptionAnimationWidget({
    Key? key,
    required this.child,
    required this.isDecrypting,
    this.onAnimationComplete,
  }) : super(key: key);

  @override
  State<EncryptionAnimationWidget> createState() => _EncryptionAnimationWidgetState();
}

class _EncryptionAnimationWidgetState extends State<EncryptionAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _chainController;
  late AnimationController _glowController;
  late AnimationController _particleController;
  late Animation<double> _chainAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _blurAnimation;
  late Animation<double> _particleAnimation;

  final List<Particle> _particles = [];
  bool _animationCompleted = false;

  @override
  void initState() {
    super.initState();

    // Chain movement animation
    _chainController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Glow effect animation
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Particle burst animation
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    if (widget.isDecrypting) {
      // Receiver: chains break and blur fades
      _chainAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _chainController, curve: Curves.easeInOut),
      );
      _blurAnimation = Tween<double>(begin: 8.0, end: 0.0).animate(
        CurvedAnimation(parent: _chainController, curve: Curves.easeOut),
      );
    } else {
      // Sender: chains appear
      _chainAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _chainController, curve: Curves.easeInOut),
      );
      _blurAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(_chainController);
    }

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _particleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _particleController, curve: Curves.easeOut),
    );

    _chainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.isDecrypting) {
          _generateParticles();
          _particleController.forward();
        }
        setState(() {
          _animationCompleted = true;
        });
        widget.onAnimationComplete?.call();
      }
    });

    // Start animations
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _chainController.forward();
        _glowController.repeat(reverse: true);
      }
    });
  }

  void _generateParticles() {
    final random = math.Random();
    for (int i = 0; i < 15; i++) {
      _particles.add(Particle(
        x: 0.5 + (random.nextDouble() - 0.5) * 0.2,
        y: 0.5 + (random.nextDouble() - 0.5) * 0.2,
        vx: (random.nextDouble() - 0.5) * 0.015,
        vy: (random.nextDouble() - 0.5) * 0.015,
        size: random.nextDouble() * 4 + 2,
      ));
    }
  }

  @override
  void dispose() {
    _chainController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_chainController, _glowController, _particleController]),
      builder: (context, child) {
        return Stack(
          children: [
            // Blurred content (for receiver)
            if (widget.isDecrypting && !_animationCompleted)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: _blurAnimation.value,
                    sigmaY: _blurAnimation.value,
                  ),
                  child: widget.child,
                ),
              )
            else
              widget.child,

            // Chain overlay
            if (!_animationCompleted || _chainAnimation.value > 0)
              Positioned.fill(
                child: CustomPaint(
                  painter: ChainPainter(
                    progress: _chainAnimation.value,
                    glowIntensity: _glowAnimation.value,
                    isDecrypting: widget.isDecrypting,
                  ),
                ),
              ),

            // Particle effects (for receiver)
            if (widget.isDecrypting && _particles.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: ParticlePainter(
                    particles: _particles,
                    progress: _particleAnimation.value,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Custom painter for crossed chains
class ChainPainter extends CustomPainter {
  final double progress;
  final double glowIntensity;
  final bool isDecrypting;

  ChainPainter({
    required this.progress,
    required this.glowIntensity,
    required this.isDecrypting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Chain paint
    final chainPaint = Paint()
      ..color = Color.lerp(
        const Color(0xFFB0B0B0), // Grey
        const Color(0xFF00A8FF), // Blue
        glowIntensity,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Glow paint
    final glowPaint = Paint()
      ..color = const Color(0xFF00A8FF).withOpacity(glowIntensity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Draw two crossed chains
    final chain1Start = Offset(
      centerX - size.width * 0.3 * progress,
      centerY - size.height * 0.3 * progress,
    );
    final chain1End = Offset(
      centerX + size.width * 0.3 * progress,
      centerY + size.height * 0.3 * progress,
    );

    final chain2Start = Offset(
      centerX + size.width * 0.3 * progress,
      centerY - size.height * 0.3 * progress,
    );
    final chain2End = Offset(
      centerX - size.width * 0.3 * progress,
      centerY + size.height * 0.3 * progress,
    );

    // Draw glow first
    if (glowIntensity > 0.3) {
      _drawChainLinks(canvas, chain1Start, chain1End, glowPaint, size);
      _drawChainLinks(canvas, chain2Start, chain2End, glowPaint, size);
    }

    // Draw chains
    _drawChainLinks(canvas, chain1Start, chain1End, chainPaint, size);
    _drawChainLinks(canvas, chain2Start, chain2End, chainPaint, size);
  }

  void _drawChainLinks(Canvas canvas, Offset start, Offset end, Paint paint, Size size) {
    final linkCount = 4;
    final dx = (end.dx - start.dx) / linkCount;
    final dy = (end.dy - start.dy) / linkCount;

    for (int i = 0; i < linkCount; i++) {
      final x1 = start.dx + dx * i;
      final y1 = start.dy + dy * i;
      final x2 = start.dx + dx * (i + 0.8);
      final y2 = start.dy + dy * (i + 0.8);

      // Draw oval chain link
      final rect = Rect.fromPoints(
        Offset(x1 - 8, y1 - 4),
        Offset(x1 + 8, y1 + 4),
      );
      canvas.drawOval(rect, paint);
    }
  }

  @override
  bool shouldRepaint(ChainPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}

/// Particle class for burst effect
class Particle {
  double x, y; // Position (0-1 normalized)
  double vx, vy; // Velocity
  double size;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
  });
}

/// Custom painter for particle burst
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  ParticlePainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00A8FF).withOpacity((1 - progress) * 0.8)
      ..style = PaintingStyle.fill;

    for (final particle in particles) {
      final x = (particle.x + particle.vx * progress * 50) * size.width;
      final y = (particle.y + particle.vy * progress * 50) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        particle.size * (1 - progress * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
