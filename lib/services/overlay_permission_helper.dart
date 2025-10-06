import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'system_overlay_service.dart';

/// Helper to request and manage overlay permission
class OverlayPermissionHelper {
  static const String _permissionAskedKey = 'overlay_permission_asked';

  /// Check and request overlay permission if needed
  static Future<void> checkAndRequestPermission(BuildContext context) async {
    // Check if we already have permission
    final hasPermission = await SystemOverlayService.hasOverlayPermission();
    if (hasPermission) {
      // print('[OverlayPermission] ✅ Already granted');
      return;
    }

    // Check if we've already asked before
    final prefs = await SharedPreferences.getInstance();
    final hasAsked = prefs.getBool(_permissionAskedKey) ?? false;

    if (!hasAsked) {
      // First time - show explanation dialog
      await _showPermissionDialog(context);
      await prefs.setBool(_permissionAskedKey, true);
    }
  }

  /// Show dialog explaining overlay permission
  static Future<void> _showPermissionDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Floating Call Overlay'),
        content: const Text(
          'To show call notifications over other apps when you minimize Zarq, '
          'we need permission to display overlays.\n\n'
          'This allows you to see who\'s calling and control the call '
          'while using other apps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await SystemOverlayService.requestOverlayPermission();

              // Show hint about enabling in settings
              await Future.delayed(const Duration(milliseconds: 300));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enable "Display over other apps" permission'),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  /// Manually request permission (for settings)
  static Future<void> requestPermission(BuildContext context) async {
    final hasPermission = await SystemOverlayService.hasOverlayPermission();
    if (hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission already granted')),
        );
      }
      return;
    }

    await SystemOverlayService.requestOverlayPermission();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable "Display over other apps" permission'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}
