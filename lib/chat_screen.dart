import 'dart:async';
import 'dart:convert';
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

import 'chat_background.dart';
import 'home_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/device_service.dart';
import 'services/SignalService.dart';
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
    _messageSubscription = _websocketService.stream.listen((data) {
      print("[ChatScreen] 🔍 WebSocket stream received: $data");

      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        print("[ChatScreen] 🔍 Message type: $type");

        if (type == 'local_message_saved') {
          final conversationId = data['conversation_id'] as int?;
          print("[ChatScreen] 🔍 local_message_saved for conversation: $conversationId");
          if (conversationId == widget.conversationInfo.conversationId) {
            _refreshMessagesFromDb();
          }
        } else if (type == 'local_sent_message') {
          final conversationId = data['conversation_id'] as int?;
          print("[ChatScreen] 🔍 local_sent_message for conversation: $conversationId");
          if (conversationId == widget.conversationInfo.conversationId) {
            _handleLocalSentMessage(data);
          }
        } else if (type == 'message_status_update') {
          // Handle real-time status updates
          print("[ChatScreen] 🔍 message_status_update received: $data");
          final messageId = data['message_id'] as int?;
          final status = data['status'] as String?;
          final conversationId = data['conversation_id'] as int?;

          print("[ChatScreen] 🔍 Status update - messageId: $messageId, status: $status, conversationId: $conversationId");

          if (conversationId == widget.conversationInfo.conversationId &&
              messageId != null && status != null) {
            print("[ChatScreen] 🔍 Calling _updateMessageStatusInUI...");
            _updateMessageStatusInUI(messageId, status);
          } else {
            print("[ChatScreen] ❌ Status update filtered out - wrong conversation or missing data");
          }
        }
      } else {
        print("[ChatScreen] 🔍 Non-map data received: ${data.runtimeType}");
      }
    });
  }

  Future<void> testForwardSecrecy() async {
    try {
      print("[ForwardSecrecyTest] Starting forward secrecy test...");

      if (_recipientUid == null) {
        print("[ForwardSecrecyTest] No recipient UID, cannot test");
        return;
      }

      // Get current messages count for comparison
      final messagesBefore = _chatProvider.messages.length;
      print("[ForwardSecrecyTest] Messages before session clear: $messagesBefore");

      // Log some current message IDs for tracking
      final currentMessageIds = _chatProvider.messages.map((m) => m.id).take(3).toList();
      print("[ForwardSecrecyTest] Sample message IDs: $currentMessageIds");

      // Clear the Signal Protocol session
      print("[ForwardSecrecyTest] Clearing Signal Protocol session...");
      await SignalService.clearSession(recipientUid: _recipientUid!);
      print("[ForwardSecrecyTest] Session cleared successfully");

      // Clear the decryption cache to force re-decryption attempts
      _decryptedMessageIds.clear();
      print("[ForwardSecrecyTest] Cleared decryption cache");

      // Try to refresh and decrypt existing messages
      print("[ForwardSecrecyTest] Attempting to decrypt old messages...");
      await _refreshMessagesFromDb();

      // Check results
      final messagesAfter = _chatProvider.messages.length;
      print("[ForwardSecrecyTest] Messages after session clear: $messagesAfter");

      // Count messages that failed to decrypt
      final failedDecryptions = _chatProvider.messages
          .where((msg) => msg.content.contains("Failed to decrypt"))
          .length;

      print("[ForwardSecrecyTest] Messages that failed to decrypt: $failedDecryptions");

      // Analyze results
      if (failedDecryptions > 0) {
        print("[ForwardSecrecyTest] ✅ FORWARD SECRECY WORKING: ${failedDecryptions} messages failed to decrypt after session clear");
      } else {
        print("[ForwardSecrecyTest] ❌ FORWARD SECRECY ISSUE: All messages still decryptable after session clear");
      }

      print("[ForwardSecrecyTest] Forward secrecy test completed");

    } catch (e) {
      print("[ForwardSecrecyTest] Test error: $e");
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

    await _refreshMessagesFromDb();

    // NEW: Load and merge sent messages from quick replies
    await _loadAndMergeSentMessages();

    print("[ChatScreen] 🔍 About to call syncMessageStatuses for conversation ${widget.conversationInfo.conversationId}");
    await _websocketService.syncMessageStatuses(widget.conversationInfo.conversationId);

    // Mark messages as read when opening chat
    await _markMessagesAsRead();

    print("[ChatScreen] ✅ syncMessageStatuses call completed");
    if (mounted) setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(instant: true));
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

      // Check if content looks like encrypted base64 data
      if (message.content.length > 50 && _isBase64(message.content)) {
        try {
          final decryptedContent = await SignalService.decryptMessage(
            senderUid: message.senderUid!,
            ciphertextB64: message.content,
          );

          if (decryptedContent != null) {
            final decryptedMessage = message.copyWith(content: decryptedContent);
            messages[i] = decryptedMessage;

            // Update database with decrypted content
            await _dbService.insertMessage(decryptedMessage);
            _decryptedMessageIds.add(message.id);
          }
        } catch (e) {
          print('Failed to decrypt message ${message.id}: $e');
          messages[i] = message.copyWith(content: '*** Failed to decrypt ***');
        }
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

  Future<bool> _ensureSessionEstablished() async {
    print("🔍 _ensureSessionEstablished called for $_recipientUid");

    if (_recipientUid == null || widget.conversationInfo.isGroup) {
      print("❌ Skipping session: recipientUid=$_recipientUid, isGroup=${widget.conversationInfo.isGroup}");
      return false;
    }

    if (_establishingSession) {
      print("⏳ Session establishment already in progress");
      return false;
    }

    final restored = await SignalService.restoreSessionState(recipientUid: _recipientUid!);
    if (restored) {
      setState(() => _sessionEstablished = true);
      return true;
    }

    print("🔍 Checking if session already established: $_sessionEstablished");

    // First check if session already exists
    if (!_sessionEstablished) {
      print("🔍 Calling SignalService.hasSession for $_recipientUid");
      final hasSession = await SignalService.hasSession(recipientUid: _recipientUid!);
      print("✅ SignalService.hasSession returned: $hasSession");
      if (hasSession) {
        setState(() => _sessionEstablished = true);
        return true;
      }
    } else {
      return true;
    }

    // Only create new session if none exists
    setState(() => _establishingSession = true);

    try {
      final bundle = await DeviceService.fetchPrekeyBundle(
        targetUid: _recipientUid!,
        deviceId: 1,
      );

      if (bundle == null) {
        return false;
      }

      final success = await SignalService.initSession(
        recipientUid: _recipientUid!,
        prekeyBundle: bundle,
      );

      if (success) {
        setState(() => _sessionEstablished = true);
        return true;
      }

      return false; // Add this return statement

    } catch (e) {
      print('Error establishing session: $e');
      return false;
    } finally {
      setState(() => _establishingSession = false);
    }
  }

  Future<void> _sendMessage() async {
    print("📤 _sendMessage called");
    print("🔍 Current recipientUid: $_recipientUid");
    print("🔍 Is group chat: ${widget.conversationInfo.isGroup}");
    final messageText = _controller.text.trim();
    if (messageText.isEmpty) return;

    // Ensure WebSocket is connected before sending
    if (!_websocketService.isConnected) {
      print("WebSocket disconnected - attempting reconnect...");
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final token = await user.getIdToken();
          await _websocketService.connect(token);
        } catch (e) {
          print("Failed to reconnect WebSocket: $e");
          // Show error to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Connection lost. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
    }

    // Clear the input field immediately for better UX
    _controller.clear();

    // Create optimistic message with "sending" status
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final optimisticMessage = Message(
      id: tempId,
      conversationId: widget.conversationInfo.conversationId,
      username: _currentUser,
      content: messageText,
      timestamp: DateTime.now(),
      senderUid: _currentUserUid,
      status: MessageStatus.sending,
    );

    // Add optimistic message to UI immediately
    _chatProvider.addMessage(optimisticMessage);
    _scrollToBottom();

    try {
      String? encryptedContent;

      if (widget.conversationInfo.isGroup) {
        // For groups, use plaintext encoding for now
        encryptedContent = base64Encode(utf8.encode(messageText));
      } else {
        // For 1-on-1 chats, use Signal protocol encryption
        if (_recipientUid == null) {
          throw Exception('No recipient UID for 1-on-1 chat');
        }

        // Ensure session is established
        if (!_sessionEstablished) {
          print("No session established, waiting for session setup...");
          final sessionReady = await _ensureSessionEstablished();
          if (!sessionReady) {
            throw Exception('Failed to establish encrypted session');
          }
          await Future.delayed(Duration(milliseconds: 100));
        }

        // Encrypt the message
        encryptedContent = await SignalService.encryptMessage(
          recipientUid: _recipientUid!,
          plaintext: messageText,
        );

        if (encryptedContent == null) {
          throw Exception('Failed to encrypt message');
        }
      }

      // Send encrypted content to server
      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedContent,
      );

      // Update optimistic message with real server ID and "sent" status
      final realMessageId = response['message_id'] as int;
      final sentMessage = optimisticMessage.copyWith(
        id: realMessageId,
        status: MessageStatus.sent,
      );

      // Save to database with real ID
      await _dbService.insertMessage(sentMessage);

      // Update UI to show "sent" status (keep the message visible for sender)
      _chatProvider.updateMessageStatus(tempId, sentMessage);

    } catch (e) {
      print('Error sending message: $e');

      // Update optimistic message to show failed status
      final failedMessage = optimisticMessage.copyWith(
        status: MessageStatus.failed,
      );
      _chatProvider.updateMessageStatus(tempId, failedMessage);

      // Restore the message text for retry
      _controller.text = messageText;

      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _sendMessage(),
            ),
          ),
        );
      }
    }
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
              actions: [
                if (!widget.conversationInfo.isGroup && _recipientUid != null)
                  IconButton(
                    icon: const Icon(Icons.security),
                    onPressed: () {
                      testForwardSecrecy();
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Forward secrecy test started - check logs'))
                      );
                    },
                  ),
              ],
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

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Messages?'),
        content: Text(
          'Are you sure you want to delete ${_selectedMessageIds.length} selected message(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User not authenticated.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final token = await user.getIdToken();
      final List<int> idsToDelete = _selectedMessageIds.toList();

      for (int messageId in idsToDelete) {
        try {
          final url = Uri.parse('http://192.168.29.81:8080/messages/$messageId');
          final response = await http.delete(
            url,
            headers: {'Authorization': 'Bearer $token'},
          );

          if (response.statusCode != 200) {
            print('Failed to delete message $messageId: ${response.statusCode}');
          }
          await _dbService.deleteMessage(messageId);
        } catch (e) {
          print('Error deleting message $messageId: $e');
        }
      }

      await _refreshMessagesFromDb();
      _clearSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Messages deletion process initiated.'),
            backgroundColor: Colors.green,
          ),
        );
      }
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


  Future<void> _retryMessage(Message failedMessage) async {
    final retryMessage = failedMessage.copyWith(status: MessageStatus.sending);
    _chatProvider.updateMessageStatus(failedMessage.id, retryMessage);

    _controller.text = failedMessage.content;
    await _sendMessage();
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