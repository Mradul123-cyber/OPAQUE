import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal_lib; // Use prefix
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/message_model.dart' as signal_lib;
import 'package:zarq_messenger/services/conversation_service.dart';

import 'chat_background.dart';
import 'home_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _currentUser = "";
  String? _currentUserUid;

  // Services
  late final ChatProvider _chatProvider;
  late final ConversationService _apiService;
  late final DatabaseService _dbService;
  late final WebSocketService _websocketService;

  bool _isLoading = true;
  StreamSubscription? _webSocketSubscription;

  final Set<int> _selectedMessageIds = {};
  bool _isMultiSelectionMode = false;
  final GlobalKey _lastMessageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _apiService = Provider.of<ConversationService>(context, listen: false);
    _dbService = Provider.of<DatabaseService>(context, listen: false);
    _websocketService = Provider.of<WebSocketService>(context, listen: false);

    _chatProvider.setCurrentConversationId(
      widget.conversationInfo.conversationId,
    );
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    await _getCurrentUser();
    if (_currentUserUid == null) return;

    await _refreshMessagesFromDb();
    if (mounted) setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(instant: true),
    );
  }

  Future<void> _refreshMessagesFromDb() async {
    final messages = await _dbService.getMessages(
      widget.conversationInfo.conversationId,
    );
    if (mounted) {
      _chatProvider.setMessages(messages);
    }
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
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
                    title: Text(widget.conversationInfo.chatTitle),
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
                              ..sort(
                                (a, b) => a.timestamp.compareTo(b.timestamp),
                              );
                            return ListView.builder(
                              controller: _scrollController,
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                return _buildMessageBubble(
                                  message,
                                  index,
                                  messages.length,
                                );
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
          final url = Uri.parse(
            'http://192.168.29.81:8080/messages/$messageId',
          );
          final response = await http.delete(
            url,
            headers: {'Authorization': 'Bearer $token'},
          );

          if (response.statusCode != 200 && response.statusCode != 200) {
            // handle both snake/dart typo just in case; primary is response.statusCode
            print(
              'Failed to delete message $messageId: ${response.statusCode}',
            );
          }
        } catch (e) {
          print('Error deleting message $messageId: $e');
        }
      }
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

      Widget _buildMessageBubble(signal_lib.Message message, int index, int itemCount) {
    final isMe = message.senderUid == _currentUserUid;
    final bool isSelected = _selectedMessageIds.contains(message.id);
    final Key? itemKey = (index == itemCount - 1) ? _lastMessageKey : null;

    return InkWell(
      key: itemKey,
      onLongPress: () => _toggleMessageSelection(message),
      onTap: () {
        if (_isMultiSelectionMode) {
          _toggleMessageSelection(message);
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
              gradient: (isMe
                  ? (isSelected
                        ? const LinearGradient(
                            colors: [Colors.green, Colors.lightGreen],
                          )
                        : const LinearGradient(
                            colors: [Colors.deepPurple, Colors.purpleAccent],
                          ))
                  : (isSelected
                        ? const LinearGradient(
                            colors: [Colors.blueGrey, Colors.lightBlueAccent],
                          )
                        : LinearGradient(
                            colors: [Colors.grey[800]!, Colors.grey[900]!],
                          ))),
              border: isSelected
                  ? Border.all(
                      color: isMe ? Colors.lightGreenAccent : Colors.blueAccent,
                      width: 2,
                    )
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                Text(message.content, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  DateFormat('hh:mm a').format(message.timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copySelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    final messagesToCopy =
        _chatProvider.messages
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
