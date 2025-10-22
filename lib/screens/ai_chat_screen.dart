import 'package:flutter/material.dart';
import 'package:googleapis/script/v1.dart';
import 'package:zarq_messenger/services/ai_service.dart';
import 'package:zarq_messenger/services/ai_chat_history_service.dart';
import 'dart:async';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AIService _aiService = AIService();
  final AIChatHistoryService _historyService = AIChatHistoryService.instance;

  bool _isOnDeviceMode = false; // Cloud AI mode (default)
  bool _isTerminalMode = true; // Default to terminal UI
  List<AIMessage> _messages = [];
  bool _isTyping = false;
  bool _isInitializing = true;
  int? _currentConversationId;
  List<AIConversation> _conversations = [];

  // Terminal animation states
  String _currentTypingText = '';
  int _typingIndex = 0;
  Timer? _typingTimer;
  bool _showCursor = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    _initializeAI();
    _startCursorBlink();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
    });
  }

  void _startCursorBlink() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 530), (timer) {
      if (mounted) {
        setState(() {
          _showCursor = !_showCursor;
        });
      }
    });
  }

  Future<void> _initializeAI() async {
    setState(() {
      _isInitializing = true;
    });

    await _aiService.initialize();
    await _historyService.init();

    // Load last conversation or create new one
    await _loadLastConversation();

    setState(() {
      _isInitializing = false;
    });

    // Only add welcome message if no previous messages
    if (_messages.isEmpty) {
      _addWelcomeMessage();
    }
  }

  Future<void> _loadLastConversation() async {
    try {
      final lastConv = await _historyService.getLastConversation();
      if (lastConv != null) {
        _currentConversationId = lastConv.id;
        _isTerminalMode = lastConv.isTerminalMode;
        _isOnDeviceMode = lastConv.isOnDeviceMode;

        // Load messages
        final messageData = await _historyService.getMessages(lastConv.id);
        setState(() {
          _messages = messageData.map((data) => AIMessage(
            content: data.content,
            isUser: data.isUser,
            timestamp: data.timestamp,
            isOnDevice: data.isOnDevice,
          )).toList();
        });
      } else {
        // Create new conversation
        await _createNewConversation();
      }

      // Load all conversations for sidebar
      await _loadConversations();
    } catch (e) {
      debugPrint('[AIChatScreen] Error loading conversation: $e');
      await _createNewConversation();
    }
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await _historyService.getAllConversations();
      setState(() {
        _conversations = conversations;
      });
    } catch (e) {
      debugPrint('[AIChatScreen] Error loading conversations: $e');
    }
  }

  Future<void> _createNewConversation() async {
    try {
      final title = 'New Chat - ${_formatDate(DateTime.now())}';
      final id = await _historyService.createConversation(
        title: title,
        isTerminalMode: _isTerminalMode,
        isOnDeviceMode: _isOnDeviceMode,
      );

      setState(() {
        _currentConversationId = id;
        _messages = [];
      });

      await _loadConversations();
    } catch (e) {
      debugPrint('[AIChatScreen] Error creating conversation: $e');
    }
  }

  Future<void> _switchConversation(int conversationId) async {
    try {
      // Close drawer first
      Navigator.pop(context);

      // Load selected conversation
      final messageData = await _historyService.getMessages(conversationId);
      final conversation = _conversations.firstWhere((c) => c.id == conversationId);

      setState(() {
        _currentConversationId = conversationId;
        _isTerminalMode = conversation.isTerminalMode;
        _isOnDeviceMode = conversation.isOnDeviceMode;
        _messages = messageData.map((data) => AIMessage(
          content: data.content,
          isUser: data.isUser,
          timestamp: data.timestamp,
          isOnDevice: data.isOnDevice,
        )).toList();
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('[AIChatScreen] Error switching conversation: $e');
      // Close drawer even on error
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _deleteConversation(int conversationId) async {
    try {
      await _historyService.deleteConversation(conversationId);
      await _loadConversations();

      // If deleted current conversation, create new one
      if (_currentConversationId == conversationId) {
        await _createNewConversation();
        _addWelcomeMessage();
      }
    } catch (e) {
      debugPrint('[AIChatScreen] Error deleting conversation: $e');
    }
  }

  Future<void> _renameConversation(int conversationId, String currentTitle) async {
    final newTitle = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Rename',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _RenameDialog(
          currentTitle: currentTitle,
          isTerminalMode: _isTerminalMode,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != currentTitle) {
      try {
        await _historyService.updateConversationTitle(conversationId, newTitle);
        await _loadConversations();
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        debugPrint('[AIChatScreen] Error renaming conversation: $e');
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    super.dispose();
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(AIMessage(
        content: "System initialized successfully.\n"
            "Zarq AI Terminal - Powered by Gemini\n"
            "Cloud connection established.\n\n"
            "Type your message below...",
        isUser: false,
        timestamp: DateTime.now(),
        isOnDevice: true,
      ));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startTypingAnimation(String text) {
    if (!_isTerminalMode) {
      // In simple mode, just add message directly
      setState(() {
        _messages.add(AIMessage(
          content: text,
          isUser: false,
          timestamp: DateTime.now(),
          isOnDevice: _isOnDeviceMode,
        ));
        _isTyping = false;
      });
      _scrollToBottom();
      return;
    }

    // Terminal mode - with smooth typing animation
    _currentTypingText = '';
    _typingIndex = 0;

    _typingTimer?.cancel();

    // Batch updates for smoother performance
    int updateCounter = 0;
    const int batchSize = 5; // Add 5 characters per batch
    const int updateFrequency = 3; // Update UI every 3 batches

    _typingTimer = Timer.periodic(const Duration(milliseconds: 8), (timer) {
      if (_typingIndex < text.length) {
        // Add characters in batches
        final charsToAdd = (_typingIndex + batchSize > text.length)
            ? text.length - _typingIndex
            : batchSize;
        _currentTypingText = text.substring(0, _typingIndex + charsToAdd);
        _typingIndex += charsToAdd;
        updateCounter++;

        // Only call setState every few iterations to reduce lag
        if (updateCounter >= updateFrequency || _typingIndex >= text.length) {
          if (mounted) {
            setState(() {});
            updateCounter = 0;

            // Scroll smoothly
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
              }
            });
          }
        }
      } else {
        timer.cancel();
        // Animation complete, add the full message
        if (mounted) {
          setState(() {
            _messages.add(AIMessage(
              content: text,
              isUser: false,
              timestamp: DateTime.now(),
              isOnDevice: _isOnDeviceMode,
            ));
            _isTyping = false;
            _currentTypingText = '';
          });
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Add user message
    setState(() {
      _messages.add(AIMessage(
        content: text,
        isUser: true,
        timestamp: DateTime.now(),
        isOnDevice: _isOnDeviceMode,
      ));
      _isTyping = true;
    });

    _messageController.clear();
    _scrollToBottom();

    // Save user message to database
    if (_currentConversationId != null) {
      try {
        await _historyService.saveMessage(
          conversationId: _currentConversationId!,
          content: text,
          isUser: true,
          isOnDevice: _isOnDeviceMode,
        );
      } catch (e) {
        debugPrint('[AIChatScreen] Error saving user message: $e');
      }
    }

    // Call backend AI service
    final response = await _aiService.processChat(text);

    // Remove markdown and format for terminal
    String cleanContent = response.content
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'__'), '')
        .replaceAll(RegExp(r'\*'), '')
        .replaceAll(RegExp(r'`'), '')
        .replaceAll(RegExp(r'##+ '), '')
        .replaceAll(RegExp(r'^\* ', multiLine: true), '> ')
        .replaceAll(RegExp(r'^\- ', multiLine: true), '> ');

    // Save AI response to database
    if (_currentConversationId != null) {
      try {
        await _historyService.saveMessage(
          conversationId: _currentConversationId!,
          content: cleanContent,
          isUser: false,
          isOnDevice: _isOnDeviceMode,
        );
      } catch (e) {
        debugPrint('[AIChatScreen] Error saving AI message: $e');
      }
    }

    // Start typing animation
    _startTypingAnimation(cleanContent);
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF00FF41), width: 3),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  color: Color(0xFF00FF41),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '[ INITIALIZING SYSTEM... ]',
                style: TextStyle(
                  color: Color(0xFF00FF41),
                  fontFamily: 'Courier',
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _isTerminalMode ? const Color(0xFF0D1117) : Colors.white,
      drawer: _buildHistorySidebar(),
      appBar: AppBar(
        backgroundColor: _isTerminalMode ? const Color(0xFF0D1117) : Colors.white,
        elevation: _isTerminalMode ? 0 : 1,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isTerminalMode ? 'ZARQ AI TERMINAL' : 'Zarq AI Assistant',
                  style: TextStyle(
                    color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
                    fontFamily: _isTerminalMode ? 'Courier' : null,
                    fontSize: _isTerminalMode ? 14 : 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: _isTerminalMode ? 2 : 0,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_isTerminalMode)
                  const Text(
                    '[CLOUD AI MODE]',
                    style: TextStyle(
                      color: Color(0xFF00BFFF),
                      fontFamily: 'Courier',
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  )
                else
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud,
                          size: 14,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Cloud AI • Powered by Gemini',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          // New chat button
          IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
              size: 22,
            ),
            onPressed: () async {
              await _createNewConversation();
              setState(() {
                _messages = [];
              });
              _addWelcomeMessage();
            },
            tooltip: 'New Chat',
          ),
          // UI Mode toggle
          IconButton(
            icon: Icon(
              _isTerminalMode ? Icons.chat_bubble_outline : Icons.terminal,
              color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isTerminalMode = !_isTerminalMode;
              });
            },
            tooltip: _isTerminalMode ? 'Switch to Simple UI' : 'Switch to Terminal UI',
          ),
          IconButton(
            icon: Icon(
              Icons.info_outline,
              color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
              size: 20,
            ),
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: _isTerminalMode ? _buildTerminalUI() : _buildSimpleUI(),
    );
  }

  Widget _buildTerminalUI() {
    return Column(
      children: [
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(
              top: BorderSide(color: Color(0xFF00BFFF), width: 1),
              bottom: BorderSide(color: Color(0xFF00BFFF), width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF00BFFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF00BFFF),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CLOUD AI MODE | POWERED BY GEMINI',
                  style: TextStyle(
                    color: Color(0xFF00BFFF),
                    fontFamily: 'Courier',
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length && _isTyping) {
                return _buildTypingMessage();
              }
              return _buildTerminalMessage(_messages[index]);
            },
          ),
        ),

        // Input
        _buildTerminalInput(),
      ],
    );
  }

  Widget _buildSimpleUI() {
    return Column(
      children: [
        // Simple status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            border: const Border(
              bottom: BorderSide(
                color: Colors.blue,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_outlined,
                size: 18,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Powered by Gemini • Cloud AI • Enhanced capabilities',
                  style: TextStyle(
                    color: Colors.blue[900],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _buildSimpleTypingIndicator();
                  }
                  return _buildSimpleMessageBubble(_messages[index]);
                },
              );
            },
          ),
        ),

        // Input
        _buildSimpleInput(),
      ],
    );
  }

  Widget _buildTerminalMessage(AIMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt line
          Row(
            children: [
              Text(
                message.isUser ? 'user@zarq:~\$ ' : 'ai@zarq:~\$ ',
                style: const TextStyle(
                  color: Color(0xFF00FF41),
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  color: const Color(0xFF00FF41).withOpacity(0.5),
                  fontFamily: 'Courier',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Message content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser
                  ? const Color(0xFF161B22)
                  : Colors.transparent,
              border: message.isUser
                  ? Border.all(color: const Color(0xFF00FF41).withOpacity(0.3), width: 1)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              message.content,
              style: TextStyle(
                color: message.isUser
                    ? Colors.white
                    : const Color(0xFF00FF41),
                fontFamily: 'Courier',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingMessage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ai@zarq:~\$ ',
                style: TextStyle(
                  color: Color(0xFF00FF41),
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatTime(DateTime.now()),
                style: TextStyle(
                  color: const Color(0xFF00FF41).withOpacity(0.5),
                  fontFamily: 'Courier',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _currentTypingText,
                  style: const TextStyle(
                    color: Color(0xFF00FF41),
                    fontFamily: 'Courier',
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
              if (_showCursor)
                Container(
                  width: 8,
                  height: 16,
                  color: Colors.white,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(
          top: BorderSide(color: Color(0xFF00FF41), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '> ',
            style: TextStyle(
              color: Color(0xFF00FF41),
              fontFamily: 'Courier',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              cursorColor: Colors.white,
              cursorWidth: 8,
              cursorHeight: 16,
              style: const TextStyle(
                color: Color(0xFF00FF41),
                fontFamily: 'Courier',
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter command...',
                hintStyle: TextStyle(
                  color: Color(0xFF30363D),
                  fontFamily: 'Courier',
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00FF41), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.send,
                color: Color(0xFF00FF41),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1117),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFF00FF41), width: 1),
          ),
          title: const Text(
            '[ SYSTEM INFO ]',
            style: TextStyle(
              color: Color(0xFF00FF41),
              fontFamily: 'Courier',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const SingleChildScrollView(
            child: Text(
              'ZARQ AI TERMINAL v2.0\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
              '> CLOUD AI MODE:\n'
              '  • Powered by Gemini\n'
              '  • Enhanced capabilities\n'
              '  • Context-aware responses\n'
              '  • Multi-turn conversations\n\n'
              '> PRIVACY NOTICE:\n'
              '  • AI messages processed by Google\n'
              '  • Your E2EE messages remain private\n'
              '  • AI chat is separate from messaging\n\n'
              '> All conversations stored\n'
              '  encrypted on your device.\n\n'
              'Built with ❤️ for privacy',
              style: TextStyle(
                color: Color(0xFF00BFFF),
                fontFamily: 'Courier',
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '[ CLOSE ]',
                style: TextStyle(
                  color: Color(0xFF00FF41),
                  fontFamily: 'Courier',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildHistorySidebar() {
    return Drawer(
      backgroundColor: _isTerminalMode ? const Color(0xFF0D1117) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isTerminalMode ? const Color(0xFF161B22) : Colors.grey[100],
                border: Border(
                  bottom: BorderSide(
                    color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isTerminalMode ? '[ CHAT HISTORY ]' : 'Chat History',
                        style: TextStyle(
                          color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
                          fontFamily: _isTerminalMode ? 'Courier' : null,
                          fontSize: _isTerminalMode ? 14 : 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: _isTerminalMode ? 2 : 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_conversations.length} conversation${_conversations.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: _isTerminalMode
                          ? const Color(0xFF00FF41).withOpacity(0.6)
                          : Colors.grey[600],
                      fontFamily: _isTerminalMode ? 'Courier' : null,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Conversations list
            Expanded(
              child: _conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _isTerminalMode
                              ? '> No conversations yet...\n> Start a new chat!'
                              : 'No conversations yet.\nStart chatting to see history here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isTerminalMode
                                ? const Color(0xFF00FF41).withOpacity(0.5)
                                : Colors.grey,
                            fontFamily: _isTerminalMode ? 'Courier' : null,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _conversations.length,
                      itemBuilder: (context, index) {
                        final conv = _conversations[index];
                        final isActive = conv.id == _currentConversationId;

                        return Dismissible(
                          key: Key('conv_${conv.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: _isTerminalMode ? const Color(0xFF161B22) : Colors.red[50],
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(
                              Icons.delete_outline,
                              color: _isTerminalMode ? const Color(0xFFFF0000) : Colors.red,
                            ),
                          ),
                          onDismissed: (direction) {
                            _deleteConversation(conv.id);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isActive
                                  ? (_isTerminalMode
                                      ? const Color(0xFF161B22)
                                      : Colors.blue.withOpacity(0.1))
                                  : null,
                              border: isActive && _isTerminalMode
                                  ? Border(
                                      left: BorderSide(
                                        color: const Color(0xFF00FF41),
                                        width: 3,
                                      ),
                                    )
                                  : null,
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              leading: Icon(
                                conv.isTerminalMode ? Icons.terminal : Icons.chat_bubble_outline,
                                color: _isTerminalMode
                                    ? (isActive ? const Color(0xFF00FF41) : const Color(0xFF00FF41).withOpacity(0.5))
                                    : (isActive ? Colors.blue : Colors.grey),
                                size: 20,
                              ),
                              title: Text(
                                conv.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _isTerminalMode
                                      ? (isActive ? const Color(0xFF00FF41) : const Color(0xFF00FF41).withOpacity(0.7))
                                      : (isActive ? Colors.blue : Colors.black87),
                                  fontFamily: _isTerminalMode ? 'Courier' : null,
                                  fontSize: 13,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                _formatDate(conv.updatedAt),
                                style: TextStyle(
                                  color: _isTerminalMode
                                      ? const Color(0xFF00FF41).withOpacity(0.4)
                                      : Colors.grey[600],
                                  fontFamily: _isTerminalMode ? 'Courier' : null,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _renameConversation(conv.id, conv.title),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: _isTerminalMode
                                              ? const Color(0xFF00FF41).withOpacity(0.7)
                                              : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (!isActive) {
                                  _switchConversation(conv.id);
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                              onLongPress: () => _renameConversation(conv.id, conv.title),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isTerminalMode ? const Color(0xFF161B22) : Colors.grey[100],
                border: Border(
                  top: BorderSide(
                    color: _isTerminalMode ? const Color(0xFF00FF41) : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: _isTerminalMode
                        ? const Color(0xFF00FF41).withOpacity(0.5)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isTerminalMode
                          ? '< Swipe left to delete >'
                          : 'Swipe left to delete',
                      style: TextStyle(
                        color: _isTerminalMode
                            ? const Color(0xFF00FF41).withOpacity(0.5)
                            : Colors.grey[600],
                        fontFamily: _isTerminalMode ? 'Courier' : null,
                        fontSize: 11,
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
  }

  // Simple UI widgets - Web AI Chat style (no bubbles)
  Widget _buildSimpleMessageBubble(AIMessage message) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive padding based on screen width
        final horizontalPadding = constraints.maxWidth > 600 ? 24.0 : 16.0;
        final avatarSize = constraints.maxWidth > 600 ? 36.0 : 32.0;
        final spacing = constraints.maxWidth > 600 ? 16.0 : 12.0;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          decoration: BoxDecoration(
            color: message.isUser ? Colors.white : const Color(0xFFF7F7F8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: message.isUser ? const Color(0xFF5B5BD6) : const Color(0xFF19C37D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  message.isUser ? Icons.person : Icons.stars_rounded,
                  color: Colors.white,
                  size: avatarSize * 0.6,
                ),
              ),
              SizedBox(width: spacing),
              // Message content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender label
                    Text(
                      message.isUser ? 'You' : 'Zarq AI',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Message text
                    SelectableText(
                      message.content,
                      style: const TextStyle(
                        color: Color(0xFF2D2D2D),
                        fontSize: 15,
                        height: 1.6,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimpleTypingIndicator() {
    // Web AI style typing indicator - no bubble
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth > 600 ? 24.0 : 16.0;
        final avatarSize = constraints.maxWidth > 600 ? 36.0 : 32.0;
        final spacing = constraints.maxWidth > 600 ? 16.0 : 12.0;

        return Container(
          width: double.infinity,
          color: const Color(0xFFF7F7F8),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF19C37D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.stars_rounded,
                  color: Colors.white,
                  size: avatarSize * 0.6,
                ),
              ),
              SizedBox(width: spacing),
              // Typing dots
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSimpleTypingDot(0),
                    const SizedBox(width: 6),
                    _buildSimpleTypingDot(1),
                    const SizedBox(width: 6),
                    _buildSimpleTypingDot(2),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimpleTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        final delay = index * 0.15;
        final animValue = (value - delay).clamp(0.0, 1.0);
        final bounce = (animValue < 0.5) ? animValue * 2 : 2 - (animValue * 2);

        return Transform.translate(
          offset: Offset(0, -bounce * 4),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Colors.blue[600]!.withOpacity(0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3 * bounce),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        );
      },
      onEnd: () {
        if (mounted && _isTyping) {
          setState(() {});
        }
      },
    );
  }

  Widget _buildSimpleInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ask me anything...',
                  hintStyle: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.blue[600],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Separate stateful dialog for renaming to properly manage controller lifecycle
class _RenameDialog extends StatefulWidget {
  final String currentTitle;
  final bool isTerminalMode;

  const _RenameDialog({
    required this.currentTitle,
    required this.isTerminalMode,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.isTerminalMode ? const Color(0xFF0D1117) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: widget.isTerminalMode
            ? const BorderSide(color: Color(0xFF00FF41), width: 1)
            : BorderSide.none,
      ),
      title: Text(
        widget.isTerminalMode ? '[ RENAME CHAT ]' : 'Rename Chat',
        style: TextStyle(
          color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
          fontFamily: widget.isTerminalMode ? 'Courier' : null,
          fontSize: widget.isTerminalMode ? 14 : 18,
          fontWeight: FontWeight.bold,
          letterSpacing: widget.isTerminalMode ? 2 : 0,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        cursorColor: Colors.white,
        cursorWidth: 8,
        cursorHeight: 16,
        style: TextStyle(
          color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.black,
          fontFamily: widget.isTerminalMode ? 'Courier' : null,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: widget.isTerminalMode ? '> Enter new name...' : 'Enter new name',
          hintStyle: TextStyle(
            color: widget.isTerminalMode
                ? const Color(0xFF00FF41).withOpacity(0.5)
                : Colors.grey,
            fontFamily: widget.isTerminalMode ? 'Courier' : null,
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.grey,
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.blue,
              width: 2,
            ),
          ),
        ),
        maxLength: 50,
        onSubmitted: (value) {
          final title = value.trim();
          Navigator.of(context).pop(title.isNotEmpty ? title : null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(
            widget.isTerminalMode ? '[ CANCEL ]' : 'Cancel',
            style: TextStyle(
              color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.grey,
              fontFamily: widget.isTerminalMode ? 'Courier' : null,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            final title = _controller.text.trim();
            Navigator.of(context).pop(title.isNotEmpty ? title : null);
          },
          child: Text(
            widget.isTerminalMode ? '[ SAVE ]' : 'Save',
            style: TextStyle(
              color: widget.isTerminalMode ? const Color(0xFF00FF41) : Colors.blue,
              fontFamily: widget.isTerminalMode ? 'Courier' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class AIMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isOnDevice;

  AIMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    required this.isOnDevice,
  });
}
