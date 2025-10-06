// lib/profile_background.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui';

class ProfileBackground extends StatefulWidget {
  final Widget child;
  const ProfileBackground({super.key, required this.child});

  @override
  State<ProfileBackground> createState() => _ProfileBackgroundState();
}

class _ProfileBackgroundState extends State<ProfileBackground> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _auroraAnimation;

  late List<FrostParticle> _frostParticles;

  final Random _random = Random();
  StreamSubscription? _gyroscopeSubscription;
  Offset _parallaxOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    // A single controller to drive all animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Specific animation for the aurora's slow pulse
    _auroraAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true),
        curve: Curves.easeInOut,
      ),
    );

    _frostParticles = [];

    if (!kIsWeb) {
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        if (mounted) {
          setState(() {
            _parallaxOffset = Offset(-event.y * 25, -event.x * 25);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  void _onHover(PointerEvent details, Size size) {
    if (kIsWeb) {
      final screenCenter = Offset(size.width / 2, size.height / 2);
      final mousePosition = details.localPosition;
      final newOffset = Offset(
        (screenCenter.dx - mousePosition.dx) * 0.1,
        (screenCenter.dy - mousePosition.dy) * 0.1,
      );
      if ((newOffset - _parallaxOffset).distance > 1) {
        setState(() => _parallaxOffset = newOffset);
      }
    }
  }

  void _handleInteraction(Offset position) {
    if (mounted) {
      // Create a burst of frost
      for (int i = 0; i < 15; i++) {
        _frostParticles.add(FrostParticle(position: position, random: _random));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return MouseRegion(
      onHover: (event) => _onHover(event, size),
      child: GestureDetector(
        onPanDown: (details) => _handleInteraction(details.localPosition),
        onTapDown: (details) => _handleInteraction(details.localPosition),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            // Update frost particles only
            for (var frost in _frostParticles) {
              frost.update();
            }
            _frostParticles.removeWhere((p) => p.isDone);

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xff000c29), Color(0xff1c2541), Color(0xff0a1128)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  CustomPaint(
                    size: size,
                    painter: ArcticAuroraPainter(
                      frostParticles: _frostParticles,
                      auroraAnimation: _auroraAnimation,
                      parallaxOffset: _parallaxOffset,
                    ),
                  ),
                  widget.child,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ArcticAuroraPainter extends CustomPainter {
  final List<FrostParticle> frostParticles;
  final Animation<double> auroraAnimation;
  final Offset parallaxOffset;

  ArcticAuroraPainter({
    required this.frostParticles,
    required this.auroraAnimation,
    required this.parallaxOffset,
  }) : super(repaint: auroraAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // Layer 1: Pulsing Aurora
    final auroraPaint = Paint();
    final rect = Rect.fromLTWH(-size.width * 0.5, 0, size.width * 2, size.height * 0.6);
    final center = Offset(size.width * 0.5 + (auroraAnimation.value * size.width * 0.2 - size.width * 0.1), size.height * 0.2);

    auroraPaint.shader = RadialGradient(
      center: Alignment.topCenter,
      radius: 1.5,
      colors: [
        const Color(0x8800ff99), // Bright Teal
        const Color(0x6600ddff), // Bright Cyan
        const Color(0x006633ff), // Transparent Purple
      ],
      stops: [0.0, 0.5 + (auroraAnimation.value * 0.2), 1.0],
    ).createShader(rect);
    auroraPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(center, size.width, auroraPaint);

    // Layer 2: Interactive Frost
    final frostPaint = Paint()..color = Colors.white;
    for (var particle in frostParticles) {
      final progress = particle.life / particle.maxLife;
      final opacity = sin(progress * pi); // Fade in and out
      frostPaint.color = Colors.white.withOpacity(opacity * 0.7);
      canvas.drawCircle(particle.position, particle.radius * (1 - progress), frostPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ArcticAuroraPainter oldDelegate) => true;
}

// Data Models
class FrostParticle {
  Offset position;
  Offset velocity;
  double radius;
  double life = 0;
  final double maxLife;

  FrostParticle({required this.position, required Random random})
      : velocity = Offset.fromDirection(random.nextDouble() * 2 * pi, random.nextDouble() * 0.5),
        radius = random.nextDouble() * 1.2 + 0.8,
        maxLife = random.nextDouble() * 40 + 30;

  bool get isDone => life >= maxLife;

  void update() {
    life++;
    position += velocity;
    velocity *= 0.92; // Damping
  }
}
