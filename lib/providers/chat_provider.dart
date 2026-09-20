// lib/providers/chat_provider.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../message_model.dart';
import '../services/database_service.dart';

class ChatProvider with ChangeNotifier {
  List<Message> _messages = [];
  List<String> _onlineUsers = [];
  int? _currentConversationId;

  // Persistent message cache: conversationId -> List<Message>
  // Keeps messages in memory for instant loading
  final Map<int, List<Message>> _messageCache = {};

  // Track last load time for each conversation
  final Map<int, DateTime> _lastLoadTime = {};

  // Cache expiry duration (5 minutes)
  static const Duration _cacheExpiry = Duration(minutes: 5);

  List<Message> get messages => _messages;
  List<String> get onlineUsers => _onlineUsers;
  int? get currentConversationId => _currentConversationId;

  /// Check if cached messages exist and are fresh
  bool hasCachedMessages(int conversationId) {
    if (!_messageCache.containsKey(conversationId)) return false;

    final lastLoad = _lastLoadTime[conversationId];
    if (lastLoad == null) return false;

    // Cache is valid if loaded within last 5 minutes
    final isExpired = DateTime.now().difference(lastLoad) > _cacheExpiry;
    return !isExpired;
  }

  /// Get cached messages for instant display
  List<Message>? getCachedMessages(int conversationId) {
    if (hasCachedMessages(conversationId)) {
      return List.from(_messageCache[conversationId]!);
    }
    return null;
  }

  /// This is now the primary way to update the UI.
  /// It replaces the entire list with a new one, ensuring no duplicates.
  void setMessages(List<Message> messages, {int? conversationId}) {
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

    // Update cache for this conversation
    if (conversationId != null) {
      _messageCache[conversationId] = List.from(_messages);
      _lastLoadTime[conversationId] = DateTime.now();
    }

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
    // Note: Don't clear _messageCache here - we want to keep it for instant loading
    notifyListeners();
  }

  /// Clear cache for a specific conversation (use when user logs out or deletes conversation)
  void clearConversationCache(int conversationId) {
    _messageCache.remove(conversationId);
    _lastLoadTime.remove(conversationId);
  }

  /// Clear all cached messages (use on logout)
  void clearAllCache() {
    _messageCache.clear();
    _lastLoadTime.clear();
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

  /// Update a message by replacing it with a new version (for reactions, edits, etc.)
  void updateMessage(Message updatedMessage) {
    final index = _messages.indexWhere((msg) => msg.id == updatedMessage.id);
    if (index != -1) {
      // Create a new list to ensure Flutter detects the change
      final newMessages = List<Message>.from(_messages);
      newMessages[index] = updatedMessage;
      _messages = newMessages;
      notifyListeners();
    }
  }

  void editMessage(int messageId, String newContent, DateTime editedAt) {
    bool changed = false;
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final updated = _messages[index].copyWith(
        content: newContent,
        isEdited: true,
        editedAt: editedAt,
      );
      final newMessages = List<Message>.from(_messages);
      newMessages[index] = updated;
      _messages = newMessages;
      changed = true;
    }

    // Always update persistent message cache across all cached conversations
    for (final cachedList in _messageCache.values) {
      final cacheIndex = cachedList.indexWhere((m) => m.id == messageId);
      if (cacheIndex != -1) {
        cachedList[cacheIndex] = cachedList[cacheIndex].copyWith(
          content: newContent,
          isEdited: true,
          editedAt: editedAt,
        );
      }
    }

    if (changed) {
      notifyListeners();
    }
  }
}
