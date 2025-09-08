import 'package:flutter/material.dart';

enum AppTheme {
  digitalStarfield,
  forest,
  volcano,
  comets,
}

class ThemeNotifier extends ChangeNotifier {
  AppTheme _currentTheme = AppTheme.digitalStarfield; // Default theme

  AppTheme get currentTheme => _currentTheme;

  void setTheme(AppTheme theme) {
    if (_currentTheme != theme) {
      _currentTheme = theme;
      notifyListeners(); // Tell the app to rebuild with the new theme
    }
  }
}