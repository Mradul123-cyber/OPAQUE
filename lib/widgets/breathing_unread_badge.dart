
import 'package:flutter/material.dart';

class BreathingUnreadBadge extends StatefulWidget {
  final double size;

  const BreathingUnreadBadge({
    super.key,
    required this.size,
  });

  @override
  State<BreathingUnreadBadge> createState() => _BreathingUnreadBadgeState();
}

class _BreathingUnreadBadgeState extends State<BreathingUnreadBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFF5F5F5),
            width: 2,
          ),
        ),
      ),
    );
  }
}
