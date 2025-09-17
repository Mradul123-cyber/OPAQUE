import 'dart:async';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../message_model.dart';

class SentMessageService {
  static const MethodChannel _channel = MethodChannel('com.zarq/sent_messages');
  static final StreamController<Message> _sentMessageController = StreamController<Message>.broadcast();

  static Stream<Message> get sentMessageStream => _sentMessageController.stream;

  static void initialize() {
    _channel.setMethodCallHandler(_handleMethodCall);
    print('[SentMessageService] Initialized');
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMessageSent':
        await _handleSentMessage(call.arguments);
        break;
      default:
        print('[SentMessageService] Unknown method: ${call.method}');
    }
  }

  static Future<void> _handleSentMessage(dynamic arguments) async {
    try {
      final data = Map<String, dynamic>.from(arguments);

      final conversationId = data['conversation_id'] as int;
      final localMessageId = data['local_message_id'] as int;
      final realMessageId = data['real_message_id'] as int;  // ADD THIS
      final messageText = data['message_text'] as String;
      final senderUid = data['sender_uid'] as String;
      final timestamp = data['timestamp'] as int;

      print('[SentMessageService] Processing sent message: $messageText');
      print('[SentMessageService] Local ID: $localMessageId, Real ID: $realMessageId');

      // Get current user info
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != senderUid) {
        print('[SentMessageService] User mismatch or not authenticated');
        return;
      }

      // Create message object with REAL database ID
      final message = Message(
        id: realMessageId,  // USE REAL ID instead of local ID
        conversationId: conversationId,
        username: currentUser.displayName ?? 'You',
        content: messageText,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        senderUid: senderUid,
        status: MessageStatus.sent,
      );

      // Broadcast the message to listeners
      _sentMessageController.add(message);

      print('[SentMessageService] Broadcasted sent message with real ID: ${message.id}');

    } catch (e) {
      print('[SentMessageService] Error handling sent message: $e');
    }
  }

  static void dispose() {
    _sentMessageController.close();
  }
}