import 'package:flutter/material.dart';
import 'dart:math' as math;

class TutorialChatScreen extends StatefulWidget {
  const TutorialChatScreen({super.key});

  @override
  State<TutorialChatScreen> createState() => _TutorialChatScreenState();
}

class _TutorialChatScreenState extends State<TutorialChatScreen>
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
      'hi': 'दोस्त खोजें और चैट करें',
      'en': 'Find Friends & Chat',
    },
    'title': {
      'hi': 'सामाजिक कनेक्शन',
      'en': 'Social Connections',
    },
    'subtitle': {
      'hi': 'दोस्त खोजें, अनुरोध भेजें, और सुरक्षित चैट करें',
      'en': 'Find friends, send requests, and chat securely',
    },
    'connectionFlowTitle': {
      'hi': 'दोस्ती प्रक्रिया',
      'en': 'Friendship Process',
    },
    'searchUsernameTitle': {
      'hi': 'यूज़रनेम से खोजें',
      'en': 'Search by Username',
    },
    'searchUsernameDesc': {
      'hi': 'किसी भी उपयोगकर्ता को उनके यूज़रनेम से खोजें और अनुरोध भेजें।',
      'en': 'Find any user by their username and send request.',
    },
    'importContactsTitle': {
      'hi': 'संपर्क आयात करें',
      'en': 'Import Contacts',
    },
    'importContactsDesc': {
      'hi': 'अपने फ़ोन संपर्कों से उपयोगकर्ताओं को खोजें और तुरंत अनुरोध भेजें।',
      'en': 'Find users from your phone contacts and send requests instantly.',
    },
    'friendRequestsTitle': {
      'hi': 'दोस्त अनुरोध प्रणाली',
      'en': 'Friend Requests System',
    },
    'friendRequestsDesc': {
      'hi': 'अनुरोध भेजें और प्राप्त करें। स्वीकार करने के बाद चैट शुरू करें।',
      'en': 'Send and receive requests. Start chatting after acceptance.',
    },
    'myFriendsTitle': {
      'hi': 'मेरे दोस्त टैब',
      'en': 'My Friends Tab',
    },
    'myFriendsDesc': {
      'hi': '500 तक दोस्त जोड़ें। लंबे दबाकर विकल्प देखें।',
      'en': 'Add up to 500 friends. Long press for options.',
    },
    'longPressTitle': {
      'hi': 'लंबा दबाएं क्रियाएं',
      'en': 'Long Press Actions',
    },
    'longPressDesc': {
      'hi': 'दोस्त कार्ड पर लंबा दबाएं: बातचीत खोलें या दोस्त हटाएं।',
      'en': 'Long press friend card: Open conversation or remove friend.',
    },
    'createGroupTitle': {
      'hi': 'ग्रुप बनाएं',
      'en': 'Create Groups',
    },
    'createGroupDesc': {
      'hi': 'अपने दोस्तों के साथ ग्रुप बनाएं। 100 तक सदस्य जोड़ें।',
      'en': 'Create groups with your friends. Add up to 100 members.',
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
      duration: const Duration(seconds: 8),
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

              // Connection Flow Animation
              Container(
                height: screenHeight * (isSmallScreen ? 0.45 : 0.5),
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _getText('connectionFlowTitle'),
                        key: ValueKey('flowTitle_$_isHindi'),
                        style: TextStyle(
                          color: Colors.greenAccent,
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
                            painter: ConnectionFlowPainter(
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
                icon: Icons.search,
                title: _getText('searchUsernameTitle'),
                description: _getText('searchUsernameDesc'),
                color: Colors.blueAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.contacts,
                title: _getText('importContactsTitle'),
                description: _getText('importContactsDesc'),
                color: Colors.orangeAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.person_add_alt_1,
                title: _getText('friendRequestsTitle'),
                description: _getText('friendRequestsDesc'),
                color: Colors.purpleAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.people,
                title: _getText('myFriendsTitle'),
                description: _getText('myFriendsDesc'),
                color: Colors.cyanAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.touch_app,
                title: _getText('longPressTitle'),
                description: _getText('longPressDesc'),
                color: Colors.pinkAccent,
                isSmallScreen: isSmallScreen,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              _buildFeatureCard(
                icon: Icons.group_add,
                title: _getText('createGroupTitle'),
                description: _getText('createGroupDesc'),
                color: Colors.greenAccent,
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
        // Search label (top left)
        Positioned(
          left: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('search_$_isHindi'),
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 10,
                vertical: isSmallScreen ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search,
                    color: Colors.white,
                    size: isSmallScreen ? 12 : 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isHindi ? 'खोजें' : 'Search',
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
        // Accept label (top right)
        Positioned(
          right: isSmallScreen ? 5 : 10,
          top: isSmallScreen ? 5 : 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey('accept_$_isHindi'),
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
                    Icons.check_circle,
                    color: Colors.white,
                    size: isSmallScreen ? 12 : 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isHindi ? 'स्वीकार' : 'Accept',
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

class ConnectionFlowPainter extends CustomPainter {
  final double progress;
  final double pulseValue;
  final bool isHindi;

  ConnectionFlowPainter({
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
    final userLeftX = isSmall ? 40.0 : 60.0;
    final userRightX = size.width - (isSmall ? 40.0 : 60.0);

    // Animation phases (8 second cycle)
    final phase = (progress * 8) % 8;

    // Draw Users
    _drawUser(canvas, Offset(userLeftX, centerY), Colors.blueAccent, isSmall, 'Raj');
    _drawUser(canvas, Offset(userRightX, centerY), Colors.purpleAccent, isSmall, 'Arjun');

    // Draw connecting line
    _drawConnectingLine(canvas, userLeftX, userRightX, centerY, isSmall);

    // Phase 1 (0-2): Send friend request (left → right)
    if (phase < 2) {
      final requestProgress = phase / 2;
      _drawFriendRequest(canvas, userLeftX, userRightX, centerY, requestProgress, isSmall, true);
    }

    // Phase 2 (2-4): Accept request (right side)
    if (phase >= 2 && phase < 4) {
      _drawAcceptButton(canvas, Offset(userRightX, centerY - (isSmall ? 40 : 50)), isSmall);
    }

    // Phase 3 (4-6): Friend cards appear
    if (phase >= 4 && phase < 6) {
      _drawFriendCards(canvas, size, centerX, centerY, isSmall);
    }

    // Phase 4 (6-8): Long press menu & chat
    if (phase >= 6) {
      _drawLongPressMenu(canvas, Offset(centerX, centerY), isSmall);
      final chatProgress = (phase - 6) / 2;
      _drawChatBubbles(canvas, centerX, centerY, chatProgress, isSmall);
    }
  }

  void _drawUser(Canvas canvas, Offset position, Color color, bool isSmall, String name) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // User circle
    canvas.drawCircle(position, isSmall ? 25 : 30, paint);

    // User icon
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Head
    canvas.drawCircle(
      Offset(position.dx, position.dy - (isSmall ? 5 : 8)),
      isSmall ? 6 : 8,
      iconPaint,
    );

    // Body (half circle)
    final bodyRect = Rect.fromCenter(
      center: Offset(position.dx, position.dy + (isSmall ? 8 : 12)),
      width: isSmall ? 18 : 24,
      height: isSmall ? 14 : 18,
    );
    canvas.drawArc(bodyRect, 0, math.pi, false, iconPaint);

    // Name label
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: color,
          fontSize: isSmall ? 10 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy + (isSmall ? 32 : 38),
      ),
    );
  }

  void _drawConnectingLine(Canvas canvas, double leftX, double rightX, double y, bool isSmall) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(leftX + (isSmall ? 25 : 30), y),
      Offset(rightX - (isSmall ? 25 : 30), y),
      paint,
    );
  }

  void _drawFriendRequest(Canvas canvas, double fromX, double toX, double y,
                          double progress, bool isSmall, bool isRequest) {
    final currentX = fromX + (toX - fromX) * progress;

    // Request icon
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    final size = isSmall ? 16.0 : 20.0;
    canvas.drawCircle(Offset(currentX, y), size / 2, paint);

    // Glow
    paint.color = Colors.greenAccent.withOpacity(0.3);
    canvas.drawCircle(Offset(currentX, y), size * 0.8, paint);

    // Person add icon
    final iconPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(currentX - 2, y - 2), 3, iconPaint);
    canvas.drawLine(
      Offset(currentX + 2, y),
      Offset(currentX + 5, y),
      iconPaint,
    );
  }

  void _drawAcceptButton(Canvas canvas, Offset position, bool isSmall) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    final width = isSmall ? 50.0 : 60.0;
    final height = isSmall ? 24.0 : 28.0;

    // Button
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: width, height: height),
      Radius.circular(isSmall ? 12 : 14),
    );
    canvas.drawRRect(rect, paint);

    // Check icon
    final checkPaint = Paint()
      ..color = const Color(0xFF0a1128)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final checkPath = Path();
    checkPath.moveTo(position.dx - 8, position.dy);
    checkPath.lineTo(position.dx - 4, position.dy + 4);
    checkPath.lineTo(position.dx + 8, position.dy - 6);
    canvas.drawPath(checkPath, checkPaint);
  }

  void _drawFriendCards(Canvas canvas, Size size, double centerX, double centerY, bool isSmall) {
    final cardWidth = isSmall ? 70.0 : 90.0;
    final cardHeight = isSmall ? 50.0 : 65.0;

    // Left card (Raj)
    _drawFriendCard(
      canvas,
      Offset(centerX - (isSmall ? 50 : 60), centerY),
      cardWidth,
      cardHeight,
      Colors.blueAccent,
      'Raj',
      isSmall,
    );

    // Right card (Arjun)
    _drawFriendCard(
      canvas,
      Offset(centerX + (isSmall ? 50 : 60), centerY),
      cardWidth,
      cardHeight,
      Colors.purpleAccent,
      'Arjun',
      isSmall,
    );
  }

  void _drawFriendCard(Canvas canvas, Offset position, double width, double height,
                       Color color, String name, bool isSmall) {
    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Card background
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: width, height: height),
      Radius.circular(isSmall ? 8 : 12),
    );
    canvas.drawRRect(rect, paint);

    // Border
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.color = color;
    canvas.drawRRect(rect, paint);

    // User icon
    canvas.drawCircle(
      Offset(position.dx, position.dy - (isSmall ? 8 : 10)),
      isSmall ? 8 : 10,
      Paint()..color = color..style = PaintingStyle.fill,
    );

    // Name
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: Colors.white,
          fontSize: isSmall ? 9 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy + (isSmall ? 8 : 12),
      ),
    );
  }

  void _drawLongPressMenu(Canvas canvas, Offset position, bool isSmall) {
    final menuWidth = isSmall ? 100.0 : 120.0;
    final menuHeight = isSmall ? 60.0 : 75.0;

    final paint = Paint()
      ..color = const Color(0xFF1a2a4a)
      ..style = PaintingStyle.fill;

    // Menu background
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: menuWidth, height: menuHeight),
      Radius.circular(isSmall ? 8 : 10),
    );
    canvas.drawRRect(rect, paint);

    // Border
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    paint.color = Colors.cyanAccent;
    canvas.drawRRect(rect, paint);

    // Chat icon
    final chatPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(position.dx, position.dy - (isSmall ? 12 : 15)),
      isSmall ? 6 : 8,
      chatPaint,
    );

    // Remove icon
    final removePaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(position.dx, position.dy + (isSmall ? 12 : 15)),
      isSmall ? 6 : 8,
      removePaint,
    );
  }

  void _drawChatBubbles(Canvas canvas, double centerX, double centerY,
                        double progress, bool isSmall) {
    final bubbleSize = isSmall ? 12.0 : 16.0;
    final spacing = isSmall ? 20.0 : 25.0;

    final paint = Paint()..style = PaintingStyle.fill;

    // Left bubbles (sent)
    if (progress > 0.3) {
      paint.color = Colors.blueAccent;
      _drawBubble(canvas, Offset(centerX - spacing, centerY - spacing), bubbleSize, paint);
    }

    // Right bubbles (received)
    if (progress > 0.6) {
      paint.color = Colors.purpleAccent;
      _drawBubble(canvas, Offset(centerX + spacing, centerY + spacing), bubbleSize, paint);
    }
  }

  void _drawBubble(Canvas canvas, Offset position, double size, Paint paint) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: size * 1.5, height: size),
      Radius.circular(size / 2),
    );
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(ConnectionFlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.isHindi != isHindi;
  }
}
