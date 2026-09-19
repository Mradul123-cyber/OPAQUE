// lib/services/user_settings_provider.dart
// Local storage only - no server API calls

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'user_settings_local_service.dart';

class UserSettingsProvider with ChangeNotifier {
  final UserSettingsLocalService _localService = UserSettingsLocalService();

  // Store the full settings object
  UserSettings _settings = UserSettings(
    bubbleStyle: 'default_rounded',
    myBubbleColorStart: '719CDD',
    myBubbleColorEnd: '507FC3',
    isDarkMode: false,
    groupScreenStyle: 'static',
    cardBubbleColor: 'blue',
    encryptionAnimationStyle: 'static',
  );

  UserSettings get currentSettings => _settings;
  String get bubbleStyleKey => _settings.bubbleStyle;
  String get colorStartHex => _settings.myBubbleColorStart;
  String get colorEndHex => _settings.myBubbleColorEnd;
  String get bubbleColorStart => _settings.myBubbleColorStart;
  String get bubbleColorEnd => _settings.myBubbleColorEnd;
  bool get isDarkMode => _settings.isDarkMode;
  String get groupScreenStyle => _settings.groupScreenStyle;
  String get cardBubbleColor => _settings.cardBubbleColor;
  String get encryptionAnimationStyle => _settings.encryptionAnimationStyle;

  UserSettingsProvider() {
    _loadInitialStyle();
  }

  Future<void> _loadInitialStyle() async {
    try {
      // Load from local storage (instant, no network call)
      _settings = await _localService.loadSettings();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user settings from local storage: $e');
    }
  }

  // Unified save method for style, colors, and global theme
  Future<void> saveSettings({
    String? styleKey,
    String? colorStart,
    String? colorEnd,
    bool? isDarkMode,
    String? groupScreenStyle,
    String? cardBubbleColor,
    String? encryptionAnimationStyle,
  }) async {
    // Update local state
    _settings = UserSettings(
      bubbleStyle: styleKey ?? _settings.bubbleStyle,
      myBubbleColorStart: colorStart ?? _settings.myBubbleColorStart,
      myBubbleColorEnd: colorEnd ?? _settings.myBubbleColorEnd,
      isDarkMode: isDarkMode ?? _settings.isDarkMode,
      groupScreenStyle: groupScreenStyle ?? _settings.groupScreenStyle,
      cardBubbleColor: cardBubbleColor ?? _settings.cardBubbleColor,
      encryptionAnimationStyle:
          encryptionAnimationStyle ?? _settings.encryptionAnimationStyle,
    );

    // Save to local storage (instant, no network call)
    await _localService.saveSettings(_settings);

    // Notify UI
    notifyListeners();
  }

  // Reset to defaults
  Future<void> resetToDefaults() async {
    await _localService.clearSettings();
    _settings = UserSettings(
      bubbleStyle: 'default_rounded',
      myBubbleColorStart: '719CDD',
      myBubbleColorEnd: '507FC3',
      isDarkMode: false,
      groupScreenStyle: 'static',
      cardBubbleColor: 'blue',
      encryptionAnimationStyle: 'static',
    );
    notifyListeners();
  }
}
