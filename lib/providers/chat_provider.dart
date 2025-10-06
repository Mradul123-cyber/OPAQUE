// lib/providers/chat_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../message_model.dart';
import '../services/database_service.dart';

class ChatProvider with ChangeNotifier {
  List<Message> _messages = [];
  List<String> _onlineUsers = [];
  int? _currentConversationId;

  List<Message> get messages => _messages;
  List<String> get onlineUsers => _onlineUsers;
  int? get currentConversationId => _currentConversationId;

  /// This is now the primary way to update the UI.
  /// It replaces the entire list with a new one, ensuring no duplicates.
  void setMessages(List<Message> messages) {
    // Preserve messages that are actively being processed or available for retry
    final pendingMessages = _messages.where((msg) =>
    msg.status == MessageStatus.sending ||
        msg.status == MessageStatus.failed
    ).toList();

    // Keep pending messages, and remove database messages with same ID
    // (pending messages take precedence over database to show correct status)
    final pendingMessageIds = pendingMessages.map((msg) => msg.id).toSet();
    final filteredDbMessages = messages.where((dbMsg) =>
    !pendingMessageIds.contains(dbMsg.id)
    ).toList();

    _messages = [...filteredDbMessages, ...pendingMessages];
    notifyListeners();
  }

  /// This is a simple helper for adding a single message, used for temporary messages.
  void addMessage(Message message) {
    // print("=== ChatProvider.addMessage START ===");
    // print("Adding message ID: ${message.id}");
    // print("Adding message content: '${message.content}'");
    // print("Adding message timestamp: ${message.timestamp}");

    // Check if message already exists to avoid duplicates
    if (_messages.any((msg) => msg.id == message.id)) {
      // print("Message ${message.id} already exists - skipping");
      return;
    }

    // Convert to UTC for consistent comparison
    final newMessageUtc = message.timestamp.toUtc();
    // print("New message UTC: $newMessageUtc");

    // Find correct insertion point by timestamp (chronological order)
    int insertIndex = 0;

    for (int i = 0; i < _messages.length; i++) {
      final existingMessageUtc = _messages[i].timestamp.toUtc();
      // print("Comparing: $newMessageUtc vs existing: $existingMessageUtc");

      if (newMessageUtc.isBefore(existingMessageUtc)) {
        insertIndex = i;
        // print("Inserting at index $i (new message is earlier)");
        break;
      }
      insertIndex = i + 1; // Insert after this message
    }

    // print("Final insertion index: $insertIndex");
    _messages.insert(insertIndex, message);

    // print("Messages after insertion:");
    for (int i = 0; i < _messages.length; i++) {
      // print("  [$i] ID:${_messages[i].id} timestamp:${_messages[i].timestamp.toUtc()}");
    }

    notifyListeners();
  }

  void removeMessage(int messageId) {
    _messages.removeWhere((message) => message.id == messageId);
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void setOnlineUsers(List<String> users) {
    _onlineUsers = users;
    notifyListeners();
  }

  void setCurrentConversationId(int? id) {
    _currentConversationId = id;
  }

  void updateMessageStatus(int oldMessageId, Message newMessage) {
    final index = _messages.indexWhere((message) => message.id == oldMessageId);
    if (index != -1) {
      _messages[index] = newMessage;
      notifyListeners();

      // Only save persistent states to database (exclude temporary UI states)
      if (newMessage.status != MessageStatus.sending &&
          newMessage.status != MessageStatus.failed) {
        _saveMessageToDatabase(newMessage);
      }
    }
  }

// Add this helper method to update database
  Future<void> _saveMessageToDatabase(Message message) async {
    try {
      final dbService = DatabaseService.instance;
      await dbService.insertMessage(message);
    } catch (e) {
      // print('Error saving message to database: $e');
    }
  }

  void updateMessageStatusById(int messageId, MessageStatus newStatus) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      final oldStatus = _messages[index].status;

      // ✅ PERFORMANCE FIX: Only update and notify if status actually changed
      if (oldStatus == newStatus) {
        // print("[ChatProvider] ⏭️ Message $messageId already has status $newStatus, skipping");
        return;
      }

      // Status progression check: don't downgrade status
      // read > delivered > sent > sending
      final statusOrder = {
        MessageStatus.sending: 0,
        MessageStatus.sent: 1,
        MessageStatus.delivered: 2,
        MessageStatus.read: 3,
        MessageStatus.failed: -1,
        MessageStatus.decrypting: 0,
        MessageStatus.decryptFailed: -1,
      };

      final oldOrder = statusOrder[oldStatus] ?? 0;
      final newOrder = statusOrder[newStatus] ?? 0;

      if (oldOrder >= newOrder && oldOrder >= 0 && newOrder >= 0) {
        // print("[ChatProvider] ⏭️ Message $messageId status not updated - $oldStatus is higher than $newStatus");
        return;
      }

      _messages[index] = _messages[index].copyWith(status: newStatus);
      // print("[ChatProvider] ✅ Message $messageId status updated: $oldStatus → $newStatus");
      notifyListeners();
    }
  }

  void removeMessageByContent(String content) {
    _messages.removeWhere((message) => message.content == content && message.senderUid == FirebaseAuth.instance.currentUser?.uid);
    // Don't call notifyListeners() here since we'll add the message right after
  }
}
