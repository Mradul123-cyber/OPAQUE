import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_settings_provider.dart';
import '../services/notes_password_service.dart';
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
    BubbleOption(resourceKey: 'square_corners', name: 'Square'),
    BubbleOption(resourceKey: 'minimal', name: 'Minimal'),
    BubbleOption(resourceKey: 'modern_card', name: 'Modern Cards'),
  ];

  // Card bubble color options
  final Map<String, Map<String, dynamic>> _cardColorOptions = {
    'blue': {
      'name': 'Blue',
      'color': Color(0xFFE3F2FD),
      'border': Color(0xFF90CAF9),
    },
    'green': {
      'name': 'Green',
      'color': Color(0xFFE8F5E9),
      'border': Color(0xFF81C784),
    },
    'red': {
      'name': 'Red',
      'color': Color(0xFFFFEBEE),
      'border': Color(0xFFEF5350),
    },
    'purple': {
      'name': 'Purple',
      'color': Color(0xFFF3E5F5),
      'border': Color(0xFFBA68C8),
    },
    'orange': {
      'name': 'Orange',
      'color': Color(0xFFFFF3E0),
      'border': Color(0xFFFFB74D),
    },
    'yellow': {
      'name': 'Yellow',
      'color': Color(0xFFFFFDE7),
      'border': Color(0xFFFFF176),
    },
  };

  // Home screen background options (deprecated, using global isDarkMode)

  // Create Group screen background options
  final List<Map<String, String>> _groupScreenOptions = [
    {
      'key': 'static',
      'name': 'Modern Cards',
      'description': 'Colorful card-based UI (Default)',
    },
    {
      'key': 'dynamic',
      'name': 'Dynamic Leaves',
      'description': 'Animated falling leaves',
    },
  ];

  void _handleSettingChange({
    String? styleKey,
    String? colorStart,
    String? colorEnd,
    bool? isDarkMode,
    String? groupScreenStyle,
    String? cardBubbleColor,
  }) async {
    final provider = Provider.of<UserSettingsProvider>(context, listen: false);

    await provider.saveSettings(
      styleKey: styleKey,
      colorStart: colorStart,
      colorEnd: colorEnd,
      isDarkMode: isDarkMode,
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
    return Consumer<UserSettingsProvider>(
      builder: (context, userSettings, child) {
        final isDark = userSettings.isDarkMode;
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
              backgroundColor: isDark ? const Color(0xFF0a1128) : Colors.white,
              elevation: 0,
              title: Text(
                'Customization',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: appBarTitleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconTheme: IconThemeData(
                color: isDark ? Colors.cyanAccent : const Color(0xFF3D00B8),
              ),
            ),
            body: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0a1128),
                          Color(0xFF1a1f3a),
                          Color(0xFF0d1b2a),
                          Color(0xFF16213e),
                        ],
                        stops: [0.0, 0.3, 0.6, 1.0],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFF7F7FB),
                          Colors.white,
                          const Color(0xFFEDF2F7),
                        ],
                      ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mainPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section: Global Dark Theme
                    _buildSectionHeader(
                      Icons.dark_mode,
                      'Global Theme',
                      isDark,
                    ),
                    SizedBox(height: itemSpacing),
                    _buildGlobalThemeCard(userSettings, isDark),

                    SizedBox(height: sectionSpacing),

                    // Section: Message Bubbles
                    _buildSectionHeader(
                      Icons.chat_bubble_outline,
                      'Message Bubbles',
                      isDark,
                    ),
                    SizedBox(height: itemSpacing),
                    _buildBubbleStyleCard(userSettings, isDark),
                    SizedBox(height: itemSpacing),
                    // Show card color picker only for modern_card style
                    if (userSettings.bubbleStyleKey == 'modern_card')
                      _buildCardColorPicker(userSettings, isDark)
                    else
                      _buildBubbleColorCards(userSettings, isDark),

                    SizedBox(height: sectionSpacing),

                    // Section: Group Screen
                    _buildSectionHeader(
                      Icons.group_add,
                      'Group Screen',
                      isDark,
                    ),
                    SizedBox(height: itemSpacing),
                    _buildGroupScreenStyleCard(userSettings, isDark),

                    SizedBox(height: sectionSpacing),

                    // Section: Notes Security
                    _buildSectionHeader(Icons.lock, 'Notes Security', isDark),
                    SizedBox(height: itemSpacing),
                    _buildNotesSecurityCard(isDark),

                    SizedBox(height: sectionSpacing),

                    // Section: Call Overlay
                    _buildSectionHeader(
                      Icons.phone_in_talk,
                      'Call Overlay',
                      isDark,
                    ),
                    SizedBox(height: itemSpacing),
                    _buildCallOverlayStyleCard(isDark),

                    SizedBox(height: sectionSpacing),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.06).clamp(20.0, 28.0);
    final fontSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final spacing = (screenWidth * 0.03).clamp(10.0, 14.0);

    return Row(
      children: [
        Icon(
          icon,
          color: isDark ? Colors.cyanAccent : const Color(0xFF3D00B8),
          size: iconSize,
        ),
        SizedBox(width: spacing),
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalThemeCard(UserSettingsProvider userSettings, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final switchLabelFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);

    // Check global theme status
    final isGlobalDark = userSettings.isDarkMode;

    return Card(
      color: isDark ? const Color(0xFF1B263B).withOpacity(0.6) : Colors.white,
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: isDark
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Theme Toggle",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Apply light/dark theme across the entire application",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: descFontSize,
              ),
            ),
            SizedBox(height: spacing2),
            Container(
              padding: EdgeInsets.all(cardPadding * 0.8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0a1128).withOpacity(0.5)
                    : const Color(0xFFF7F7FB),
                borderRadius: BorderRadius.circular(borderRadius * 0.7),
                border: Border.all(
                  color: isDark
                      ? Colors.cyanAccent.withOpacity(0.3)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isGlobalDark ? Icons.dark_mode : Icons.light_mode,
                        color: isGlobalDark ? Colors.cyanAccent : Colors.amber,
                        size: (screenWidth * 0.06).clamp(20.0, 28.0),
                      ),
                      SizedBox(width: cardPadding),
                      Text(
                        isGlobalDark
                            ? 'Dark Mode Enabled'
                            : 'Light Mode Enabled',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: switchLabelFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: isGlobalDark,
                    onChanged: (bool value) {
                      _handleGlobalThemeChange(value);
                    },
                    activeColor: isDark
                        ? Colors.cyanAccent
                        : const Color(0xFF3D00B8),
                    activeTrackColor:
                        (isDark ? Colors.cyanAccent : const Color(0xFF3D00B8))
                            .withOpacity(0.5),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.grey.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGlobalThemeChange(bool isDark) {
    _handleSettingChange(isDarkMode: isDark);

    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDark
                ? 'Dark theme enabled for all screens!'
                : 'Light theme enabled for all screens!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildBubbleStyleCard(UserSettingsProvider userSettings, bool isDark) {
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
      color: isDark ? const Color(0xFF1B263B).withOpacity(0.6) : Colors.white,
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: isDark
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Bubble Style",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose the shape of your message bubbles",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: descFontSize,
              ),
            ),
            SizedBox(height: spacing2),
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0a1128).withOpacity(0.5)
                    : const Color(0xFFF7F7FB),
                borderRadius: BorderRadius.circular(borderRadius * 0.7),
                border: Border.all(
                  color: isDark
                      ? Colors.cyanAccent.withOpacity(0.3)
                      : Colors.grey.shade300,
                ),
              ),
              padding: EdgeInsets.symmetric(horizontal: cardPadding),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: currentValue,
                  hint: Text(
                    "Select Style",
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: dropdownFontSize,
                    ),
                  ),
                  dropdownColor: isDark
                      ? const Color(0xFF1B263B)
                      : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: dropdownFontSize,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.cyanAccent : const Color(0xFF3D00B8),
                  ),
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

  Widget _buildBubbleColorCards(
    UserSettingsProvider userSettings,
    bool isDark,
  ) {
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

  Widget _buildCardColorPicker(UserSettingsProvider userSettings, bool isDark) {
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
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
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
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
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
      '667EEA': Colors.blueAccent, // Default Start
      '764BA2': Colors.deepPurple, // Default End
      'FF4500': Colors.orangeAccent, // Bright Orange
      '4CAF50': Colors.green, // Green
      'DC143C': Colors.redAccent, // Crimson Red
    };

    // Helper to check if a color is selected (case-insensitive comparison)
    bool isSelected(String hex) =>
        hex.toUpperCase() == (currentColor?.toUpperCase() ?? '');

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
                              ),
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

  Widget _buildGroupScreenStyleCard(
    UserSettingsProvider userSettings,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);

    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);
    final spacing3 = (screenHeight * 0.015).clamp(10.0, 14.0);

    final currentStyle = userSettings.groupScreenStyle;

    return Card(
      color: isDark ? const Color(0xFF1B263B).withOpacity(0.6) : Colors.white,
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: isDark
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Group Screen Theme",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose visual style for group creation screen",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: descFontSize,
              ),
            ),
            SizedBox(height: spacing2),
            ..._groupScreenOptions.map((option) {
              final isSelected = currentStyle == option['key'];
              return Padding(
                padding: EdgeInsets.only(bottom: spacing3),
                child: _buildOptionToggle(
                  isDark: isDark,
                  label: option['name']!,
                  description: option['description']!,
                  isSelected: isSelected,
                  onTap: () =>
                      _handleSettingChange(groupScreenStyle: option['key']),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSecurityCard(bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final buttonFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 10.0);
    final spacing2 = (screenHeight * 0.02).clamp(12.0, 18.0);

    return Card(
      color: isDark ? const Color(0xFF1B263B).withOpacity(0.6) : Colors.white,
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: isDark
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Password Protection",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Secure your notes with screen lock and individual note locks",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: descFontSize,
              ),
            ),
            SizedBox(height: spacing2),

            // App Lock Button
            FutureBuilder<bool>(
              future: NotesPasswordService.instance.isPasswordEnabled(),
              builder: (context, snapshot) {
                final isEnabled = snapshot.data ?? false;

                return ElevatedButton.icon(
                  onPressed: () => _handleNotesPasswordToggle(isEnabled),
                  icon: Icon(
                    isEnabled ? Icons.lock : Icons.lock_open,
                    size: (screenWidth * 0.05).clamp(18.0, 22.0),
                    color: (isDark || isEnabled) ? Colors.black : Colors.white,
                  ),
                  label: Text(
                    isEnabled
                        ? 'Change/Disable Screen Lock'
                        : 'Enable Screen Lock',
                    style: TextStyle(
                      fontSize: buttonFontSize,
                      color: (isDark || isEnabled)
                          ? Colors.black
                          : Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEnabled
                        ? Colors.orange
                        : (isDark
                              ? Colors.cyanAccent
                              : const Color(0xFF3D00B8)),
                    foregroundColor: isEnabled ? Colors.white : Colors.black,
                    padding: EdgeInsets.symmetric(
                      horizontal: cardPadding,
                      vertical: spacing1 * 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius * 0.7),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleNotesPasswordToggle(bool isCurrentlyEnabled) async {
    if (isCurrentlyEnabled) {
      // Show options: Change Password or Disable
      await _showPasswordManagementDialog();
    } else {
      // Setup new password
      await _showPasswordSetupDialog();
    }
  }

  Future<void> _showPasswordSetupDialog() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Setup Notes Password',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter password (min 4 characters)',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: obscureConfirm,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade400,
                    ),
                    onPressed: () =>
                        setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final password = passwordController.text;
                final confirm = confirmController.text;

                if (password.length < 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password must be at least 4 characters'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final success = await NotesPasswordService.instance.setPassword(
                  password,
                );

                if (mounted) {
                  Navigator.pop(context);

                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notes password enabled successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    setState(() {}); // Refresh the card
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to set password'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Set Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasswordManagementDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Manage Password',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'What would you like to do?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showChangePasswordDialog();
            },
            child: const Text(
              'Change Password',
              style: TextStyle(color: Colors.cyanAccent),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showDisablePasswordDialog();
            },
            child: const Text('Disable', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Change Password',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Current password',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'New password (min 4 characters)',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Confirm new password',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPassword = oldPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirm = confirmController.text;

              if (newPassword.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('New password must be at least 4 characters'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (newPassword != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Passwords do not match'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final success = await NotesPasswordService.instance
                  .changePassword(oldPassword, newPassword);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Password changed successfully!'
                          : 'Incorrect current password',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
                if (success) setState(() {});
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDisablePasswordDialog() async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Disable Password',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your password to disable protection',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Current password',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              final isValid = await NotesPasswordService.instance
                  .verifyPassword(password);

              if (isValid) {
                await NotesPasswordService.instance.disablePassword();

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password protection disabled'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  setState(() {});
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Incorrect password'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
  }

  Widget _buildCallOverlayStyleCard(bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;

    final cardPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final descFontSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final spacing1 = (MediaQuery.of(context).size.height * 0.01).clamp(
      6.0,
      10.0,
    );
    final spacing2 = (MediaQuery.of(context).size.height * 0.02).clamp(
      12.0,
      18.0,
    );
    final spacing3 = (MediaQuery.of(context).size.height * 0.015).clamp(
      10.0,
      14.0,
    );

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
      color: isDark ? const Color(0xFF1B263B).withOpacity(0.6) : Colors.white,
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: isDark
              ? Colors.cyanAccent.withOpacity(0.3)
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Minimized Call Style",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing1),
            Text(
              "Choose how the call appears when minimized",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: descFontSize,
              ),
            ),
            SizedBox(height: spacing2),
            ...overlayOptions.map((option) {
              final isSelected =
                  (option['key'] == 'circular' && _isCircularOverlay) ||
                  (option['key'] == 'horizontal' && !_isCircularOverlay);
              return Padding(
                padding: EdgeInsets.only(bottom: spacing3),
                child: _buildOptionToggle(
                  isDark: isDark,
                  label: option['name'] as String,
                  description: option['description'] as String,
                  isSelected: isSelected,
                  icon: option['icon'] as IconData,
                  onTap: () =>
                      _saveCallOverlayStyle(option['key'] == 'circular'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionToggle({
    required bool isDark,
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);
    final optionPadding = (screenWidth * 0.04).clamp(12.0, 18.0);
    final optionNameFontSize = (screenWidth * 0.0375).clamp(13.0, 16.0);
    final optionDescFontSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final spacing4 = (MediaQuery.of(context).size.height * 0.005).clamp(
      3.0,
      6.0,
    );
    final iconSize = (screenWidth * 0.07).clamp(24.0, 32.0);

    final colorPrimary = isDark ? Colors.cyanAccent : const Color(0xFF3D00B8);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius * 0.7),
      child: Container(
        padding: EdgeInsets.all(optionPadding),
        decoration: BoxDecoration(
          color: isSelected
              ? colorPrimary.withOpacity(0.15)
              : (isDark
                    ? const Color(0xFF0a1128).withOpacity(0.3)
                    : const Color(0xFFF7F7FB)),
          borderRadius: BorderRadius.circular(borderRadius * 0.7),
          border: Border.all(
            color: isSelected
                ? colorPrimary
                : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? colorPrimary
                  : (isDark ? Colors.white54 : Colors.grey),
            ),
            SizedBox(width: optionPadding),
            if (icon != null) ...[
              Icon(
                icon,
                color: isSelected
                    ? colorPrimary
                    : (isDark ? Colors.white70 : Colors.black54),
                size: iconSize,
              ),
              SizedBox(width: optionPadding),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? colorPrimary
                          : (isDark ? Colors.white : Colors.black87),
                      fontSize: optionNameFontSize,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  SizedBox(height: spacing4),
                  Text(
                    description,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: optionDescFontSize,
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
