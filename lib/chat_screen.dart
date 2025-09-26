import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/message_model.dart' as signal_lib;
import 'package:zarq_messenger/services/conversation_service.dart';
import 'package:flutter/services.dart';
import 'package:zarq_messenger/services/deletion_service.dart';

import 'chat_background.dart';
import 'home_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/device_service.dart';
import 'package:flutter/services.dart';
import 'services/sent_message_service.dart';

class ChatScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final ConversationInfo conversationInfo;

  const ChatScreen({
    super.key,
    required this.channel,
    required this.conversationInfo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.zarq/signal');
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentUser = "";
  String? _currentUserUid;
  StreamSubscription? _messageSubscription;

  // Services
  late final ChatProvider _chatProvider;
  late final ConversationService _apiService;
  late final DatabaseService _dbService;
  late final WebSocketService _websocketService;

  bool _isLoading = true;

  // Track which messages have been decrypted to avoid re-decryption
  final Set<int> _decryptedMessageIds = {};

  final Set<int> _selectedMessageIds = {};
  bool _isMultiSelectionMode = false;
  final GlobalKey _lastMessageKey = GlobalKey();

  final Set<int> _processedSentMessageIds = {};

  // Signal protocol session state
  bool _sessionEstablished = false;
  bool _establishingSession = false;
  String? _recipientUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _apiService = Provider.of<ConversationService>(context, listen: false);
    _dbService = Provider.of<DatabaseService>(context, listen: false);
    _websocketService = Provider.of<WebSocketService>(context, listen: false);

    _chatProvider.setCurrentConversationId(widget.conversationInfo.conversationId);
    _initializeChat();

    // Listen for new messages AND status updates from WebSocket
    _messageSubscription = _websocketService.stream.listen((data) async {
      print("[ChatScreen] 🔍 WebSocket stream received: $data");

      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        print("[ChatScreen] 🔍 Message type: $type");

        if (type == 'local_message_saved') {
  final conversationId = data['conversation_id'] as int?;
  final messageId = data['message_id'] as int?;
  print("[ChatScreen] 🔍 local_message_saved for conversation: $conversationId");
  if (conversationId == widget.conversationInfo.conversationId && messageId != null) {
    // Only add the specific new message, don't reload everything
    _addNewMessageToUI(messageId);
  }
} else if (type == 'local_sent_message') {
          final conversationId = data['conversation_id'] as int?;
          print("[ChatScreen] 🔍 local_sent_message for conversation: $conversationId");
          if (conversationId == widget.conversationInfo.conversationId) {
            _handleLocalSentMessage(data);
          }
        }else if (type == 'message_status_update') {
          print("[ChatScreen] 🔍 message_status_update received: $data");
          final messageId = data['message_id'] as int?;
          final status = data['status'] as String?;
          final conversationId = data['conversation_id'] as int?;

          // Debug each condition separately:
          print("[ChatScreen] 🔍 Expected conversationId: ${widget.conversationInfo.conversationId}");
          print("[ChatScreen] 🔍 Received conversationId: $conversationId");

          final conversationMatches = conversationId == widget.conversationInfo.conversationId;
          final messageIdValid = messageId != null;
          final statusValid = status != null;

          print("[ChatScreen] 🔍 Conversation matches: $conversationMatches");
          print("[ChatScreen] 🔍 MessageId valid: $messageIdValid (value: $messageId)");
          print("[ChatScreen] 🔍 Status valid: $statusValid (value: $status)");
          print("[ChatScreen] 🔍 Combined condition result: ${conversationMatches && messageIdValid && statusValid}");

          if (conversationMatches && messageIdValid && statusValid) {
            print("[ChatScreen] ✅ Status update accepted");
            _updateMessageStatusInUI(messageId, status);
          } else {
            print("[ChatScreen] ❌ Status update filtered out");
            print("[ChatScreen] ❌ Reason: conversationMatches=$conversationMatches, messageIdValid=$messageIdValid, statusValid=$statusValid");
          }
        }
          else if (type == 'message_deleted') {
  final messageId = data['message_id'] as int?;
  final deletionType = data['deletion_type'] as String?;
  final conversationId = data['conversation_id'] as int?;

  if (messageId != null && conversationId == widget.conversationInfo.conversationId) {
    if (deletionType == 'delete_for_everyone') {
      _handleDeletedForEveryone(messageId);
    } else {
      // Add the database update for persistence:
      await _dbService.markMessageAsDeletedForMe(messageId);
      _chatProvider.removeMessage(messageId);
    }
  }
}
      } else {
        print("[ChatScreen] 🔍 Non-map data received: ${data.runtimeType}");
      }
    });
  }

