// lib/home_background.dart
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

// Main widget for the background
class HomeBackground extends StatefulWidget {
  final Widget child;
  const HomeBackground({super.key, required this.child});

  @override
  State<HomeBackground> createState() => _HomeBackgroundState();
}

class _HomeBackgroundState extends State<HomeBackground> with TickerProviderStateMixin {
  late AnimationController _nebulaController;
  late AnimationController _starController;
  
  late List<Star> _stars;
  late List<ShootingStar> _shootingStars;
  
  final Random _random = Random();
  StreamSubscription? _gyroscopeSubscription;
  Offset _parallaxOffset = Offset.zero;
  Offset? _gravityWellPosition;

  late Timer _shootingStarTimer;

  @override
  void initState() {
    super.initState();
    // Controller for the slow nebula swirl
    _nebulaController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();

    // Controller for the main animation loop (stars, etc.)
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1000), // Effectively infinite
    )..repeat();

    // Initialize all visual elements
    _stars = List.generate(200, (index) => _createStar());
    _shootingStars = [];

    // Platform-specific parallax input
    if (!kIsWeb) {
      _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
        if (mounted) {
          setState(() {
            _parallaxOffset = Offset(-event.y * 20, -event.x * 20);
          });
        }
      });
    }

    // Timer to spawn shooting stars
    _shootingStarTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (mounted && _shootingStars.length < 3) {
        setState(() {
          _shootingStars.add(ShootingStar(random: _random));
        });
      }
    });
  }

  Star _createStar() {
    return Star(
      position: Offset(_random.nextDouble(), _random.nextDouble()),
      radius: _random.nextDouble() * 1.2 + 0.3,
      color: Colors.white.withOpacity(_random.nextDouble() * 0.7 + 0.3),
      depth: _random.nextDouble() * 0.6 + 0.1, // Depth from 0.1 (far) to 0.7 (near)
    );
  }

  @override
  void dispose() {
    _nebulaController.dispose();
    _starController.dispose();
    _gyroscopeSubscription?.cancel();
    _shootingStarTimer.cancel();
    super.dispose();
  }

  // --- Interaction Handlers ---
  void _onPanStart(DragStartDetails details) {
    setState(() {
      _gravityWellPosition = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _gravityWellPosition = details.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _gravityWellPosition = null;
    });
  }

  void _onHover(PointerEvent details, Size size) {
    if (kIsWeb) {
      final screenCenter = Offset(size.width / 2, size.height / 2);
      final mousePosition = details.localPosition;
      final newOffset = Offset(
        (screenCenter.dx - mousePosition.dx) * 0.1,
        (screenCenter.dy - mousePosition.dy) * 0.1,
      );
      setState(() {
        _parallaxOffset = newOffset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return MouseRegion(
      onHover: (event) => _onHover(event, size),
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTapDown: (details) => _onPanStart(DragStartDetails(globalPosition: details.globalPosition, localPosition: details.localPosition)),
        onTapUp: (details) => _onPanEnd(DragEndDetails()),
        child: Container(
          color: const Color(0xFF000411), // Deep space color
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_nebulaController, _starController]),
                builder: (context, child) {
                  // Update shooting star positions
                  for (var star in _shootingStars) {
                    star.update();
                  }
                  _shootingStars.removeWhere((star) => star.isOffScreen(size));

                  return CustomPaint(
                    size: size,
                    painter: NebulaPainter(
                      nebulaAnimation: _nebulaController.value,
                      stars: _stars,
                      shootingStars: _shootingStars,
                      parallaxOffset: _parallaxOffset,
                      gravityWellPosition: _gravityWellPosition,
                    ),
                    child: Container(),
                  );
                },
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Painter for all background elements
class NebulaPainter extends CustomPainter {
  final double nebulaAnimation;
  final List<Star> stars;
  final List<ShootingStar> shootingStars;
  final Offset parallaxOffset;
  final Offset? gravityWellPosition;

  NebulaPainter({
    required this.nebulaAnimation,
    required this.stars,
    required this.shootingStars,
    required this.parallaxOffset,
    this.gravityWellPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the swirling nebula
    final nebulaPaint = Paint();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    nebulaPaint.shader = LinearGradient(
      colors: const [
        Color(0x443a0ca3), // Cosmic Purple
        Color(0x554cc9f0), // Cyan
        Color(0x337209b7), // Another Purple
      ],
      transform: GradientRotation(nebulaAnimation * 2 * pi),
    ).createShader(rect);
    canvas.drawRect(rect, nebulaPaint);

    // 2. Draw the stars with parallax and gravity effects
    final starPaint = Paint();
    for (var star in stars) {
      var starPosition = Offset(
        (star.position.dx * size.width) + (parallaxOffset.dx * star.depth),
        (star.position.dy * size.height) + (parallaxOffset.dy * star.depth),
      );

      double starRadius = star.radius;
      starPaint.color = star.color;
      
      // Apply gravity well effect
      if (gravityWellPosition != null) {
        final distanceVector = starPosition - gravityWellPosition!;
        final distance = distanceVector.distance;
        if (distance < 200) {
          final force = 1 - (distance / 200);
          final gravityOffset = Offset.fromDirection(distanceVector.direction, -force * 20);
          starPosition += gravityOffset;
          
          // Stretch the star
          if (distance < 100) {
            starPaint.strokeWidth = star.radius * 1.5;
            starPaint.strokeCap = StrokeCap.round;
            final stretchVector = Offset.fromDirection(distanceVector.direction, -force * 5);
            canvas.drawLine(starPosition, starPosition + stretchVector, starPaint);
            continue; // Skip drawing the circle
          }
        }
      }
      canvas.drawCircle(starPosition, starRadius, starPaint);
    }

    // 3. Draw the shooting stars
    final shootingStarPaint = Paint()..strokeCap = StrokeCap.round;
    for (var star in shootingStars) {
      shootingStarPaint.shader = LinearGradient(
        colors: [Colors.white, Colors.white.withOpacity(0.0)],
        stops: const [0.0, 0.8],
      ).createShader(Rect.fromPoints(star.position, star.tailPosition));
      
      shootingStarPaint.strokeWidth = star.radius * 1.5;
      canvas.drawLine(star.tailPosition, star.position, shootingStarPaint);
    }
  }

  @override
  bool shouldRepaint(covariant NebulaPainter oldDelegate) => true;
}

// Data models for celestial objects
class Star {
  Offset position;
  double radius;
  Color color;
  double depth; // For parallax effect

  Star({
    required this.position,
    required this.radius,
    required this.color,
    required this.depth,
  });
}

class ShootingStar {
  late Offset position;
  late Offset velocity;
  late double radius;
  final Random random;

  ShootingStar({required this.random}) {
    radius = random.nextDouble() * 1.5 + 0.5;
    // Start from off-screen
    if (random.nextBool()) { // Horizontal
      position = Offset(random.nextBool() ? -50 : 50, random.nextDouble() * 500);
      velocity = Offset((random.nextBool() ? 1 : -1) * (random.nextDouble() * 5 + 5), (random.nextDouble() - 0.5) * 2);
    } else { // Vertical
      position = Offset(random.nextDouble() * 500, random.nextBool() ? -50 : 50);
      velocity = Offset((random.nextDouble() - 0.5) * 2, (random.nextBool() ? 1 : -1) * (random.nextDouble() * 5 + 5));
    }
  }

  Offset get tailPosition => position - (velocity * 10);

  void update() {
    position += velocity;
  }

  bool isOffScreen(Size size) {
    return position.dx < -100 || position.dx > size.width + 100 ||
           position.dy < -100 || position.dy > size.height + 100;
  }
}
