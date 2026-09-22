// lib/services/user_settings_local_service.dart
import 'package:shared_preferences/shared_preferences.dart';

// Simple model for user customization settings
class UserSettings {
  final String bubbleStyle;
  final String myBubbleColorStart;
  final String myBubbleColorEnd;
  final bool isDarkMode;
  final String groupScreenStyle;
  final String cardBubbleColor;
  final String encryptionAnimationStyle; // 'dynamic', 'minimal', 'static'
  /// When true: local contact name → display name → username.
  /// When false: display name → local contact name → username.
  final bool preferLocalContactNames;

  UserSettings({
    required this.bubbleStyle,
    required this.myBubbleColorStart,
    required this.myBubbleColorEnd,
    this.isDarkMode = false,
    this.groupScreenStyle = 'static',
    this.cardBubbleColor = 'blue',
    this.encryptionAnimationStyle = 'static', // Default to static
    this.preferLocalContactNames = true,
  });
}

/// Local storage service for user customization settings
class UserSettingsLocalService {
  // Storage keys
  static const String _bubbleStyleKey = 'bubble_style';
  static const String _colorStartKey = 'bubble_color_start';
  static const String _colorEndKey = 'bubble_color_end';
  static const String _isDarkModeKey = 'is_dark_mode';
  static const String _groupScreenStyleKey = 'group_screen_style';
  static const String _cardBubbleColorKey = 'card_bubble_color';
  static const String _encryptionAnimationStyleKey =
      'encryption_animation_style';
  static const String _preferLocalContactNamesKey =
      'prefer_local_contact_names';

  /// Load settings from local storage
  Future<UserSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return UserSettings(
        bubbleStyle: prefs.getString(_bubbleStyleKey) ?? 'default_rounded',
        myBubbleColorStart: prefs.getString(_colorStartKey) ?? '719CDD',
        myBubbleColorEnd: prefs.getString(_colorEndKey) ?? '507FC3',
        isDarkMode: prefs.getBool(_isDarkModeKey) ?? false,
        groupScreenStyle: prefs.getString(_groupScreenStyleKey) ?? 'static',
        cardBubbleColor: prefs.getString(_cardBubbleColorKey) ?? 'blue',
        encryptionAnimationStyle:
            prefs.getString(_encryptionAnimationStyleKey) ?? 'static',
        preferLocalContactNames:
            prefs.getBool(_preferLocalContactNamesKey) ?? true,
      );
    } catch (e) {
      // Return defaults on error
      return UserSettings(
        bubbleStyle: 'default_rounded',
        myBubbleColorStart: '719CDD',
        myBubbleColorEnd: '507FC3',
        isDarkMode: false,
        groupScreenStyle: 'static',
        cardBubbleColor: 'blue',
        encryptionAnimationStyle: 'static',
        preferLocalContactNames: true,
      );
    }
  }

  /// Save settings to local storage
  Future<void> saveSettings(UserSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setString(_bubbleStyleKey, settings.bubbleStyle),
      prefs.setString(_colorStartKey, settings.myBubbleColorStart),
      prefs.setString(_colorEndKey, settings.myBubbleColorEnd),
      prefs.setBool(_isDarkModeKey, settings.isDarkMode),
      prefs.setString(_groupScreenStyleKey, settings.groupScreenStyle),
      prefs.setString(_cardBubbleColorKey, settings.cardBubbleColor),
      prefs.setString(
        _encryptionAnimationStyleKey,
        settings.encryptionAnimationStyle,
      ),
      prefs.setBool(
        _preferLocalContactNamesKey,
        settings.preferLocalContactNames,
      ),
    ]);
  }

  /// Clear all customization settings (reset to defaults)
  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.remove(_bubbleStyleKey),
      prefs.remove(_colorStartKey),
      prefs.remove(_colorEndKey),
      prefs.remove(_isDarkModeKey),
      prefs.remove(_groupScreenStyleKey),
      prefs.remove(_cardBubbleColorKey),
      prefs.remove(_encryptionAnimationStyleKey),
      prefs.remove(_preferLocalContactNamesKey),
    ]);
  }
}
