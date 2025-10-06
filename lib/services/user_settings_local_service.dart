// lib/services/user_settings_local_service.dart
import 'package:shared_preferences/shared_preferences.dart';

// Simple model for user customization settings
class UserSettings {
  final String bubbleStyle;
  final String myBubbleColorStart;
  final String myBubbleColorEnd;
  final String homeScreenStyle;
  final String groupScreenStyle;
  final String cardBubbleColor;

  UserSettings({
    required this.bubbleStyle,
    required this.myBubbleColorStart,
    required this.myBubbleColorEnd,
    this.homeScreenStyle = 'default',
    this.groupScreenStyle = 'static',
    this.cardBubbleColor = 'blue',
  });
}

/// Local storage service for user customization settings
/// Stores all settings in SharedPreferences (device only, no server)
class UserSettingsLocalService {
  // Storage keys
  static const String _bubbleStyleKey = 'bubble_style';
  static const String _colorStartKey = 'bubble_color_start';
  static const String _colorEndKey = 'bubble_color_end';
  static const String _homeScreenStyleKey = 'home_screen_style';
  static const String _groupScreenStyleKey = 'group_screen_style';
  static const String _cardBubbleColorKey = 'card_bubble_color';

  /// Load settings from local storage
  Future<UserSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return UserSettings(
        bubbleStyle: prefs.getString(_bubbleStyleKey) ?? 'default_rounded',
        myBubbleColorStart: prefs.getString(_colorStartKey) ?? '667EEA',
        myBubbleColorEnd: prefs.getString(_colorEndKey) ?? '764BA2',
        homeScreenStyle: prefs.getString(_homeScreenStyleKey) ?? 'default',
        groupScreenStyle: prefs.getString(_groupScreenStyleKey) ?? 'static',
        cardBubbleColor: prefs.getString(_cardBubbleColorKey) ?? 'blue',
      );
    } catch (e) {
      // Return defaults on error
      return UserSettings(
        bubbleStyle: 'default_rounded',
        myBubbleColorStart: '667EEA',
        myBubbleColorEnd: '764BA2',
        homeScreenStyle: 'default',
        groupScreenStyle: 'static',
        cardBubbleColor: 'blue',
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
      prefs.setString(_homeScreenStyleKey, settings.homeScreenStyle),
      prefs.setString(_groupScreenStyleKey, settings.groupScreenStyle),
      prefs.setString(_cardBubbleColorKey, settings.cardBubbleColor),
    ]);
  }

  /// Clear all customization settings (reset to defaults)
  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.remove(_bubbleStyleKey),
      prefs.remove(_colorStartKey),
      prefs.remove(_colorEndKey),
      prefs.remove(_homeScreenStyleKey),
      prefs.remove(_groupScreenStyleKey),
      prefs.remove(_cardBubbleColorKey),
    ]);
  }
}
