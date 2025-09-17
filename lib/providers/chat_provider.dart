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
    // Keep any optimistic/sending messages that aren't in the database yet
    final pendingMessages = _messages.where((msg) =>
    msg.status == MessageStatus.sending ||
        !messages.any((dbMsg) => dbMsg.id == msg.id)
    ).toList();

    // Merge database messages with pending messages
    _messages = [...messages, ...pendingMessages];
    notifyListeners();
  }

  /// This is a simple helper for adding a single message, used for temporary messages.
  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  void removeMessage(int messageId) {
    _messages.removeWhere((message) => message.id == messageId);
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

      // Also save to database immediately to prevent conflicts with setMessages
      _saveMessageToDatabase(newMessage);
    }
  }

// Add this helper method to update database
  Future<void> _saveMessageToDatabase(Message message) async {
    try {
      final dbService = DatabaseService.instance;
      await dbService.insertMessage(message);
    } catch (e) {
      print('Error saving message to database: $e');
    }
  }

  void updateMessageStatusById(int messageId, MessageStatus newStatus) {
    print("[ChatProvider] 🔍 Updating message $messageId to $newStatus");
    print("[ChatProvider] 🔍 Current messages count: ${_messages.length}");

    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      final oldStatus = _messages[index].status;
      _messages[index] = _messages[index].copyWith(status: newStatus);
      print("[ChatProvider] ✅ Message $messageId status updated from $oldStatus to $newStatus");
      print("[ChatProvider] 🔍 Notifying UI listeners...");
      notifyListeners();
    } else {
      print("[ChatProvider] ❌ Message $messageId not found in provider");
      // Debug: Show what messages we do have
      print("[ChatProvider] 🔍 Available message IDs: ${_messages.map((m) => m.id).toList()}");
    }
  }

  void removeMessageByContent(String content) {
    _messages.removeWhere((message) => message.content == content && message.senderUid == FirebaseAuth.instance.currentUser?.uid);
    // Don't call notifyListeners() here since we'll add the message right after
  }
}
