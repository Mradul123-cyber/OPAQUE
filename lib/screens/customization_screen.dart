import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_settings_provider.dart';
import '../widgets/call_aware_screen.dart';
import '../widgets/global_call_overlay.dart';

// Simple bubble option model (no server fetch needed)
class BubbleOption {
  final String resourceKey;
  final String name;

  BubbleOption({required this.resourceKey, required this.name});
}

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  bool _isCircularOverlay = false;

  @override
  void initState() {
    super.initState();
    _loadCallOverlayStyle();
  }

  Future<void> _loadCallOverlayStyle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isCircularOverlay = prefs.getBool('call_overlay_circular') ?? false;
    });
  }

  Future<void> _saveCallOverlayStyle(bool isCircular) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('call_overlay_circular', isCircular);
    setState(() {
      _isCircularOverlay = isCircular;
    });

    // Reload the GlobalCallOverlay style
    GlobalCallOverlay.globalKey.currentState?.reloadStyle();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call overlay style updated!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // Hardcoded bubble style options (no server call needed)
  final List<BubbleOption> _bubbleOptions = [
    BubbleOption(resourceKey: 'default_rounded', name: 'Rounded'),
    BubbleOption(resourceKey: 'soft_edges', name: 'Soft Edges'),
    BubbleOption(resourceKey: 'square', name: 'Square'),
    BubbleOption(resourceKey: 'minimal', name: 'Minimal'),
    BubbleOption(resourceKey: 'modern_card', name: 'Modern Cards'),
  ];

  // Card bubble color options
  final Map<String, Map<String, dynamic>> _cardColorOptions = {
    'blue': {'name': 'Blue', 'color': Color(0xFFE3F2FD), 'border': Color(0xFF90CAF9)},
    'green': {'name': 'Green', 'color': Color(0xFFE8F5E9), 'border': Color(0xFF81C784)},
    'red': {'name': 'Red', 'color': Color(0xFFFFEBEE), 'border': Color(0xFFEF5350)},
    'purple': {'name': 'Purple', 'color': Color(0xFFF3E5F5), 'border': Color(0xFFBA68C8)},
    'orange': {'name': 'Orange', 'color': Color(0xFFFFF3E0), 'border': Color(0xFFFFB74D)},
    'yellow': {'name': 'Yellow', 'color': Color(0xFFFFFDE7), 'border': Color(0xFFFFF176)},
  };

  // Home screen background options - Only Light Theme for now
  final List<Map<String, String>> _homeScreenOptions = [
    {'key': 'default', 'name': 'Light Theme', 'description': 'Clean white background'},
  ];

  // Create Group screen background options
  final List<Map<String, String>> _groupScreenOptions = [
    {'key': 'static', 'name': 'Modern Cards', 'description': 'Colorful card-based UI (Default)'},
    {'key': 'dynamic', 'name': 'Dynamic Leaves', 'description': 'Animated falling leaves'},
  ];

  void _handleSettingChange({String? styleKey, String? colorStart, String? colorEnd, String? homeScreenStyle, String? groupScreenStyle, String? cardBubbleColor}) async {
    final provider = Provider.of<UserSettingsProvider>(context, listen: false);

    // Save to local storage (instant, no network delay)
    await provider.saveSettings(
      styleKey: styleKey,
      colorStart: colorStart,
      colorEnd: colorEnd,
      homeScreenStyle: homeScreenStyle,
      groupScreenStyle: groupScreenStyle,
      cardBubbleColor: cardBubbleColor,
    );

    // Optional: Show brief confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final mainPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final sectionSpacing = (screenHeight * 0.04).clamp(24.0, 40.0);
    final itemSpacing = (screenHeight * 0.02).clamp(12.0, 20.0);

    return CallAwareScreen(
      screenName: 'CustomizationScreen',
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0a1128),
        elevation: 0,
        title: Text('Customization', style: TextStyle(color: Colors.white, fontSize: appBarTitleSize)),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0a1128),
              Color(0xFF1a1f3a),
              Color(0xFF0d1b2a),
              Color(0xFF16213e),
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: SingleChildScrollView(
                padding: EdgeInsets.all(mainPadding),
                child: Consumer<UserSettingsProvider>(
                  builder: (context, userSettings, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section: Message Bubbles
                        _buildSectionHeader(Icons.chat_bubble_outline, 'Message Bubbles'),
                        SizedBox(height: itemSpacing),
                        _buildBubbleStyleCard(userSettings),
                        SizedBox(height: itemSpacing),
                        // Show card color picker only for modern_card style
                        if (userSettings.bubbleStyleKey == 'modern_card')
                          _buildCardColorPicker(userSettings)
                        else
                          _buildBubbleColorCards(userSettings),

                        SizedBox(height: sectionSpacing),

                        // Section: Home Screen
                        _buildSectionHeader(Icons.home_outlined, 'Home Screen'),
                        SizedBox(height: itemSpacing),
                        _buildHomeScreenStyleCard(userSettings),

                        SizedBox(height: sectionSpacing),

                        // Section: Create Group Screen
                        _buildSectionHeader(Icons.group_add, 'Create Group Screen'),
                        SizedBox(height: itemSpacing),
                        _buildGroupScreenStyleCard(userSettings),

                        SizedBox(height: sectionSpacing),

                        // Section: Call Overlay
                        _buildSectionHeader(Icons.phone_in_talk, 'Call Overlay'),
                        SizedBox(height: itemSpacing),
                        _buildCallOverlayStyleCard(),

                        SizedBox(height: sectionSpacing),
                      ],
                    );
                  },
                ),
              ),
      ),
      )
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final fontSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final spacing = (screenWidth * 0.03).clamp(10.0, 14.0);

    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: iconSize),
        SizedBox(width: spacing),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBubbleStyleCard(UserSettingsProvider userSettings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final dropdownFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);

    String? currentValue = userSettings.bubbleStyleKey;

    if (_bubbleOptions.isNotEmpty &&
        !_bubbleOptions.any((option) => option.resourceKey == currentValue)) {
      currentValue = _bubbleOptions.first.resourceKey;
    }

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Bubble Style",
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose the shape of your message bubbles",
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0a1128).withOpacity(0.5),
                borderRadius: BorderRadius.circular(borderRadius * 0.7),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
              ),
              padding: EdgeInsets.symmetric(horizontal: cardPadding),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: currentValue,
                  hint: Text("Select Style", style: TextStyle(color: Colors.white70, fontSize: dropdownFontSize)),
                  dropdownColor: const Color(0xFF0a1128).withOpacity(0.95),
                  style: TextStyle(color: Colors.white, fontSize: dropdownFontSize),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                  items: _bubbleOptions.map((BubbleOption option) {
                    return DropdownMenuItem<String>(
                      value: option.resourceKey,
                      child: Text(option.name),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      _handleSettingChange(styleKey: newValue);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleColorCards(UserSettingsProvider userSettings) {
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing = (screenHeight * 0.015).clamp(10.0, 16.0);

    return Column(
      children: [
        _buildColorCard(
          title: "Bubble Start Color",
          description: "Top gradient color",
          currentColor: userSettings.bubbleColorStart,
          onColorSelected: (color) {
            _handleSettingChange(colorStart: color);
          },
        ),
        SizedBox(height: spacing),
        _buildColorCard(
          title: "Bubble End Color",
          description: "Bottom gradient color",
          currentColor: userSettings.bubbleColorEnd,
          onColorSelected: (color) {
            _handleSettingChange(colorEnd: color);
          },
        ),
      ],
    );
  }

  Widget _buildCardColorPicker(UserSettingsProvider userSettings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final nameFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final wrapSpacing = (screenWidth * 0.03).clamp(10.0, 14.0);
    final cardWidth = (screenWidth * 0.25).clamp(90.0, 120.0);
    final cardHeight = (screenHeight * 0.1).clamp(70.0, 90.0);
    final iconSize = (screenWidth * 0.06).clamp(20.0, 28.0);

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Card Color",
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose the color for your message cards",
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            Wrap(
              spacing: wrapSpacing,
              runSpacing: wrapSpacing,
              children: _cardColorOptions.entries.map((entry) {
                final colorKey = entry.key;
                final colorData = entry.value;
                final isSelected = userSettings.cardBubbleColor == colorKey;

                return GestureDetector(
                  onTap: () {
                    _handleSettingChange(cardBubbleColor: colorKey);
                  },
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: colorData['color'] as Color,
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(
                        color: isSelected
                          ? Colors.cyanAccent
                          : (colorData['border'] as Color),
                        width: isSelected ? 3 : 2,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ] : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: Colors.cyanAccent,
                            size: iconSize,
                          ),
                        SizedBox(height: spacing1 * 0.5),
                        Text(
                          colorData['name'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.black87 : Colors.black54,
                            fontSize: nameFontSize,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCard({
    required String title,
    required String description,
    required String? currentColor,
    required Function(String) onColorSelected,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final spacing1 = (screenHeight * 0.005).clamp(3.0, 6.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final wrapSpacing = (screenWidth * 0.03).clamp(10.0, 14.0);
    final circleSize = (screenWidth * 0.1).clamp(35.0, 50.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);

    // Use the same colors as the original settings screen (6-digit hex WITHOUT '#')
    final Map<String, Color> colorOptions = {
      '667EEA': Colors.blueAccent,   // Default Start
      '764BA2': Colors.deepPurple,   // Default End
      'FF4500': Colors.orangeAccent, // Bright Orange
      '4CAF50': Colors.green,        // Green
      'DC143C': Colors.redAccent,    // Crimson Red
    };

    // Helper to check if a color is selected (case-insensitive comparison)
    bool isSelected(String hex) => hex.toUpperCase() == (currentColor?.toUpperCase() ?? '');

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              description,
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            Wrap(
              spacing: wrapSpacing,
              runSpacing: wrapSpacing,
              children: colorOptions.entries.map((entry) {
                final hex = entry.key;
                final color = entry.value;
                final selected = isSelected(hex);
                return GestureDetector(
                  onTap: () => onColorSelected(hex),
                  child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle, // CIRCLE shape like original!
                      border: Border.all(
                        color: selected ? Colors.cyanAccent : Colors.white24,
                        width: selected ? 3 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: selected
                        ? Icon(Icons.check, color: Colors.white, size: iconSize)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreenStyleCard(UserSettingsProvider userSettings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final optionNameFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final optionDescFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final spacing3 = (screenHeight * 0.015).clamp(10.0, 14.0);
    final spacing4 = (screenHeight * 0.005).clamp(3.0, 6.0);
    final optionPadding = (screenWidth * 0.04).clamp(12.0, 18.0);

    final currentStyle = userSettings.homeScreenStyle ?? 'default';

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Background Style",
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose your home screen background",
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            ..._homeScreenOptions.map((option) {
              final isSelected = currentStyle == option['key'];
              return Padding(
                padding: EdgeInsets.only(bottom: spacing3),
                child: InkWell(
                  onTap: () => _handleSettingChange(homeScreenStyle: option['key']),
                  borderRadius: BorderRadius.circular(borderRadius * 0.7),
                  child: Container(
                    padding: EdgeInsets.all(optionPadding),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyanAccent.withOpacity(0.15)
                          : const Color(0xFF0a1128).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(borderRadius * 0.7),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : Colors.white24,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.cyanAccent : Colors.white54,
                        ),
                        SizedBox(width: optionPadding),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option['name']!,
                                style: TextStyle(
                                  color: isSelected ? Colors.cyanAccent : Colors.white,
                                  fontSize: optionNameFontSize,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              SizedBox(height: spacing4),
                              Text(
                                option['description']!,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: optionDescFontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            // Coming Soon Message
            Container(
              padding: EdgeInsets.all(optionPadding),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(borderRadius * 0.7),
                border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, color: Colors.orange, size: optionNameFontSize),
                  SizedBox(width: optionPadding * 0.5),
                  Text(
                    'More themes coming soon...',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: optionDescFontSize,
                      fontStyle: FontStyle.italic,
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

  Widget _buildGroupScreenStyleCard(UserSettingsProvider userSettings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final optionNameFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final optionDescFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final spacing3 = (screenHeight * 0.015).clamp(10.0, 14.0);
    final spacing4 = (screenHeight * 0.005).clamp(3.0, 6.0);
    final optionPadding = (screenWidth * 0.04).clamp(12.0, 18.0);

    final currentStyle = userSettings.groupScreenStyle ?? 'static';

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Background Style",
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose your create group screen background",
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            ..._groupScreenOptions.map((option) {
              final isSelected = currentStyle == option['key'];
              return Padding(
                padding: EdgeInsets.only(bottom: spacing3),
                child: InkWell(
                  onTap: () => _handleSettingChange(groupScreenStyle: option['key']),
                  borderRadius: BorderRadius.circular(borderRadius * 0.7),
                  child: Container(
                    padding: EdgeInsets.all(optionPadding),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyanAccent.withOpacity(0.15)
                          : const Color(0xFF0a1128).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(borderRadius * 0.7),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : Colors.white24,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.cyanAccent : Colors.white54,
                        ),
                        SizedBox(width: optionPadding),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option['name']!,
                                style: TextStyle(
                                  color: isSelected ? Colors.cyanAccent : Colors.white,
                                  fontSize: optionNameFontSize,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              SizedBox(height: spacing4),
                              Text(
                                option['description']!,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: optionDescFontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCallOverlayStyleCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final optionNameFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final optionDescFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final spacing3 = (screenHeight * 0.015).clamp(10.0, 14.0);
    final spacing4 = (screenHeight * 0.005).clamp(3.0, 6.0);
    final optionPadding = (screenWidth * 0.04).clamp(12.0, 18.0);
    final iconSize = (screenWidth * 0.07).clamp(24.0, 32.0);

    final overlayOptions = [
      {
        'key': 'horizontal',
        'name': 'Horizontal Bar',
        'description': 'Compact bar with avatar, name, and controls',
        'icon': Icons.view_agenda,
      },
      {
        'key': 'circular',
        'name': 'Circular Bubble',
        'description': 'Avatar bubble that expands to show controls',
        'icon': Icons.circle,
      },
    ];

    return Card(
      color: const Color(0xFF1B263B).withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Minimized Call Style",
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose how the call appears when minimized",
              style: TextStyle(color: Colors.white60, fontSize: descFontSize),
            ),
            SizedBox(height: spacing2),
            ...overlayOptions.map((option) {
              final isSelected = (option['key'] == 'circular' && _isCircularOverlay) ||
                                 (option['key'] == 'horizontal' && !_isCircularOverlay);
              return Padding(
                padding: EdgeInsets.only(bottom: spacing3),
                child: InkWell(
                  onTap: () => _saveCallOverlayStyle(option['key'] == 'circular'),
                  borderRadius: BorderRadius.circular(borderRadius * 0.7),
                  child: Container(
                    padding: EdgeInsets.all(optionPadding),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyanAccent.withOpacity(0.15)
                          : const Color(0xFF0a1128).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(borderRadius * 0.7),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : Colors.white24,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.cyanAccent : Colors.white54,
                        ),
                        SizedBox(width: optionPadding),
                        Icon(
                          option['icon'] as IconData,
                          color: isSelected ? Colors.cyanAccent : Colors.white70,
                          size: iconSize,
                        ),
                        SizedBox(width: optionPadding),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option['name'] as String,
                                style: TextStyle(
                                  color: isSelected ? Colors.cyanAccent : Colors.white,
                                  fontSize: optionNameFontSize,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              SizedBox(height: spacing4),
                              Text(
                                option['description'] as String,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: optionDescFontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
