import 'package:flutter/material.dart';
import 'dart:math' as math;

class TutorialE2EEScreen extends StatefulWidget {
  const TutorialE2EEScreen({super.key});

  @override
  State<TutorialE2EEScreen> createState() => _TutorialE2EEScreenState();
}

class _TutorialE2EEScreenState extends State<TutorialE2EEScreen>
    with TickerProviderStateMixin {
  late AnimationController _flowController;
  late AnimationController _pulseController;
  late AnimationController _languageToggleController;
  late Animation<double> _flowAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _languageToggleAnimation;

  bool _isHindi = true; // Default to Hindi

  // Language content maps
  final Map<String, Map<String, String>> _content = {
    'title': {
      'hi': 'आपके संदेश अटूट हैं',
      'en': 'Your Messages Are Unbreakable',
    },
    'subtitle': {
      'hi': 'यहां देखें E2EE आपकी गोपनीयता की रक्षा कैसे करता है',
      'en': 'Here\'s how E2EE protects your privacy',
    },
    'appBarTitle': {
      'hi': 'एंड-टू-एंड एन्क्रिप्शन',
      'en': 'End-to-End Encryption',
    },
    'you': {
      'hi': 'आप',
      'en': 'You',
    },
    'typeMessage': {
      'hi': 'संदेश लिखें',
      'en': 'Type message',
    },
    'encrypt': {
      'hi': 'एन्क्रिप्ट',
      'en': 'Encrypt',
    },
    'lockWithKey': {
      'hi': 'कुंजी से लॉक',
      'en': 'Lock with key',
    },
    'internet': {
      'hi': 'इंटरनेट',
      'en': 'Internet',
    },
    'encryptedData': {
      'hi': 'एन्क्रिप्टेड डेटा',
      'en': 'Encrypted data',
    },
    'decrypt': {
      'hi': 'डिक्रिप्ट',
      'en': 'Decrypt',
    },
    'unlockWithKey': {
      'hi': 'कुंजी से अनलॉक',
      'en': 'Unlock with key',
    },
    'friend': {
      'hi': 'दोस्त',
      'en': 'Friend',
    },
    'readMessage': {
      'hi': 'संदेश पढ़ें',
      'en': 'Read message',
    },
    'zeroAccessTitle': {
      'hi': 'शून्य एक्सेस',
      'en': 'Zero Access',
    },
    'zeroAccessDesc': {
      'hi': 'Zarq भी आपके संदेश नहीं पढ़ सकता। केवल आप और आपके प्राप्तकर्ता के पास कुंजियाँ हैं।',
      'en': 'Not even Zarq can read your messages. Only you and your recipient have the keys.',
    },
    'uniqueKeysTitle': {
      'hi': 'विशिष्ट कुंजियाँ',
      'en': 'Unique Keys',
    },
    'uniqueKeysDesc': {
      'hi': 'हर बातचीत को अद्वितीय एन्क्रिप्शन कुंजियाँ मिलती हैं जो आपके डिवाइस से कभी बाहर नहीं जातीं।',
      'en': 'Every conversation gets unique encryption keys that never leave your device.',
    },
    'signalProtocolTitle': {
      'hi': 'सिग्नल प्रोटोकॉल',
      'en': 'Signal Protocol',
    },
    'signalProtocolDesc': {
      'hi': 'विश्व भर में लाखों लोगों द्वारा विश्वसनीय सैन्य-ग्रेड एन्क्रिप्शन।',
      'en': 'Military-grade encryption trusted by millions worldwide.',
    },
    'doubleTapHint': {
      'hi': '🌐 अंग्रेजी में बदलने के लिए डबल टैप करें',
      'en': '🌐 Double tap to convert to Hindi',
    },
  };

  @override
  void initState() {
    super.initState();

    // Flow animation for the message traveling
    _flowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _flowAnimation = CurvedAnimation(
      parent: _flowController,
      curve: Curves.easeInOut,
    );

    // Pulse animation for locks
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    // Language toggle animation
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
    _flowController.dispose();
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
              SizedBox(height: isSmallScreen ? 20 : 40),

              // Animated Flowchart
              SizedBox(
                height: screenHeight * (isSmallScreen ? 0.45 : 0.5),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_flowAnimation, _pulseAnimation]),
                  builder: (context, child) {
                    return CustomPaint(
                      painter: E2EEFlowchartPainter(
                        flowProgress: _flowAnimation.value,
                        pulseValue: _pulseAnimation.value,
                      ),
                      child: _buildFlowchartContent(isSmallScreen, isMediumScreen),
                    );
                  },
                ),
              ),

              SizedBox(height: isSmallScreen ? 20 : 40),

              // Key Points
              _buildInfoCard(
                icon: Icons.shield_outlined,
                title: _getText('zeroAccessTitle'),
                description: _getText('zeroAccessDesc'),
                color: Colors.cyanAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildInfoCard(
                icon: Icons.vpn_key_outlined,
                title: _getText('uniqueKeysTitle'),
                description: _getText('uniqueKeysDesc'),
                color: Colors.purpleAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildInfoCard(
                icon: Icons.verified_user_outlined,
                title: _getText('signalProtocolTitle'),
                description: _getText('signalProtocolDesc'),
                color: Colors.greenAccent,
                isSmallScreen: isSmallScreen,
              ),

              const SizedBox(height: 24),

              // Double tap hint with animation
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

  Widget _buildFlowchartContent(bool isSmallScreen, bool isMediumScreen) {
    final nodeWidth = isSmallScreen ? 85.0 : (isMediumScreen ? 95.0 : 100.0);
    final leftOffset = isSmallScreen ? 10.0 : 20.0;
    final rightOffset = isSmallScreen ? 10.0 : 20.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Sender (You)
            Positioned(
              left: leftOffset,
              top: 20,
              child: _buildNode(
                icon: Icons.person,
                label: _getText('you'),
                subLabel: _getText('typeMessage'),
                color: Colors.blueAccent,
                width: nodeWidth,
                isSmallScreen: isSmallScreen,
              ),
            ),

            // Encryption Lock
            Positioned(
              left: leftOffset,
              top: isSmallScreen ? 120 : 150,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return _buildNode(
                    icon: Icons.lock,
                    label: _getText('encrypt'),
                    subLabel: _getText('lockWithKey'),
                    color: Colors.cyanAccent,
                    scale: 1.0 + (_pulseAnimation.value * 0.1),
                    width: nodeWidth,
                    isSmallScreen: isSmallScreen,
                  );
                },
              ),
            ),

            // Network/Cloud
            Positioned(
              left: 0,
              right: 0,
              top: isSmallScreen ? 220 : 280,
              child: Center(
                child: _buildNode(
                  icon: Icons.cloud_outlined,
                  label: _getText('internet'),
                  subLabel: _getText('encryptedData'),
                  color: Colors.orangeAccent,
                  width: nodeWidth + 40,
                  isSmallScreen: isSmallScreen,
                ),
              ),
            ),

            // Decryption Lock
            Positioned(
              right: rightOffset,
              top: isSmallScreen ? 120 : 150,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return _buildNode(
                    icon: Icons.lock_open,
                    label: _getText('decrypt'),
                    subLabel: _getText('unlockWithKey'),
                    color: Colors.greenAccent,
                    scale: 1.0 + (_pulseAnimation.value * 0.1),
                    width: nodeWidth,
                    isSmallScreen: isSmallScreen,
                  );
                },
              ),
            ),

            // Receiver (Friend)
            Positioned(
              right: rightOffset,
              top: 20,
              child: _buildNode(
                icon: Icons.person_outline,
                label: _getText('friend'),
                subLabel: _getText('readMessage'),
                color: Colors.purpleAccent,
                width: nodeWidth,
                isSmallScreen: isSmallScreen,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNode({
    required IconData icon,
    required String label,
    required String subLabel,
    required Color color,
    double? width,
    double scale = 1.0,
    required bool isSmallScreen,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Transform.scale(
        key: ValueKey('${label}_$subLabel'),
        scale: scale,
        child: Container(
          width: width,
          padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
            border: Border.all(color: color.withOpacity(0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: isSmallScreen ? 8 : 12,
                spreadRadius: isSmallScreen ? 1 : 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: isSmallScreen ? 24 : 32),
              SizedBox(height: isSmallScreen ? 4 : 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 12 : 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isSmallScreen ? 2 : 4),
              Text(
                subLabel,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: isSmallScreen ? 9 : 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
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
        padding: EdgeInsets.all(isSmallScreen ? 14 : 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
              ),
              child: Icon(icon, color: color, size: isSmallScreen ? 22 : 28),
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
                      fontSize: isSmallScreen ? 15 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 2 : 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isSmallScreen ? 12 : 14,
                      height: 1.4,
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

class E2EEFlowchartPainter extends CustomPainter {
  final double flowProgress;
  final double pulseValue;

  E2EEFlowchartPainter({
    required this.flowProgress,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Define positions with responsive calculations
    final isSmallWidth = size.width < 360;
    final leftOffset = isSmallWidth ? 52.5 : 70.0;
    final rightOffset = isSmallWidth ? 52.5 : 70.0;
    final encryptY = isSmallWidth ? 160.0 : 200.0;
    final networkY = isSmallWidth ? 270.0 : 330.0;

    final senderCenter = Offset(leftOffset, 70);
    final encryptCenter = Offset(leftOffset, encryptY);
    final actualNetworkCenter = Offset(size.width / 2, networkY);
    final actualDecryptCenter = Offset(size.width - rightOffset, encryptY);
    final receiverCenter = Offset(size.width - rightOffset, 70);

    // Draw connection lines with gradient
    _drawAnimatedLine(
      canvas,
      senderCenter,
      encryptCenter,
      Colors.blueAccent,
      Colors.cyanAccent,
      flowProgress,
      0.0,
      0.2,
    );

    _drawAnimatedLine(
      canvas,
      encryptCenter,
      actualNetworkCenter,
      Colors.cyanAccent,
      Colors.orangeAccent,
      flowProgress,
      0.2,
      0.5,
    );

    _drawAnimatedLine(
      canvas,
      actualNetworkCenter,
      actualDecryptCenter,
      Colors.orangeAccent,
      Colors.greenAccent,
      flowProgress,
      0.5,
      0.8,
    );

    _drawAnimatedLine(
      canvas,
      actualDecryptCenter,
      receiverCenter,
      Colors.greenAccent,
      Colors.purpleAccent,
      flowProgress,
      0.8,
      1.0,
    );

    // Draw animated message packet
    _drawMovingPacket(canvas, [
      senderCenter,
      encryptCenter,
      actualNetworkCenter,
      actualDecryptCenter,
      receiverCenter,
    ], flowProgress);
  }

  void _drawAnimatedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color startColor,
    Color endColor,
    double progress,
    double segmentStart,
    double segmentEnd,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Calculate segment progress
    double segmentProgress = 0.0;
    if (progress >= segmentStart && progress <= segmentEnd) {
      segmentProgress = (progress - segmentStart) / (segmentEnd - segmentStart);
    } else if (progress > segmentEnd) {
      segmentProgress = 1.0;
    }

    // Draw base line (dim)
    paint.color = startColor.withOpacity(0.2);
    canvas.drawLine(start, end, paint);

    // Draw animated line
    if (segmentProgress > 0) {
      final animatedEnd = Offset(
        start.dx + (end.dx - start.dx) * segmentProgress,
        start.dy + (end.dy - start.dy) * segmentProgress,
      );

      paint.shader = LinearGradient(
        colors: [startColor, endColor],
      ).createShader(Rect.fromPoints(start, animatedEnd));

      canvas.drawLine(start, animatedEnd, paint);

      // Draw arrow at the end
      _drawArrow(canvas, start, animatedEnd, endColor);
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowSize = 10.0;
    final direction = (end - start);
    final angle = math.atan2(direction.dy, direction.dx);

    final arrowPath = Path();
    arrowPath.moveTo(end.dx, end.dy);
    arrowPath.lineTo(
      end.dx - arrowSize * math.cos(angle - math.pi / 6),
      end.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    arrowPath.lineTo(
      end.dx - arrowSize * math.cos(angle + math.pi / 6),
      end.dy - arrowSize * math.sin(angle + math.pi / 6),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, paint);
  }

  void _drawMovingPacket(Canvas canvas, List<Offset> points, double progress) {
    if (points.length < 2) return;

    // Calculate total path length
    double totalLength = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalLength += (points[i + 1] - points[i]).distance;
    }

    // Find position along path
    double targetDistance = totalLength * progress;
    double currentDistance = 0;

    for (int i = 0; i < points.length - 1; i++) {
      final segmentLength = (points[i + 1] - points[i]).distance;

      if (currentDistance + segmentLength >= targetDistance) {
        final segmentProgress = (targetDistance - currentDistance) / segmentLength;
        final position = Offset(
          points[i].dx + (points[i + 1].dx - points[i].dx) * segmentProgress,
          points[i].dy + (points[i + 1].dy - points[i].dy) * segmentProgress,
        );

        // Draw packet
        final paint = Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.fill;

        canvas.drawCircle(position, 8, paint);

        // Draw glow
        paint.color = Colors.yellowAccent.withOpacity(0.3);
        canvas.drawCircle(position, 14, paint);

        // Draw message icon
        final iconPaint = Paint()
          ..color = const Color(0xFF0a1128)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(position, 5, iconPaint);

        break;
      }

      currentDistance += segmentLength;
    }
  }

  @override
  bool shouldRepaint(E2EEFlowchartPainter oldDelegate) {
    return oldDelegate.flowProgress != flowProgress ||
        oldDelegate.pulseValue != pulseValue;
  }
}
