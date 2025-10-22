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
  final String encryptionAnimationStyle; // 'dynamic', 'minimal', 'static'
  final String findFriendsScreenStyle; // 'default' or 'dark'
  final String friendRequestsScreenStyle; // 'default' or 'dark'

  UserSettings({
    required this.bubbleStyle,
    required this.myBubbleColorStart,
    required this.myBubbleColorEnd,
    this.homeScreenStyle = 'default',
    this.groupScreenStyle = 'static',
    this.cardBubbleColor = 'blue',
    this.encryptionAnimationStyle = 'static', // Default to static (animations disabled for now)
    this.findFriendsScreenStyle = 'default',
    this.friendRequestsScreenStyle = 'default',
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
  static const String _encryptionAnimationStyleKey = 'encryption_animation_style';
  static const String _findFriendsScreenStyleKey = 'find_friends_screen_style';
  static const String _friendRequestsScreenStyleKey = 'friend_requests_screen_style';

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
        encryptionAnimationStyle: prefs.getString(_encryptionAnimationStyleKey) ?? 'static',
        findFriendsScreenStyle: prefs.getString(_findFriendsScreenStyleKey) ?? 'default',
        friendRequestsScreenStyle: prefs.getString(_friendRequestsScreenStyleKey) ?? 'default',
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
        encryptionAnimationStyle: 'static',
        findFriendsScreenStyle: 'default',
        friendRequestsScreenStyle: 'default',
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
      prefs.setString(_encryptionAnimationStyleKey, settings.encryptionAnimationStyle),
      prefs.setString(_findFriendsScreenStyleKey, settings.findFriendsScreenStyle),
      prefs.setString(_friendRequestsScreenStyleKey, settings.friendRequestsScreenStyle),
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
      prefs.remove(_encryptionAnimationStyleKey),
      prefs.remove(_findFriendsScreenStyleKey),
      prefs.remove(_friendRequestsScreenStyleKey),
    ]);
  }
}
