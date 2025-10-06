// lib/widgets/call_aware_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/global_call_manager.dart';
import 'global_call_overlay.dart';

/// A wrapper widget that makes any screen aware of active calls.
/// When back button is pressed and there's a maximized call overlay,
/// it minimizes the overlay first before allowing navigation.
class CallAwareScreen extends StatelessWidget {
  final Widget child;
  final String screenName;

  const CallAwareScreen({
    super.key,
    required this.child,
    this.screenName = 'Screen',
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final callManager = Provider.of<GlobalCallManager>(context, listen: false);
        // print('[$screenName] 🔙 Back pressed - isInCall: ${callManager.isInCall}, isMinimized: ${GlobalCallOverlay.isMinimized}');

        // Priority: If call is active AND not minimized, minimize it first
        if (callManager.isInCall && !GlobalCallOverlay.isMinimized) {
          // print('[$screenName] 🔙 Active call detected - minimizing call overlay');
          GlobalCallOverlay.minimize();
          return false; // Don't pop the screen
        }

        // If call is minimized or no call - allow normal navigation
        // print('[$screenName] ✅ Allowing navigation back');
        return true; // Allow pop
      },
      child: child,
    );
  }
}
