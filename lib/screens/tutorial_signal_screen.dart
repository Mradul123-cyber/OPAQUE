import 'package:flutter/material.dart';
import 'dart:math' as math;

class TutorialSignalScreen extends StatefulWidget {
  const TutorialSignalScreen({super.key});

  @override
  State<TutorialSignalScreen> createState() => _TutorialSignalScreenState();
}

class _TutorialSignalScreenState extends State<TutorialSignalScreen>
    with TickerProviderStateMixin {
  late AnimationController _ratchetController;
  late AnimationController _pulseController;
  late AnimationController _languageToggleController;
  late Animation<double> _ratchetAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _languageToggleAnimation;

  bool _isHindi = true;

  final Map<String, Map<String, String>> _content = {
    'appBarTitle': {
      'hi': 'सिग्नल प्रोटोकॉल',
      'en': 'Signal Protocol',
    },
    'title': {
      'hi': 'मिलिट्री-ग्रेड एन्क्रिप्शन',
      'en': 'Military-Grade Encryption',
    },
    'subtitle': {
      'hi': 'सिग्नल प्रोटोकॉल की तकनीकी विशेषताएं',
      'en': 'Technical Features of Signal Protocol',
    },
    'doubleRatchetTitle': {
      'hi': 'डबल रैचेट एल्गोरिथम',
      'en': 'Double Ratchet Algorithm',
    },
    'rootKeyLabel': {
      'hi': 'रूट की',
      'en': 'Root Key',
    },
    'dhRatchetLabel': {
      'hi': 'DH रैचेट',
      'en': 'DH Ratchet',
    },
    'sendChainLabel': {
      'hi': 'भेजें चेन',
      'en': 'Send Chain',
    },
    'recvChainLabel': {
      'hi': 'प्राप्त चेन',
      'en': 'Recv Chain',
    },
    'msgKeyLabel': {
      'hi': 'संदेश कुंजी',
      'en': 'Msg Key',
    },
    'kdfLabel': {
      'hi': 'KDF',
      'en': 'KDF',
    },
    'forwardSecrecyTitle': {
      'hi': 'फॉरवर्ड सिक्रेसी',
      'en': 'Forward Secrecy',
    },
    'forwardSecrecyDesc': {
      'hi': 'प्रत्येक संदेश के लिए अद्वितीय कुंजी। पुरानी कुंजी तुरंत हटा दी जाती है।',
      'en': 'Unique key per message. Old keys deleted immediately.',
    },
    'x3dhTitle': {
      'hi': 'X3DH की एक्सचेंज',
      'en': 'X3DH Key Exchange',
    },
    'x3dhDesc': {
      'hi': 'सुरक्षित सत्र स्थापना: आइडेंटिटी, साइन्ड प्री-की, वन-टाइम प्री-की',
      'en': 'Secure session setup: Identity, Signed Pre-key, One-time Pre-key',
    },
    'preKeysTitle': {
      'hi': 'प्री-की बंडल',
      'en': 'Pre-Key Bundle',
    },
    'preKeysDesc': {
      'hi': 'सर्वर पर पूर्व-जनित कुंजियाँ। ऑफलाइन संदेश सक्षम करता है।',
      'en': 'Pre-generated keys on server. Enables offline messaging.',
    },
    'aeadTitle': {
      'hi': 'AEAD एन्क्रिप्शन',
      'en': 'AEAD Encryption',
    },
    'aeadDesc': {
      'hi': 'AES-256-CBC + HMAC-SHA256 या AES-256-GCM प्रमाणित एन्क्रिप्शन',
      'en': 'AES-256-CBC + HMAC-SHA256 or AES-256-GCM authenticated encryption',
    },
    'sesameTitle': {
      'hi': 'सीज़मी एल्गोरिथम',
      'en': 'Sesame Algorithm',
    },
    'sesameDesc': {
      'hi': 'बड़े ग्रुप के लिए स्मार्ट कुंजी वितरण। 1000 लोगों के लिए केवल ~10 कदम',
      'en': 'Smart key distribution for large groups. Only ~10 steps for 1000 people',
    },
    'openSourceTitle': {
      'hi': 'ओपन सोर्स प्रोटोकॉल',
      'en': 'Open Source Protocol',
    },
    'openSourceDesc': {
      'hi': 'सिग्नल प्रोटोकॉल की स्पेसिफिकेशन और कोड सार्वजनिक। किसी भी विशेषज्ञ द्वारा ऑडिट योग्य',
      'en': 'Signal Protocol specs and code are public. Auditable by any expert worldwide',
    },
    'doubleTapHint': {
      'hi': '🌐 अंग्रेजी में बदलने के लिए डबल टैप करें',
      'en': '🌐 Double tap to convert to Hindi',
    },
  };

  @override
  void initState() {
    super.initState();

    _ratchetController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    _ratchetAnimation = CurvedAnimation(
      parent: _ratchetController,
      curve: Curves.linear,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    _languageToggleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _languageToggleAnimation = CurvedAnimation(
      parent: _languageToggleController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _ratchetController.dispose();
    _pulseController.dispose();
    _languageToggleController.dispose();
    super.dispose();
  }

  String _getText(String key) {
    return _content[key]?[_isHindi ? 'hi' : 'en'] ?? '';
  }

  void _toggleLanguage() {
    setState(() {
      _isHindi = !_isHindi;
    });
    _languageToggleController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 360;
    final isMediumScreen = screenWidth >= 360 && screenWidth < 400;

    return GestureDetector(
      onDoubleTap: _toggleLanguage,
      child: Scaffold(
        backgroundColor: const Color(0xFF0a1128),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _getText('appBarTitle'),
              key: ValueKey(_isHindi),
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallScreen ? 16 : 18,
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16.0 : 24.0,
            vertical: 16.0,
          ),
          child: Column(
            children: [
              // Header
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _getText('title'),
                  key: ValueKey('title_$_isHindi'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 22 : (isMediumScreen ? 24 : 28),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _getText('subtitle'),
                  key: ValueKey('subtitle_$_isHindi'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 13 : (isMediumScreen ? 14 : 16),
                    color: Colors.white60,
                  ),
                ),
              ),
              SizedBox(height: isSmallScreen ? 20 : 30),

              // Double Ratchet Visualization
              Container(
                height: screenHeight * (isSmallScreen ? 0.5 : 0.55),
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.deepOrange.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _getText('doubleRatchetTitle'),
                        key: ValueKey('drTitle_$_isHindi'),
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 4 : 8),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _ratchetAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: DoubleRatchetPainter(
                              progress: _ratchetAnimation.value,
                              isHindi: _isHindi,
                            ),
                            child: _buildRatchetLabels(isSmallScreen),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: isSmallScreen ? 20 : 30),

              // Technical Features
              _buildTechFeature(
                icon: Icons.sync_alt,
                title: _getText('forwardSecrecyTitle'),
                description: _getText('forwardSecrecyDesc'),
                color: Colors.greenAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildTechFeature(
                icon: Icons.key,
                title: _getText('x3dhTitle'),
                description: _getText('x3dhDesc'),
                color: Colors.cyanAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildTechFeature(
                icon: Icons.inventory_2_outlined,
                title: _getText('preKeysTitle'),
                description: _getText('preKeysDesc'),
                color: Colors.purpleAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildTechFeature(
                icon: Icons.security,
                title: _getText('aeadTitle'),
                description: _getText('aeadDesc'),
                color: Colors.amberAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildTechFeature(
                icon: Icons.people_outline,
                title: _getText('sesameTitle'),
                description: _getText('sesameDesc'),
                color: Colors.pinkAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildTechFeature(
                icon: Icons.code,
                title: _getText('openSourceTitle'),
                description: _getText('openSourceDesc'),
                color: Colors.lightBlueAccent,
                isSmallScreen: isSmallScreen,
              ),

              const SizedBox(height: 24),

              // Double tap hint
              AnimatedBuilder(
                animation: _languageToggleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_languageToggleAnimation.value * 0.2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _getText('doubleTapHint'),
                          key: ValueKey('hint_$_isHindi'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatchetLabels(bool isSmallScreen) {
    return Stack(
      children: [
        // Raj (Left)
        Positioned(
          left: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('raj_$_isHindi'),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 10,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent),
              ),
              child: Text(
                'Raj',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 10 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        // Arjun (Right)
        Positioned(
          right: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('arjun_$_isHindi'),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 10,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purpleAccent),
              ),
              child: Text(
                'Arjun',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 10 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        // Root Key label (top center)
        Positioned(
          left: 0,
          right: 0,
          top: isSmallScreen ? 5 : 10,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey('rootkey_$_isHindi'),
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 8 : 10,
                  vertical: isSmallScreen ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepOrange),
                ),
                child: Text(
                  _getText('rootKeyLabel'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechFeature({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isSmallScreen,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('${title}_$description'),
        padding: EdgeInsets.all(isSmallScreen ? 14 : 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseAnimation.value * 0.1),
                  child: Container(
                    padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 12),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: isSmallScreen ? 24 : 28),
                  ),
                );
              },
            ),
            SizedBox(width: isSmallScreen ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: isSmallScreen ? 15 : 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 3 : 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isSmallScreen ? 12 : 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoubleRatchetPainter extends CustomPainter {
  final double progress;
  final bool isHindi;

  DoubleRatchetPainter({
    required this.progress,
    required this.isHindi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isSmall = size.width < 300;
    final centerX = size.width / 2;

    // Define key positions
    final topMargin = isSmall ? 35.0 : 45.0;
    final rootKeyY = topMargin;
    final dhRatchetY = rootKeyY + (isSmall ? 60 : 80);
    final chainY = dhRatchetY + (isSmall ? 50 : 65);
    final msgKeyY = chainY + (isSmall ? 45 : 60);

    // Animation phases (8 seconds cycle)
    final phase = (progress * 8) % 8;

    // Draw Root Key (top center)
    _drawRootKey(canvas, Offset(centerX, rootKeyY), isSmall);

    // Draw DH Ratchet mechanism
    _drawDHRatchet(canvas, Offset(centerX, dhRatchetY), phase, isSmall);

    // Draw Chain Keys (left = Raj send, right = Arjun send)
    final rajChainX = centerX - (isSmall ? 80 : 100);
    final arjunChainX = centerX + (isSmall ? 80 : 100);

    _drawChainKey(canvas, Offset(rajChainX, chainY),
                  Colors.blueAccent, isSmall, isHindi, true);
    _drawChainKey(canvas, Offset(arjunChainX, chainY),
                  Colors.purpleAccent, isSmall, isHindi, false);

    // Draw Message Keys (derived from chains)
    if (phase >= 1 && phase < 3) {
      // Raj sends message 1
      _drawMessageKey(canvas, Offset(rajChainX, msgKeyY),
                     Colors.cyanAccent, isSmall, '1');
      _drawMessage(canvas, rajChainX, arjunChainX, msgKeyY + 20,
                  (phase - 1) / 2, Colors.cyanAccent, isSmall);
    }

    if (phase >= 3 && phase < 5) {
      // Arjun sends message 2
      _drawMessageKey(canvas, Offset(arjunChainX, msgKeyY),
                     Colors.pinkAccent, isSmall, '2');
      _drawMessage(canvas, arjunChainX, rajChainX, msgKeyY + 20,
                  (phase - 3) / 2, Colors.pinkAccent, isSmall);
    }

    if (phase >= 5 && phase < 7) {
      // Raj sends message 3
      _drawMessageKey(canvas, Offset(rajChainX, msgKeyY),
                     Colors.greenAccent, isSmall, '3');
      _drawMessage(canvas, rajChainX, arjunChainX, msgKeyY + 20,
                  (phase - 5) / 2, Colors.greenAccent, isSmall);
    }

    // Draw connecting lines
    _drawConnectingLines(canvas, size, centerX, rootKeyY, dhRatchetY,
                         chainY, rajChainX, arjunChainX, msgKeyY, isSmall);

    // Draw KDF labels
    _drawKDFLabels(canvas, rajChainX, arjunChainX, chainY, msgKeyY, isSmall);
  }

  void _drawRootKey(Canvas canvas, Offset position, bool isSmall) {
    final paint = Paint()
      ..color = Colors.deepOrange
      ..style = PaintingStyle.fill;

    // Draw key shape
    canvas.drawCircle(position, isSmall ? 15 : 18, paint);

    // Draw lock icon
    final lockPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final lockSize = isSmall ? 8.0 : 10.0;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(position.dx, position.dy - lockSize / 4),
        width: lockSize,
        height: lockSize,
      ),
      math.pi,
      math.pi,
      false,
      lockPaint,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(position.dx, position.dy + lockSize / 4),
        width: lockSize,
        height: lockSize / 2,
      ),
      lockPaint..style = PaintingStyle.fill,
    );
  }

  void _drawDHRatchet(Canvas canvas, Offset position, double phase, bool isSmall) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final radius = isSmall ? 20.0 : 25.0;
    final teeth = 6;

    // Rotate ratchet when DH exchange happens (phases 0-1, 4-5)
    final rotation = (phase >= 0 && phase < 1) ? (phase * 2 * math.pi / teeth) :
                     (phase >= 4 && phase < 5) ? ((phase - 4) * 2 * math.pi / teeth) : 0;

    for (int i = 0; i < teeth; i++) {
      final angle = (i * 2 * math.pi / teeth) + rotation;
      final x1 = position.dx + radius * math.cos(angle);
      final y1 = position.dy + radius * math.sin(angle);
      final x2 = position.dx + (radius + 8) * math.cos(angle);
      final y2 = position.dy + (radius + 8) * math.sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // Center
    final centerPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, isSmall ? 15 : 18, centerPaint);

    // DH label
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'DH',
        style: TextStyle(
          color: const Color(0xFF0a1128),
          fontSize: isSmall ? 11 : 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2,
             position.dy - textPainter.height / 2),
    );
  }

  void _drawChainKey(Canvas canvas, Offset position, Color color,
                     bool isSmall, bool isHindi, bool isSend) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw rounded rectangle for chain
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: position,
        width: isSmall ? 50 : 60,
        height: isSmall ? 24 : 28,
      ),
      Radius.circular(isSmall ? 12 : 14),
    );
    canvas.drawRRect(rect, paint);

    // Draw label
    final label = isSend
        ? (isHindi ? 'भेजें' : 'Send')
        : (isHindi ? 'प्राप्त' : 'Recv');

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF0a1128),
          fontSize: isSmall ? 9 : 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2,
             position.dy - textPainter.height / 2),
    );
  }

  void _drawMessageKey(Canvas canvas, Offset position, Color color,
                       bool isSmall, String number) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw key icon
    canvas.drawCircle(position, isSmall ? 10 : 12, paint);

    // Draw number
    final textPainter = TextPainter(
      text: TextSpan(
        text: number,
        style: TextStyle(
          color: const Color(0xFF0a1128),
          fontSize: isSmall ? 9 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2,
             position.dy - textPainter.height / 2),
    );
  }

  void _drawMessage(Canvas canvas, double fromX, double toX, double y,
                    double progress, Color color, bool isSmall) {
    final currentX = fromX + (toX - fromX) * progress;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Message envelope
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(currentX, y),
        width: isSmall ? 25 : 30,
        height: isSmall ? 16 : 20,
      ),
      Radius.circular(isSmall ? 8 : 10),
    );
    canvas.drawRRect(rect, paint);

    // Envelope flap
    final flapPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final flapPath = Path();
    flapPath.moveTo(currentX - (isSmall ? 8 : 10), y - (isSmall ? 4 : 5));
    flapPath.lineTo(currentX, y);
    flapPath.lineTo(currentX + (isSmall ? 8 : 10), y - (isSmall ? 4 : 5));
    canvas.drawPath(flapPath, flapPaint);
  }

  void _drawConnectingLines(Canvas canvas, Size size, double centerX,
                           double rootKeyY, double dhRatchetY, double chainY,
                           double rajChainX, double arjunChainX,
                           double msgKeyY, bool isSmall) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Root to DH Ratchet
    linePaint.color = Colors.deepOrange.withOpacity(0.5);
    canvas.drawLine(
      Offset(centerX, rootKeyY + (isSmall ? 15 : 18)),
      Offset(centerX, dhRatchetY - (isSmall ? 25 : 30)),
      linePaint,
    );

    // DH Ratchet to Chain Keys
    linePaint.color = Colors.orangeAccent.withOpacity(0.5);
    canvas.drawLine(
      Offset(centerX, dhRatchetY + (isSmall ? 25 : 30)),
      Offset(rajChainX, chainY - (isSmall ? 12 : 14)),
      linePaint,
    );
    canvas.drawLine(
      Offset(centerX, dhRatchetY + (isSmall ? 25 : 30)),
      Offset(arjunChainX, chainY - (isSmall ? 12 : 14)),
      linePaint,
    );

    // Chain Keys to Message Keys
    linePaint.color = Colors.blueAccent.withOpacity(0.5);
    canvas.drawLine(
      Offset(rajChainX, chainY + (isSmall ? 12 : 14)),
      Offset(rajChainX, msgKeyY - (isSmall ? 10 : 12)),
      linePaint,
    );

    linePaint.color = Colors.purpleAccent.withOpacity(0.5);
    canvas.drawLine(
      Offset(arjunChainX, chainY + (isSmall ? 12 : 14)),
      Offset(arjunChainX, msgKeyY - (isSmall ? 10 : 12)),
      linePaint,
    );
  }

  void _drawKDFLabels(Canvas canvas, double rajChainX, double arjunChainX,
                     double chainY, double msgKeyY, bool isSmall) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'KDF',
        style: TextStyle(
          color: Colors.white60,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // KDF labels between chains and message keys
    textPainter.paint(
      canvas,
      Offset(rajChainX - textPainter.width / 2,
             chainY + (msgKeyY - chainY) / 2 - textPainter.height / 2),
    );

    textPainter.paint(
      canvas,
      Offset(arjunChainX - textPainter.width / 2,
             chainY + (msgKeyY - chainY) / 2 - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(DoubleRatchetPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isHindi != isHindi;
  }
}
