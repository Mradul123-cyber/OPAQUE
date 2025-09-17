import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class NavigationHandler {
  static const MethodChannel _channel = MethodChannel('com.zarq/navigation');
  static GlobalKey<NavigatorState>? _navigatorKey;

  // Store target conversation ID for HomeScreen to handle
  static int? pendingConversationId;

  // Initialize the navigation handler - call this in your main.dart
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _channel.setMethodCallHandler(_handleMethodCall);
    print('[NavigationHandler] Initialized with navigator key');
  }

  // Handle method calls from Kotlin
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('[NavigationHandler] Received method call: ${call.method}');
    print('[NavigationHandler] Arguments: ${call.arguments}');

    switch (call.method) {
      case 'openConversation':
        final args = call.arguments as Map<dynamic, dynamic>;
        final conversationId = args['conversation_id'] as int?;
        final messageId = args['message_id'] as int?;

        if (conversationId != null) {
          await _navigateToConversation(conversationId, messageId);

          // Send confirmation back to Kotlin
          await _logNavigationEvent('Navigation completed for conversation $conversationId');
          return 'Navigation successful';
        } else {
          await _logNavigationEvent('Invalid conversation ID received');
          return 'Invalid conversation ID';
        }

      default:
        print('[NavigationHandler] Unknown method: ${call.method}');
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  // Navigate to specific conversation by going to HomeScreen and setting target
  static Future<void> _navigateToConversation(int conversationId, int? messageId) async {
    final context = _navigatorKey?.currentContext;
    if (context == null) {
      print('[NavigationHandler] No navigator context available');
      return;
    }

    print('[NavigationHandler] Navigating to conversation: $conversationId');

    try {
      // Store the target conversation ID
      pendingConversationId = conversationId;

      // Navigate to home screen (which will handle opening the conversation)
      Navigator.of(context).popUntil((route) => route.isFirst);

      print('[NavigationHandler] Set pending conversation ID: $conversationId');
      print('[NavigationHandler] HomeScreen should now open this conversation');

    } catch (e) {
      print('[NavigationHandler] Navigation error: $e');
      await _logNavigationEvent('Navigation failed: $e');
    }
  }

  // Send log events back to Kotlin for debugging
  static Future<void> _logNavigationEvent(String event) async {
    try {
      await _channel.invokeMethod('logNavigationEvent', {'event': event});
    } catch (e) {
      print('[NavigationHandler] Failed to send log event: $e');
    }
  }

  // Method for HomeScreen to check if there's a pending conversation to open
  static int? getPendingConversationId() {
    final id = pendingConversationId;
    pendingConversationId = null; // Clear after getting
    return id;
  }

  // Optional: Method to manually trigger navigation for testing
  static Future<void> testNavigation(int conversationId) async {
    print('[NavigationHandler] Testing navigation to conversation: $conversationId');
    await _navigateToConversation(conversationId, null);
  }
}