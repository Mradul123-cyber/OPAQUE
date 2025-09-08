// lib/common/starfield_background.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'starfield_painter.dart';

class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({super.key});

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground> with SingleTickerProviderStateMixin {
  List<Star> _farStars = [];
  List<Star> _nearStars = [];
  late AnimationController _controller;
  bool _starsGenerated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _generateStars(context.size!);
      }
    });
  }

  void _generateStars(Size size) {
    final random = Random();
    _farStars = List.generate(200, (index) {
      return Star(
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
        random.nextDouble() * 0.8,
        random.nextDouble() * 0.5 + 0.4,
        random.nextDouble() * 1.0 + 0.5,
        random.nextDouble() * 0.5 + 0.1,
      );
    });
    _nearStars = List.generate(50, (index) {
      return Star(
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
        random.nextDouble() * 1.5,
        random.nextDouble() * 0.4 + 0.6,
        random.nextDouble() * 1.2 + 0.8,
        random.nextDouble() * 0.8 + 0.2,
      );
    });
    setState(() { _starsGenerated = true; });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1a0c2e), Color(0xFF0c1428)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: StarfieldPainter(
                stars: _farStars,
                time: _controller.value * 2 * pi,
              ),
              child: Container(),
            );
          },
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: StarfieldPainter(
                stars: _nearStars,
                time: _controller.value * 2 * pi * 1.5,
              ),
              child: Container(),
            );
          },
        ),
      ],
    );
  }
}