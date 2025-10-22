import 'package:flutter/material.dart';
import 'dart:math';

class TutorialAIScreen extends StatefulWidget {
  const TutorialAIScreen({Key? key}) : super(key: key);

  @override
  State<TutorialAIScreen> createState() => _TutorialAIScreenState();
}

class _TutorialAIScreenState extends State<TutorialAIScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  String _currentLanguage = 'hi'; // Default Hindi

  final Map<String, Map<String, String>> _content = {
    'title': {
      'hi': 'AI से शक्तिशाली बनें',
      'en': 'Supercharge with AI',
    },
    'subtitle': {
      'hi': 'Gemini 2.5 Flash द्वारा संचालित - आपकी बातचीत को बेहतर बनाएं',
      'en': 'Powered by Gemini 2.5 Flash - Enhance your conversations',
    },
    'separateAITitle': {
      'hi': 'समर्पित AI चैट',
      'en': 'Dedicated AI Chat',
    },
    'separateAIDesc': {
      'hi':
          'टर्मिनल मोड (हैकर-स्टाइल) या सिंपल मोड (साफ़-सुथरा) में AI के साथ बात करें।',
      'en':
          'Chat with AI in Terminal Mode (hacker-style) or Simple Mode (clean interface).',
    },
    'aiModeTitle': {
      'hi': 'नॉर्मल चैट में AI MODE',
      'en': 'AI MODE in Normal Chats',
    },
    'aiModeDesc': {
      'hi':
          'इनपुट फील्ड में AI बटन क्लिक करें। अब संदेश पर टैप करें - अनुवाद, सारांश या व्याख्या करें।',
      'en':
          'Click AI button in input field. Now tap message - Translate, Summarize or Explain.',
    },
    'magicButtonTitle': {
      'hi': 'मैजिक टेक्स्ट सुधार',
      'en': 'Magic Text Improvement',
    },
    'magicButtonDesc': {
      'hi':
          'AI MODE में टाइप करें → पीले मैजिक बटन पर क्लिक करें → Formal/Casual/Concise/Fix Grammar।',
      'en':
          'Type in AI MODE → Click yellow magic button → Formal/Casual/Concise/Fix Grammar.',
    },
    'languageTitle': {
      'hi': 'भाषा चुनाव',
      'en': 'Language Selection',
    },
    'languageDesc': {
      'hi':
          'सभी AI प्रतिक्रियाओं के लिए अपनी पसंदीदा भाषा चुनें। 15+ भाषाएं समर्थित।',
      'en':
          'Choose your preferred language for all AI responses. 15+ languages supported.',
    },
    'privacyWarningTitle': {
      'hi': '⚠️ गोपनीयता नोट',
      'en': '⚠️ Privacy Note',
    },
    'privacyWarningDesc': {
      'hi':
          'AI सुविधाएं E2EE को बायपास करती हैं। आपके चयनित संदेश Gemini सर्वर पर जाते हैं।',
      'en':
          'AI features bypass E2EE. Your selected messages go to Gemini server.',
    },
    'toggleHint': {
      'hi': '🌐 Double tap to convert',
      'en': '🌐 Double tap to convert',
    },
  };

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleLanguage() {
    setState(() {
      _currentLanguage = _currentLanguage == 'hi' ? 'en' : 'hi';
    });
  }

  String _getText(String key) {
    return _content[key]?[_currentLanguage] ?? '';
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
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 24,
                vertical: isSmallScreen ? 16 : 20,
              ),
              child: Column(
                children: [
                  // Title
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _getText('title'),
                      key: ValueKey('title_$_currentLanguage'),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 26 : (isMediumScreen ? 28 : 32),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),

                  // Subtitle
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _getText('subtitle'),
                      key: ValueKey('subtitle_$_currentLanguage'),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : (isMediumScreen ? 13 : 14),
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 20 : 24),

                  // Animation
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        size: Size(
                          screenWidth - (isSmallScreen ? 32 : 48),
                          isSmallScreen ? 280 : (isMediumScreen ? 320 : 360),
                        ),
                        painter: AIAnimationPainter(
                          progress: _controller.value,
                        ),
                      );
                    },
                  ),
                  SizedBox(height: isSmallScreen ? 20 : 24),

                  // Feature Cards
                  _buildFeatureCard(
                    'separateAITitle',
                    'separateAIDesc',
                    Icons.terminal,
                    Colors.green,
                    isSmallScreen,
                    isMediumScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  _buildFeatureCard(
                    'aiModeTitle',
                    'aiModeDesc',
                    Icons.psychology,
                    Colors.blue,
                    isSmallScreen,
                    isMediumScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  _buildFeatureCard(
                    'magicButtonTitle',
                    'magicButtonDesc',
                    Icons.auto_fix_high,
                    Colors.amber,
                    isSmallScreen,
                    isMediumScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  _buildFeatureCard(
                    'languageTitle',
                    'languageDesc',
                    Icons.language,
                    Colors.purple,
                    isSmallScreen,
                    isMediumScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  // Privacy Warning Card
                  _buildWarningCard(
                    'privacyWarningTitle',
                    'privacyWarningDesc',
                    Icons.warning_amber_rounded,
                    isSmallScreen,
                    isMediumScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 20),

                  // Toggle hint
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _getText('toggleHint'),
                      key: ValueKey('toggleHint_$_currentLanguage'),
                      style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 12,
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    String titleKey,
    String descKey,
    IconData icon,
    Color iconColor,
    bool isSmallScreen,
    bool isMediumScreen,
  ) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('${titleKey}_$_currentLanguage'),
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: iconColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: isSmallScreen ? 20 : 24,
              ),
            ),
            SizedBox(width: isSmallScreen ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getText(titleKey),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : (isMediumScreen ? 15 : 16),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),
                  Text(
                    _getText(descKey),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : (isMediumScreen ? 12 : 13),
                      color: Colors.white70,
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

  Widget _buildWarningCard(
    String titleKey,
    String descKey,
    IconData icon,
    bool isSmallScreen,
    bool isMediumScreen,
  ) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('${titleKey}_$_currentLanguage'),
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.orange.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: Colors.orange,
              size: isSmallScreen ? 24 : 28,
            ),
            SizedBox(width: isSmallScreen ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getText(titleKey),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : (isMediumScreen ? 15 : 16),
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),
                  Text(
                    _getText(descKey),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : (isMediumScreen ? 12 : 13),
                      color: Colors.white70,
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

class AIAnimationPainter extends CustomPainter {
  final double progress;

  AIAnimationPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // 12-second animation cycle
    // Phase 1 (0-3s): Show separate AI chat with Terminal/Simple toggle
    // Phase 2 (3-6s): Show AI MODE button in normal chat
    // Phase 3 (6-9s): Show message tap → bottom sheet (Translate/Summarize/Explain)
    // Phase 4 (9-12s): Show magic button for text improvement

    final phase = (progress * 12) % 12;

    // Draw modern phone mockup
    _drawModernPhone(canvas, size);

    if (phase < 3) {
      _drawPhase1(canvas, size, phase / 3);
    } else if (phase < 6) {
      _drawPhase2(canvas, size, (phase - 3) / 3);
    } else if (phase < 9) {
      _drawPhase3(canvas, size, (phase - 6) / 3);
    } else {
      _drawPhase4(canvas, size, (phase - 9) / 3);
    }
  }

  void _drawModernPhone(Canvas canvas, Size size) {
    final paint = Paint();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final phoneWidth = size.width * 0.75;
    final phoneHeight = size.height * 0.85;

    // Shadow
    final shadowPath = Path();
    shadowPath.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX + 3, centerY + 5),
          width: phoneWidth,
          height: phoneHeight,
        ),
        const Radius.circular(30),
      ),
    );
    paint
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(shadowPath, paint);

    // Phone body
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: phoneWidth,
        height: phoneHeight,
      ),
      const Radius.circular(30),
    );
    paint
      ..color = const Color(0xFF0f1419)
      ..maskFilter = null;
    canvas.drawRRect(phoneRect, paint);

    // Phone border (subtle gradient effect)
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withOpacity(0.15);
    canvas.drawRRect(phoneRect, paint);

    // Notch
    final notchRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY - phoneHeight / 2 + 10),
        width: phoneWidth * 0.3,
        height: 6,
      ),
      const Radius.circular(3),
    );
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.black.withOpacity(0.8);
    canvas.drawRRect(notchRect, paint);
  }

  // Phase 1: Separate AI chat screen with Terminal/Simple toggle
  void _drawPhase1(Canvas canvas, Size size, double phaseProgress) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final phoneWidth = size.width * 0.75;
    final phoneHeight = size.height * 0.85;

    // Screen content area
    final contentTop = centerY - phoneHeight / 2 + 30;
    final contentBottom = centerY + phoneHeight / 2 - 20;
    final contentLeft = centerX - phoneWidth / 2 + 15;
    final contentRight = centerX + phoneWidth / 2 - 15;

    // Modern toggle switch at top
    final toggleY = contentTop + 25;
    final toggleWidth = phoneWidth * 0.5;
    final toggleHeight = 40.0;

    // Toggle background
    final toggleBg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, toggleY),
        width: toggleWidth,
        height: toggleHeight,
      ),
      const Radius.circular(20),
    );
    paint.color = const Color(0xFF1c1f26);
    canvas.drawRRect(toggleBg, paint);

    // Animated slider
    final sliderOffset = phaseProgress < 0.5
        ? -(toggleWidth / 4)
        : (toggleWidth / 4);
    final sliderX = centerX + (sliderOffset * (phaseProgress < 0.5 ? (1 - phaseProgress * 2) : (phaseProgress - 0.5) * 2)) + (phaseProgress >= 0.5 ? sliderOffset : 0);

    final slider = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(sliderX, toggleY),
        width: toggleWidth / 2 - 4,
        height: toggleHeight - 6,
      ),
      const Radius.circular(17),
    );

    // Gradient for active toggle
    final gradient = LinearGradient(
      colors: phaseProgress < 0.5
          ? [const Color(0xFF00FF41), const Color(0xFF00CC33)]
          : [const Color(0xFF2196F3), const Color(0xFF1976D2)],
    );
    paint.shader = gradient.createShader(slider.outerRect);
    canvas.drawRRect(slider, paint);
    paint.shader = null;

    // Labels
    _drawCleanText(canvas, 'Terminal', centerX - toggleWidth / 4, toggleY,
        phaseProgress < 0.5 ? Colors.white : Colors.white38, 11);
    _drawCleanText(canvas, 'Simple', centerX + toggleWidth / 4, toggleY,
        phaseProgress >= 0.5 ? Colors.white : Colors.white38, 11);

    // Content area based on mode
    final contentY = contentTop + 80;

    if (phaseProgress < 0.5) {
      // Terminal Mode - Modern terminal UI
      final terminalRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          contentLeft,
          contentY,
          contentRight,
          contentBottom - 60,
        ),
        const Radius.circular(12),
      );

      // Terminal background with subtle gradient
      paint.color = const Color(0xFF0a0e14);
      canvas.drawRRect(terminalRect, paint);

      // Terminal header bar
      final headerRect = Rect.fromLTRB(contentLeft, contentY, contentRight, contentY + 35);
      paint.color = const Color(0xFF0D1117);
      canvas.drawRect(headerRect, paint);

      // Terminal title
      _drawCleanText(canvas, 'ZARQ AI TERMINAL', centerX, contentY + 17,
          const Color(0xFF00FF41), 10, bold: true);

      // Terminal prompt with cursor animation
      final promptY = contentY + 60;
      final cursorOpacity = (sin((phaseProgress * 20) * pi) + 1) / 2;

      _drawLeftAlignText(canvas, '> User: Hello AI', contentLeft + 12, promptY,
          const Color(0xFF00FF41), 9.5);
      _drawLeftAlignText(canvas, '> AI: Hello! How can I', contentLeft + 12, promptY + 25,
          const Color(0xFF00DD3A), 9.5);
      _drawLeftAlignText(canvas, '  assist you today?', contentLeft + 12, promptY + 45,
          const Color(0xFF00DD3A), 9.5);

      // Blinking cursor
      paint.color = Color.fromRGBO(0, 255, 65, cursorOpacity);
      canvas.drawRect(
        Rect.fromLTWH(contentLeft + 12, promptY + 58, 8, 12),
        paint,
      );

    } else {
      // Simple Mode - Clean chat interface
      final chatY = contentY + 20;

      // User message (right)
      final userBubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          contentRight - 110,
          chatY,
          100,
          45,
        ),
        const Radius.circular(20),
      );
      paint.color = const Color(0xFF2196F3);
      canvas.drawRRect(userBubble, paint);

      // Subtle shadow
      paint
        ..color = Colors.black.withOpacity(0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawRRect(userBubble.shift(const Offset(0, 2)), paint);
      paint.maskFilter = null;

      _drawCleanText(canvas, 'Hello', contentRight - 60, chatY + 22, Colors.white, 10);

      // AI response (left)
      final aiBubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          contentLeft + 10,
          chatY + 65,
          130,
          55,
        ),
        const Radius.circular(20),
      );
      paint.color = const Color(0xFF2a2d35);
      canvas.drawRRect(aiBubble, paint);

      _drawLeftAlignText(canvas, 'Hello! How can', contentLeft + 20, chatY + 80,
          Colors.white, 9.5);
      _drawLeftAlignText(canvas, 'I help you today?', contentLeft + 20, chatY + 100,
          Colors.white, 9.5);

      // AI icon
      paint.color = const Color(0xFF2196F3);
      canvas.drawCircle(Offset(contentLeft + 20, chatY + 70), 5, paint);
    }

    // "Powered by Gemini" badge at bottom
    _drawCleanText(canvas, 'Powered by Gemini Pro', centerX, contentBottom - 30,
        Colors.white24, 8.5);
  }

  // Phase 2: AI MODE button in normal chat
  void _drawPhase2(Canvas canvas, Size size, double phaseProgress) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final phoneWidth = size.width * 0.75;
    final phoneHeight = size.height * 0.85;

    final contentTop = centerY - phoneHeight / 2 + 30;
    final contentBottom = centerY + phoneHeight / 2 - 20;
    final contentLeft = centerX - phoneWidth / 2 + 15;
    final contentRight = centerX + phoneWidth / 2 - 15;

    // Header with contact name
    _drawCleanText(canvas, 'Raj', centerX, contentTop + 15, Colors.white, 12, bold: true);

    // Friend's message
    final messageY = contentTop + 60;
    final msgBubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(contentLeft + 5, messageY, 140, 48),
      const Radius.circular(18),
    );
    paint.color = const Color(0xFF2a2d35);
    canvas.drawRRect(msgBubble, paint);

    _drawLeftAlignText(canvas, 'Hey! How are you?', contentLeft + 18, messageY + 24,
        Colors.white, 10);

    // Input field at bottom
    final inputY = contentBottom - 60;
    final inputRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(contentLeft, inputY, contentRight - contentLeft, 50),
      const Radius.circular(25),
    );
    paint.color = const Color(0xFF1c1f26);
    canvas.drawRRect(inputRect, paint);

    // AI button with animation
    final aiButtonOpacity = (phaseProgress * 2).clamp(0.0, 1.0);
    final aiButtonX = contentLeft + 12;
    final aiButtonY = inputY + 12;

    if (phaseProgress < 0.5) {
      // AI button appearing
      final scale = aiButtonOpacity;
      final aiButton = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(aiButtonX + 30 * scale, aiButtonY + 13),
          width: 60 * scale,
          height: 26 * scale,
        ),
        const Radius.circular(13),
      );

      final gradient = const LinearGradient(
        colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
      );
      paint.shader = gradient.createShader(aiButton.outerRect);
      canvas.drawRRect(aiButton, paint);
      paint.shader = null;

      if (scale > 0.3) {
        _drawCleanText(canvas, 'AI', aiButtonX + 30 * scale, aiButtonY + 13,
            Colors.white.withOpacity(scale), 9.5, bold: true);
      }
    } else {
      // AI MODE ON indicator
      final indicatorWidth = 120.0;
      final indicator = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(contentLeft + indicatorWidth / 2 + 10, aiButtonY + 13),
          width: indicatorWidth,
          height: 30,
        ),
        const Radius.circular(15),
      );

      // Glowing effect
      paint
        ..color = const Color(0xFF00FF41).withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(indicator, paint);
      paint.maskFilter = null;

      paint.color = const Color(0xFF00FF41).withOpacity(0.2);
      canvas.drawRRect(indicator, paint);

      // Icon
      paint.color = const Color(0xFF00FF41);
      canvas.drawCircle(Offset(contentLeft + 25, aiButtonY + 13), 6, paint);

      _drawCleanText(canvas, 'AI MODE ON', contentLeft + indicatorWidth / 2 + 20,
          aiButtonY + 13, const Color(0xFF00FF41), 9.5, bold: true);
    }
  }

  // Phase 3: Message tap → bottom sheet (Translate/Summarize/Explain)
  void _drawPhase3(Canvas canvas, Size size, double phaseProgress) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final phoneWidth = size.width * 0.75;
    final phoneHeight = size.height * 0.85;

    final contentTop = centerY - phoneHeight / 2 + 30;
    final contentBottom = centerY + phoneHeight / 2 - 20;
    final contentLeft = centerX - phoneWidth / 2 + 15;

    // Message being tapped
    final messageY = contentTop + 80;
    final messageBubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(contentLeft + 5, messageY, 160, 70),
      const Radius.circular(18),
    );

    // Tap highlight effect
    if (phaseProgress < 0.3) {
      final highlightOpacity = (0.3 - phaseProgress) / 0.3;
      paint
        ..color = const Color(0xFF2196F3).withOpacity(0.3 * highlightOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(messageBubble, paint);
      paint.maskFilter = null;
    }

    paint.color = const Color(0xFF2a2d35);
    canvas.drawRRect(messageBubble, paint);

    _drawLeftAlignText(canvas, 'This is a long', contentLeft + 18, messageY + 20,
        Colors.white, 9.5);
    _drawLeftAlignText(canvas, 'message that needs', contentLeft + 18, messageY + 38,
        Colors.white, 9.5);
    _drawLeftAlignText(canvas, 'translation', contentLeft + 18, messageY + 56,
        Colors.white, 9.5);

    // Bottom sheet sliding up
    if (phaseProgress > 0.2) {
      final sheetProgress = ((phaseProgress - 0.2) / 0.8).clamp(0.0, 1.0);
      final easeProgress = _easeOutCubic(sheetProgress);
      final sheetHeight = 180.0;
      final sheetY = contentBottom - (sheetHeight * easeProgress);

      // Sheet shadow
      paint
        ..color = Colors.black.withOpacity(0.3 * easeProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(contentLeft - 5, sheetY + 3, phoneWidth - 20, sheetHeight),
          const Radius.circular(20),
        ),
        paint,
      );
      paint.maskFilter = null;

      // Sheet background
      final sheetRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(contentLeft - 5, sheetY, phoneWidth - 20, sheetHeight),
        const Radius.circular(20),
      );
      paint.color = const Color(0xFF1c1f26);
      canvas.drawRRect(sheetRect, paint);

      // Handle bar
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, sheetY + 12),
          width: 40,
          height: 4,
        ),
        const Radius.circular(2),
      );
      paint.color = Colors.white.withOpacity(0.2);
      canvas.drawRRect(handleRect, paint);

      // Options
      final optionY = sheetY + 35;
      _drawModernOption(canvas, paint, contentLeft + 5, optionY, phoneWidth - 30,
          'Translate', const Color(0xFF2196F3), Icons.translate.codePoint);
      _drawModernOption(canvas, paint, contentLeft + 5, optionY + 50, phoneWidth - 30,
          'Summarize', const Color(0xFF4CAF50), Icons.summarize.codePoint);
      _drawModernOption(canvas, paint, contentLeft + 5, optionY + 100, phoneWidth - 30,
          'Explain', const Color(0xFFFF9800), Icons.lightbulb.codePoint);
    }
  }

  // Phase 4: Magic button for text improvement
  void _drawPhase4(Canvas canvas, Size size, double phaseProgress) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final phoneWidth = size.width * 0.75;
    final phoneHeight = size.height * 0.85;

    final contentTop = centerY - phoneHeight / 2 + 30;
    final contentBottom = centerY + phoneHeight / 2 - 20;
    final contentLeft = centerX - phoneWidth / 2 + 15;
    final contentRight = centerX + phoneWidth / 2 - 15;

    // AI MODE indicator at top
    final indicatorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, contentTop + 20),
        width: 120,
        height: 28,
      ),
      const Radius.circular(14),
    );
    paint.color = const Color(0xFF00FF41).withOpacity(0.15);
    canvas.drawRRect(indicatorRect, paint);

    paint.color = const Color(0xFF00FF41);
    canvas.drawCircle(Offset(centerX - 40, contentTop + 20), 5, paint);

    _drawCleanText(canvas, 'AI MODE ON', centerX + 10, contentTop + 20,
        const Color(0xFF00FF41), 9.5, bold: true);

    // Input field
    final inputY = contentBottom - 65;
    final inputRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(contentLeft, inputY, contentRight - contentLeft, 50),
      const Radius.circular(25),
    );
    paint.color = const Color(0xFF1c1f26);
    canvas.drawRRect(inputRect, paint);

    // Input text
    _drawLeftAlignText(canvas, 'hey can u help me', contentLeft + 15, inputY + 25,
        Colors.white70, 10);

    // Magic button (animated)
    final magicButtonOpacity = phaseProgress < 0.3 ? (phaseProgress / 0.3) : 1.0;
    final pulseScale = 1.0 + (0.15 * sin((phaseProgress * 12) * pi));
    final magicButtonSize = 36.0 * pulseScale;
    final magicX = contentRight - 50;
    final magicY = inputY + 25;

    // Glowing rings
    for (int i = 2; i >= 0; i--) {
      paint
        ..color = Colors.amber.withOpacity(0.15 * magicButtonOpacity / (i + 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + i * 2.0);
      canvas.drawCircle(
        Offset(magicX, magicY),
        magicButtonSize / 2 + 6 + (i * 4),
        paint,
      );
    }
    paint.maskFilter = null;

    // Button with gradient
    final magicGradient = const RadialGradient(
      colors: [Color(0xFFFFD740), Color(0xFFFFA000)],
    );
    paint.shader = magicGradient.createShader(
      Rect.fromCircle(center: Offset(magicX, magicY), radius: magicButtonSize / 2),
    );
    canvas.drawCircle(Offset(magicX, magicY), magicButtonSize / 2, paint);
    paint.shader = null;

    // Star icon
    _drawStar(canvas, Offset(magicX, magicY), magicButtonSize / 3.5,
        paint..color = Colors.white);

    // Bottom sheet
    if (phaseProgress > 0.3) {
      final sheetProgress = ((phaseProgress - 0.3) / 0.7).clamp(0.0, 1.0);
      final easeProgress = _easeOutCubic(sheetProgress);
      final sheetHeight = 210.0;
      final sheetY = contentBottom - (sheetHeight * easeProgress);

      // Shadow
      paint
        ..color = Colors.black.withOpacity(0.3 * easeProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(contentLeft - 5, sheetY + 3, phoneWidth - 20, sheetHeight),
          const Radius.circular(20),
        ),
        paint,
      );
      paint.maskFilter = null;

      // Sheet background
      final sheetRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(contentLeft - 5, sheetY, phoneWidth - 20, sheetHeight),
        const Radius.circular(20),
      );
      paint.color = const Color(0xFF1c1f26);
      canvas.drawRRect(sheetRect, paint);

      // Handle bar
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, sheetY + 12),
          width: 40,
          height: 4,
        ),
        const Radius.circular(2),
      );
      paint.color = Colors.white.withOpacity(0.2);
      canvas.drawRRect(handleRect, paint);

      // Options
      final optionY = sheetY + 35;
      _drawModernOption(canvas, paint, contentLeft + 5, optionY, phoneWidth - 30,
          'Make Formal', const Color(0xFF9C27B0), Icons.business_center.codePoint);
      _drawModernOption(canvas, paint, contentLeft + 5, optionY + 45, phoneWidth - 30,
          'Make Casual', const Color(0xFF2196F3), Icons.emoji_emotions.codePoint);
      _drawModernOption(canvas, paint, contentLeft + 5, optionY + 90, phoneWidth - 30,
          'Make Concise', const Color(0xFF4CAF50), Icons.compress.codePoint);
      _drawModernOption(canvas, paint, contentLeft + 5, optionY + 135, phoneWidth - 30,
          'Fix Grammar', const Color(0xFFFF9800), Icons.spellcheck.codePoint);
    }
  }

  // Helper: Modern option button
  void _drawModernOption(Canvas canvas, Paint paint, double x, double y,
      double width, String text, Color color, int iconCode) {
    final optionRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, 38),
      const Radius.circular(12),
    );

    // Background with subtle gradient
    paint.color = color.withOpacity(0.12);
    canvas.drawRRect(optionRect, paint);

    // Icon container
    final iconCircle = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x + 22, y + 19),
        width: 30,
        height: 30,
      ),
      const Radius.circular(15),
    );
    paint.color = color.withOpacity(0.25);
    canvas.drawRRect(iconCircle, paint);

    // Icon dot
    paint.color = color;
    canvas.drawCircle(Offset(x + 22, y + 19), 5, paint);

    // Text
    _drawLeftAlignText(canvas, text, x + 45, y + 19, Colors.white, 10.5);
  }

  // Helper: Clean centered text
  void _drawCleanText(Canvas canvas, String text, double x, double y,
      Color color, double fontSize, {bool bold = false}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  // Helper: Left-aligned text
  void _drawLeftAlignText(Canvas canvas, String text, double x, double y,
      Color color, double fontSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(x, y - textPainter.height / 2),
    );
  }

  // Helper: Star icon
  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * 36 - 90) * pi / 180;
      final r = (i % 2 == 0) ? radius : radius / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // Helper: Ease out cubic animation
  double _easeOutCubic(double t) {
    return 1 - pow(1 - t, 3).toDouble();
  }

  @override
  bool shouldRepaint(AIAnimationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