Future<void> _addNewMessageToUI(int messageId) async {
  final allMessages = await _dbService.getAllMessagesInConversation(widget.conversationInfo.conversationId);
  final matchingMessages = allMessages.where((msg) => msg.id == messageId);

  if (matchingMessages.isNotEmpty && !await _dbService.isMessageDeletedForMe(messageId)) {
    _chatProvider.addMessage(matchingMessages.first);
  }
}

  void _handleLocalSentMessage(Map<String, dynamic> data) {
    try {
      final messageJson = data['message'] as Map<String, dynamic>;
      final message = Message.fromJson(messageJson);

      print('[ChatScreen] Processing local sent message with ID: ${message.id}');

      // Check for duplicates by ID and content
      final existsInProvider = _chatProvider.messages.any((existing) =>
      existing.id == message.id ||
          (existing.content == message.content && existing.senderUid == message.senderUid)
      );

      if (existsInProvider || _processedSentMessageIds.contains(message.id)) {
        print('[ChatScreen] Ignoring duplicate sent message: ${message.id}');
        return;
      }

      _processedSentMessageIds.add(message.id);
      _chatProvider.addMessage(message);

      print('[ChatScreen] Added local sent message to UI with real ID: ${message.id}');

      // Save to database and scroll
      _dbService.insertMessage(message);
      _scrollToBottom();

    } catch (e) {
      print('[ChatScreen] Error handling local sent message: $e');
    }
  }

  void _updateMessageStatusInUI(int messageId, String statusString) {
    try {
      print("[ChatScreen] 🔍 Attempting to update message $messageId status to '$statusString'");

      final status = MessageStatus.values.firstWhere(
            (s) => s.toString().split('.').last == statusString,
      );

      print("[ChatScreen] 🔍 Converted '$statusString' to $status");
      _chatProvider.updateMessageStatusById(messageId, status);
      print("[ChatScreen] ✅ Called updateMessageStatusById for message $messageId");
    } catch (e) {
      print("[ChatScreen] ❌ Error updating message status in UI: $e");
    }
  }

  Future<void> _markMessagesAsRead() async {
    await _websocketService.markMessagesAsRead(widget.conversationInfo.conversationId);
  }


  Future<void> _initializeChat() async {
    await _getCurrentUser();
    if (_currentUserUid == null) return;

    // Determine recipient UID for 1-on-1 chats
    if (!widget.conversationInfo.isGroup && widget.conversationInfo.partnerUid != null) {
      _recipientUid = widget.conversationInfo.partnerUid;
    }

    // Load messages from database immediately (don't wait for WebSocket)
    await _refreshMessagesFromDb();
    await _loadAndMergeSentMessages();

    // Show UI immediately - don't wait for WebSocket
    if (mounted) setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(instant: true));

    // WebSocket operations can happen in background (async, don't await)
    _performBackgroundWebSocketTasks();
  }

