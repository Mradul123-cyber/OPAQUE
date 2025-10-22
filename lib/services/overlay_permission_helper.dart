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
    final screenWidth = MediaQuery.of(context).size.width;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.phone_in_talk,
                color: Colors.cyanAccent,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Floating Call Overlay',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (screenWidth * 0.05).clamp(18.0, 22.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stay connected while multitasking',
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: (screenWidth * 0.038).clamp(14.0, 17.0),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.visibility,
              'See who\'s calling while using other apps',
              screenWidth,
            ),
            const SizedBox(height: 12),
            _buildFeatureRow(
              Icons.touch_app,
              'Quick access to call controls',
              screenWidth,
            ),
            const SizedBox(height: 12),
            _buildFeatureRow(
              Icons.swap_horiz,
              'Switch between apps without missing calls',
              screenWidth,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.white60,
                    size: (screenWidth * 0.045).clamp(16.0, 20.0),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You\'ll be redirected to settings to enable this permission',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: (screenWidth * 0.032).clamp(12.0, 15.0),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              'Not Now',
              style: TextStyle(
                color: Colors.white60,
                fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await SystemOverlayService.requestOverlayPermission();

              // Show hint about enabling in settings
              await Future.delayed(const Duration(milliseconds: 300));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.settings, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Enable "Display over other apps" permission',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.grey[850],
                    duration: const Duration(seconds: 4),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Enable',
              style: TextStyle(
                fontSize: (screenWidth * 0.038).clamp(14.0, 17.0),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper to build feature rows
  static Widget _buildFeatureRow(IconData icon, String text, double screenWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.cyanAccent,
          size: (screenWidth * 0.05).clamp(18.0, 22.0),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: (screenWidth * 0.035).clamp(13.0, 16.0),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Manually request permission (for settings)
  static Future<void> requestPermission(BuildContext context) async {
    final hasPermission = await SystemOverlayService.hasOverlayPermission();
    if (hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 12),
                Text('Permission already granted', style: TextStyle(color: Colors.white)),
              ],
            ),
            backgroundColor: Colors.grey[850],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    await SystemOverlayService.requestOverlayPermission();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.settings, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enable "Display over other apps" permission',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.grey[850],
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}
