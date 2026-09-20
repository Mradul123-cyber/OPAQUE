import 'package:flutter/material.dart';
import '../widgets/opaque_toast.dart';
import 'system_overlay_service.dart';

/// Helper to request and manage overlay permission
class OverlayPermissionHelper {

  /// Manually request permission (for settings)
  static Future<void> requestPermission(BuildContext context) async {
    final hasPermission = await SystemOverlayService.hasOverlayPermission();
    if (hasPermission) {
      if (context.mounted) {
        OpaqueToast.show(context, 'Already enabled');
      }
      return;
    }

    await SystemOverlayService.requestOverlayPermission();

    if (context.mounted) {
      OpaqueToast.show(context, 'Enable in settings');
    }
  }
}