// Separate method for WebSocket operations
  Future<void> _performBackgroundWebSocketTasks() async {
    // These operations happen after UI is already shown
    await _websocketService.syncMessageStatuses(widget.conversationInfo.conversationId);
    await _markMessagesAsRead();
    print("[ChatScreen] Background WebSocket tasks completed");
  }

  Future<void> _refreshMessagesFromDb() async {
    final messages = await _dbService.getMessages(widget.conversationInfo.conversationId);

    // Decrypt messages that haven't been decrypted yet
    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];

      // Skip if it's our own message or already decrypted (ORIGINAL LOGIC RESTORED)
      if (message.senderUid == _currentUserUid || _decryptedMessageIds.contains(message.id)) {
        continue;
      }
    }

    if (mounted) {
      _chatProvider.setMessages(messages);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }


  Future<void> _loadAndMergeSentMessages() async {
    try {
      // Load sent messages for this conversation from local storage
      final sentMessages = await _loadSentMessagesFromStorage();

      if (sentMessages.isNotEmpty) {
        print('[ChatScreen] Loading ${sentMessages.length} sent messages from storage');

        for (final message in sentMessages) {
          // Check if message already exists in ChatProvider by ID or content
          final existsInProvider = _chatProvider.messages.any((existing) =>
          existing.id == message.id ||
              (existing.content == message.content && existing.senderUid == message.senderUid)
          );

          if (!existsInProvider && !_processedSentMessageIds.contains(message.id)) {
            _processedSentMessageIds.add(message.id);
            _chatProvider.addMessage(message);
            print('[ChatScreen] Added sent message: ${message.id}');
          } else {
            print('[ChatScreen] Skipped duplicate sent message: ${message.id}');
          }
        }

        // Re-sort messages by timestamp
        final allMessages = _chatProvider.messages.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _chatProvider.setMessages(allMessages);
      }
    } catch (e) {
      print('[ChatScreen] Error loading sent messages: $e');
    }
  }

  Future<List<Message>> _loadSentMessagesFromStorage() async {
    try {
      // This calls Android to get stored sent messages for this conversation
      final result = await platform.invokeMethod('getStoredSentMessages', {
        'conversation_id': widget.conversationInfo.conversationId,
      });

      if (result != null && result is List) {
        return result.map((messageJson) {
          final data = Map<String, dynamic>.from(messageJson);
          return Message(
            id: data['id'] as int,
            conversationId: data['conversation_id'] as int,
            username: _currentUser,
            content: data['content'] as String,
            timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
            senderUid: _currentUserUid,
            status: MessageStatus.sent,
          );
        }).toList();
      }

      return [];
    } catch (e) {
      print('[ChatScreen] Error loading sent messages from storage: $e');
      return [];
    }
  }

  bool _isBase64(String str) {
    try {
      base64Decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _sendMessage() async {

}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _messageSubscription?.cancel();
    _chatProvider.setCurrentConversationId(null);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUser = user.displayName ?? user.email ?? "Anonymous User";
      _currentUserUid = user.uid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, keyManager, child) {
        return ChatBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _isMultiSelectionMode
                ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              title: Text('${_selectedMessageIds.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copySelectedMessages,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteSelectedMessages,
                ),
              ],
            )
                : AppBar(
              title: Column(
                children: [
                  Text(widget.conversationInfo.chatTitle),
                  if (!widget.conversationInfo.isGroup && _recipientUid != null)
                    Text(
                      _establishingSession
                          ? 'Establishing secure connection...'
                          : _sessionEstablished
                          ? 'End-to-end encrypted'
                          : 'Tap to establish encryption',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                ],
              ),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple, Colors.purpleAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Consumer<ChatProvider>(
                    builder: (context, chatProvider, child) {
                      final messages = [...chatProvider.messages]
                        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
                      return ListView.builder(
                        controller: _scrollController,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return _buildMessageBubble(message, index, messages.length);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            labelText: 'Send a message',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (instant) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          if (_lastMessageKey.currentContext != null) {
            Scrollable.ensureVisible(
              _lastMessageKey.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignment: 1.0,
            );
          } else {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });
  }

  void _toggleMessageSelection(signal_lib.Message message) {
    if (message.senderUid != _currentUserUid) return;
    if (message.content == "This message was deleted") return;
    setState(() {
      if (_selectedMessageIds.contains(message.id)) {
        _selectedMessageIds.remove(message.id);
      } else {
        _selectedMessageIds.add(message.id);
      }
      _isMultiSelectionMode = _selectedMessageIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _isMultiSelectionMode = false;
    });
  }

  void _showMessageOptions(Message message) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 20),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.white),
            title: Text('Delete for me', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(message, 'delete_for_me');
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text('Delete for everyone', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteForEveryoneConfirmation(message);
            },
          ),
          ListTile(
            leading: Icon(Icons.archive, color: Colors.amber),
            title: Text('Recoverable delete', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Recoverable delete - Coming soon!'),
                  backgroundColor: Colors.amber[700],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void _showDeleteForEveryoneConfirmation(Message message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text('Delete for everyone?', style: TextStyle(color: Colors.white)),
      content: Text(
        'This message will be deleted for all participants in the conversation.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _deleteMessage(message, 'delete_for_everyone');
          },
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

Future<void> _deleteMessage(Message message, String deletionType) async {
  final success = await DeletionService.deleteMessage(
    messageId: message.id,
    deletionType: deletionType,
  );

  if (success) {
    if (deletionType == 'delete_for_everyone') {
      // Update database locally AND UI
      await _dbService.markMessageAsDeletedForEveryone(message.id);
      _handleDeletedForEveryone(message.id);
    } else {
      // Update database locally AND UI
      await _dbService.markMessageAsDeletedForMe(message.id);
      _chatProvider.removeMessage(message.id);
    }
  } else {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete message')),
      );
    }
  }
}

Future<void> _handleDeletedForEveryone(int messageId) async {
  final messageIndex = _chatProvider.messages.indexWhere((msg) => msg.id == messageId);
  if (messageIndex != -1) {
    final deletedMessage = _chatProvider.messages[messageIndex].copyWith(
      content: "This message was deleted",
    );
    _chatProvider.messages[messageIndex] = deletedMessage;
    _chatProvider.notifyListeners();

    await _dbService.markMessageAsDeletedForEveryone(messageId);
  }
}

Future<void> _deleteSelectedMessages() async {
  if (_selectedMessageIds.isEmpty) return;

  // Show deletion type selection dialog
  final deletionType = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text('Delete ${_selectedMessageIds.length} messages?',
                  style: TextStyle(color: Colors.white)),
      content: Text(
        'Choose deletion type:',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('delete_for_me'),
          child: Text('Delete for me', style: TextStyle(color: Colors.white)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('delete_for_everyone'),
          child: Text('Delete for everyone', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (deletionType == null) return;

  // Additional confirmation for delete_for_everyone
  if (deletionType == 'delete_for_everyone') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text('Delete for everyone?', style: TextStyle(color: Colors.white)),
        content: Text(
          'These messages will be deleted for all participants.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }

  final List<int> idsToDelete = _selectedMessageIds.toList();
  int successCount = 0;

  for (int messageId in idsToDelete) {
    final success = await DeletionService.deleteMessage(
      messageId: messageId,
      deletionType: deletionType,
    );

    if (success) {
      successCount++;
      if (deletionType == 'delete_for_everyone') {
        _handleDeletedForEveryone(messageId);
      } else {
        _chatProvider.removeMessage(messageId);
      }
    }
  }

  _clearSelection();

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$successCount of ${idsToDelete.length} messages deleted'),
        backgroundColor: successCount == idsToDelete.length ? Colors.green : Colors.orange,
      ),
    );
  }
}

  Widget _buildMessageBubble(Message message, int index, int itemCount) {
    final isMe = message.senderUid == _currentUserUid;
    final bool isSelected = _selectedMessageIds.contains(message.id);
    final Key? itemKey = (index == itemCount - 1) ? _lastMessageKey : null;

    return InkWell(
      key: itemKey,
      onLongPress: () => _toggleMessageSelection(message),
      onTap: () {
        if (_isMultiSelectionMode) {
          _toggleMessageSelection(message);
        } else if (message.content == "This message was deleted") {
          _showDeletedMessageOptions(message);
        } else if (message.isFailed && isMe) {
          _retryMessage(message);
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: _getMessageGradient(message, isMe, isSelected),
              border: isSelected
                  ? Border.all(
                color: isMe ? Colors.lightGreenAccent : Colors.blueAccent,
                width: 2,
              )
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? "You" : message.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 16,
                    color: message.isFailed ? Colors.white70 : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('hh:mm a').format(message.timestamp),
                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildMessageStatusIcon(message),
                    ],
                    if (!widget.conversationInfo.isGroup && !isMe) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.lock, size: 10, color: Colors.white54),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _getMessageGradient(Message message, bool isMe, bool isSelected) {
    if (message.isFailed && isMe) {
      return const LinearGradient(colors: [Colors.red, Colors.redAccent]);
    }

    if (isSelected) {
      return isMe
          ? const LinearGradient(colors: [Colors.green, Colors.lightGreen])
          : const LinearGradient(colors: [Colors.blueGrey, Colors.lightBlueAccent]);
    }

    return isMe
        ? const LinearGradient(colors: [Colors.deepPurple, Colors.purpleAccent])
        : LinearGradient(colors: [Colors.grey[800]!, Colors.grey[900]!]);
  }

  Widget _buildMessageStatusIcon(Message message) {
    switch (message.status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        );
      case MessageStatus.sent:
      // Cloud upload icon
        return const Icon(
          Icons.cloud_upload,
          size: 12,
          color: Colors.white54,
        );
      case MessageStatus.delivered:
      // Satellite dish emoji 📡
        return const Text(
          '📡',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white54,
          ),
        );
      case MessageStatus.read:
      // Eye emoji 👁️
        return const Text(
          '👁️',
          style: TextStyle(
            fontSize: 10,
            color: Colors.blue,
          ),
        );
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.red);
    }
  }

void _showDeletedMessageOptions(Message message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text('Remove deleted message?', style: TextStyle(color: Colors.white)),
      content: Text(
        'This will permanently remove this deleted message from your view.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _removeDeletedMessage(message.id);
          },
          child: Text('Remove', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

Future<void> _removeDeletedMessage(int messageId) async {
  await _dbService.markMessageAsDeletedForMe(messageId);
  _chatProvider.removeMessage(messageId);
}


  Future<void> _retryMessage(Message failedMessage) async {
    final retryMessage = failedMessage.copyWith(status: MessageStatus.sending);
    _chatProvider.updateMessageStatus(failedMessage.id, retryMessage);

    print("🔄 _retryMessage called for message: ${failedMessage.content}");
  }

  Future<void> _copySelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final messagesToCopy = _chatProvider.messages
        .where((msg) => _selectedMessageIds.contains(msg.id))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final String copiedText = messagesToCopy.map((m) => m.content).join('\n');

    await Clipboard.setData(ClipboardData(text: copiedText));
    _clearSelection();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message(s) copied to clipboard.'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }
}