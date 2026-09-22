import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'websocket_service.dart';

class NavigationHandler {
  static const MethodChannel _channel = MethodChannel('com.zarq/navigation');
  static GlobalKey<NavigatorState>? _navigatorKey;

  // Store target conversation ID for HomeScreen to handle
  static int? pendingConversationId;

  // Direct callback for active HomeScreen to open conversation immediately
  static void Function(int conversationId)? onOpenConversation;

  // Store auto-answer flag for incoming calls
  static String? _autoAnswerCallerUid;
  static bool get hasAutoAnswerPending => _autoAnswerCallerUid != null;

  // Initialize the navigation handler - call this in your main.dart
  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _channel.setMethodCallHandler(_handleMethodCall);

    // Consume any pending cold-start conversation from notification tap
    _channel.invokeMethod('getPendingConversation').then((pendingId) {
      if (pendingId is int) {
        _navigateToConversation(pendingId, null);
      }
    }).catchError((_) {});
  }

  // Handle method calls from Kotlin
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    // print('[NavigationHandler] Received method call: ${call.method}');
    // print('[NavigationHandler] Arguments: ${call.arguments}');

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

      case 'handleIncomingCall':
        final args = call.arguments as Map<dynamic, dynamic>;
        final callerUid = args['caller_uid'] as String?;
        final callerName = args['caller_name'] as String?;
        final callType = args['call_type'] as String?;
        final autoAnswer = args['auto_answer'] as bool? ?? false;

        // print('[NavigationHandler] ✅ RECEIVED handleIncomingCall:');
        // print('[NavigationHandler]   - Caller: $callerName');
        // print('[NavigationHandler]   - CallerUID: $callerUid');
        // print('[NavigationHandler]   - CallType: $callType');
        // print('[NavigationHandler]   - AutoAnswer: $autoAnswer');

        if (callerUid != null && callerName != null && callType != null) {
          await _handleIncomingCallFromNotification(callerUid, callerName, callType, autoAnswer);
          await _logNavigationEvent('Incoming call handled for $callerName');
          // print('[NavigationHandler] ✅ Call handling completed, auto-answer flag set: ${_autoAnswerCallerUid != null}');
          return 'Call handled successfully';
        } else {
          await _logNavigationEvent('Invalid call parameters');
          // print('[NavigationHandler] ❌ Invalid call parameters');
          return 'Invalid call parameters';
        }

      default:
        // print('[NavigationHandler] Unknown method: ${call.method}');
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
      // print('[NavigationHandler] No navigator context available');
      return;
    }

    // print('[NavigationHandler] Navigating to conversation: $conversationId');

    try {
      // Store the target conversation ID
      pendingConversationId = conversationId;

      // Navigate to home screen (which will handle opening the conversation)
      Navigator.of(context).popUntil((route) => route.isFirst);

      if (onOpenConversation != null) {
        onOpenConversation!(conversationId);
      }
    } catch (e) {
      await _logNavigationEvent('Navigation failed: $e');
    }
  }

  // Handle incoming call from notification
  static Future<void> _handleIncomingCallFromNotification(
    String callerUid,
    String callerName,
    String callType,
    bool autoAnswer,
  ) async {
    // print('[NavigationHandler] Processing incoming call from $callerName');

    try {
      if (autoAnswer) {
        // Store the caller UID for auto-answering when call_offer arrives
        _autoAnswerCallerUid = callerUid;
        print('[NavigationHandler] ✅ Auto-answer enabled for caller: $callerUid');
        print('[NavigationHandler] Call will be automatically accepted when call_offer arrives');
      }

      // CRITICAL: Force WebSocket reconnection when app opens from notification
      final context = _navigatorKey?.currentContext;
      if (context != null) {
        print('[NavigationHandler] 🔄 Getting WebSocketService from context...');

        try {
          final wsService = Provider.of<WebSocketService>(context, listen: false);

          if (!wsService.isConnected) {
            print('[NavigationHandler] ⚠️ WebSocket NOT connected, forcing reconnection...');
            await wsService.reconnect();
            print('[NavigationHandler] ✅ WebSocket reconnection initiated');
            // No delay needed - WebSocket will queue messages if not connected yet
          } else {
            print('[NavigationHandler] ✅ WebSocket already connected');
          }
        } catch (e) {
          print('[NavigationHandler] ⚠️ Could not get WebSocketService: $e');
          print('[NavigationHandler] Will wait for natural reconnection in main.dart');
        }
      } else {
        print('[NavigationHandler] ⚠️ No navigator context available for WebSocket access');
      }

      print('[NavigationHandler] App opened for incoming call from $callerName');
      print('[NavigationHandler] Waiting for call_offer via WebSocket...');

      // The call flow:
      // 1. FCM notification opens app (we are here)
      // 2. WebSocket force-reconnects above
      // 3. Backend delivers pending call_offer via WebSocket
      // 4. WebSocketService receives call_offer
      // 5. GlobalCallManager.handleIncomingCall() shows UI
      // 6. If autoAnswer=true, GlobalCallManager auto-accepts the call

    } catch (e) {
      // print('[NavigationHandler] Error handling incoming call: $e');
      await _logNavigationEvent('Incoming call error: $e');
    }
  }

  // Check if we should auto-answer a call from this caller
  static bool shouldAutoAnswer(String callerUid) {
    // print('[NavigationHandler] shouldAutoAnswer check:');
    // print('[NavigationHandler]   - Checking callerUid: $callerUid');
    // print('[NavigationHandler]   - Stored _autoAnswerCallerUid: $_autoAnswerCallerUid');

    if (_autoAnswerCallerUid == callerUid) {
      // print('[NavigationHandler] ✅ MATCH! Clearing flag and returning TRUE for auto-answer');
      _autoAnswerCallerUid = null; // Clear after checking
      return true;
    }

    // print('[NavigationHandler] ❌ No match, returning FALSE');
    return false;
  }

  // Clear auto-answer flag (in case of timeout or error)
  static void clearAutoAnswer() {
    _autoAnswerCallerUid = null;
  }

  // Send log events back to Kotlin for debugging
  static Future<void> _logNavigationEvent(String event) async {
    try {
      await _channel.invokeMethod('logNavigationEvent', {'event': event});
    } catch (e) {
      // print('[NavigationHandler] Failed to send log event: $e');
    }
  }

  // Notify native Kotlin when entering or leaving a conversation
  static Future<void> setActiveConversation(int conversationId) async {
    try {
      await _channel.invokeMethod('setActiveConversation', {'conversationId': conversationId});
    } catch (_) {}
  }

  static Future<void> clearActiveConversation() async {
    try {
      await _channel.invokeMethod('clearActiveConversation');
    } catch (_) {}
  }

  // Method for HomeScreen to check if there's a pending conversation to open
  static int? getPendingConversationId() {
    final id = pendingConversationId;
    pendingConversationId = null; // Clear after getting
    return id;
  }

  // Optional: Method to manually trigger navigation for testing
  static Future<void> testNavigation(int conversationId) async {
    // print('[NavigationHandler] Testing navigation to conversation: $conversationId');
    await _navigateToConversation(conversationId, null);
  }
}