// lib/providers/chat_provider.dart
import 'package:flutter/foundation.dart';
import '../message_model.dart';

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
    _messages = messages;
    notifyListeners();
  }

  /// This is a simple helper for adding a single message, used for temporary messages.
  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  void removeMessage(int id) {
    _messages.removeWhere((msg) => msg.id == id);
    notifyListeners();
  }

  void setOnlineUsers(List<String> users) {
    _onlineUsers = users;
    notifyListeners();
  }

  void setCurrentConversationId(int? id) {
    _currentConversationId = id;
  }
}
