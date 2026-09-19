import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Animated profile avatar that flips between user's profile picture and app logo
class AnimatedProfileAvatar extends StatefulWidget {
  final String? imageUrl;
  final double size;
  final bool enableAnimation;
  final Duration flipDuration;
  final Duration displayDuration;

  const AnimatedProfileAvatar({
    super.key,
    this.imageUrl,
    this.size = 50.0,
    this.enableAnimation = true,
    this.flipDuration = const Duration(milliseconds: 800),
    this.displayDuration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedProfileAvatar> createState() => _AnimatedProfileAvatarState();
}

class _AnimatedProfileAvatarState extends State<AnimatedProfileAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Timer? _timer;
  bool _showLogo = false;

  @override
  void initState() {
    super.initState();

    // Setup animation controller for flip effect
    _controller = AnimationController(
      duration: widget.flipDuration,
      vsync: this,
    );

    // Curved animation for smooth flip
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Start periodic flipping if animation is enabled
    if (widget.enableAnimation) {
      _startPeriodicFlip();
    }
  }

  void _startPeriodicFlip() {
    _timer = Timer.periodic(widget.displayDuration, (timer) {
      if (mounted) {
        _flip();
      }
    });
  }

  void _flip() {
    setState(() {
      _showLogo = !_showLogo;
    });

    if (_controller.status == AnimationStatus.completed) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // Calculate rotation angle for horizontal flip
        final angle = _animation.value * math.pi;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective
          ..rotateY(angle);

        // Determine which side is visible
        final isShowingFront = angle < math.pi / 2;

        return Transform(
          transform: transform,
          alignment: Alignment.center,
          child: isShowingFront
              ? _buildProfileSide()
              : Transform(
                  transform: Matrix4.identity()..rotateY(math.pi),
                  alignment: Alignment.center,
                  child: _buildLogoSide(),
                ),
        );
      },
    );
  }

  Widget _buildProfileSide() {
    return ClipOval(
      child: Container(
        width: widget.size,
        height: widget.size,
        child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                imageBuilder: (context, imageProvider) => Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                placeholder: (context, url) => _buildDefaultAvatar(),
                errorWidget: (context, url, error) => _buildDefaultAvatar(),
              )
            : _buildDefaultAvatar(),
      ),
    );
  }

  Widget _buildLogoSide() {
    return ClipOval(
      child: Image.asset(
        'assets/zarq_logo_circle.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: widget.size,
      height: widget.size,
      color: Colors.cyanAccent.withOpacity(0.2),
      child: Icon(
        Icons.person,
        size: widget.size * 0.6,
        color: Colors.cyanAccent,
      ),
    );
  }
}
