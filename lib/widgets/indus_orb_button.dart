import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A beautifully animated oval button with bold ancient Indus floral motifs
/// and a glowing breathing animation effect.
class IndusOrbButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isDarkMode;

  const IndusOrbButton({
    super.key,
    required this.onTap,
    required this.isDarkMode,
  });

  @override
  State<IndusOrbButton> createState() => _IndusOrbButtonState();
}

class _IndusOrbButtonState extends State<IndusOrbButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            // Extra padding so floral motifs that extend outside the oval
            // are not clipped by the Container boundary
            width: 104,
            height: 60,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFD4A017,
                  ).withOpacity(_glowAnimation.value * 0.75),
                  blurRadius: 20 * _glowAnimation.value,
                  spreadRadius: 3 * _glowAnimation.value,
                ),
                BoxShadow(
                  color: const Color(
                    0xFFFF6B00,
                  ).withOpacity(_glowAnimation.value * 0.4),
                  blurRadius: 36 * _glowAnimation.value,
                  spreadRadius: 5 * _glowAnimation.value,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _IndusFloralPainter(
                glowValue: _glowAnimation.value,
                isDarkMode: widget.isDarkMode,
              ),
              child: Center(
                child: Text(
                  'Indus',
                  style: GoogleFonts.cinzel(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: widget.isDarkMode
                        ? const Color(0xFFFFF8DC) // warm cream on dark
                        : const Color(0xFFFFFAE0), // bright cream on gold
                    shadows: [
                      Shadow(
                        color: widget.isDarkMode
                            ? const Color(0xFFFFD700).withOpacity(0.9)
                            : Colors.black.withOpacity(0.55),
                        blurRadius: 8,
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 2,
                        offset: const Offset(0.5, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// CustomPainter — Bold ancient Indus Valley floral oval motif
class _IndusFloralPainter extends CustomPainter {
  final double glowValue;
  final bool isDarkMode;

  _IndusFloralPainter({required this.glowValue, required this.isDarkMode});

  // ─── Color palette ───────────────────────────────────────────────────────
  static const Color _gold = Color(0xFFD4A017);
  static const Color _amber = Color(0xFFFF9500);
  static const Color _cream = Color(0xFFFFF3DC);
  static const Color _deep = Color(0xFF3B1A00);

  // ── Light mode palette (Gold medallion look) ──────────────────────────────
  static const Color _lmHighlight = Color(0xFFFFE066); // bright gold highlight
  static const Color _lmGold = Color(0xFFFFD700); // vivid gold for chains
  static const Color _lmEdge = Color(0xFF7A5200); // deep golden-brown rim

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = cx - 8;
    final ry = cy - 8;
    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );

    // ── 1. Deep base fill — multi-stop radial for 3D sphere depth ─────────────
    final bgGradient = RadialGradient(
      center: const Alignment(-0.25, -0.4), // off-center = directional light
      radius: 1.0,
      colors: isDarkMode
          ? [
              const Color(0xFF8C4E00), // bright amber highlight center
              const Color(0xFF5C2E00), // mid warm brown
              const Color(0xFF2A1300), // dark shadow edge
              const Color(0xFF0D0500), // deep black rim
            ]
          : [
              const Color(0xFFFFF0A0), // bright gold center highlight
              const Color(0xFFD4A017), // warm amber mid
              const Color(0xFF9A7000), // deep golden tone
              _lmEdge, // dark golden-brown rim
            ],
      stops: const [0.0, 0.38, 0.72, 1.0],
    );
    canvas.drawOval(
      ovalRect,
      Paint()..shader = bgGradient.createShader(ovalRect),
    );

    // ── 2. Inner shadow ring — darkens the very edge of the fill ──────────────
    //       Creates a subtle "inset" look before the border
    final innerShadowGrad = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        Colors.transparent,
        Colors.transparent,
        Colors.black.withOpacity(isDarkMode ? 0.55 : 0.45),
      ],
      stops: const [0.0, 0.65, 1.0],
    );
    canvas.drawOval(
      ovalRect,
      Paint()..shader = innerShadowGrad.createShader(ovalRect),
    );

    // ── 3. Outer border ring ───────────────────────────────────────────────────
    canvas.drawOval(
      ovalRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..color = isDarkMode ? _gold : _lmGold,
    );

    // ── 4. Secondary inner decorative ring ────────────────────────────────────
    final rxi = rx - 5;
    final ryi = ry - 5;
    final innerRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rxi * 2,
      height: ryi * 2,
    );
    canvas.drawOval(
      innerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = (isDarkMode ? _amber : _lmHighlight).withOpacity(0.65),
    );

    // ── 5. Diamond chain on outer border ──────────────────────────────────────
    _drawDiamondChain(
      canvas,
      cx,
      cy,
      rx,
      ry,
      fillColor: isDarkMode ? _gold : _lmGold,
      strokeColor: isDarkMode
          ? _cream.withOpacity(0.7)
          : Colors.white.withOpacity(0.6),
    );

    // ── 6. Mandala spoke hints ────────────────────────────────────────────────
    _drawMandalaSpokeHints(canvas, cx, cy, rxi * 0.60, ryi * 0.60);

    // ── 7. Specular highlight — top-left bright oval (3D glass shine) ─────────
    final specRect = Rect.fromCenter(
      center: Offset(cx - rx * 0.18, cy - ry * 0.35),
      width: rx * 0.9,
      height: ry * 0.55,
    );
    final specGrad = RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [
        Colors.white.withOpacity(isDarkMode ? 0.18 : 0.22),
        Colors.white.withOpacity(0.0),
      ],
    );
    canvas.drawOval(
      specRect,
      Paint()..shader = specGrad.createShader(specRect),
    );

    // ── 8. Rim light arc — thin bright crescent at very top ───────────────────
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(isDarkMode ? 0.30 : 0.40);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: (rx - 1) * 2,
        height: (ry - 1) * 2,
      ),
      -2.4, // start angle (roughly 10 o'clock)
      1.8, // sweep (about 100°)
      false,
      rimPaint,
    );
  }

  // ── Diamond chain ─────────────────────────────────────────────────────────
  void _drawDiamondChain(
    Canvas canvas,
    double cx,
    double cy,
    double rx,
    double ry, {
    Color? fillColor,
    Color? strokeColor,
  }) {
    const steps = 28;
    final fillP = Paint()..color = (fillColor ?? _gold).withOpacity(0.92);
    final strokeP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = (strokeColor ?? _cream.withOpacity(0.7));

    for (int i = 0; i < steps; i++) {
      final t = (2 * pi * i) / steps;
      final bx = cx + rx * cos(t);
      final by = cy + ry * sin(t);

      canvas.save();
      canvas.translate(bx, by);
      canvas.rotate(t + pi / 2);

      final d = Path()
        ..moveTo(0, -4.5)
        ..lineTo(2.8, 0)
        ..lineTo(0, 4.5)
        ..lineTo(-2.8, 0)
        ..close();
      canvas.drawPath(d, fillP);
      canvas.drawPath(d, strokeP);

      canvas.restore();
    }
  }

  // ── Subtle mandala spoke hints at center ──────────────────────────────────
  void _drawMandalaSpokeHints(
    Canvas canvas,
    double cx,
    double cy,
    double rxs,
    double rys,
  ) {
    final spokePaint = Paint()
      ..color = _gold.withOpacity(0.18)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 12; i++) {
      final a = (pi / 6) * i;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + rxs * cos(a), cy + rys * sin(a)),
        spokePaint,
      );
    }

    // Center rosette dot
    canvas.drawCircle(
      Offset(cx, cy),
      3,
      Paint()..color = _gold.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(_IndusFloralPainter old) =>
      old.glowValue != glowValue || old.isDarkMode != isDarkMode;
}
