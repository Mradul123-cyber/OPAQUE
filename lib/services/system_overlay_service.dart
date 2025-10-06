import 'package:flutter/services.dart';
import 'dart:developer' as developer;

/// Service to manage system-level overlay for calls that float over other apps
class SystemOverlayService {
  static const MethodChannel _channel = MethodChannel('com.zarq/overlay');

  /// Callback when end call button is clicked on system overlay
  static Function()? onEndCallFromOverlay;

  /// Callback when mute button is toggled on system overlay
  static Function(bool isMuted)? onToggleMuteFromOverlay;

  /// Initialize method channel handler for callbacks from Android
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'endCall':
          developer.log('End call triggered from system overlay', name: 'SystemOverlay');
          onEndCallFromOverlay?.call();
          break;
        case 'toggleMute':
          final isMuted = call.arguments['isMuted'] as bool? ?? false;
          developer.log('Toggle mute triggered from system overlay: $isMuted', name: 'SystemOverlay');
          onToggleMuteFromOverlay?.call(isMuted);
          break;
        default:
          developer.log('Unknown method: ${call.method}', name: 'SystemOverlay');
      }
    });
    developer.log('SystemOverlayService initialized', name: 'SystemOverlay');
  }

  /// Check if SYSTEM_ALERT_WINDOW permission is granted
  static Future<bool> hasOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod('checkOverlayPermission');
      developer.log('Overlay permission check: $result', name: 'SystemOverlay');
      return result as bool;
    } catch (e) {
      developer.log('Error checking overlay permission: $e', name: 'SystemOverlay');
      return false;
    }
  }

  /// Request SYSTEM_ALERT_WINDOW permission (opens settings)
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
      developer.log('Requested overlay permission', name: 'SystemOverlay');
    } catch (e) {
      developer.log('Error requesting overlay permission: $e', name: 'SystemOverlay');
    }
  }

  /// Show system overlay with caller info
  static Future<bool> showOverlay({
    required String callerName,
    required bool isVideo,
    String? avatarUrl,
    bool isMuted = false,
  }) async {
    try {
      developer.log('Showing system overlay for $callerName (video: $isVideo, muted: $isMuted)', name: 'SystemOverlay');

      final result = await _channel.invokeMethod('showSystemOverlay', {
        'callerName': callerName,
        'isVideo': isVideo,
        'avatarUrl': avatarUrl,
        'isMuted': isMuted,
      });

      developer.log('System overlay shown: $result', name: 'SystemOverlay');
      return result as bool;
    } catch (e) {
      developer.log('Error showing system overlay: $e', name: 'SystemOverlay');
      return false;
    }
  }

  /// Hide system overlay
  static Future<void> hideOverlay() async {
    try {
      await _channel.invokeMethod('hideSystemOverlay');
      developer.log('System overlay hidden', name: 'SystemOverlay');
    } catch (e) {
      developer.log('Error hiding system overlay: $e', name: 'SystemOverlay');
    }
  }
}
