import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/theme_notifier.dart';
import 'starfield_background.dart';
import 'forest_background.dart';

class ChatBackground extends StatelessWidget {
  final Widget child;
  const ChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Get the current theme from the notifier
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    Widget background;
    // Choose the widget based on the current theme
    switch (themeNotifier.currentTheme) {
      case AppTheme.forest:
        background = const ForestBackground();
        break;
      // We can add cases for Volcano, Comets, etc. later
      default:
        background = const StarfieldBackground();
    }

    return Stack(children: [background, child]);
  }
}
