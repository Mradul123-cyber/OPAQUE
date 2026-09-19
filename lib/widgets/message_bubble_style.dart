import 'package:flutter/material.dart';

BorderRadius messageBubbleRadius(
  bool isMe,
  String styleKey,
  double screenWidth, {
  bool preview = false,
}) {
  // Exact radii from the approved HTML. Rounded and Squared have no tail.
  final defaultRadius = Radius.circular(preview ? 14 : 16);
  const smallRadius = Radius.circular(4);
  switch (styleKey) {
    case 'square_corners':
      return BorderRadius.circular(7);
    case 'soft_edges':
      return BorderRadius.circular(21);
    case 'minimal':
    case 'minimalist':
      // Use Radius.zero or a very small radius (like 1.0) for truly sharp edges
      const sharpRadius = Radius.circular(1.0);
      final standardRadius = Radius.circular(
        (screenWidth * 0.045).clamp(16.0, 22.0),
      );

      return BorderRadius.only(
        // Sharp top corners
        topLeft: sharpRadius,
        topRight: sharpRadius,

        // Rounded bottom corner opposite the tail, sharp tail corner
        bottomLeft: isMe ? standardRadius : sharpRadius,
        bottomRight: isMe ? sharpRadius : standardRadius,
      );

    case 'default_rounded':
    default:
      // Soft: the small corner is at the top, beside the speaker.
      return BorderRadius.only(
        topLeft: isMe ? defaultRadius : smallRadius,
        topRight: isMe ? smallRadius : defaultRadius,
        bottomLeft: defaultRadius,
        bottomRight: defaultRadius,
      );
  }
}

BoxDecoration messageCardDecoration(
  bool isMe,
  bool isSelected,
  String cardColorKey,
  double screenWidth, {
  bool preview = false,
}) {
  // Retain existing card colours and saved preference keys.
  final Map<String, Map<String, dynamic>> cardColors = {
    'blue': {
      'color': const Color(0xFFE3F2FD),
      'border': const Color(0xFF90CAF9),
    },
    'green': {
      'color': const Color(0xFFE8F5E9),
      'border': const Color(0xFF81C784),
    },
    'red': {
      'color': const Color(0xFFFFEBEE),
      'border': const Color(0xFFEF5350),
    },
    'purple': {
      'color': const Color(0xFFF3E5F5),
      'border': const Color(0xFFBA68C8),
    },
    'orange': {
      'color': const Color(0xFFFFF3E0),
      'border': const Color(0xFFFFB74D),
    },
    'yellow': {
      'color': const Color(0xFFFFFDE7),
      'border': const Color(0xFFFFF176),
    },
  };

  final colorData = cardColors[cardColorKey] ?? cardColors['blue']!;
  final cardColor = colorData['color'] as Color;
  final borderColor = colorData['border'] as Color;
  final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);

  return BoxDecoration(
    color: isSelected
        ? (isMe ? const Color(0xFFE1BEE7) : const Color(0xFFB0BEC5))
        : (isMe ? cardColor : Colors.white),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: isSelected
          ? (isMe ? const Color(0xFFCE93D8) : const Color(0xFF90A4AE))
          : (isMe ? borderColor : Colors.grey[300]!),
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: (isMe ? borderColor : Colors.grey).withValues(alpha: 0.2),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
