import 'package:flutter/material.dart';
import 'dart:math' as math;

class TutorialBackupScreen extends StatefulWidget {
  const TutorialBackupScreen({super.key});

  @override
  State<TutorialBackupScreen> createState() => _TutorialBackupScreenState();
}

class _TutorialBackupScreenState extends State<TutorialBackupScreen>
    with TickerProviderStateMixin {
  late AnimationController _flowController;
  late AnimationController _pulseController;
  late AnimationController _languageToggleController;
  late Animation<double> _flowAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _languageToggleAnimation;

  bool _isHindi = true;

  final Map<String, Map<String, String>> _content = {
    'appBarTitle': {
      'hi': 'एन्क्रिप्टेड बैकअप',
      'en': 'Encrypted Backups',
    },
    'title': {
      'hi': 'अपने संदेश कभी न खोएं',
      'en': 'Never Lose Your Messages',
    },
    'subtitle': {
      'hi': 'स्वचालित एन्क्रिप्टेड बैकअप और पुनर्स्थापना',
      'en': 'Automatic encrypted backup and restore',
    },
    'backupFlowTitle': {
      'hi': 'बैकअप और पुनर्स्थापना प्रक्रिया',
      'en': 'Backup & Restore Process',
    },
    'phoneLabel': {
      'hi': 'फोन',
      'en': 'Phone',
    },
    'messagesLabel': {
      'hi': 'संदेश',
      'en': 'Messages',
    },
    'encryptLabel': {
      'hi': 'एन्क्रिप्ट',
      'en': 'Encrypt',
    },
    'passwordLabel': {
      'hi': 'पासवर्ड',
      'en': 'Password',
    },
    'cloudLabel': {
      'hi': 'क्लाउड',
      'en': 'Cloud',
    },
    'encryptedLabel': {
      'hi': 'एन्क्रिप्टेड',
      'en': 'Encrypted',
    },
    'decryptLabel': {
      'hi': 'डिक्रिप्ट',
      'en': 'Decrypt',
    },
    'restoreLabel': {
      'hi': 'पुनर्स्थापना',
      'en': 'Restore',
    },
    'autoBackupTitle': {
      'hi': 'स्वचालित बैकअप',
      'en': 'Auto Backup',
    },
    'autoBackupDesc': {
      'hi': 'दैनिक स्वचालित बैकअप। आपके नए संदेश सुरक्षित रूप से सहेजे जाते हैं।',
      'en': 'Daily automatic backups. Your new messages are saved securely.',
    },
    'passwordProtectedTitle': {
      'hi': 'पासवर्ड सुरक्षित',
      'en': 'Password Protected',
    },
    'passwordProtectedDesc': {
      'hi': 'केवल आपका पासवर्ड बैकअप को अनलॉक कर सकता है। Zarq के पास कोई एक्सेस नहीं।',
      'en': 'Only your password can unlock backups. Zarq has zero access.',
    },
    'crossDeviceTitle': {
      'hi': 'क्रॉस-डिवाइस पुनर्स्थापना',
      'en': 'Cross-Device Restore',
    },
    'crossDeviceDesc': {
      'hi': 'Google Drive से या बैकअप फ़ाइल ट्रांसफर करके नए डिवाइस पर पुनर्स्थापित करें।',
      'en': 'Restore on new device via Google Drive or by transferring backup file.',
    },
    'manualBackupTitle': {
      'hi': 'मैन्युअल बैकअप',
      'en': 'Manual Backup',
    },
    'manualBackupDesc': {
      'hi': 'किसी भी समय एक टैप में तुरंत बैकअप बनाएं। पूर्ण नियंत्रण।',
      'en': 'Create instant backup anytime with one tap. Full control.',
    },
    'localBackupTitle': {
      'hi': 'स्थानीय + क्लाउड',
      'en': 'Local + Cloud',
    },
    'localBackupDesc': {
      'hi': 'डिवाइस पर स्थानीय बैकअप + वैकल्पिक क्लाउड सिंक। आपकी पसंद।',
      'en': 'Local backup on device + optional cloud sync. Your choice.',
    },
    'doubleTapHint': {
      'hi': '🌐 अंग्रेजी में बदलने के लिए डबल टैप करें',
      'en': '🌐 Double tap to convert to Hindi',
    },
  };

  @override
  void initState() {
    super.initState();

    _flowController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();

    _flowAnimation = CurvedAnimation(
      parent: _flowController,
      curve: Curves.easeInOut,
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
              SizedBox(height: isSmallScreen ? 20 : 30),

              // Backup/Restore Flow Animation
              Container(
                height: screenHeight * (isSmallScreen ? 0.45 : 0.5),
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.blueAccent.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _getText('backupFlowTitle'),
                        key: ValueKey('flowTitle_$_isHindi'),
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_flowAnimation, _pulseAnimation]),
                        builder: (context, child) {
                          return CustomPaint(
                            painter: BackupFlowPainter(
                              progress: _flowAnimation.value,
                              pulseValue: _pulseAnimation.value,
                              isHindi: _isHindi,
                            ),
                            child: _buildFlowLabels(isSmallScreen),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: isSmallScreen ? 20 : 30),

              // Feature Cards
              _buildFeatureCard(
                icon: Icons.schedule,
                title: _getText('autoBackupTitle'),
                description: _getText('autoBackupDesc'),
                color: Colors.greenAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.lock_outline,
                title: _getText('passwordProtectedTitle'),
                description: _getText('passwordProtectedDesc'),
                color: Colors.orangeAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.devices,
                title: _getText('crossDeviceTitle'),
                description: _getText('crossDeviceDesc'),
                color: Colors.purpleAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.touch_app,
                title: _getText('manualBackupTitle'),
                description: _getText('manualBackupDesc'),
                color: Colors.cyanAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.sync_alt,
                title: _getText('localBackupTitle'),
                description: _getText('localBackupDesc'),
                color: Colors.pinkAccent,
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

  Widget _buildFlowLabels(bool isSmallScreen) {
    return Stack(
      children: [
        // Backup label (left)
        Positioned(
          left: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('backup_$_isHindi'),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 10,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.upload,
                    color: Colors.white,
                    size: isSmallScreen ? 12 : 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isHindi ? 'बैकअप' : 'Backup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 10 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Restore label (right)
        Positioned(
          right: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('restore_$_isHindi'),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 10,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purpleAccent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download,
                    color: Colors.white,
                    size: isSmallScreen ? 12 : 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getText('restoreLabel'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 10 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
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

class BackupFlowPainter extends CustomPainter {
  final double progress;
  final double pulseValue;
  final bool isHindi;

  BackupFlowPainter({
    required this.progress,
    required this.pulseValue,
    required this.isHindi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isSmall = size.width < 300;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Define positions
    final phoneLeftX = isSmall ? 40.0 : 60.0;
    final phoneRightX = size.width - (isSmall ? 40.0 : 60.0);
    final cloudY = centerY;

    // Animation phases (6 second cycle)
    final phase = (progress * 6) % 6;

    // Draw Phone (left - source)
    _drawPhone(canvas, Offset(phoneLeftX, centerY), Colors.blueAccent, isSmall);

    // Draw Cloud (center)
    _drawCloud(canvas, Offset(centerX, cloudY), isSmall);

    // Draw Phone (right - destination)
    _drawPhone(canvas, Offset(phoneRightX, centerY), Colors.purpleAccent, isSmall);

    // Draw connecting lines
    _drawConnectingLines(canvas, phoneLeftX, phoneRightX, centerX, centerY, isSmall);

    // Backup animation (phase 0-3: left phone → cloud)
    if (phase < 3) {
      final backupProgress = phase / 3;
      _drawBackupFlow(canvas, phoneLeftX, centerX, centerY, backupProgress, isSmall);
    }

    // Restore animation (phase 3-6: cloud → right phone)
    if (phase >= 3) {
      final restoreProgress = (phase - 3) / 3;
      _drawRestoreFlow(canvas, centerX, phoneRightX, centerY, restoreProgress, isSmall);
    }

    // Draw encryption/decryption locks
    _drawLocks(canvas, size, centerX, centerY, phase, isSmall);
  }

  void _drawPhone(Canvas canvas, Offset position, Color color, bool isSmall) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final width = isSmall ? 30.0 : 40.0;
    final height = isSmall ? 50.0 : 65.0;

    // Phone outline
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: width, height: height),
      Radius.circular(isSmall ? 6 : 8),
    );
    canvas.drawRRect(rect, paint);

    // Screen
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: position,
        width: width - (isSmall ? 8 : 10),
        height: height - (isSmall ? 12 : 16),
      ),
      Radius.circular(isSmall ? 4 : 6),
    );
    paint.style = PaintingStyle.fill;
    paint.color = color.withOpacity(0.3);
    canvas.drawRRect(screenRect, paint);

    // Message bubbles
    final bubblePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(position.dx, position.dy - (isSmall ? 10 : 15) + i * (isSmall ? 8 : 12)),
        isSmall ? 2 : 3,
        bubblePaint,
      );
    }
  }

  void _drawCloud(Canvas canvas, Offset position, bool isSmall) {
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;

    final scale = isSmall ? 0.7 : 1.0;

    // Cloud shape
    canvas.drawCircle(Offset(position.dx, position.dy), 18 * scale, paint);
    canvas.drawCircle(Offset(position.dx - 15 * scale, position.dy + 5 * scale), 12 * scale, paint);
    canvas.drawCircle(Offset(position.dx + 15 * scale, position.dy + 5 * scale), 12 * scale, paint);

    // Lock icon on cloud
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

  void _drawConnectingLines(Canvas canvas, double leftX, double rightX,
                            double centerX, double centerY, bool isSmall) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Left phone to cloud
    canvas.drawLine(
      Offset(leftX + (isSmall ? 15 : 20), centerY),
      Offset(centerX - (isSmall ? 25 : 35), centerY),
      paint,
    );

    // Cloud to right phone
    canvas.drawLine(
      Offset(centerX + (isSmall ? 25 : 35), centerY),
      Offset(rightX - (isSmall ? 15 : 20), centerY),
      paint,
    );
  }

  void _drawBackupFlow(Canvas canvas, double startX, double endX,
                       double y, double progress, bool isSmall) {
    final currentX = startX + (endX - startX) * progress;

    // Data packet
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    final size = isSmall ? 14.0 : 18.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(currentX, y), width: size, height: size),
      Radius.circular(isSmall ? 6 : 8),
    );
    canvas.drawRRect(rect, paint);

    // Glow
    paint.color = Colors.greenAccent.withOpacity(0.3);
    canvas.drawCircle(Offset(currentX, y), isSmall ? 12 : 16, paint);

    // Arrow icon
    final arrowPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final arrowPath = Path();
    arrowPath.moveTo(currentX - 4, y - 2);
    arrowPath.lineTo(currentX + 4, y - 2);
    arrowPath.lineTo(currentX, y + 4);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint..style = PaintingStyle.fill);
  }

  void _drawRestoreFlow(Canvas canvas, double startX, double endX,
                        double y, double progress, bool isSmall) {
    final currentX = startX + (endX - startX) * progress;

    // Data packet
    final paint = Paint()
      ..color = Colors.purpleAccent
      ..style = PaintingStyle.fill;

    final size = isSmall ? 14.0 : 18.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(currentX, y), width: size, height: size),
      Radius.circular(isSmall ? 6 : 8),
    );
    canvas.drawRRect(rect, paint);

    // Glow
    paint.color = Colors.purpleAccent.withOpacity(0.3);
    canvas.drawCircle(Offset(currentX, y), isSmall ? 12 : 16, paint);

    // Download icon
    final arrowPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final arrowPath = Path();
    arrowPath.moveTo(currentX, y - 4);
    arrowPath.lineTo(currentX, y + 2);
    arrowPath.moveTo(currentX - 3, y - 1);
    arrowPath.lineTo(currentX, y + 2);
    arrowPath.lineTo(currentX + 3, y - 1);
    canvas.drawPath(arrowPath, arrowPaint);
  }

  void _drawLocks(Canvas canvas, Size size, double centerX, double centerY,
                  double phase, bool isSmall) {
    // Encrypt lock (left side)
    if (phase < 3) {
      _drawLock(canvas, Offset(centerX - (isSmall ? 50 : 70), centerY),
                Colors.orangeAccent, true, isSmall);
    }

    // Decrypt lock (right side)
    if (phase >= 3) {
      _drawLock(canvas, Offset(centerX + (isSmall ? 50 : 70), centerY),
                Colors.amberAccent, false, isSmall);
    }
  }

  void _drawLock(Canvas canvas, Offset position, Color color,
                 bool isLocked, bool isSmall) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final lockSize = isSmall ? 10.0 : 14.0;

    // Lock body
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(position.dx, position.dy + lockSize / 4),
        width: lockSize,
        height: lockSize / 1.5,
      ),
      paint..style = PaintingStyle.fill,
    );

    // Lock shackle
    if (isLocked) {
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(position.dx, position.dy - lockSize / 6),
          width: lockSize * 0.7,
          height: lockSize * 0.7,
        ),
        math.pi,
        math.pi,
        false,
        paint..style = PaintingStyle.stroke,
      );
    } else {
      // Open shackle
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(position.dx + lockSize / 3, position.dy - lockSize / 6),
          width: lockSize * 0.7,
          height: lockSize * 0.7,
        ),
        math.pi,
        math.pi * 0.7,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BackupFlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.isHindi != isHindi;
  }
}
