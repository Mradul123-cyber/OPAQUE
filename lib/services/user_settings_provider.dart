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
    myBubbleColorStart: '667EEA',
    myBubbleColorEnd: '764BA2',
    homeScreenStyle: 'default',
    groupScreenStyle: 'static',
    cardBubbleColor: 'blue',
    encryptionAnimationStyle: 'static',
    findFriendsScreenStyle: 'default',
    friendRequestsScreenStyle: 'default',
    notesScreenStyle: 'default',
  );

  UserSettings get currentSettings => _settings;
  String get bubbleStyleKey => _settings.bubbleStyle;
  String get colorStartHex => _settings.myBubbleColorStart;
  String get colorEndHex => _settings.myBubbleColorEnd;
  String get bubbleColorStart => _settings.myBubbleColorStart;
  String get bubbleColorEnd => _settings.myBubbleColorEnd;
  String get homeScreenStyle => _settings.homeScreenStyle;
  String get groupScreenStyle => _settings.groupScreenStyle;
  String get cardBubbleColor => _settings.cardBubbleColor;
  String get encryptionAnimationStyle => _settings.encryptionAnimationStyle;
  String get findFriendsScreenStyle => _settings.findFriendsScreenStyle;
  String get friendRequestsScreenStyle => _settings.friendRequestsScreenStyle;
  String get notesScreenStyle => _settings.notesScreenStyle;

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

  // Unified save method for style, colors, and home screen
  Future<void> saveSettings({
    String? styleKey,
    String? colorStart,
    String? colorEnd,
    String? homeScreenStyle,
    String? groupScreenStyle,
    String? cardBubbleColor,
    String? encryptionAnimationStyle,
    String? findFriendsScreenStyle,
    String? friendRequestsScreenStyle,
    String? notesScreenStyle,
  }) async {
    // Update local state
    _settings = UserSettings(
      bubbleStyle: styleKey ?? _settings.bubbleStyle,
      myBubbleColorStart: colorStart ?? _settings.myBubbleColorStart,
      myBubbleColorEnd: colorEnd ?? _settings.myBubbleColorEnd,
      homeScreenStyle: homeScreenStyle ?? _settings.homeScreenStyle,
      groupScreenStyle: groupScreenStyle ?? _settings.groupScreenStyle,
      cardBubbleColor: cardBubbleColor ?? _settings.cardBubbleColor,
      encryptionAnimationStyle: encryptionAnimationStyle ?? _settings.encryptionAnimationStyle,
      findFriendsScreenStyle: findFriendsScreenStyle ?? _settings.findFriendsScreenStyle,
      friendRequestsScreenStyle: friendRequestsScreenStyle ?? _settings.friendRequestsScreenStyle,
      notesScreenStyle: notesScreenStyle ?? _settings.notesScreenStyle,
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
      myBubbleColorStart: '667EEA',
      myBubbleColorEnd: '764BA2',
      homeScreenStyle: 'default',
      groupScreenStyle: 'static',
      cardBubbleColor: 'blue',
      encryptionAnimationStyle: 'static',
      findFriendsScreenStyle: 'default',
      friendRequestsScreenStyle: 'default',
      notesScreenStyle: 'default',
    );
    notifyListeners();
  }
}