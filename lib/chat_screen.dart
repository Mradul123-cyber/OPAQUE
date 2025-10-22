import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:zarq_messenger/message_model.dart' as signal_lib;
import 'package:zarq_messenger/providers/home_provider.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:zarq_messenger/services/conversation_service.dart';
import 'package:flutter/services.dart';
import 'package:zarq_messenger/services/deletion_service.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/services/webrtc_service.dart';

import 'home_screen.dart';
import 'message_model.dart';
import 'providers/chat_provider.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/device_service.dart';
import 'services/file_service.dart';
import 'models/message_reaction.dart';
import 'widgets/message_reactions_widget.dart';
import 'widgets/encryption_animation_widget.dart';
import 'widgets/particle_animation_widget.dart';
import 'widgets/ai_processing_particles.dart';
import 'services/group_encryption_service.dart';
import 'services/ai_service.dart';
import 'widgets/call_aware_screen.dart';
import 'services/global_call_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/fullscreen_image_viewer.dart';
import 'widgets/fullscreen_video_player.dart';
import 'widgets/global_call_overlay.dart';
import 'widgets/voice_message_recorder.dart';
import 'widgets/voice_message_player.dart';
import 'screens/group_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final WebSocketChannel? channel; // Nullable for offline mode
  final ConversationInfo conversationInfo;

  const ChatScreen({
    super.key,
    this.channel, // Optional for offline mode
    required this.conversationInfo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const platform = MethodChannel('com.zarq/signal');
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  String _currentUser = "";
  String? _currentUserUid;
  String? _currentUserAvatar;
  StreamSubscription? _messageSubscription;

  // Services
  late final ChatProvider _chatProvider;
  late final ConversationService _apiService;
  late final DatabaseService _dbService;
  late final WebSocketService _websocketService;
  final AIService _aiService = AIService();

  bool _isLoading = true;
  final Set<int> _decryptedMessageIds = {};
  final Set<int> _selectedMessageIds = {};
  final Set<int> _animatedMessageIds = {}; // Track which messages have been animated
  bool _isMultiSelectionMode = false;
  final GlobalKey _lastMessageKey = GlobalKey();
  final Set<int> _processedSentMessageIds = {};

  bool _sessionEstablished = false;
  bool _establishingSession = false;
  String? _recipientUid;
  bool _backgroundTasksCompleted = false;
  bool _groupEncryptionSetup = false;

  // Voice message recording state
  bool _isRecordingVoice = false;
  bool _hasTextInput = false;

  // AI mode state
  bool _isAIMode = false;
  bool _isAIProcessing = false;

  // Message search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Group member count state
  int? _groupMemberCount;

  // Typing indicator state
  bool _isOtherUserTyping = false;
  String? _typingUserUid;
  Timer? _typingTimer;
  bool _isCurrentlyTyping = false;

  // Typing animation controller
  late AnimationController _typingAnimationController;
  late List<Animation<double>> _typingDotAnimations;

  // Presence/online status state
  bool _isRecipientOnline = false;
  DateTime? _recipientLastSeen;

  // Cache for downloaded images
  final Map<int, Uint8List> _imageCache = {};

  // Cache for downloaded videos (stores file paths, not bytes)
  final Map<int, String> _videoCache = {};

  // Cache for video thumbnails (stores thumbnail bytes)
  final Map<int, Uint8List> _thumbnailCache = {};

  // Cache for downloaded documents (stores file paths, not bytes)
  final Map<int, String> _documentCache = {};

  // Wallpaper state
  Color _chatBackgroundColor = const Color(0xFFECE5DD);
  String? _chatBackgroundImage;

  // Blocked users
  List<String> _blockedUsers = [];
  bool _isUserBlocked = false;

  // E2E encryption banner state
  bool _showEncryptionBanner = true;
  bool _isRemovingBanner = false;
  bool _isBannerInHindi = true; // Default to Hindi

  // Cache for downloaded audio (stores file paths, not bytes)
  final Map<int, String> _audioCache = {};

  // Track in-progress image/video/audio loads to prevent duplicate decryption
  final Map<int, Future<Uint8List?>> _imageLoadingFutures = {};
  final Map<int, Future<String?>> _videoLoadingFutures = {};
  final Map<int, Future<String?>> _audioLoadingFutures = {};

  // Reply-to-message state
  Message? _replyingToMessage;

  // Cache for pending attachment metadata (for messages that haven't arrived yet)
  final Map<int, Map<String, dynamic>> _pendingAttachments = {};

  // Pagination state
  static const int _messagesPerPage = 50;
  bool _hasMoreMessages = false;
  bool _isLoadingMoreMessages = false;
  int _loadedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _apiService = Provider.of<ConversationService>(context, listen: false);
    _dbService = Provider.of<DatabaseService>(context, listen: false);
    _websocketService = Provider.of<WebSocketService>(context, listen: false);

    _chatProvider.setCurrentConversationId(widget.conversationInfo.conversationId);

    // 🚀 FIX: Mark messages as read IMMEDIATELY to clear badge instantly
    _markMessagesAsRead();

    _initializeChat();
    _loadWallpaper();
    _loadEncryptionBannerPreference();
    _aiService.initialize(); // Initialize AI service

    // Initialize typing animation controller (WhatsApp-style bouncing dots)
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Create 3 bouncing dot animations with staggered delays
    _typingDotAnimations = List.generate(3, (index) {
      final start = index * 0.2; // Stagger each dot by 20% of cycle
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.0, end: -8.0).chain(CurveTween(curve: Curves.easeOut)),
          weight: 25.0,
        ),
        TweenSequenceItem(
          tween: Tween(begin: -8.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
          weight: 25.0,
        ),
        TweenSequenceItem(
          tween: ConstantTween(0.0),
          weight: 50.0,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _typingAnimationController,
          curve: Interval(start, start + 0.5 > 1.0 ? 1.0 : start + 0.5, curve: Curves.linear),
        ),
      );
    });

    // Add scroll listener for pagination
    _scrollController.addListener(_onScroll);

    // Listen to text input changes for voice/send button toggle and typing indicators
    // Listen to text input changes for voice/send button toggle and typing indicators
    _controller.addListener(() {
      setState(() {
        _hasTextInput = _controller.text.trim().isNotEmpty;
      });
      _handleTypingIndicator();
    });

    // Listen to focus changes to scroll to last message when input is focused
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Small delay to let keyboard animation start
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollToBottom(instant: true); // Instant jump like WhatsApp
          }
        });
      }
    });

    // Setup GlobalCallManager callback for sending signals
    final callManager = Provider.of<GlobalCallManager>(context, listen: false);
    callManager.onSendSignal = (signalData) {
      final message = jsonEncode(signalData);
      // Only send if channel is available (online mode)
      widget.channel?.sink.add(message);
      // print('[ChatScreen] 📞 Sent call signal via GlobalCallManager: ${signalData['type']}');
    };

    _messageSubscription = _websocketService.stream.listen((data) async {
      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        // print('[ChatScreen] 📨 WebSocket message received: type=$type');

        if (type == 'local_message_saved') {
          final conversationId = data['conversation_id'] as int?;
          final messageId = data['message_id'] as int?;
          if (conversationId == widget.conversationInfo.conversationId && messageId != null) {
            await _addSingleMessageToUI(messageId);
          }
        } else if (type == 'local_sent_message') {
          final conversationId = data['conversation_id'] as int?;
          if (conversationId == widget.conversationInfo.conversationId) {
            _handleLocalSentMessage(data);
          }
        } else if (type == 'message_status_update') {
          final messageId = data['message_id'] as int?;
          final status = data['status'] as String?;
          final conversationId = data['conversation_id'] as int?;

          if (conversationId == widget.conversationInfo.conversationId &&
              messageId != null && status != null) {
            _updateMessageStatusInUI(messageId, status);
          }
        } else if (type == 'message_deleted') {
          final messageId = data['message_id'] as int?;
          final deletionType = data['deletion_type'] as String?;
          final conversationId = data['conversation_id'] as int?;

          if (messageId != null && conversationId == widget.conversationInfo.conversationId) {
            if (deletionType == 'delete_for_everyone') {
              _handleDeletedForEveryone(messageId);
            } else {
              await _dbService.markMessageAsDeletedForMe(messageId);
              _chatProvider.removeMessage(messageId);
            }
          }
        } else if (type == 'attachment_uploaded') {
          final messageId = data['message_id'] as int?;
          final attachmentId = data['attachment_id'] as int?;
          final conversationId = data['conversation_id'] as int?;

          if (messageId != null && conversationId == widget.conversationInfo.conversationId) {
            await _handleAttachmentUploaded(messageId, attachmentId, data);
          }
        } else if (type == 'typing') {
          final conversationId = data['conversation_id'] as int?;
          final senderUid = data['sender_uid'] as String?;
          final isTyping = data['is_typing'] as bool?;

          // print('[ChatScreen] ⌨️ RECEIVED typing data: convId=$conversationId, senderUid=$senderUid, isTyping=$isTyping');
          // print('[ChatScreen] ⌨️ Current: myConvId=${widget.conversationInfo.conversationId}, myUid=$_currentUserUid');

          if (conversationId == widget.conversationInfo.conversationId &&
              senderUid != null && isTyping != null && senderUid != _currentUserUid) {
            // print('[ChatScreen] ⌨️ ✅ Conditions met, calling handler');
            _handleTypingIndicatorReceived(senderUid, isTyping);
          } else {
            // print('[ChatScreen] ⌨️ ❌ Conditions NOT met:');
            // print('  - ConvId match: ${conversationId == widget.conversationInfo.conversationId}');
            // print('  - SenderUid not null: ${senderUid != null}');
            // print('  - IsTyping not null: ${isTyping != null}');
            // print('  - Not own message: ${senderUid != _currentUserUid}');
          }
        } else if (type == 'presence_status') {
          final userUid = data['user_uid'] as String?;
          final isOnline = data['is_online'] as bool?;
          final lastSeenTimestamp = data['last_seen'] as int?;

          if (userUid == _recipientUid && isOnline != null) {
            _handlePresenceUpdate(isOnline, lastSeenTimestamp);
          }
        } else if (type == 'reaction_added') {
          final messageId = data['message_id'] as int?;
          final userUid = data['user_uid'] as String?;
          final username = data['username'] as String?;
          final emoji = data['emoji'] as String?;

          if (messageId != null && userUid != null && emoji != null) {
            _handleReactionAdded(messageId, userUid, username, emoji);
          }
        } else if (type == 'reaction_removed') {
          final messageId = data['message_id'] as int?;
          final userUid = data['user_uid'] as String?;
          final emoji = data['emoji'] as String?;

          if (messageId != null && userUid != null && emoji != null) {
            _handleReactionRemoved(messageId, userUid, emoji);
          }
        }
        // Note: Call signaling (call_offer, call_answer, ice_candidate, call_rejected, call_ended)
        // is now handled by GlobalCallManager via its own WebSocket listener
      }
    });
  }

  Future<void> _addSingleMessageToUI(int messageId) async {
    final allMessages = await _dbService.getAllMessagesInConversation(widget.conversationInfo.conversationId);
    var newMessage = allMessages.where((msg) => msg.id == messageId).firstOrNull;

    if (newMessage != null && !await _dbService.isMessageDeletedForMe(messageId)) {
      // Check if there's pending attachment data for this message
      if (_pendingAttachments.containsKey(messageId)) {
        final attachmentData = _pendingAttachments[messageId]!;

        // Apply attachment metadata
        newMessage = newMessage.copyWith(
          attachmentId: attachmentData['attachment_id'] as int?,
          attachmentType: attachmentData['file_type'] as String?,
          hasAttachment: true,
          mediaEncryptionKey: attachmentData['media_encryption_key'] as String?,
          mediaEncryptionIv: attachmentData['media_encryption_iv'] as String?,
          senderDeviceId: attachmentData['sender_device_id'] as int? ?? newMessage.senderDeviceId,
        );

        // Save updated message to database
        await _dbService.insertMessage(newMessage);

        // Remove from pending cache
        _pendingAttachments.remove(messageId);
      }

      _chatProvider.addMessage(newMessage);
      _scrollToBottom();

      // ✅ FIX: Mark message as read if it's from another user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && newMessage.senderUid != currentUser.uid) {
        await _markMessagesAsRead();
      }
    }
  }

  void _handleLocalSentMessage(Map<String, dynamic> data) {
    try {
      final messageJson = data['message'] as Map<String, dynamic>;
      var message = Message.fromJson(messageJson);

      final existsInProvider = _chatProvider.messages.any((existing) =>
      existing.id == message.id ||
          (existing.content == message.content && existing.senderUid == message.senderUid));

      if (existsInProvider || _processedSentMessageIds.contains(message.id)) {
        return;
      }

      // Check if there's pending attachment data for this message
      if (_pendingAttachments.containsKey(message.id)) {
        final attachmentData = _pendingAttachments[message.id]!;

        message = message.copyWith(
          attachmentId: attachmentData['attachment_id'] as int?,
          attachmentType: attachmentData['file_type'] as String?,
          hasAttachment: true,
          mediaEncryptionKey: attachmentData['media_encryption_key'] as String?,
          mediaEncryptionIv: attachmentData['media_encryption_iv'] as String?,
          senderDeviceId: attachmentData['sender_device_id'] as int? ?? message.senderDeviceId,
        );

        _pendingAttachments.remove(message.id);
      }

      _processedSentMessageIds.add(message.id);
      _chatProvider.addMessage(message);
      _dbService.insertMessage(message);
      _scrollToBottom();
    } catch (e) {
      // print('[ChatScreen] Error handling local sent message: $e');
    }
  }

  void _updateMessageStatusInUI(int messageId, String statusString) {
    try {
      final status = MessageStatus.values.firstWhere(
            (s) => s.toString().split('.').last == statusString,
      );
      _chatProvider.updateMessageStatusById(messageId, status);
    } catch (e) {
      // print("[ChatScreen] Error updating message status: $e");
    }
  }

  Future<void> _markMessagesAsRead() async {
    await _websocketService.markMessagesAsRead(widget.conversationInfo.conversationId);
  }

  Future<void> _initializeChat() async {
    final startTime = DateTime.now();
    print('[ChatScreen] 🚀 _initializeChat started');

    await _getCurrentUser();
    if (_currentUserUid == null) return;

    // Set recipient info immediately (no await)
    if (!widget.conversationInfo.isGroup && widget.conversationInfo.partnerUid != null) {
      _recipientUid = widget.conversationInfo.partnerUid;
    }

    // 🚀 SHOW MESSAGES IMMEDIATELY (don't wait for session/encryption)
    await _refreshMessagesFromDb();

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('[ChatScreen] ✅ Messages shown in ${elapsed}ms');

    if (mounted) setState(() => _isLoading = false);

    // Scroll to bottom instantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom(instant: true);
      });
    });

    // ⏰ Do everything else in BACKGROUND (don't block UI, fire and forget)
    _initializeInBackground().then((_) {
      // Background tasks completed
    }).catchError((error) {
      // Silent error handling - don't interrupt user
      // print('[ChatScreen] Background init error: $error');
    });
  }

  /// Background initialization - doesn't block UI
  Future<void> _initializeInBackground() async {
    try {
      if (!widget.conversationInfo.isGroup && widget.conversationInfo.partnerUid != null) {
        // Check session in background (may fail offline)
        try {
          await _checkExistingSession();
        } catch (e) {
          // Offline: Session check failed, but user can still read messages
          print('[ChatScreen] ⚠️ Session check failed (offline?): $e');
        }

        // Query recipient's presence status for 1-1 chats (may fail offline)
        try {
          _websocketService.queryPresenceStatus(_recipientUid!);
        } catch (e) {
          print('[ChatScreen] ⚠️ Presence query failed (offline?): $e');
        }

        // Load blocked users (may fail offline)
        try {
          await _loadBlockedUsers();
        } catch (e) {
          print('[ChatScreen] ⚠️ Blocked users load failed (offline?): $e');
        }
      } else if (widget.conversationInfo.isGroup) {
        // Setup group encryption for group chats (may fail offline)
        try {
          await _setupGroupEncryption();
        } catch (e) {
          print('[ChatScreen] ⚠️ Group encryption setup failed (offline?): $e');
        }

        // Fetch group member count (may fail offline)
        try {
          await _fetchGroupMemberCount();
        } catch (e) {
          print('[ChatScreen] ⚠️ Group member count fetch failed (offline?): $e');
        }
      }

      // Background WebSocket tasks (may fail offline)
      try {
        _performBackgroundWebSocketTasks();
      } catch (e) {
        print('[ChatScreen] ⚠️ Background WebSocket tasks failed (offline?): $e');
      }
    } catch (e) {
      print('[ChatScreen] ⚠️ Background initialization failed: $e');
      // Don't crash - user can still view cached messages
    }
  }

  Future<void> _performBackgroundWebSocketTasks() async {
    if (_backgroundTasksCompleted) return;

    await _websocketService.syncMessageStatuses(widget.conversationInfo.conversationId);
    await _markMessagesAsRead();

    _backgroundTasksCompleted = true;
  }

  Future<void> _refreshMessagesFromDb() async {
    final conversationId = widget.conversationInfo.conversationId;

    // 🚀 INSTANT LOADING: Check if we have cached messages
    final cachedMessages = _chatProvider.getCachedMessages(conversationId);

    if (cachedMessages != null) {
      print('[ChatScreen] ⚡ CACHE HIT! Showing ${cachedMessages.length} cached messages instantly');

      // Show cached messages INSTANTLY (no loading spinner!)
      if (mounted) {
        // Single setState to minimize rebuilds
        setState(() {
          _loadedMessageCount = cachedMessages.length;
          _isLoading = false; // ✅ Stop loading immediately
        });

        // Set messages without creating new list (reuse cached)
        _chatProvider.setMessages(cachedMessages, conversationId: conversationId);
      }

      // Background refresh: Update from database silently
      _refreshMessagesInBackground(conversationId);
      return;
    }

    print('[ChatScreen] ❌ CACHE MISS - Loading from database...');

    // No cache: Load from database (first time or cache expired)
    final messages = await _dbService.getMessages(
      conversationId,
      limit: _messagesPerPage,
    );

    // Check if there are more messages to load
    final totalCount = await _dbService.getMessageCount(conversationId);

    if (mounted) {
      setState(() {
        _loadedMessageCount = messages.length;
        _hasMoreMessages = messages.length < totalCount;
        _isLoading = false;
      });

      _chatProvider.setMessages(messages, conversationId: conversationId);

      // Use multiple frame callbacks to ensure scroll happens after ListView builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom(instant: true);
        });
      });
    }
  }

  /// Background refresh: Update messages silently without blocking UI
  Future<void> _refreshMessagesInBackground(int conversationId) async {
    try {
      final messages = await _dbService.getMessages(
        conversationId,
        limit: _messagesPerPage,
      );

      final totalCount = await _dbService.getMessageCount(conversationId);

      if (mounted) {
        setState(() {
          _loadedMessageCount = messages.length;
          _hasMoreMessages = messages.length < totalCount;
        });

        // Update messages silently (don't scroll, don't interrupt user)
        _chatProvider.setMessages(messages, conversationId: conversationId);
      }
    } catch (e) {
      // print('[ChatScreen] Background refresh failed: $e');
      // Silently fail - user already sees cached messages
    }
  }

  /// Scroll listener for pagination
  /// In reversed ListView, scrolling UP (to older messages) increases scroll position
  void _onScroll() {
    if (_scrollController.hasClients && !_isLoadingMoreMessages && _hasMoreMessages) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      // Load more when user scrolls within 200 pixels of the top (older messages)
      if (currentScroll >= maxScroll - 200) {
        _loadMoreMessages();
      }
    }
  }

  /// Load older messages when scrolling up
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMoreMessages || !_hasMoreMessages) return;

    setState(() => _isLoadingMoreMessages = true);

    try {
      // Load next batch of older messages
      final olderMessages = await _dbService.loadOlderMessages(
        widget.conversationInfo.conversationId,
        currentCount: _loadedMessageCount,
        limit: _messagesPerPage,
      );

      if (olderMessages.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
          _isLoadingMoreMessages = false;
        });
        return;
      }

      // Save current scroll position to maintain it after adding messages
      final currentOffset = _scrollController.offset;

      // Prepend older messages to the existing list
      final currentMessages = _chatProvider.messages;
      final updatedMessages = [...olderMessages, ...currentMessages];

      setState(() {
        _loadedMessageCount = updatedMessages.length;
      });

      _chatProvider.setMessages(updatedMessages, conversationId: widget.conversationInfo.conversationId);

      // Restore scroll position (adjust for new items added)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(currentOffset);
        }
      });

    } catch (e) {
      // print('[ChatScreen] Error loading more messages: $e');
    } finally {
      setState(() => _isLoadingMoreMessages = false);
    }
  }

  Future<void> _sendMessage() async {
    // 🚀 OFFLINE MODE: Prevent sending when no internet connection
    if (widget.channel == null || !_websocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📴 No internet connection. Please connect to send messages.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Prevent sending messages to blocked users
    if (_isUserBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send messages to blocked users. Unblock them first.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final messageText = _controller.text.trim();

    // Check conditions based on chat type
    if (messageText.isEmpty) return;
    if (!widget.conversationInfo.isGroup && _recipientUid == null) return;

    _controller.clear();
    // Keep keyboard open after sending message
    // FocusScope.of(context).unfocus(); // Commented out to keep keyboard visible

    final tempMessageId = -DateTime.now().millisecondsSinceEpoch;
    final replyToMessageId = _replyingToMessage?.id;
    final optimisticMessage = Message(
      id: tempMessageId,
      conversationId: widget.conversationInfo.conversationId,
      username: _currentUser,
      content: messageText,
      timestamp: DateTime.now().toUtc(),
      senderUid: _currentUserUid,
      status: MessageStatus.sending,
      isEncrypted: true,
      isQuickReply: false,
      replyToMessageId: replyToMessageId,
      repliedMessageContent: _replyingToMessage?.content,
      repliedMessageSenderName: _replyingToMessage?.username,
    );

    // Clear reply state
    _cancelReply();

    _chatProvider.addMessage(optimisticMessage);
    _scrollToBottom();

    try {
      String? encryptedMessage;
      int? myDeviceId;
      int? recipientDeviceId;

      if (widget.conversationInfo.isGroup) {
        // GROUP ENCRYPTION - Use Sender Keys
        // print('[ChatScreen] Encrypting group message');

        if (!_groupEncryptionSetup) {
          throw Exception('Group encryption not setup');
        }

        encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: messageText,
        );

        myDeviceId = await SignalService.getDeviceId();
      } else {
        // 1-ON-1 ENCRYPTION - Use existing Signal Protocol
        // print('[ChatScreen] Encrypting 1-on-1 message');

        recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
        if (recipientDeviceId == null) throw Exception('No recipient device ID');

        myDeviceId = await SignalService.getDeviceId();
        if (myDeviceId == null) throw Exception('No device ID');

        bool hasValidSendingSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId,
        );

        if (!hasValidSendingSession) {
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );

          if (prekeyBundle == null) throw Exception('No prekey bundle');

          encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: messageText,
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedMessage = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: messageText,
            deviceId: recipientDeviceId,
          );
        }
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedMessage,
        replyToMessageId: replyToMessageId,
      );

      final realMessageId = response['message_id'] ?? tempMessageId;
      final sentMessage = Message(
        id: realMessageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: messageText,
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sent,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        isQuickReply: false,
        replyToMessageId: replyToMessageId,
        repliedMessageContent: optimisticMessage.repliedMessageContent,
        repliedMessageSenderName: optimisticMessage.repliedMessageSenderName,
      );

      _chatProvider.updateMessageStatus(tempMessageId, sentMessage);
    } catch (e) {
      final failedMessage = optimisticMessage.copyWith(status: MessageStatus.failed);
      _chatProvider.updateMessageStatus(tempMessageId, failedMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Start voice recording
  void _startVoiceRecording() {
    // 🚀 OFFLINE MODE: Prevent voice messages when no internet connection
    if (widget.channel == null || !_websocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📴 No internet connection. Please connect to send voice messages.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Prevent voice messages to blocked users
    if (_isUserBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send voice messages to blocked users. Unblock them first.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isMultiSelectionMode) {
      _clearSelection();
      return;
    }

    setState(() {
      _isRecordingVoice = true;
    });
  }

  // Send voice message with E2EE
  Future<void> _sendVoiceMessage(String audioPath, int duration) async{
    setState(() {
      _isRecordingVoice = false;
    });

    if (!widget.conversationInfo.isGroup && _recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient not found'), backgroundColor: Colors.red),
      );
      return;
    }

    int? tempMessageId;
    int? actualMessageId; // Track the current message ID (temp or real)

    try {
      // Create optimistic message
      tempMessageId = -DateTime.now().millisecondsSinceEpoch;
      actualMessageId = tempMessageId; // Initially points to temp ID
      final optimisticMessage = Message(
        id: tempMessageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Voice message]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        isEncrypted: true,
        hasAttachment: false,
        audioDuration: duration,
      );

      _chatProvider.addMessage(optimisticMessage);
      _scrollToBottom();

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sending voice message...'), duration: Duration(seconds: 2)),
        );
      }

      final myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      String? encryptedMessage;
      int? recipientDeviceId;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt placeholder with sender keys
        // print('[ChatScreen] Encrypting voice message placeholder for group');
        encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: '[Voice message]',
        );
      } else {
        // 1-ON-1: Encrypt with Signal Protocol
        recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
        if (recipientDeviceId == null) {
          throw Exception('Recipient device not found');
        }

        bool hasValidSendingSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId,
        );

        if (!hasValidSendingSession) {
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );

          if (prekeyBundle == null) throw Exception('No prekey bundle');

          encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: '[Voice message]',
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedMessage = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: '[Voice message]',
            deviceId: recipientDeviceId,
          );
        }
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      // Send encrypted placeholder message
      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedMessage,
      );

      final messageId = response['message_id'];
      if (messageId == null) {
        throw Exception('Failed to create message');
      }

      // Update optimistic message with real ID
      final sentMessage = Message(
        id: messageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Voice message]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sent,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        hasAttachment: false,
        audioDuration: duration,
      );

      _chatProvider.updateMessageStatus(tempMessageId, sentMessage);

      actualMessageId = messageId; // Update to real ID after message is confirmed

      // Read audio file
      final audioFile = File(audioPath);
      final audioData = await audioFile.readAsBytes();

      // STEP 1: Encrypt audio with AES-256-GCM
      final encryptionResult = FileService.encryptAudioData(
        audioData: audioData,
      );

      final encryptedAudioData = encryptionResult['encryptedData'] as Uint8List;
      final aesKey = encryptionResult['key'] as Uint8List;
      final aesIv = encryptionResult['iv'] as Uint8List;

      // STEP 2: Encrypt the AES key
      final aesKeyB64 = base64.encode(aesKey);
      String? encryptedAesKeyForRecipient;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt AES key with sender keys
        // print('[ChatScreen] Encrypting AES key for group voice message');
        encryptedAesKeyForRecipient = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: aesKeyB64,
        );
      } else {
        // 1-ON-1: Encrypt AES key with Signal Protocol
        // CRITICAL: Validate session before encrypting to prevent corrupted encryption
        bool hasValidSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId!,
        );

        if (!hasValidSession) {
          // Session invalid - establish new session silently
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );
          if (prekeyBundle == null) throw Exception('No prekey bundle available for AES key encryption');

          encryptedAesKeyForRecipient = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedAesKeyForRecipient = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            deviceId: recipientDeviceId!,
          );
        }
      }

      if (encryptedAesKeyForRecipient == null) {
        throw Exception('Failed to encrypt AES key');
      }

      // STEP 2.5: For sender, store raw AES key
      final senderAesKeyB64 = aesKeyB64;

      // STEP 3: Upload encrypted audio to server
      final result = await FileService.uploadEncryptedFile(
        encryptedData: encryptedAudioData,
        messageId: messageId,
        conversationId: widget.conversationInfo.conversationId,
        fileType: 'audio',
        mimeType: 'audio/aac',
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        senderMediaEncryptionKey: senderAesKeyB64,
      );

      final attachmentId = result!['attachment_id'];

      // STEP 4: Save decrypted audio to local storage for sender
      await FileService.saveAudioToPersistentStorage(audioData, attachmentId);

      // STEP 5: Update message with attachment info and E2EE backup metadata
      final updatedMessage = sentMessage.copyWith(
        attachmentId: attachmentId,
        attachmentType: 'audio',
        hasAttachment: true,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        senderMediaEncryptionKey: senderAesKeyB64,
        // E2EE Backup: Store encrypted AES key with metadata
        encryptedMediaKey: encryptedAesKeyForRecipient,
        mediaEncryptionType: widget.conversationInfo.isGroup ? 'sender_keys' : 'signal',
        mediaRecipientUid: widget.conversationInfo.isGroup ? null : _recipientUid,
        mediaRecipientDeviceId: widget.conversationInfo.isGroup ? null : recipientDeviceId,
        mediaGroupId: widget.conversationInfo.isGroup ? widget.conversationInfo.conversationId.toString() : null,
        mediaSenderUid: _currentUserUid,
        mediaSenderDeviceId: myDeviceId,
      );

      _chatProvider.updateMessageStatus(messageId, updatedMessage);

      // Delete temp audio file
      try {
        await audioFile.delete();
      } catch (e) {
        // print('[ChatScreen] Error deleting temp audio file: $e');
      }

      // print('[ChatScreen] ✅ Voice message sent successfully with E2EE');
    } catch (e) {
      // print('[ChatScreen] ❌ Error sending voice message: $e');

      if (actualMessageId != null) {
        final messages = _chatProvider.messages;
        final messageIndex = messages.indexWhere((m) => m.id == actualMessageId);

        if (messageIndex != -1) {
          final failedMessage = messages[messageIndex].copyWith(status: MessageStatus.failed);
          _chatProvider.updateMessageStatus(actualMessageId, failedMessage);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Show modern attachment picker dialog
  void _showImagePickerDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final titleSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final iconSize1 = (screenWidth * 0.06).clamp(20.0, 28.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final spacing2 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final borderRadius2 = (screenWidth * 0.08).clamp(28.0, 35.0);
    final handleWidth = (screenWidth * 0.1).clamp(35.0, 45.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Color(0xFFF8F9FA),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padding1 * 1.2, horizontal: padding1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: handleWidth,
                    height: 4,
                    margin: EdgeInsets.only(bottom: padding1),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header with icon
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(padding2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                          borderRadius: BorderRadius.circular(borderRadius1),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF667EEA).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.attach_file, color: Colors.white, size: iconSize1),
                      ),
                      SizedBox(width: spacing2),
                      Text(
                        'Send Attachment',
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2D3436),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: padding1 * 1.2),
                  // Grid of attachment options
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: spacing2,
                    crossAxisSpacing: spacing2,
                    childAspectRatio: 0.85,
                    children: [
                      _buildAttachmentOption(
                        icon: Icons.photo_camera_rounded,
                        label: 'Camera',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendImageMessage(ImageSource.camera);
                        },
                      ),
                      _buildAttachmentOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFA709A), Color(0xFFFEE140)],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendImageMessage(ImageSource.gallery);
                        },
                      ),
                      _buildAttachmentOption(
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B6B), Color(0xFFEE5A6F)],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendVideoMessage(ImageSource.camera);
                        },
                      ),
                      _buildAttachmentOption(
                        icon: Icons.video_library_rounded,
                        label: 'Videos',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFA500), Color(0xFFFF6347)],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendVideoMessage(ImageSource.gallery);
                        },
                      ),
                      _buildAttachmentOption(
                        icon: Icons.insert_drive_file_rounded,
                        label: 'Document',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _sendDocumentMessage();
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: spacing2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Build individual attachment option tile with gradient
  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize1 = (screenWidth * 0.08).clamp(28.0, 36.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final spacing2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final borderRadius3 = (screenWidth * 0.05).clamp(18.0, 24.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius3),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(borderRadius3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(padding2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: iconSize1, color: Colors.white),
              ),
              SizedBox(height: spacing2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: smallTextSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Send image message
  Future<void> _sendImageMessage(ImageSource source) async {
    // 🚀 OFFLINE MODE: Prevent image sending when no internet connection
    if (widget.channel == null || !_websocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📴 No internet connection. Please connect to send images.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!widget.conversationInfo.isGroup && _recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient not found'), backgroundColor: Colors.red),
      );
      return;
    }

    int? tempMessageId;

    try {
      // STEP 1: Pick image FIRST before creating any message bubble
      final pickedFile = await FileService.pickImage(source: source);
      if (pickedFile == null) {
        // print('[ChatScreen] User cancelled image selection');
        return; // Exit silently, no error, no bubble
      }

      // STEP 2: Now that image is picked, create optimistic message
      tempMessageId = -DateTime.now().millisecondsSinceEpoch;
      final optimisticMessage = Message(
        id: tempMessageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Image]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        isEncrypted: true,
        hasAttachment: false,
      );

      _chatProvider.addMessage(optimisticMessage);
      _scrollToBottom();

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing image...'), duration: Duration(seconds: 2)),
        );
      }

      final myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      String? encryptedMessage;
      int? recipientDeviceId;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt placeholder with sender keys
        // print('[ChatScreen] Encrypting image placeholder for group');
        encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: '[Image]',
        );
      } else {
        // 1-ON-1: Encrypt with Signal Protocol
        recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
        if (recipientDeviceId == null) {
          throw Exception('Recipient device not found');
        }

        bool hasValidSendingSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId,
        );

        if (!hasValidSendingSession) {
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );

          if (prekeyBundle == null) throw Exception('No prekey bundle');

          encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: '[Image]',
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedMessage = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: '[Image]',
            deviceId: recipientDeviceId,
          );
        }
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      // Send encrypted placeholder message
      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedMessage,
      );

      final messageId = response['message_id'];
      if (messageId == null) {
        throw Exception('Failed to create message');
      }

      // Update optimistic message with real ID
      final sentMessage = Message(
        id: messageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Image]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sent,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        hasAttachment: false,
      );

      _chatProvider.updateMessageStatus(tempMessageId, sentMessage);

      // Now compress, encrypt and upload the image
      // Get dimensions
      final dimensions = await FileService.getImageDimensions(pickedFile.path);

      // Compress image
      final compressedData = await FileService.compressImage(pickedFile.path);
      if (compressedData == null) {
        throw Exception('Compression failed');
      }

      // STEP 1: Encrypt image with AES-256-GCM
      final encryptionResult = FileService.encryptImageData(
        imageData: compressedData,
      );

      final encryptedImageData = encryptionResult['encryptedData'] as Uint8List;
      final aesKey = encryptionResult['key'] as Uint8List;
      final aesIv = encryptionResult['iv'] as Uint8List;

      // STEP 2: Encrypt the AES key
      final aesKeyB64 = base64.encode(aesKey);
      String? encryptedAesKeyForRecipient;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt AES key with sender keys
        // print('[ChatScreen] Encrypting AES key for group image');
        encryptedAesKeyForRecipient = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: aesKeyB64,
        );
      } else {
        // 1-ON-1: Encrypt AES key with Signal Protocol
        // CRITICAL: Validate session before encrypting to prevent corrupted encryption
        bool hasValidSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId!,
        );

        if (!hasValidSession) {
          // Session invalid - establish new session silently
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );
          if (prekeyBundle == null) throw Exception('No prekey bundle available for AES key encryption');

          encryptedAesKeyForRecipient = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedAesKeyForRecipient = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            deviceId: recipientDeviceId!,
          );
        }
      }

      if (encryptedAesKeyForRecipient == null) {
        throw Exception('Failed to encrypt AES key');
      }

      // STEP 2.5: For sender, store raw AES key
      final senderAesKeyB64 = aesKeyB64;

      // STEP 3: Upload encrypted image to server WITH encryption metadata
      // NOTE: We do NOT send sender_media_encryption_key to server (security: Option 1)
      final result = await FileService.uploadEncryptedFile(
        encryptedData: encryptedImageData,
        messageId: messageId,
        conversationId: widget.conversationInfo.conversationId,
        fileType: 'image',
        mimeType: 'image/jpeg',
        width: dimensions?['width'],
        height: dimensions?['height'],
        mediaEncryptionKey: encryptedAesKeyForRecipient, // Signal-encrypted AES key for recipient
        mediaEncryptionIv: base64.encode(aesIv), // IV in base64
        // senderMediaEncryptionKey: NOT sent to server - stored locally only
      );

      if (result == null) {
        throw Exception('Failed to upload image');
      }

      // STEP 4: Update message with encryption metadata
      final attachmentId = result['attachment_id'] as int;

      // Cache the decrypted image for sender
      _imageCache[attachmentId] = compressedData;
      await FileService.saveImageToPersistentStorage(compressedData, attachmentId);

      // Store message with encryption metadata and E2EE backup metadata
      // SECURITY: Raw AES key stored ONLY in local database, never sent to server
      final messageWithEncryption = sentMessage.copyWith(
        attachmentId: attachmentId,
        hasAttachment: true,
        attachmentType: 'image',
        mediaEncryptionKey: encryptedAesKeyForRecipient, // Signal-encrypted AES key for recipient
        mediaEncryptionIv: base64.encode(aesIv), // IV in base64 (can be plaintext)
        senderMediaEncryptionKey: senderAesKeyB64, // Raw AES key (base64) - LOCAL STORAGE ONLY
        // E2EE Backup: Store encrypted AES key with metadata
        encryptedMediaKey: encryptedAesKeyForRecipient,
        mediaEncryptionType: widget.conversationInfo.isGroup ? 'sender_keys' : 'signal',
        mediaRecipientUid: widget.conversationInfo.isGroup ? null : _recipientUid,
        mediaRecipientDeviceId: widget.conversationInfo.isGroup ? null : recipientDeviceId,
        mediaGroupId: widget.conversationInfo.isGroup ? widget.conversationInfo.conversationId.toString() : null,
        mediaSenderUid: _currentUserUid,
        mediaSenderDeviceId: myDeviceId,
      );

      _chatProvider.updateMessageStatus(tempMessageId, messageWithEncryption);
      await _dbService.insertMessage(messageWithEncryption);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image sent!'), backgroundColor: Colors.green),
        );
      }

      // The attachment_uploaded WebSocket event will update the message with attachment info

    } catch (e) {
      // print('[ChatScreen] Error sending image: $e');

      // Remove the optimistic message if it was added
      if (tempMessageId != null) {
        _chatProvider.removeMessage(tempMessageId);
      }

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Send video message
  Future<void> _sendVideoMessage(ImageSource source) async {
    // 🚀 OFFLINE MODE: Prevent video sending when no internet connection
    if (widget.channel == null || !_websocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📴 No internet connection. Please connect to send videos.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!widget.conversationInfo.isGroup && _recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient not found'), backgroundColor: Colors.red),
      );
      return;
    }

    int? tempMessageId;

    try {
      // STEP 1: Pick video FIRST
      final pickedFile = await FileService.pickVideo(source: source);
      if (pickedFile == null) {
        // print('[ChatScreen] User cancelled video selection');
        return;
      }

      // STEP 2: Create optimistic message IMMEDIATELY (before thumbnail generation)
      tempMessageId = -DateTime.now().millisecondsSinceEpoch;

      final optimisticMessage = Message(
        id: tempMessageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Video]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        isEncrypted: true,
        hasAttachment: true,
        attachmentType: 'video',
      );

      _chatProvider.addMessage(optimisticMessage);
      _scrollToBottom();

      // STEP 3: Generate thumbnail for preview (after message is shown)
      final cachedTempId = tempMessageId; // Capture for async callback
      FileService.generateVideoThumbnail(pickedFile.path).then((thumbnailPreview) {
        if (thumbnailPreview != null && mounted && cachedTempId != null) {
          _thumbnailCache[cachedTempId] = thumbnailPreview;
          // Trigger rebuild of message list to show thumbnail
          _chatProvider.notifyListeners();
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing video...'), duration: Duration(seconds: 3)),
        );
      }

      final myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      String? encryptedMessage;
      int? recipientDeviceId;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt placeholder with sender keys
        // print('[ChatScreen] Encrypting video placeholder for group');
        encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: '[Video]',
        );
      } else {
        // 1-ON-1: Encrypt with Signal Protocol
        recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
        if (recipientDeviceId == null) throw Exception('Recipient device not found');

        bool hasValidSendingSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId,
        );

        if (!hasValidSendingSession) {
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );
          if (prekeyBundle == null) throw Exception('No prekey bundle');

          encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: '[Video]',
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedMessage = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: '[Video]',
            deviceId: recipientDeviceId,
          );
        }
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      // Send message
      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedMessage,
      );

      final messageId = response['message_id'];
      if (messageId == null) throw Exception('Failed to create message');

      // Update with real ID (status: sending while video is being processed)
      final sentMessage = Message(
        id: messageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '[Video]',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        hasAttachment: true,
        attachmentType: 'video',
      );

      _chatProvider.updateMessageStatus(tempMessageId, sentMessage);

      // Copy thumbnail from temp ID to real ID
      if (tempMessageId != null && _thumbnailCache.containsKey(tempMessageId)) {
        _thumbnailCache[messageId] = _thumbnailCache[tempMessageId]!;
        _thumbnailCache.remove(tempMessageId);
        // Trigger UI update to show thumbnail with new ID
        _chatProvider.notifyListeners();
      }

      // Compress video
      final compressedVideoFile = await FileService.compressVideo(pickedFile.path);
      if (compressedVideoFile == null) {
        throw Exception('Video compression failed');
      }

      // Check compressed video size
      final compressedSize = await compressedVideoFile.length();
      if (compressedSize > FileService.maxCompressedVideoSize) {
        throw Exception(
          'Video too large after compression: ${(compressedSize / (1024 * 1024)).toStringAsFixed(1)}MB. '
          'Maximum allowed: ${(FileService.maxCompressedVideoSize / (1024 * 1024)).toStringAsFixed(0)}MB'
        );
      }

      // Get metadata
      final metadata = await FileService.getVideoMetadata(compressedVideoFile.path);
      final videoDuration = metadata?['duration'] != null
          ? (metadata!['duration'] as int) ~/ 1000 // Convert ms to seconds
          : null;

      // Read video bytes
      final videoBytes = await compressedVideoFile.readAsBytes();

      // Encrypt video with AES
      final encryptionResult = FileService.encryptWithAES(data: videoBytes);
      final encryptedVideoData = encryptionResult['encryptedData'] as Uint8List;
      final aesKey = encryptionResult['key'] as Uint8List;
      final aesIv = encryptionResult['iv'] as Uint8List;

      // Encrypt AES key
      final aesKeyB64 = base64.encode(aesKey);
      String? encryptedAesKeyForRecipient;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt AES key with sender keys
        // print('[ChatScreen] Encrypting AES key for group video');
        encryptedAesKeyForRecipient = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: aesKeyB64,
        );
      } else {
        // 1-ON-1: Encrypt AES key with Signal Protocol
        // CRITICAL: Validate session before encrypting AES key to prevent corrupted encryption
        // Session may become invalid during video processing (identity key changes, etc.)
        bool hasValidSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId!,
        );

        if (!hasValidSession) {
          // Session invalid - must establish new session
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId!,
          );
          if (prekeyBundle == null) throw Exception('No prekey bundle available for AES key encryption');

          encryptedAesKeyForRecipient = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId!,
          );
        } else {
          encryptedAesKeyForRecipient = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: aesKeyB64,
            deviceId: recipientDeviceId!,
          );
        }
      }

      if (encryptedAesKeyForRecipient == null) throw Exception('Failed to encrypt video key for recipient');

      // For SENDER: Store raw AES key (no Signal Protocol encryption needed)
      // This will be stored ONLY in local database, never sent to server
      final senderAesKeyB64 = aesKeyB64; // Raw AES key for sender

      // Upload encrypted video to server
      // NOTE: We do NOT send sender_media_encryption_key to server (security: Option 1)
      final uploadResult = await FileService.uploadEncryptedFile(
        encryptedData: encryptedVideoData,
        messageId: messageId,
        conversationId: widget.conversationInfo.conversationId,
        fileType: 'video',
        mimeType: 'video/mp4',
        width: metadata?['width'],
        height: metadata?['height'],
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        // senderMediaEncryptionKey: NOT sent to server - stored locally only
      );

      if (uploadResult == null) throw Exception('Video upload failed');

      // Cache decrypted video for sender
      _videoCache[uploadResult['attachment_id']] = compressedVideoFile.path;
      await FileService.saveVideoToPersistentStorage(videoBytes, uploadResult['attachment_id']);

      // Copy thumbnail from messageId to attachmentId (reuse generated thumbnail)
      if (_thumbnailCache.containsKey(messageId)) {
        final thumbnail = _thumbnailCache[messageId]!;
        _thumbnailCache[uploadResult['attachment_id']] = thumbnail;
        await FileService.saveThumbnailToPersistentStorage(thumbnail, uploadResult['attachment_id']);
        // Remove message ID cache since we now have attachmentId
        _thumbnailCache.remove(messageId);
      }

      // Update message with attachment info and mark as sent with E2EE backup metadata
      // SECURITY: Raw AES key stored ONLY in local database, never sent to server
      final completedMessage = sentMessage.copyWith(
        status: MessageStatus.sent,
        hasAttachment: true,
        attachmentType: 'video',
        attachmentId: uploadResult['attachment_id'],
        videoDuration: videoDuration,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        senderMediaEncryptionKey: senderAesKeyB64, // Raw AES key (base64) - LOCAL STORAGE ONLY
        // E2EE Backup: Store encrypted AES key with metadata
        encryptedMediaKey: encryptedAesKeyForRecipient,
        mediaEncryptionType: widget.conversationInfo.isGroup ? 'sender_keys' : 'signal',
        mediaRecipientUid: widget.conversationInfo.isGroup ? null : _recipientUid,
        mediaRecipientDeviceId: widget.conversationInfo.isGroup ? null : recipientDeviceId,
        mediaGroupId: widget.conversationInfo.isGroup ? widget.conversationInfo.conversationId.toString() : null,
        mediaSenderUid: _currentUserUid,
        mediaSenderDeviceId: myDeviceId,
      );
      _chatProvider.updateMessageStatus(messageId, completedMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      // print('[ChatScreen] Error sending video: $e');

      if (tempMessageId != null) {
        _chatProvider.removeMessage(tempMessageId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send video: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Send document message
  Future<void> _sendDocumentMessage() async {
    // 🚀 OFFLINE MODE: Prevent document sending when no internet connection
    if (widget.channel == null || !_websocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📴 No internet connection. Please connect to send documents.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!widget.conversationInfo.isGroup && _recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient not found'), backgroundColor: Colors.red),
      );
      return;
    }

    int? tempMessageId;

    try {
      // STEP 1: Pick document FIRST
      final pickedFile = await FileService.pickDocument();
      if (pickedFile == null) {
        // print('[ChatScreen] User cancelled document selection');
        return;
      }

      // Get file info
      final fileName = pickedFile.name;
      final fileSize = pickedFile.size;
      final filePath = pickedFile.path;

      if (filePath == null) {
        throw Exception('File path is null');
      }

      // Check document size
      if (fileSize > FileService.maxDocumentSize) {
        throw Exception(
          'Document too large: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB. '
          'Maximum allowed: ${(FileService.maxDocumentSize / (1024 * 1024)).toStringAsFixed(0)}MB'
        );
      }

      // Get MIME type
      final mimeInfo = FileService.getFileMimeType(filePath);
      final mimeType = mimeInfo['mimeType'] ?? 'application/octet-stream';
      final extension = mimeInfo['extension'] ?? '';

      // STEP 2: Create optimistic message
      tempMessageId = -DateTime.now().millisecondsSinceEpoch;

      final optimisticMessage = Message(
        id: tempMessageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '📄 $fileName',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        isEncrypted: true,
        hasAttachment: true,
        attachmentType: 'document',
      );

      _chatProvider.addMessage(optimisticMessage);
      _scrollToBottom();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing document...'), duration: Duration(seconds: 2)),
        );
      }

      final myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      String? encryptedMessage;
      int? recipientDeviceId;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt placeholder with sender keys
        // print('[ChatScreen] Encrypting document placeholder for group');
        encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: '📄 $fileName',
        );
      } else {
        // 1-ON-1: Encrypt with Signal Protocol
        recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
        if (recipientDeviceId == null) throw Exception('Recipient device not found');

        bool hasValidSendingSession = await SignalService.isSessionValidForSending(
          recipientUid: _recipientUid!,
          deviceId: recipientDeviceId,
        );

        if (!hasValidSendingSession) {
          final prekeyBundle = await DeviceService.fetchPrekeyBundle(
            targetUid: _recipientUid!,
            deviceId: recipientDeviceId,
          );
          if (prekeyBundle == null) throw Exception('No prekey bundle');

          encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
            recipientUid: _recipientUid!,
            plaintext: '📄 $fileName',
            prekeyBundle: prekeyBundle,
            deviceId: recipientDeviceId,
          );
        } else {
          encryptedMessage = await SignalService.encryptMessage(
            recipientUid: _recipientUid!,
            plaintext: '📄 $fileName',
            deviceId: recipientDeviceId,
          );
        }
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      // Send message
      final response = await DeviceService.sendMessage(
        conversationId: widget.conversationInfo.conversationId,
        contentB64: encryptedMessage,
      );

      final messageId = response['message_id'];
      if (messageId == null) throw Exception('Failed to create message');

      // Update with real ID
      final sentMessage = Message(
        id: messageId,
        conversationId: widget.conversationInfo.conversationId,
        username: _currentUser,
        content: '📄 $fileName',
        timestamp: DateTime.now().toUtc(),
        senderUid: _currentUserUid,
        status: MessageStatus.sending,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        hasAttachment: true,
        attachmentType: 'document',
      );

      _chatProvider.updateMessageStatus(tempMessageId, sentMessage);

      // Read document bytes
      final documentBytes = await File(filePath).readAsBytes();

      // Encrypt document with AES
      final encryptionResult = FileService.encryptWithAES(data: documentBytes);
      final encryptedDocumentData = encryptionResult['encryptedData'] as Uint8List;
      final aesKey = encryptionResult['key'] as Uint8List;
      final aesIv = encryptionResult['iv'] as Uint8List;

      // Encrypt AES key
      final aesKeyB64 = base64.encode(aesKey);
      String? encryptedAesKeyForRecipient;

      if (widget.conversationInfo.isGroup) {
        // GROUP: Encrypt AES key with sender keys
        // print('[ChatScreen] Encrypting AES key for group document');
        encryptedAesKeyForRecipient = await GroupEncryptionService.encryptGroupMessage(
          groupId: widget.conversationInfo.conversationId.toString(),
          plaintext: aesKeyB64,
        );
      } else {
        // 1-ON-1: Encrypt AES key with Signal Protocol
        encryptedAesKeyForRecipient = await SignalService.encryptMessage(
          recipientUid: _recipientUid!,
          plaintext: aesKeyB64,
          deviceId: recipientDeviceId!,
        );
      }

      if (encryptedAesKeyForRecipient == null) throw Exception('Failed to encrypt document key');

      // For SENDER: Store raw AES key (no Signal Protocol encryption needed)
      final senderAesKeyB64 = aesKeyB64;

      // Upload encrypted document to server
      final uploadResult = await FileService.uploadEncryptedFile(
        encryptedData: encryptedDocumentData,
        messageId: messageId,
        conversationId: widget.conversationInfo.conversationId,
        fileType: 'document',
        mimeType: mimeType,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
      );

      if (uploadResult == null) throw Exception('Document upload failed');

      final attachmentId = uploadResult['attachment_id'] as int;

      // Cache decrypted document for sender
      await FileService.saveDocumentToPersistentStorage(documentBytes, attachmentId, extension);
      final savedPath = await FileService.getDocumentFilePath(attachmentId, extension);
      if (savedPath != null) {
        _documentCache[attachmentId] = savedPath;
      }

      // Update message with attachment info and mark as sent with E2EE backup metadata
      final completedMessage = sentMessage.copyWith(
        status: MessageStatus.sent,
        hasAttachment: true,
        attachmentType: 'document',
        attachmentId: attachmentId,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        senderMediaEncryptionKey: senderAesKeyB64, // Raw AES key (base64) - LOCAL STORAGE ONLY
        // E2EE Backup: Store encrypted AES key with metadata
        encryptedMediaKey: encryptedAesKeyForRecipient,
        mediaEncryptionType: widget.conversationInfo.isGroup ? 'sender_keys' : 'signal',
        mediaRecipientUid: widget.conversationInfo.isGroup ? null : _recipientUid,
        mediaRecipientDeviceId: widget.conversationInfo.isGroup ? null : recipientDeviceId,
        mediaGroupId: widget.conversationInfo.isGroup ? widget.conversationInfo.conversationId.toString() : null,
        mediaSenderUid: _currentUserUid,
        mediaSenderDeviceId: myDeviceId,
      );
      _chatProvider.updateMessageStatus(messageId, completedMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      // print('[ChatScreen] Error sending document: $e');

      if (tempMessageId != null) {
        _chatProvider.removeMessage(tempMessageId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send document: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<int?> _getRecipientDeviceId(String recipientUid) async {
    try {
      return await DeviceService.getActiveDeviceId(recipientUid);
    } catch (e) {
      return null;
    }
  }

  Future<void> _checkExistingSession() async {
    if (_recipientUid == null) return;

    try {
      final recipientDeviceId = await _getRecipientDeviceId(_recipientUid!);
      if (recipientDeviceId == null) return;

      final hasSession = await SignalService.hasSession(
        recipientUid: _recipientUid!,
        deviceId: recipientDeviceId,
      );

      if (mounted) setState(() => _sessionEstablished = hasSession);
    } catch (e) {
      // print('[ChatScreen] Error checking session: $e');
    }
  }

  Future<void> _setupGroupEncryption() async {
    try {
      // print('[ChatScreen] Setting up group encryption for conversation: ${widget.conversationInfo.conversationId}');

      final success = await GroupEncryptionService.setupGroupEncryption(
        groupId: widget.conversationInfo.conversationId.toString(),
      );

      if (mounted) {
        setState(() => _groupEncryptionSetup = success);
      }

      if (success) {
        // print('[ChatScreen] ✅ Group encryption setup successfully');
      } else {
        // print('[ChatScreen] ⚠️ Group encryption setup failed');
      }
    } catch (e) {
      // print('[ChatScreen] Error setting up group encryption: $e');
      if (mounted) {
        setState(() => _groupEncryptionSetup = false);
      }
    }
  }

  Future<void> _fetchGroupMemberCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final url = Uri.parse(
          'https://api.zarqmessenger.com/groups/${widget.conversationInfo.conversationId}/info');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final members = data['members'] as List?;

        setState(() {
          _groupMemberCount = members?.length ?? 0;
        });

        // print('[ChatScreen] ✅ Fetched group member count: $_groupMemberCount');
      }
    } catch (e) {
      // print('[ChatScreen] Error fetching group member count: $e');
      // Don't set error state, just keep it null
    }
  }

  // ============== Call Methods ==============

  Future<void> _startVoiceCall() async {
    if (_recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot start call: recipient not found')),
      );
      return;
    }

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for voice calls')),
        );
      }
      return;
    }

    try {
      // print('[ChatScreen] Starting voice call to: ${widget.conversationInfo.chatTitle}');
      // print('[ChatScreen] Recipient avatar URL: ${widget.conversationInfo.avatarUrl}');
      final callManager = Provider.of<GlobalCallManager>(context, listen: false);
      await callManager.startOutgoingCall(
        recipientUid: _recipientUid!,
        recipientName: widget.conversationInfo.chatTitle,
        conversationId: widget.conversationInfo.conversationId,
        callType: CallType.voice,
        recipientAvatarUrl: widget.conversationInfo.avatarUrl,
      );
    } catch (e, stackTrace) {
      // print('[ChatScreen] Error starting voice call: $e');
      // print('[ChatScreen] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    }
  }

  Future<void> _startVideoCall() async {
    if (_recipientUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot start call: recipient not found')),
      );
      return;
    }

    // Request camera and microphone permissions
    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (!permissions[Permission.camera]!.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required for video calls')),
        );
      }
      return;
    }

    if (!permissions[Permission.microphone]!.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for video calls')),
        );
      }
      return;
    }

    try {
      // print('[ChatScreen] Starting video call to: ${widget.conversationInfo.chatTitle}');
      // print('[ChatScreen] Recipient avatar URL: ${widget.conversationInfo.avatarUrl}');
      final callManager = Provider.of<GlobalCallManager>(context, listen: false);
      await callManager.startOutgoingCall(
        recipientUid: _recipientUid!,
        recipientName: widget.conversationInfo.chatTitle,
        conversationId: widget.conversationInfo.conversationId,
        callType: CallType.video,
        recipientAvatarUrl: widget.conversationInfo.avatarUrl,
      );
    } catch (e, stackTrace) {
      // print('[ChatScreen] Error starting video call: $e');
      // print('[ChatScreen] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    }
  }

  // Note: Call handling is now done by GlobalCallManager
  // All WebRTC methods have been removed

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _chatProvider.setCurrentConversationId(null);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _typingTimer?.cancel();
    _typingAnimationController.dispose(); // Dispose typing animation controller
    super.dispose();
  }

  // Handle sending typing indicator
  void _handleTypingIndicator() {
    // Cancel previous timer
    _typingTimer?.cancel();

    if (_controller.text.isNotEmpty && !_isCurrentlyTyping) {
      // User started typing
      _isCurrentlyTyping = true;
      // print('[ChatScreen] ⌨️ SENDING typing indicator: conversationId=${widget.conversationInfo.conversationId}, isTyping=true');
      _websocketService.sendTypingIndicator(
        conversationId: widget.conversationInfo.conversationId,
        isTyping: true,
      );
    }

    if (_controller.text.isNotEmpty) {
      // Set timer to stop typing indicator after 2 seconds of no input
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (_isCurrentlyTyping) {
          _isCurrentlyTyping = false;
          // print('[ChatScreen] ⌨️ SENDING typing stop (timeout): conversationId=${widget.conversationInfo.conversationId}');
          _websocketService.sendTypingIndicator(
            conversationId: widget.conversationInfo.conversationId,
            isTyping: false,
          );
        }
      });
    } else if (_isCurrentlyTyping) {
      // User cleared the text field
      _isCurrentlyTyping = false;
      // print('[ChatScreen] ⌨️ SENDING typing stop (cleared): conversationId=${widget.conversationInfo.conversationId}');
      _websocketService.sendTypingIndicator(
        conversationId: widget.conversationInfo.conversationId,
        isTyping: false,
      );
    }
  }

  // Handle receiving typing indicator
  void _handleTypingIndicatorReceived(String senderUid, bool isTyping) {
    // print('[ChatScreen] ⌨️ Typing indicator: sender=$senderUid, typing=$isTyping');
    if (mounted) {
      setState(() {
        _isOtherUserTyping = isTyping;
        _typingUserUid = isTyping ? senderUid : null;
      });
      // print('[ChatScreen] ⌨️ Typing state updated: showing=$_isOtherUserTyping');
    }
  }

  // Handle presence update
  void _handlePresenceUpdate(bool isOnline, int? lastSeenTimestamp) {
    // print('[ChatScreen] 👤 Presence update: isOnline=$isOnline, lastSeen=$lastSeenTimestamp');
    if (mounted) {
      setState(() {
        _isRecipientOnline = isOnline;
        if (lastSeenTimestamp != null) {
          _recipientLastSeen = DateTime.fromMillisecondsSinceEpoch(
            lastSeenTimestamp * 1000, // Convert from Unix seconds to milliseconds
          );
        }
      });
      // print('[ChatScreen] 👤 Status updated: online=$_isRecipientOnline, lastSeen=$_recipientLastSeen');
    }
  }

  void _handleReactionAdded(int messageId, String userUid, String? username, String emoji) {
    // Update message in chat provider
    final messageIndex = _chatProvider.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _chatProvider.messages[messageIndex];
      final reactions = List<MessageReaction>.from(
        message.reactions?.cast<MessageReaction>() ?? [],
      );

      // Add new reaction (avoid duplicates)
      final existingIndex = reactions.indexWhere(
        (r) => r.messageId == messageId && r.userUid == userUid && r.emoji == emoji,
      );

      if (existingIndex == -1) {
        reactions.add(MessageReaction(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          messageId: messageId,
          userUid: userUid,
          emoji: emoji,
          createdAt: DateTime.now(),
          username: username,
        ));

        final updatedMessage = message.copyWith(reactions: reactions);
        _chatProvider.updateMessage(updatedMessage);
      }
    }
  }

  void _handleReactionRemoved(int messageId, String userUid, String emoji) {
    // Update message in chat provider
    final messageIndex = _chatProvider.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = _chatProvider.messages[messageIndex];
      final reactions = List<MessageReaction>.from(
        message.reactions?.cast<MessageReaction>() ?? [],
      );

      // Remove reaction
      reactions.removeWhere(
        (r) => r.messageId == messageId && r.userUid == userUid && r.emoji == emoji,
      );

      final updatedMessage = message.copyWith(reactions: reactions);
      _chatProvider.updateMessage(updatedMessage);
    }
  }

  Future<void> _getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUser = user.displayName ?? user.email ?? "Anonymous User";
      _currentUserUid = user.uid;

      // 🚀 OPTIMIZATION: Fetch avatar in BACKGROUND (don't block chat opening)
      _fetchCurrentUserAvatarInBackground();
    }
  }

  /// Fetch current user's avatar in background without blocking UI
  Future<void> _fetchCurrentUserAvatarInBackground() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('https://api.zarqmessenger.com/profiles/me');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        // print('[ChatScreen] Profile response body: ${response.body}');
        final profile = jsonDecode(response.body) as Map<String, dynamic>;

        // Safely extract avatar URL
        final avatarValue = profile['profile_picture_url'];
        if (avatarValue != null && mounted) {
          setState(() {
            _currentUserAvatar = avatarValue.toString();
          });
          // print('[ChatScreen] Current user avatar: $_currentUserAvatar');
        } else {
          // print('[ChatScreen] No avatar found in profile');
        }
      } else {
        // print('[ChatScreen] Profile fetch failed with status: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      // print('[ChatScreen] Error fetching current user avatar: $e');
      // print('[ChatScreen] Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive size calculations
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final appBarTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final bodyTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize1 = (screenWidth * 0.06).clamp(20.0, 28.0);
    final iconSize2 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize3 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final borderRadius1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final borderRadius2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final spacing1 = (screenHeight * 0.01).clamp(6.0, 12.0);
    final spacing2 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final avatarSize = (screenWidth * 0.1).clamp(35.0, 45.0);

    return CallAwareScreen(
      screenName: 'ChatScreen',
      child: GestureDetector(
        onTap: () {
          // Dismiss selection mode when tapping outside
          if (_isMultiSelectionMode) {
            _clearSelection();
          }
          FocusScope.of(context).unfocus();
        },
        child: Stack(
        children: [
          // Background image (if set)
          if (_chatBackgroundImage != null)
            Positioned.fill(
              child: Image.file(
                File(_chatBackgroundImage!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: _chatBackgroundColor);
                },
              ),
            ),
          Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: _chatBackgroundImage == null ? _chatBackgroundColor : Colors.transparent,
            appBar: _isMultiSelectionMode
                ? _buildSelectionAppBar()
                : _isSearching
                  ? _buildSearchAppBar()
                  : _buildNormalAppBar(),
            body: SafeArea(
              child: Column(
                children: [
                  // Show blocked user banner
                  if (_isUserBlocked)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: padding1, vertical: spacing2),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border(
                          bottom: BorderSide(color: Colors.red[200]!, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.red[700], size: iconSize3),
                          SizedBox(width: spacing2),
                          Expanded(
                            child: Text(
                              'You have blocked ${widget.conversationInfo.chatTitle}. Unblock from menu to send messages.',
                              style: TextStyle(
                                color: Colors.red[900],
                                fontSize: smallTextSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Show AI MODE ON banner
                  if (_isAIMode)
                    Center(
                      child: Container(
                        margin: EdgeInsets.only(top: spacing1),
                        padding: EdgeInsets.symmetric(horizontal: padding2, vertical: spacing1),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                            SizedBox(width: spacing1),
                            Text(
                              'AI MODE ON',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: tinyTextSize,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(width: spacing1),
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Consumer<ChatProvider>(
                      builder: (context, chatProvider, child) {
                        var messages = [...chatProvider.messages]
                          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

                        // Filter out messages from blocked users
                        messages = messages.where((message) {
                          return !_blockedUsers.contains(message.senderUid);
                        }).toList();

                        // Filter messages based on search query
                        if (_isSearching && _searchQuery.isNotEmpty) {
                          messages = messages.where((message) {
                            return message.content.toLowerCase().contains(_searchQuery);
                          }).toList();
                        }

                        if (messages.isEmpty && _isSearching) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00ACC1).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.search_off_rounded,
                                    size: 60,
                                    color: const Color(0xFF00ACC1).withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'No messages found',
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 40),
                                  child: Text(
                                    'Try using different keywords or check your spelling',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Show search results count
                        if (_isSearching && _searchQuery.isNotEmpty) {
                          // Will show count badge in the UI
                        }

                        // Messages list with reverse scroll + banner at top (WhatsApp approach)
                        // Calculate item count: messages + loading indicator + encryption banner
                        int extraItems = 0;
                        if (_isLoadingMoreMessages && _hasMoreMessages) extraItems++;
                        if (_showEncryptionBanner) extraItems++;

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true, // Build from bottom to top like WhatsApp
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length + extraItems,
                          itemBuilder: (context, index) {
                            // Loading indicator appears when scrolling to older messages
                            if (_isLoadingMoreMessages && _hasMoreMessages && index == messages.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00ACC1)),
                                    ),
                                  ),
                                ),
                              );
                            }

                            // Encryption banner appears as the LAST item (top of conversation in reverse mode)
                            if (_showEncryptionBanner) {
                              final bannerIndex = messages.length + (_isLoadingMoreMessages && _hasMoreMessages ? 1 : 0);
                              if (index == bannerIndex) {
                                return _buildEncryptionBanner();
                              }
                            }

                            // Reverse the index to show oldest first
                            final reversedIndex = messages.length - 1 - index;
                            final message = messages[reversedIndex];
                            return Dismissible(
                              key: Key('msg_${message.id}'),
                              direction: DismissDirection.horizontal,
                              dismissThresholds: const {
                                DismissDirection.endToStart: 0.01,
                                DismissDirection.startToEnd: 0.01,
                              },
                              movementDuration: const Duration(milliseconds: 100),
                              resizeDuration: const Duration(milliseconds: 100),
                              confirmDismiss: (direction) async {
                                _setReplyToMessage(message);
                                return false; // Don't actually dismiss
                              },
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: const Icon(Icons.reply, color: Colors.black),
                              ),
                              secondaryBackground: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.reply, color: Colors.black),
                              ),
                              child: _buildMessageBubble(message, reversedIndex, messages.length),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_isOtherUserTyping)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTypingAnimation(),
                            const SizedBox(width: 8),
                            Text(
                              'typing...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _buildInputArea(),
                ],
              ),
            ),
            floatingActionButton: _buildSelectionActions(),
          ),
        ],
      ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final appBarTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final iconSize2 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize3 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final spacing2 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final avatarRadius = (screenWidth * 0.045).clamp(16.0, 22.0);
    final leadingWidth = (screenWidth * 0.25).clamp(90.0, 110.0); // Same for both 1-1 and groups
    final menuItemHeight = (screenWidth * 0.12).clamp(44.0, 52.0);
    final titleSpacing = (screenWidth * 0.025).clamp(8.0, 12.0);
    final verticalSpacing = (screenWidth * 0.01).clamp(3.0, 5.0);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: _isAIMode
                ? const LinearGradient(
                    colors: [
                      Color(0xFFFF0080), // Pink
                      Color(0xFFFF8C00), // Orange
                      Color(0xFFFFD700), // Gold
                      Color(0xFF00FF00), // Green
                      Color(0xFF00CED1), // Cyan
                      Color(0xFF9370DB), // Purple
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
              color: _isAIMode ? null : Colors.white.withOpacity(0.7),
              border: Border(
                bottom: BorderSide(
                  color: _isAIMode ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: _isAIMode ? Colors.white : Colors.black87, size: iconSize2),
        onPressed: () => Navigator.pop(context),
      ),
      leadingWidth: iconSize2 + padding2,
      titleSpacing: titleSpacing,
      title: GestureDetector(
        onTap: widget.conversationInfo.isGroup ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GroupInfoScreen(
                groupId: widget.conversationInfo.conversationId,
              ),
            ),
          );
        } : null,
        child: Row(
          children: [
            // Show avatar for both 1-1 chats and groups
            if (widget.conversationInfo.avatarUrl != null)
              Padding(
                padding: EdgeInsets.only(right: padding2 * 0.8),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundImage: NetworkImage(widget.conversationInfo.avatarUrl!),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(right: padding2 * 0.8),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: widget.conversationInfo.isGroup ? Colors.purple[300] : Colors.blue[300],
                  child: Icon(
                    widget.conversationInfo.isGroup ? Icons.group : Icons.person,
                    color: Colors.white,
                    size: appBarTitleSize * 0.9,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.conversationInfo.chatTitle,
                    style: TextStyle(
                      fontSize: appBarTitleSize,
                      fontWeight: FontWeight.w600,
                      color: _isAIMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                  // Show member count for groups
                  if (widget.conversationInfo.isGroup)
                    Text(
                      _groupMemberCount != null
                          ? '$_groupMemberCount ${_groupMemberCount == 1 ? "member" : "members"}'
                          : 'Tap for info',
                      style: TextStyle(fontSize: smallTextSize, color: _isAIMode ? Colors.white70 : Colors.grey[600]),
                    )
                  // Show online status for 1-1 chats
                  else if (!widget.conversationInfo.isGroup && _recipientUid != null)
                    Text(
                      _getStatusText(),
                      style: TextStyle(fontSize: smallTextSize, color: _isAIMode ? Colors.white70 : Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Show call buttons only for 1-1 chats (not groups)
        if (!widget.conversationInfo.isGroup && _recipientUid != null) ...[
          Consumer<GlobalCallManager>(
            builder: (context, callManager, child) => IconButton(
              icon: Icon(Icons.call, color: _isAIMode ? Colors.white : Colors.black87, size: iconSize2),
              tooltip: 'Voice Call',
              onPressed: callManager.isInCall ? null : _startVoiceCall,
            ),
          ),
          Consumer<GlobalCallManager>(
            builder: (context, callManager, child) => IconButton(
              icon: Icon(Icons.videocam, color: _isAIMode ? Colors.white : Colors.black87, size: iconSize2),
              tooltip: 'Video Call',
              onPressed: callManager.isInCall ? null : _startVideoCall,
            ),
          ),
        ],
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: _isAIMode ? Colors.white : Colors.black87, size: iconSize2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius2),
          ),
          elevation: 8,
          color: Colors.white.withOpacity(0.95),
          onSelected: (value) {
            if (value == 'search') {
              setState(() {
                _isSearching = true;
              });
            } else if (value == 'mute') {
              _toggleMuteNotifications();
            } else if (value == 'wallpaper') {
              _showWallpaperPicker();
            } else if (value == 'clear') {
              _showClearChatDialog();
            } else if (value == 'block') {
              _showBlockUserDialog();
            } else if (value == 'unblock') {
              _unblockUser();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'search',
              height: menuItemHeight,
              child: Row(
                children: [
                  Icon(Icons.search, size: iconSize3, color: Colors.grey[700]),
                  SizedBox(width: spacing2),
                  Text(
                    'Search',
                    style: TextStyle(
                      fontSize: appBarTitleSize * 0.9,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'mute',
              height: menuItemHeight,
              child: Row(
                children: [
                  Icon(Icons.notifications_off_outlined, size: iconSize3, color: Colors.grey[700]),
                  SizedBox(width: spacing2),
                  Text(
                    'Mute notifications',
                    style: TextStyle(
                      fontSize: appBarTitleSize * 0.9,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'wallpaper',
              height: menuItemHeight,
              child: Row(
                children: [
                  Icon(Icons.wallpaper_outlined, size: iconSize3, color: Colors.grey[700]),
                  SizedBox(width: spacing2),
                  Text(
                    'Change wallpaper',
                    style: TextStyle(
                      fontSize: appBarTitleSize * 0.9,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear',
              height: menuItemHeight,
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_outlined, size: iconSize3, color: Colors.orange[700]),
                  SizedBox(width: spacing2),
                  Text(
                    'Clear chat',
                    style: TextStyle(
                      fontSize: appBarTitleSize * 0.9,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.conversationInfo.isGroup)
              PopupMenuItem(
                value: _isUserBlocked ? 'unblock' : 'block',
                height: menuItemHeight,
                child: Row(
                  children: [
                    Icon(
                      _isUserBlocked ? Icons.check_circle_outline : Icons.block,
                      size: iconSize3,
                      color: _isUserBlocked ? Colors.green[700] : Colors.red[700],
                    ),
                    SizedBox(width: spacing2),
                    Text(
                      _isUserBlocked ? 'Unblock user' : 'Block user',
                      style: TextStyle(
                        fontSize: appBarTitleSize * 0.9,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bodyTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final iconSize2 = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize3 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final borderRadius1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final borderRadius2 = (screenWidth * 0.03).clamp(10.0, 14.0);
    final spacing1 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final searchBarHeight = (screenWidth * 0.1).clamp(36.0, 44.0);
    final bottomBarHeight = (screenWidth * 0.1).clamp(36.0, 44.0);

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: const Color(0xFF00ACC1), size: iconSize2),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      title: Container(
        height: searchBarHeight,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(searchBarHeight / 2),
          border: Border.all(
            color: _searchQuery.isNotEmpty
                ? const Color(0xFF00ACC1).withOpacity(0.3)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding2),
              child: Icon(Icons.search, color: const Color(0xFF00ACC1), size: iconSize3),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: bodyTextSize,
                ),
                decoration: InputDecoration(
                  hintText: 'Search in conversation...',
                  hintStyle: TextStyle(
                    color: Colors.black38,
                    fontSize: bodyTextSize,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: padding2),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
            if (_searchController.text.isNotEmpty)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(searchBarHeight / 2),
                  onTap: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                  child: Padding(
                    padding: EdgeInsets.all(spacing1),
                    child: Icon(Icons.close, color: Colors.black45, size: iconSize3),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottom: _searchQuery.isNotEmpty
          ? PreferredSize(
              preferredSize: Size.fromHeight(bottomBarHeight),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: padding1, vertical: spacing1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Consumer<ChatProvider>(
                  builder: (context, chatProvider, child) {
                    final matchCount = chatProvider.messages
                        .where((m) => m.content.toLowerCase().contains(_searchQuery))
                        .length;
                    return Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: padding2, vertical: padding2 * 0.4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00ACC1), Color(0xFF0097A7)],
                            ),
                            borderRadius: BorderRadius.circular(borderRadius2),
                          ),
                          child: Text(
                            '$matchCount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: tinyTextSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing1),
                        Text(
                          matchCount == 1 ? 'message found' : 'messages found',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: tinyTextSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final appBarTitleSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final iconSize2 = (screenWidth * 0.05).clamp(18.0, 24.0);

    return AppBar(
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00ACC1), Color(0xFF0097A7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      elevation: 2,
      leading: IconButton(
        icon: Icon(Icons.close, size: iconSize2),
        onPressed: _clearSelection,
      ),
      title: Text(
        '${_selectedMessageIds.length} selected',
        style: TextStyle(fontSize: appBarTitleSize),
      ),
    );
  }

  Widget? _buildSelectionActions() {
    if (!_isMultiSelectionMode) return null;

    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize3 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final spacing1 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final fabBottomOffset = (screenWidth * 0.2).clamp(70.0, 90.0);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + fabBottomOffset,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show Share button only if exactly 1 media message is selected
          if (_selectedMessageIds.length == 1 && _isSelectedMessageMedia())
            ...[
              FloatingActionButton(
                heroTag: 'share',
                mini: true,
                backgroundColor: const Color(0xFF667EEA),
                onPressed: () {
                  final message = _chatProvider.messages.firstWhere(
                        (m) => m.id == _selectedMessageIds.first,
                  );
                  _clearSelection();
                  _shareMediaMessage(message);
                },
                child: Icon(Icons.share, size: iconSize3),
              ),
              SizedBox(width: spacing1),
            ],
          FloatingActionButton(
            heroTag: 'info',
            mini: true,
            backgroundColor: const Color(0xFF00ACC1),
            onPressed: () {
              if (_selectedMessageIds.length == 1) {
                final message = _chatProvider.messages.firstWhere(
                      (m) => m.id == _selectedMessageIds.first,
                );
                _clearSelection(); // Dismiss before showing dialog
                _showMessageInfo(message);
              }
            },
            child: Icon(Icons.info_outline, size: iconSize3),
          ),
          SizedBox(width: spacing1),
          FloatingActionButton(
            heroTag: 'react',
            mini: true,
            backgroundColor: const Color(0xFFFFC107),
            onPressed: () {
              if (_selectedMessageIds.length == 1) {
                final selectedMessage = _chatProvider.messages.firstWhere((m) => m.id == _selectedMessageIds.first);
                _clearSelection();
                _showReactionPicker(selectedMessage.id);
              }
            },
            child: Icon(Icons.add_reaction_outlined, size: iconSize3),
          ),
          SizedBox(width: spacing1),
          FloatingActionButton(
            heroTag: 'copy',
            mini: true,
            backgroundColor: Colors.orange,
            onPressed: _copySelectedMessages,
            child: Icon(Icons.copy, size: iconSize3),
          ),
          SizedBox(width: spacing1),
          FloatingActionButton(
            heroTag: 'delete',
            mini: true,
            backgroundColor: Colors.red,
            onPressed: _deleteSelectedMessages,
            child: Icon(Icons.delete, size: iconSize3),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bodyTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final iconSize3 = (screenWidth * 0.045).clamp(16.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final spacing1 = (screenWidth * 0.02).clamp(6.0, 10.0);
    final spacing2 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final borderRadius1 = (screenWidth * 0.06).clamp(22.0, 28.0);

    return GestureDetector(
      onTap: () {
        if (_isMultiSelectionMode) {
          _clearSelection();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: spacing1, vertical: spacing1),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF667EEA).withOpacity(0.05),
              const Color(0xFF764BA2).withOpacity(0.05),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply preview
            if (_replyingToMessage != null)
              Container(
                padding: EdgeInsets.all(spacing1),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(spacing1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(width: spacing1),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _replyingToMessage!.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF667EEA),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _replyingToMessage!.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[700], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Colors.black),
                      onPressed: _cancelReply,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            // Input area
            _isRecordingVoice
                ? VoiceMessageRecorder(
                    onRecordingComplete: _sendVoiceMessage,
                    onCancel: () {
                      setState(() {
                        _isRecordingVoice = false;
                      });
                    },
                  )
                : Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(borderRadius1),
                        border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.attach_file, color: Colors.grey[600], size: iconSize3),
                            onPressed: () {
                              if (_isMultiSelectionMode) {
                                _clearSelection();
                              } else {
                                _showImagePickerDialog();
                              }
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              style: TextStyle(color: Colors.black87, fontSize: bodyTextSize),
                              decoration: InputDecoration(
                                hintText: 'Message',
                                hintStyle: TextStyle(color: Colors.grey[400], fontSize: bodyTextSize),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: spacing1, vertical: padding2),
                              ),
                              maxLines: 5,
                              minLines: 1,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendMessage(),
                              onTap: () {
                                if (_isMultiSelectionMode) {
                                  _clearSelection();
                                }
                              },
                            ),
                          ),
                          // AI Mode Toggle Button with particle animation
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.auto_awesome,
                                  color: _isAIMode ? const Color(0xFF667EEA) : Colors.grey[600],
                                  size: iconSize3,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isAIMode = !_isAIMode;
                                  });
                                },
                              ),
                              // Magic particles when processing
                              if (_isAIProcessing)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: AIProcessingParticles(
                                      isProcessing: _isAIProcessing,
                                      color: const Color(0xFF667EEA),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: spacing1),
                  // Show enhance button when in AI mode with text
                  if (_isAIMode && _hasTextInput) ...[
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6F00), Color(0xFFFFA000)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.auto_fix_high,
                          color: Colors.white,
                          size: iconSize3,
                        ),
                        tooltip: 'Enhance message',
                        onPressed: _showEnhanceOptions,
                      ),
                    ),
                    SizedBox(width: spacing1),
                  ],
                  // Send/Mic button
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        _hasTextInput ? Icons.send : Icons.mic,
                        color: Colors.white,
                        size: iconSize3,
                      ),
                      onPressed: _hasTextInput ? _sendMessage : _startVoiceRecording,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Helper function to convert HEX string (RRGGBB) to Flutter Color (0xFFRRGGBB)
  Color _colorFromHex(String hexColor) {
    // Use a try-catch or safe parsing if you want robust error handling,
    // but for clean input from the database, this is concise:
    return Color(int.parse('0xFF$hexColor'));
  }

  Widget _buildEncryptionBanner() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bannerPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final fontSize = (screenWidth * 0.035).clamp(13.0, 16.0);

    // Hindi and English content
    final title = _isBannerInHindi ? 'एंड-टू-एंड एन्क्रिप्टेड' : 'End-to-End Encrypted';
    final subtitle = _isBannerInHindi
        ? 'आपके संदेश निजी रहते हैं — केवल आप और आपका चैट पार्टनर पढ़ सकते हैं। Zarq Messenger भी नहीं'
        : 'Your messages stay private — only you and your chat partner can read them. Not even Zarq Messenger can';

    return ParticleAnimationWidget(
      isRemoving: _isRemovingBanner,
      onAnimationComplete: () {},
      child: GestureDetector(
        onTap: _showRemoveBannerDialog,
        onDoubleTap: () {
          setState(() {
            _isBannerInHindi = !_isBannerInHindi;
          });
        },
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: bannerPadding,
            vertical: bannerPadding * 0.5,
          ),
          padding: EdgeInsets.all(bannerPadding),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: fontSize * 0.85,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, int index, int itemCount) {
    final isMe = message.senderUid == _currentUserUid;
    final isSelected = _selectedMessageIds.contains(message.id);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final bodyTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final smallTextSize = (screenWidth * 0.0325).clamp(12.0, 15.0);
    final tinyTextSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final padding1 = (screenWidth * 0.04).clamp(12.0, 20.0);
    final padding2 = (screenWidth * 0.03).clamp(10.0, 16.0);
    final spacing1 = (screenWidth * 0.01).clamp(3.0, 6.0);
    final spacing2 = (screenWidth * 0.02).clamp(6.0, 10.0);

    // 🚨 1. Dynamic styling access 🚨
    final userSettings = Provider.of<UserSettingsProvider>(context);
    final styleKey = userSettings.bubbleStyleKey;
    final colorStartHex = userSettings.colorStartHex; // Get dynamic start color
    final colorEndHex = userSettings.colorEndHex;     // Get dynamic end color
    final cardBubbleColor = userSettings.cardBubbleColor; // Get card color for modern style

    // Create unique key that changes when attachment metadata arrives
    final Key itemKey;

    if (index == itemCount - 1) {
      itemKey = _lastMessageKey;
    } else {
      // Include attachment and encryption metadata in key to force rebuild when they change
      final keyString = 'msg_${message.id}_att_${message.attachmentId}_enc_${message.mediaEncryptionKey?.substring(0, 10) ?? "none"}';
      itemKey = ValueKey(keyString);
    }

    return GestureDetector(
      key: itemKey,
      onLongPress: () => _handleMessageLongPress(message),
      onTap: () {
        if (_isAIMode) {
          // Show AI options when in AI mode
          _showAIOptions(message);
        } else if (_isMultiSelectionMode) {
          _toggleMessageSelection(message);
        } else if (message.content == "This message was deleted") {
          _showDeletedMessageOptions(message);
        } else if (message.isFailed && isMe) {
          _retryMessage(message);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: spacing2, vertical: spacing1),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: _buildMessageWithAnimation(
            message,
            isMe,
            isSelected,
            styleKey,
            colorStartHex,
            colorEndHex,
            cardBubbleColor,
            screenWidth,
            padding2,
            spacing1,
            spacing2,
            smallTextSize,
            bodyTextSize,
            tinyTextSize,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageWithAnimation(
    Message message,
    bool isMe,
    bool isSelected,
    String styleKey,
    String colorStartHex,
    String colorEndHex,
    String cardBubbleColor,
    double screenWidth,
    double padding2,
    double spacing1,
    double spacing2,
    double smallTextSize,
    double bodyTextSize,
    double tinyTextSize,
  ) {
    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    final animationStyle = userSettings.encryptionAnimationStyle;
    final shouldAnimate = animationStyle == 'dynamic' && !_animatedMessageIds.contains(message.id);

    final bubbleWidget = Stack(
      clipBehavior: Clip.none, // Allow overflow to show eye icon outside bubble
      children: [
        Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: EdgeInsets.symmetric(horizontal: padding2, vertical: spacing2),
            decoration: styleKey == 'modern_card'
              ? _getModernCardDecoration(isMe, isSelected, cardBubbleColor, screenWidth)
              : BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                    colors: isMe
                        ? [const Color(0xFFE1BEE7), const Color(0xFFCE93D8)]
                        : [const Color(0xFFB0BEC5), const Color(0xFF90A4AE)],
                  )
                      : LinearGradient(
                    colors: isMe
                    // 🚨 2. DYNAMIC GRADIENT COLORS 🚨
                        ? [
                      _colorFromHex(colorStartHex),
                      _colorFromHex(colorEndHex),
                    ]
                        : [const Color(0xFFFFFFFF), const Color(0xFFF5F5F5)], // Friend's bubble remains static
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),

                  // 🚨 3. DYNAMIC BORDER RADIUS APPLICATION 🚨
                  borderRadius: _getDynamicBorderRadius(isMe, styleKey, screenWidth),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: EdgeInsets.only(bottom: spacing1),
                    child: Text(
                      message.username,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: smallTextSize,
                        color: styleKey == 'modern_card'
                          ? Colors.blue[700]
                          : const Color(0xFF667EEA),
                      ),
                    ),
                  ),
                // Display replied message if this is a reply
                if (message.replyToMessageId != null && message.repliedMessageContent != null)
                  Container(
                    margin: EdgeInsets.only(bottom: spacing1),
                    padding: EdgeInsets.all(spacing1),
                    decoration: BoxDecoration(
                      color: (isMe ? Colors.white : Colors.grey[300])?.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(
                        left: BorderSide(
                          color: isMe ? Colors.white : const Color(0xFF667EEA),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.repliedMessageSenderName ?? 'User',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: tinyTextSize,
                            color: isMe ? Colors.white : const Color(0xFF667EEA),
                          ),
                        ),
                        Text(
                          message.repliedMessageContent!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: tinyTextSize,
                            color: isMe ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Display image if has attachment (hide if message is deleted)
                if (message.hasAttachment && message.attachmentType == 'image' && message.content != 'This message was deleted')
                  _buildImageAttachment(message),
                // Display video if has attachment (hide if message is deleted)
                if (message.hasAttachment && message.attachmentType == 'video' && message.content != 'This message was deleted')
                  _buildVideoAttachment(message),
                // Display document if has attachment (hide if message is deleted)
                if (message.hasAttachment && message.attachmentType == 'document' && message.content != 'This message was deleted')
                  _buildDocumentAttachment(message),
                // Display voice message if has audio attachment (hide if message is deleted)
                if (message.hasAttachment && message.attachmentType == 'audio' && message.content != 'This message was deleted')
                  _buildVoiceMessageAttachment(message),
                // Display text content - Show placeholders for pending attachments, hide them only when attachment is actually shown
                if (message.content != 'This message was deleted' && !(message.hasAttachment && (message.content == '[Image]' || message.content == '[Video]' || message.content == '[Voice message]' || message.content.startsWith('📄'))))
                  _buildHighlightedText(
                    message.content,
                    isMe,
                    styleKey,
                  ),
                // Show "This message was deleted" text
                if (message.content == 'This message was deleted')
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: bodyTextSize,
                      fontStyle: FontStyle.italic,
                      color: styleKey == 'modern_card'
                        ? Colors.grey[600]
                        : (isMe ? Colors.white70 : Colors.grey[600]),
                    ),
                  ),
                SizedBox(height: spacing1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('hh:mm a').format(message.timestamp.toLocal()),
                      style: TextStyle(
                        fontSize: tinyTextSize,
                        color: styleKey == 'modern_card'
                          ? Colors.grey[600]
                          : (isMe ? Colors.white70 : Colors.grey[600]),
                      ),
                    ),
                    if (isMe && message.status != MessageStatus.read) ...[
                      SizedBox(width: spacing1),
                      _buildMessageStatusIcon(message, styleKey),
                    ],
                    // Static encryption lock icon
                    SizedBox(width: spacing1),
                    Icon(
                      Icons.lock,
                      size: 12,
                      color: isMe
                        ? Colors.white
                        : Colors.black.withOpacity(0.6),
                    ),
                  ],
                ),
                // Reactions display
                MessageReactionsWidget(
                  messageId: message.id,
                  reactions: message.reactions,
                  isMe: isMe,
                ),
              ],
            ),
          ),
        // Eye icon at top-left when message is read (positioned outside with partial overlap)
        if (isMe && message.status == MessageStatus.read)
          Positioned(
            top: -(screenWidth * 0.015).clamp(5.0, 8.0),
            left: -(screenWidth * 0.015).clamp(5.0, 8.0),
            child: Icon(
              Icons.visibility,
              size: (screenWidth * 0.045).clamp(16.0, 20.0),
              color: Colors.black,
            ),
          ),
      ],
    );

    // Wrap with animation if not yet animated
    if (shouldAnimate) {
      return EncryptionAnimationWidget(
        isDecrypting: !isMe, // Receiver sees decryption animation
        onAnimationComplete: () {
          if (mounted) {
            setState(() {
              _animatedMessageIds.add(message.id);
            });
          }
        },
        child: bubbleWidget,
      );
    }

    return bubbleWidget;
  }

  BorderRadius _getDynamicBorderRadius(bool isMe, String styleKey, double screenWidth) {
    final defaultRadius = Radius.circular((screenWidth * 0.045).clamp(16.0, 22.0));
    final smallRadius = Radius.circular((screenWidth * 0.01).clamp(3.0, 6.0));

    // Map the style key (resource_key from backend) to specific radii
    switch (styleKey) {
      case 'square_corners':
      // Style 1: Minimal radius on all corners
        final squareRadius = Radius.circular((screenWidth * 0.02).clamp(7.0, 10.0));
        return BorderRadius.only(
          topLeft: squareRadius,
          topRight: squareRadius,
          bottomLeft: isMe ? squareRadius : smallRadius,
          bottomRight: isMe ? smallRadius : squareRadius,
        );

      case 'soft_edges':
      // Style 2: Very soft, large radius for a pill-like look
        final softRadius = Radius.circular((screenWidth * 0.06).clamp(22.0, 28.0));
        return BorderRadius.only(
          topLeft: softRadius,
          topRight: softRadius,
          bottomLeft: isMe ? softRadius : smallRadius,
          bottomRight: isMe ? smallRadius : softRadius,
        );

      case 'minimalist':
      // Use Radius.zero or a very small radius (like 1.0) for truly sharp edges
        const sharpRadius = Radius.circular(1.0);
        final standardRadius = Radius.circular((screenWidth * 0.045).clamp(16.0, 22.0));

        return BorderRadius.only(
          // Sharp top corners
          topLeft: sharpRadius,
          topRight: sharpRadius,

          // Rounded bottom corner opposite the tail, sharp tail corner
          bottomLeft: isMe ? standardRadius : sharpRadius,
          bottomRight: isMe ? sharpRadius : standardRadius,
        );

      case 'default_rounded':
      default:
      // Original style (Rounded everywhere except the bottom corner near the speaker)
        return BorderRadius.only(
          topLeft: defaultRadius,
          topRight: defaultRadius,
          bottomLeft: isMe ? defaultRadius : smallRadius,
          bottomRight: isMe ? smallRadius : defaultRadius,
        );
    }
  }

  BoxDecoration _getModernCardDecoration(bool isMe, bool isSelected, String cardColorKey, double screenWidth) {
    // Define card color map matching customization screen
    final Map<String, Map<String, dynamic>> cardColors = {
      'blue': {'color': const Color(0xFFE3F2FD), 'border': const Color(0xFF90CAF9)},
      'green': {'color': const Color(0xFFE8F5E9), 'border': const Color(0xFF81C784)},
      'red': {'color': const Color(0xFFFFEBEE), 'border': const Color(0xFFEF5350)},
      'purple': {'color': const Color(0xFFF3E5F5), 'border': const Color(0xFFBA68C8)},
      'orange': {'color': const Color(0xFFFFF3E0), 'border': const Color(0xFFFFB74D)},
      'yellow': {'color': const Color(0xFFFFFDE7), 'border': const Color(0xFFFFF176)},
    };

    final colorData = cardColors[cardColorKey] ?? cardColors['blue']!;
    final cardColor = colorData['color'] as Color;
    final borderColor = colorData['border'] as Color;
    final borderRadius = (screenWidth * 0.03).clamp(10.0, 14.0);

    return BoxDecoration(
      color: isSelected
          ? (isMe ? const Color(0xFFE1BEE7) : const Color(0xFFB0BEC5))
          : (isMe ? cardColor : Colors.white),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isSelected
            ? (isMe ? const Color(0xFFCE93D8) : const Color(0xFF90A4AE))
            : (isMe ? borderColor : Colors.grey[300]!),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: (isMe ? borderColor : Colors.grey).withOpacity(0.2),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildMessageStatusIcon(Message message, String styleKey) {
    final iconColor = styleKey == 'modern_card' ? Colors.grey[600] : Colors.white70;
    final readIconColor = styleKey == 'modern_card' ? Colors.grey[800] : Colors.white;

    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: iconColor),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 16, color: iconColor);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 16, color: iconColor);
      case MessageStatus.read:
        return Icon(Icons.visibility, size: 16, color: readIconColor); // Eye icon
      case MessageStatus.failed:
        return Icon(Icons.error_outline, size: 16, color: iconColor);
      case MessageStatus.decrypting:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange),
        );
      case MessageStatus.decryptFailed:
        return const Icon(Icons.lock_outline, size: 16, color: Colors.red);
    }
  }

  Widget _buildImageAttachment(Message message) {
    if (message.attachmentId == null) {
      // Still uploading
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Check cache first - if cached, show immediately
    if (_imageCache.containsKey(message.attachmentId!)) {
      // print('[ChatScreen] 🖼️   → Returning cached image');
      final imageData = _imageCache[message.attachmentId!]!;
      return GestureDetector(
        onTap: () => _openFullscreenImage(imageData, message.attachmentId!),
        child: Hero(
          tag: 'image_${message.attachmentId}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              imageData,
              width: 250,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    // Not cached - load once and cache
    final encKeyPreview = message.mediaEncryptionKey != null
        ? message.mediaEncryptionKey!.substring(0, message.mediaEncryptionKey!.length < 10 ? message.mediaEncryptionKey!.length : 10)
        : 'nokey';
    // print('[ChatScreen] 🖼️   → Creating FutureBuilder to load image (key includes: $encKeyPreview)');
    return FutureBuilder<Uint8List?>(
      key: ValueKey('image_${message.attachmentId}_$encKeyPreview'), // Include encryption key in key to force rebuild
      future: _loadImage(message),
      builder: (context, snapshot) {
        // print('[ChatScreen] 🖼️   → FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');
        if (snapshot.hasError) {
          // print('[ChatScreen] 🖼️   → FutureBuilder error: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 32, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          );
        }

        final imageData = snapshot.data!;
        return GestureDetector(
          onTap: () => _openFullscreenImage(imageData, message.attachmentId!),
          child: Hero(
            tag: 'image_${message.attachmentId}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                imageData,
                width: 250,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadImage(Message message) async {
    final attachmentId = message.attachmentId;
    if (attachmentId == null) return null;

    // DEBUG: Print message encryption metadata
    // print('[ChatScreen] DEBUG _loadImage for message ${message.id}:');
    // print('[ChatScreen]   - attachmentId: $attachmentId');
    final keyPreview = message.mediaEncryptionKey != null
        ? message.mediaEncryptionKey!.substring(0, math.min(20, message.mediaEncryptionKey!.length))
        : 'null';
    // print('[ChatScreen]   - mediaEncryptionKey: $keyPreview...');
    // print('[ChatScreen]   - mediaEncryptionIv: ${message.mediaEncryptionIv}');

    // 1. Check memory cache first (fastest)
    if (_imageCache.containsKey(attachmentId)) {
      // print('[ChatScreen] Loading image $attachmentId from memory cache');
      return _imageCache[attachmentId];
    }

    // 2. Check if already loading (prevent duplicate decryption)
    if (_imageLoadingFutures.containsKey(attachmentId)) {
      // print('[ChatScreen] Image $attachmentId already loading, returning existing Future');
      return _imageLoadingFutures[attachmentId]!;
    }

    // 3. Start loading and track the Future
    final loadingFuture = _performImageLoad(message, attachmentId);
    _imageLoadingFutures[attachmentId] = loadingFuture;

    try {
      final result = await loadingFuture;
      _imageLoadingFutures.remove(attachmentId); // Clean up
      return result;
    } catch (e) {
      _imageLoadingFutures.remove(attachmentId); // Clean up on error
      rethrow;
    }
  }

  Future<Uint8List?> _performImageLoad(Message message, int attachmentId) async {
    try {
      // 1. Check persistent storage (medium speed)
      final cachedData = await FileService.loadImageFromPersistentStorage(attachmentId);
      if (cachedData != null) {
        // print('[ChatScreen] Loading image $attachmentId from persistent storage');
        // Also cache in memory for faster subsequent access
        _imageCache[attachmentId] = cachedData;
        return cachedData;
      }

      // 2.5. If encryption metadata is missing, fetch from backend
      Message workingMessage = message;
      if (message.mediaEncryptionKey == null || message.mediaEncryptionIv == null) {
        // print('[ChatScreen] ⚠️ Missing encryption metadata - fetching from backend...');
        final metadata = await FileService.fetchAttachmentMetadata(attachmentId);

        if (metadata != null) {
          final mediaEncryptionKey = metadata['media_encryption_key'] as String?;
          final mediaEncryptionIv = metadata['media_encryption_iv'] as String?;
          final senderDeviceId = metadata['sender_device_id'] as int?;

          if (mediaEncryptionKey != null && mediaEncryptionIv != null) {
            // print('[ChatScreen] ✅ Fetched encryption metadata from backend');

            // Update message with encryption metadata
            final messageIndex = _chatProvider.messages.indexWhere((m) => m.id == message.id);
            if (messageIndex != -1) {
              workingMessage = message.copyWith(
                mediaEncryptionKey: mediaEncryptionKey,
                mediaEncryptionIv: mediaEncryptionIv,
                senderDeviceId: senderDeviceId ?? message.senderDeviceId,
              );

              _chatProvider.messages[messageIndex] = workingMessage;
              _chatProvider.notifyListeners();

              // Update in database
              await _dbService.insertMessage(workingMessage);

              // print('[ChatScreen] Updated message ${message.id} with fetched encryption metadata');
            }
          } else {
            // print('[ChatScreen] ⚠️ Backend returned no encryption metadata');
          }
        } else {
          // print('[ChatScreen] ⚠️ Failed to fetch metadata from backend');
        }
      }

      // 3. Download from server (slowest)
      // print('[ChatScreen] Downloading encrypted image attachment $attachmentId...');
      final encryptedData = await FileService.downloadEncryptedFile(attachmentId);
      if (encryptedData == null) {
        // print('[ChatScreen] Failed to download image');
        return null;
      }

      // print('[ChatScreen] Downloaded ${encryptedData.length} bytes');

      // 4. Decrypt the image if encryption metadata is present
      Uint8List decryptedData;

      if (workingMessage.mediaEncryptionKey != null && workingMessage.mediaEncryptionIv != null) {
        // print('[ChatScreen] 🔐 Decrypting image with hybrid encryption...');

        final currentUser = FirebaseAuth.instance.currentUser;
        final myDeviceId = await SignalService.getDeviceId();
        final isSender = currentUser?.uid == workingMessage.senderUid;

        // print('[ChatScreen] 🔐 DECRYPTION - Message ID: ${workingMessage.id}, Attachment ID: $attachmentId');
        // print('[ChatScreen] 🔐 Current user is sender: $isSender');

        // Check if we have required fields
        if (workingMessage.senderUid == null) {
          throw Exception('Missing senderUid for decryption');
        }
        if (workingMessage.senderDeviceId == null) {
          throw Exception('Missing senderDeviceId for decryption');
        }

        // print('[ChatScreen] 🔐 My UID: ${currentUser?.uid}');
        // print('[ChatScreen] 🔐 My Device ID: $myDeviceId');
        // print('[ChatScreen] 🔐 Sender UID: ${workingMessage.senderUid}');
        // print('[ChatScreen] 🔐 Sender Device ID: ${workingMessage.senderDeviceId}');

        // STEP 1: Determine which encryption key to use and whether it needs Signal decryption
        String aesKeyB64; // This will be the raw AES key (base64)
        bool needsSignalDecryption = true;

        if (isSender && workingMessage.senderMediaEncryptionKey != null) {
          // Sender re-downloading their own media - key is stored as RAW base64 (not encrypted)
          // print('[ChatScreen] 🔐 SENDER RE-DOWNLOAD - Using raw senderMediaEncryptionKey');
          aesKeyB64 = workingMessage.senderMediaEncryptionKey!; // Already raw AES key
          needsSignalDecryption = false; // No decryption needed
          // print('[ChatScreen] 🔐 Using sender raw key (first 30 chars): ${aesKeyB64.substring(0, 30)}...');
        } else {
          // Recipient receiving media - key is encrypted with Signal or Sender Keys
          // print('[ChatScreen] 🔐 RECIPIENT RECEIVE - Using encrypted recipientMediaEncryptionKey');
          final encryptedAesKeyB64 = workingMessage.mediaEncryptionKey!;
          final decryptionSenderUid = workingMessage.senderUid!;
          final decryptionDeviceId = workingMessage.senderDeviceId!;
          // print('[ChatScreen] 🔐 Using recipient encrypted key (first 30 chars): ${encryptedAesKeyB64.substring(0, 30)}...');

          // CRITICAL: Check if this is a GROUP message (needs Sender Keys decryption)
          if (widget.conversationInfo.isGroup) {
            // print('[ChatScreen] 🔐 GROUP MEDIA - Decrypting AES key with Sender Keys Protocol');

            final decryptedAesKeyB64 = await GroupEncryptionService.decryptGroupMessage(
              senderUid: decryptionSenderUid,
              senderDeviceId: decryptionDeviceId,
              groupId: widget.conversationInfo.conversationId.toString(),
              ciphertext: encryptedAesKeyB64,
            );

            if (decryptedAesKeyB64 == null) {
              throw Exception('GroupEncryptionService.decryptGroupMessage returned null');
            }

            // print('[ChatScreen] ✅ AES key decrypted with Sender Keys Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          } else {
            // print('[ChatScreen] 🔐 1-ON-1 MEDIA - Decrypting AES key with Signal Protocol');

            // Decrypt the AES key using Signal Protocol
            final decryptedAesKeyB64 = await SignalService.decryptMessage(
              senderUid: decryptionSenderUid,
              ciphertextB64: encryptedAesKeyB64,
              deviceId: decryptionDeviceId,
            );

            if (decryptedAesKeyB64 == null) {
              throw Exception('SignalService.decryptMessage returned null');
            }

            // print('[ChatScreen] ✅ AES key decrypted with Signal Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          }
        }

        // print('[ChatScreen] 🔐 IV (base64): ${workingMessage.mediaEncryptionIv}');
        // print('[ChatScreen] 🔐 Decrypted AES Key (base64): $aesKeyB64');

        // STEP 2: Decrypt the image using AES
        try {
          final aesKey = base64.decode(aesKeyB64);
          final aesIv = base64.decode(workingMessage.mediaEncryptionIv!);

          // print('[ChatScreen] 🔐 AES Key length: ${aesKey.length} bytes');
          // print('[ChatScreen] 🔐 AES IV length: ${aesIv.length} bytes');

          decryptedData = FileService.decryptImageData(
            encryptedData: encryptedData,
            key: aesKey,
            iv: aesIv,
          );

          // print('[ChatScreen] 🎉 Image decrypted successfully!');
        } catch (e, stackTrace) {
          // print('[ChatScreen] ❌ DECRYPTION FAILED for message ${workingMessage.id}');
          // print('[ChatScreen] ❌ Error: $e');
          // print('[ChatScreen] ❌ Stack trace: $stackTrace');
          rethrow;
        }
      } else {
        // Backwards compatibility: No encryption metadata = unencrypted image
        // print('[ChatScreen] ℹ️ No encryption metadata - treating as unencrypted image');
        decryptedData = encryptedData;
      }

      // 5. Cache the DECRYPTED image in both memory and persistent storage
      _imageCache[attachmentId] = decryptedData;
      await FileService.saveImageToPersistentStorage(decryptedData, attachmentId);

      return decryptedData;
    } catch (e) {
      // print('[ChatScreen] ❌ Error loading/decrypting image: $e');
      return null;
    }
  }

  void _openFullscreenImage(Uint8List imageData, int attachmentId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenImageViewer(
          imageData: imageData,
          heroTag: 'image_$attachmentId',
        ),
      ),
    );
  }

  // Video attachment widget
  Widget _buildVideoAttachment(Message message) {
    // print('[ChatScreen] 📹 _buildVideoAttachment called for message ${message.id}');
    // print('[ChatScreen] 📹 attachmentId: ${message.attachmentId}, status: ${message.status}');
    // print('[ChatScreen] 📹 Thumbnail cache keys: ${_thumbnailCache.keys.toList()}');
    // print('[ChatScreen] 📹 Checking cache for ${message.id}: ${_thumbnailCache.containsKey(message.id)}');

    // Check if we have a thumbnail preview (even without attachmentId)
    if (message.attachmentId == null) {
      // Check if thumbnail was cached during upload (by message.id)
      if (_thumbnailCache.containsKey(message.id)) {
        // print('[ChatScreen] ✅ Found thumbnail in cache for ${message.id}');
        final thumbnailData = _thumbnailCache[message.id]!;
        return _buildUploadingThumbnail(thumbnailData, message);
      }

      // Fallback to simple loading indicator if no thumbnail
      // print('[ChatScreen] ⚠️ No thumbnail in cache for ${message.id}, showing spinner');
      return Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Uploading video...',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Check cache
    if (_videoCache.containsKey(message.attachmentId!)) {
      final videoPath = _videoCache[message.attachmentId!]!;
      return _buildVideoThumbnail(videoPath, message);
    }

    // Load video
    return FutureBuilder<String?>(
      key: ValueKey('video_${message.attachmentId}'),
      future: _loadVideo(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 250,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  'Loading video...',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Decrypting',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: 250,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 32, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text('Failed to load video', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          );
        }

        return _buildVideoThumbnail(snapshot.data!, message);
      },
    );
  }

  Widget _buildVideoThumbnail(String videoPath, Message message) {
    final attachmentId = message.attachmentId;

    // Check if thumbnail is already cached in memory
    if (attachmentId != null && _thumbnailCache.containsKey(attachmentId)) {
      final thumbnailData = _thumbnailCache[attachmentId]!;
      return _buildThumbnailWidget(thumbnailData, videoPath, message);
    }

    // Load thumbnail from persistent storage or generate new one
    return FutureBuilder<Uint8List?>(
      key: ValueKey('thumbnail_$attachmentId'),
      future: _loadOrGenerateThumbnail(videoPath, attachmentId),
      builder: (context, snapshot) {
        // Cache the thumbnail in memory when loaded/generated
        if (snapshot.hasData && attachmentId != null && snapshot.data != null) {
          _thumbnailCache[attachmentId] = snapshot.data!;
        }

        return GestureDetector(
          onTap: () => _openFullscreenVideo(videoPath),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 250,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: snapshot.hasData
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                      )
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
              // Play button overlay
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
              // Duration badge
              if (message.videoDuration != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatVideoDuration(message.videoDuration!),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadOrGenerateThumbnail(String videoPath, int? attachmentId) async {
    if (attachmentId == null) return null;

    // Try to load from persistent storage first
    final cachedThumbnail = await FileService.loadThumbnailFromPersistentStorage(attachmentId);
    if (cachedThumbnail != null) {
      // print('[ChatScreen] ✅ Loaded thumbnail from persistent storage');
      return cachedThumbnail;
    }

    // Generate new thumbnail if not cached
    // print('[ChatScreen] 🔄 Generating new thumbnail for attachment $attachmentId');
    final thumbnail = await FileService.generateVideoThumbnail(videoPath);

    if (thumbnail != null) {
      // Save to persistent storage for next time
      await FileService.saveThumbnailToPersistentStorage(thumbnail, attachmentId);
      // print('[ChatScreen] ✅ Saved thumbnail to persistent storage');
    }

    return thumbnail;
  }

  Widget _buildThumbnailWidget(Uint8List thumbnailData, String videoPath, Message message) {
    return GestureDetector(
      onTap: () => _openFullscreenVideo(videoPath),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 250,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(thumbnailData, fit: BoxFit.cover),
            ),
          ),
          // Play button overlay
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
          ),
          // Duration badge
          if (message.videoDuration != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatVideoDuration(message.videoDuration!),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Widget for showing thumbnail with loading overlay during upload
  Widget _buildUploadingThumbnail(Uint8List thumbnailData, Message message) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 250,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.3),
                BlendMode.darken,
              ),
              child: Image.memory(thumbnailData, fit: BoxFit.cover),
            ),
          ),
        ),
        // Loading overlay
        Container(
          width: 250,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Uploading...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatVideoDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Build document attachment widget
  Widget _buildDocumentAttachment(Message message) {
    // Extract filename from content (format: "📄 filename.ext")
    final fileName = message.content.replaceFirst('📄 ', '');
    final extension = path.extension(fileName).toLowerCase();

    // Get file icon based on extension
    IconData fileIcon;
    Color iconColor;

    if (extension == '.pdf') {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (extension == '.doc' || extension == '.docx') {
      fileIcon = Icons.description;
      iconColor = Colors.blue;
    } else if (extension == '.xls' || extension == '.xlsx') {
      fileIcon = Icons.table_chart;
      iconColor = Colors.green;
    } else if (extension == '.ppt' || extension == '.pptx') {
      fileIcon = Icons.slideshow;
      iconColor = Colors.orange;
    } else if (extension == '.zip' || extension == '.rar') {
      fileIcon = Icons.folder_zip;
      iconColor = Colors.purple;
    } else if (extension == '.txt') {
      fileIcon = Icons.text_snippet;
      iconColor = Colors.grey;
    } else {
      fileIcon = Icons.insert_drive_file;
      iconColor = Color(0xFF667EEA);
    }

    // Check if document is in cache OR persistent storage
    return FutureBuilder<bool>(
      future: _isDocumentDownloaded(message.attachmentId, extension),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? false;

        return GestureDetector(
          onTap: () => _openDocument(message),
          onLongPress: () => _showDocumentOptions(message),
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                // File icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    fileIcon,
                    size: 32,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                // File info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDownloaded ? 'Tap to open' : extension.toUpperCase().replaceFirst('.', ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDownloaded ? Color(0xFF667EEA) : Colors.grey[600],
                          fontWeight: isDownloaded ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                // Download/Open icon
                Icon(
                  isDownloaded ? Icons.open_in_new : Icons.download,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build voice message attachment with playback controls
  Widget _buildVoiceMessageAttachment(Message message) {
    if (message.attachmentId == null) {
      return const SizedBox();
    }

    final bool isMe = message.senderUid == _currentUserUid;

    // Check cache first (synchronously) to avoid rebuilding FutureBuilder
    final cachedPath = _audioCache[message.attachmentId];
    if (cachedPath != null) {
      final duration = message.audioDuration ?? 0;
      return VoiceMessagePlayer(
        audioPath: cachedPath,
        durationSeconds: duration,
        isSentByMe: isMe,
      );
    }

    return FutureBuilder<String?>(
      future: _loadAudio(message),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Loading audio
          return Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isMe ? Colors.white : Color(0xFF667EEA),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Loading...',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          // Error loading audio
          return Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  color: isMe ? Colors.white70 : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Failed to load audio',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        // Audio loaded successfully - show player
        final audioPath = snapshot.data!;
        final duration = message.audioDuration ?? 0;

        return VoiceMessagePlayer(
          audioPath: audioPath,
          durationSeconds: duration,
          isSentByMe: isMe,
        );
      },
    );
  }

  // Check if document is downloaded (cache or persistent storage)
  Future<bool> _isDocumentDownloaded(int? attachmentId, String extension) async {
    if (attachmentId == null) return false;

    // Check cache first
    if (_documentCache.containsKey(attachmentId)) {
      return true;
    }

    // Check persistent storage
    final exists = await FileService.documentExistsInPersistentStorage(attachmentId, extension);
    if (exists) {
      // Pre-populate cache if found in storage
      final path = await FileService.getDocumentFilePath(attachmentId, extension);
      if (path != null) {
        _documentCache[attachmentId] = path;
      }
      return true;
    }

    return false;
  }

  Future<String?> _loadVideo(Message message) async {
    final attachmentId = message.attachmentId;
    if (attachmentId == null) return null;

    // print('[ChatScreen] 📹 Loading video $attachmentId');

    // Check cache
    if (_videoCache.containsKey(attachmentId)) {
      return _videoCache[attachmentId];
    }

    // Check if already loading (prevent duplicate decryption)
    if (_videoLoadingFutures.containsKey(attachmentId)) {
      // print('[ChatScreen] Video $attachmentId already loading, returning existing Future');
      return _videoLoadingFutures[attachmentId]!;
    }

    // Start loading and track the Future
    final loadingFuture = _performVideoLoad(message, attachmentId);
    _videoLoadingFutures[attachmentId] = loadingFuture;

    try {
      final result = await loadingFuture;
      _videoLoadingFutures.remove(attachmentId); // Clean up
      return result;
    } catch (e) {
      _videoLoadingFutures.remove(attachmentId); // Clean up on error
      rethrow;
    }
  }

  Future<String?> _performVideoLoad(Message message, int attachmentId) async {
    try {
      // Check persistent storage
      final cachedPath = await FileService.getVideoFilePath(attachmentId);
      if (cachedPath != null) {
        _videoCache[attachmentId] = cachedPath;
        return cachedPath;
      }

      // Download and decrypt
      print('[ChatScreen] 📥 Downloading encrypted video $attachmentId...');
      final encryptedData = await FileService.downloadEncryptedFile(attachmentId);
      if (encryptedData == null) {
        print('[ChatScreen] ❌ Download failed');
        return null;
      }
      print('[ChatScreen] ✅ Downloaded ${encryptedData.length} bytes');

      Message workingMessage = message;
      if (message.mediaEncryptionKey == null || message.mediaEncryptionIv == null) {
        print('[ChatScreen] ⚠️ Missing encryption keys, fetching metadata...');
        final metadata = await FileService.fetchAttachmentMetadata(attachmentId);
        if (metadata != null) {
          workingMessage = message.copyWith(
            mediaEncryptionKey: metadata['media_encryption_key'],
            mediaEncryptionIv: metadata['media_encryption_iv'],
            senderDeviceId: metadata['sender_device_id'] ?? message.senderDeviceId,
          );
          print('[ChatScreen] ✅ Metadata fetched');
        }
      }

      // Decrypt
      Uint8List decryptedData;
      if (workingMessage.mediaEncryptionKey != null && workingMessage.mediaEncryptionIv != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final myDeviceId = await SignalService.getDeviceId();
        final isSender = currentUser?.uid == workingMessage.senderUid;

        print('[ChatScreen] 🔐 Video decryption - isSender: $isSender');

        // Determine which encryption key to use and whether it needs Signal decryption
        String aesKeyB64; // This will be the raw AES key (base64)

        if (isSender && workingMessage.senderMediaEncryptionKey != null) {
          // Sender re-downloading their own video - key is stored as RAW base64 (not encrypted)
          print('[ChatScreen] 🔐 SENDER RE-DOWNLOAD VIDEO - Using raw senderMediaEncryptionKey');
          aesKeyB64 = workingMessage.senderMediaEncryptionKey!; // Already raw AES key
          print('[ChatScreen] 🔐 Using sender raw key (first 30 chars): ${aesKeyB64.substring(0, math.min(30, aesKeyB64.length))}...');
        } else {
          // Recipient receiving video - key is encrypted with Signal or Sender Keys
          print('[ChatScreen] 🔐 RECIPIENT RECEIVE VIDEO - Using encrypted recipientMediaEncryptionKey');
          final encryptedAesKeyB64 = workingMessage.mediaEncryptionKey!;
          final decryptionSenderUid = workingMessage.senderUid!;
          final decryptionDeviceId = workingMessage.senderDeviceId!;
          print('[ChatScreen] 🔐 Encrypted key length: ${encryptedAesKeyB64.length}');
          print('[ChatScreen] 🔐 Sender: $decryptionSenderUid:$decryptionDeviceId');

          // CRITICAL: Check if this is a GROUP message (needs Sender Keys decryption)
          if (widget.conversationInfo.isGroup) {
            print('[ChatScreen] 🔐 GROUP VIDEO - Decrypting AES key with Sender Keys Protocol');

            final decryptedAesKeyB64 = await GroupEncryptionService.decryptGroupMessage(
              senderUid: decryptionSenderUid,
              senderDeviceId: decryptionDeviceId,
              groupId: widget.conversationInfo.conversationId.toString(),
              ciphertext: encryptedAesKeyB64,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key with Sender Keys');

            print('[ChatScreen] ✅ AES key decrypted with Sender Keys Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          } else {
            print('[ChatScreen] 🔐 1-ON-1 VIDEO - Decrypting AES key with Signal Protocol');

            final decryptedAesKeyB64 = await SignalService.decryptMessage(
              senderUid: decryptionSenderUid,
              ciphertextB64: encryptedAesKeyB64,
              deviceId: decryptionDeviceId,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key');

            print('[ChatScreen] ✅ AES key decrypted with Signal Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          }
        }

        print('[ChatScreen] 🔐 Decoding AES key and IV...');
        final aesKey = base64.decode(aesKeyB64);
        final aesIv = base64.decode(workingMessage.mediaEncryptionIv!);
        print('[ChatScreen] 🔐 Key: ${aesKey.length} bytes, IV: ${aesIv.length} bytes');

        print('[ChatScreen] 🔐 Decrypting video data...');
        decryptedData = FileService.decryptWithAES(
          encryptedData: encryptedData,
          key: aesKey,
          iv: aesIv,
        );

        print('[ChatScreen] ✅ Video decrypted successfully (${decryptedData.length} bytes)');
      } else {
        print('[ChatScreen] ⚠️ No encryption - using raw data');
        decryptedData = encryptedData;
      }

      // Save to storage
      print('[ChatScreen] 💾 Saving to persistent storage...');
      await FileService.saveVideoToPersistentStorage(decryptedData, attachmentId);
      final videoPath = await FileService.getVideoFilePath(attachmentId);

      if (videoPath != null) {
        print('[ChatScreen] ✅ Video saved: $videoPath');
        _videoCache[attachmentId] = videoPath;
        return videoPath;
      }

      print('[ChatScreen] ❌ Failed to get video path');
      return null;
    } catch (e, stackTrace) {
      print('[ChatScreen] ❌ Error loading video: $e');
      print('[ChatScreen] ❌ Stack trace: $stackTrace');
      return null;
    }
  }

  Future<String?> _loadAudio(Message message) async {
    final attachmentId = message.attachmentId;
    if (attachmentId == null) return null;

    // print('[ChatScreen] 🎵 Loading audio $attachmentId');

    // Check cache
    if (_audioCache.containsKey(attachmentId)) {
      return _audioCache[attachmentId];
    }

    // Check if already loading (prevent duplicate decryption)
    if (_audioLoadingFutures.containsKey(attachmentId)) {
      // print('[ChatScreen] Audio $attachmentId already loading, returning existing Future');
      return _audioLoadingFutures[attachmentId]!;
    }

    // Start loading and track the Future
    final loadingFuture = _performAudioLoad(message, attachmentId);
    _audioLoadingFutures[attachmentId] = loadingFuture;

    try {
      final result = await loadingFuture;
      _audioLoadingFutures.remove(attachmentId); // Clean up
      return result;
    } catch (e) {
      _audioLoadingFutures.remove(attachmentId); // Clean up on error
      rethrow;
    }
  }

  Future<String?> _performAudioLoad(Message message, int attachmentId) async {
    try {
      // Check persistent storage first
      final cachedPath = await FileService.getAudioFilePath(attachmentId);
      if (cachedPath != null) {
        // print('[ChatScreen] 🎵 Audio $attachmentId found in persistent storage');
        if (mounted) {
          setState(() {
            _audioCache[attachmentId] = cachedPath;
          });
        }
        return cachedPath;
      }

      // Download and decrypt
      // print('[ChatScreen] 🎵 Audio $attachmentId not cached, downloading...');
      final encryptedData = await FileService.downloadEncryptedFile(attachmentId);
      if (encryptedData == null) return null;

      Message workingMessage = message;
      if (message.mediaEncryptionKey == null || message.mediaEncryptionIv == null) {
        final metadata = await FileService.fetchAttachmentMetadata(attachmentId);
        if (metadata != null) {
          workingMessage = message.copyWith(
            mediaEncryptionKey: metadata['media_encryption_key'],
            mediaEncryptionIv: metadata['media_encryption_iv'],
            senderDeviceId: metadata['sender_device_id'] ?? message.senderDeviceId,
          );
        }
      }

      // Decrypt
      Uint8List decryptedData;
      if (workingMessage.mediaEncryptionKey != null && workingMessage.mediaEncryptionIv != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final isSender = currentUser?.uid == workingMessage.senderUid;

        // print('[ChatScreen] 🔐 Audio decryption - isSender: $isSender');

        // Determine which encryption key to use
        String aesKeyB64;

        if (isSender && workingMessage.senderMediaEncryptionKey != null) {
          // Sender re-downloading their own audio - key is stored as RAW base64
          // print('[ChatScreen] 🔐 SENDER RE-DOWNLOAD AUDIO - Using raw senderMediaEncryptionKey');
          aesKeyB64 = workingMessage.senderMediaEncryptionKey!;
        } else {
          // Recipient receiving audio - key is encrypted with Signal or Sender Keys
          // print('[ChatScreen] 🔐 RECIPIENT RECEIVE AUDIO - Using encrypted recipientMediaEncryptionKey');
          final encryptedAesKeyB64 = workingMessage.mediaEncryptionKey!;
          final decryptionSenderUid = workingMessage.senderUid!;
          final decryptionDeviceId = workingMessage.senderDeviceId!;

          // CRITICAL: Check if this is a GROUP message (needs Sender Keys decryption)
          if (widget.conversationInfo.isGroup) {
            // print('[ChatScreen] 🔐 GROUP AUDIO - Decrypting AES key with Sender Keys Protocol');

            final decryptedAesKeyB64 = await GroupEncryptionService.decryptGroupMessage(
              senderUid: decryptionSenderUid,
              senderDeviceId: decryptionDeviceId,
              groupId: widget.conversationInfo.conversationId.toString(),
              ciphertext: encryptedAesKeyB64,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key with Sender Keys');

            // print('[ChatScreen] ✅ AES key decrypted with Sender Keys Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          } else {
            // print('[ChatScreen] 🔐 1-ON-1 AUDIO - Decrypting AES key with Signal Protocol');

            final decryptedAesKeyB64 = await SignalService.decryptMessage(
              senderUid: decryptionSenderUid,
              ciphertextB64: encryptedAesKeyB64,
              deviceId: decryptionDeviceId,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key');

            // print('[ChatScreen] ✅ AES key decrypted with Signal Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          }
        }

        final aesKey = base64.decode(aesKeyB64);
        final aesIv = base64.decode(workingMessage.mediaEncryptionIv!);

        decryptedData = FileService.decryptAudioData(
          encryptedData: encryptedData,
          key: aesKey,
          iv: aesIv,
        );

        // print('[ChatScreen] ✅ Audio decrypted successfully');
      } else {
        decryptedData = encryptedData;
      }

      // Save to storage
      await FileService.saveAudioToPersistentStorage(decryptedData, attachmentId);
      final audioPath = await FileService.getAudioFilePath(attachmentId);

      if (audioPath != null) {
        // print('[ChatScreen] ✅ Audio $attachmentId cached successfully');
        if (mounted) {
          setState(() {
            _audioCache[attachmentId] = audioPath;
          });
        }
        return audioPath;
      }

      // print('[ChatScreen] ⚠️ Audio $attachmentId saved but path not found');
      return null;
    } catch (e) {
      // print('[ChatScreen] ❌ Error loading audio $attachmentId: $e');
      return null;
    }
  }

  void _openFullscreenVideo(String videoPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoPlayer(videoPath: videoPath),
      ),
    );
  }

  // Open document
  Future<void> _openDocument(Message message) async {
    if (message.attachmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document not available'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Check if already downloaded
      final isAlreadyDownloaded = _documentCache.containsKey(message.attachmentId!);

      // Show loading only if not downloaded
      if (!isAlreadyDownloaded && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading document...'), duration: Duration(seconds: 3)),
        );
      }

      final documentPath = await _loadDocument(message);
      if (documentPath == null) {
        throw Exception('Failed to load document');
      }

      // Refresh UI to update download icon to open icon
      if (mounted) {
        setState(() {});
      }

      // Open document with default system app
      final result = await OpenFile.open(documentPath);

      // Handle open result
      if (mounted) {
        if (result.type == ResultType.done) {
          // Successfully opened
          // print('[ChatScreen] ✅ Document opened successfully');
        } else if (result.type == ResultType.noAppToOpen) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No app found to open this file type'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (result.type == ResultType.fileNotFound) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File not found'),
              backgroundColor: Colors.red,
            ),
          );
        } else if (result.type == ResultType.permissionDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission denied to open file'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // print('[ChatScreen] Error opening document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open document: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Show document options (Share, Open) on long press
  void _showDocumentOptions(Message message) {
    final fileName = message.content.replaceFirst('📄 ', '');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 45,
                  height: 5,
                  margin: const EdgeInsets.only(top: 14, bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // File name with icon
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.insert_drive_file_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D3436),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Options with modern design
                _buildCompactOption(
                  icon: Icons.send_rounded,
                  label: 'Forward to Contact',
                  color: const Color(0xFF667EEA),
                  onTap: () {
                    Navigator.pop(context);
                    _forwardDocument(message);
                  },
                ),
                _buildCompactOption(
                  icon: Icons.share_rounded,
                  label: 'Share Externally',
                  color: const Color(0xFFFA709A),
                  onTap: () {
                    Navigator.pop(context);
                    _shareDocument(message);
                  },
                ),
                _buildCompactOption(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open Document',
                  color: const Color(0xFF11998E),
                  onTap: () {
                    Navigator.pop(context);
                    _openDocument(message);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2D3436),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Forward document to another contact
  Future<void> _forwardDocument(Message message) async {
    if (message.attachmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document not available'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Get conversations from HomeProvider
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      final conversations = homeProvider.conversations.where((c) =>
        c.conversationId != widget.conversationInfo.conversationId // Exclude current chat
      ).toList();

      if (conversations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other contacts available'), backgroundColor: Colors.orange),
        );
        return;
      }

      // Show contact picker
      final selectedConversation = await showModalBottomSheet<ConversationInfo>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, const Color(0xFFF8F9FA)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF667EEA).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Forward to Contact',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2D3436),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Contact list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, conversation),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.white, Colors.grey[50]!],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Avatar
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        conversation.chatTitle.isNotEmpty
                                            ? conversation.chatTitle[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Name
                                  Expanded(
                                    child: Text(
                                      conversation.chatTitle,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2D3436),
                                      ),
                                    ),
                                  ),
                                  // Forward icon
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Color(0xFF667EEA),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (selectedConversation == null) {
        return; // User cancelled
      }

      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forwarding document...'), duration: Duration(seconds: 3)),
        );
      }

      // Load document (download and decrypt if needed)
      final documentPath = await _loadDocument(message);
      if (documentPath == null) {
        throw Exception('Failed to load document');
      }

      // Read document bytes
      final documentBytes = await File(documentPath).readAsBytes();
      final fileName = message.content.replaceFirst('📄 ', '');
      final mimeInfo = FileService.getFileMimeType(documentPath);
      final mimeType = mimeInfo['mimeType'] ?? 'application/octet-stream';

      // Get recipient device ID
      final recipientUid = selectedConversation.partnerUid;
      if (recipientUid == null) {
        throw Exception('Recipient UID not found');
      }

      final recipientDeviceId = await DeviceService.getActiveDeviceId(recipientUid);
      if (recipientDeviceId == null) {
        throw Exception('Recipient device not found');
      }

      final myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      // Encrypt message content
      bool hasValidSendingSession = await SignalService.isSessionValidForSending(
        recipientUid: recipientUid,
        deviceId: recipientDeviceId,
      );

      String? encryptedMessage;
      if (!hasValidSendingSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: recipientUid,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: recipientUid,
          plaintext: '📄 $fileName',
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedMessage = await SignalService.encryptMessage(
          recipientUid: recipientUid,
          plaintext: '📄 $fileName',
          deviceId: recipientDeviceId,
        );
      }

      if (encryptedMessage == null) throw Exception('Encryption failed');

      // Send message
      final response = await DeviceService.sendMessage(
        conversationId: selectedConversation.conversationId,
        contentB64: encryptedMessage,
      );

      final messageId = response['message_id'];
      if (messageId == null) throw Exception('Failed to create message');

      // Encrypt document with AES
      final encryptionResult = FileService.encryptWithAES(data: documentBytes);
      final encryptedDocumentData = encryptionResult['encryptedData'] as Uint8List;
      final aesKey = encryptionResult['key'] as Uint8List;
      final aesIv = encryptionResult['iv'] as Uint8List;

      // Encrypt AES key with Signal Protocol (for RECIPIENT)
      final aesKeyB64 = base64.encode(aesKey);
      final encryptedAesKeyForRecipient = await SignalService.encryptMessage(
        recipientUid: recipientUid,
        plaintext: aesKeyB64,
        deviceId: recipientDeviceId,
      );

      if (encryptedAesKeyForRecipient == null) {
        throw Exception('Failed to encrypt document key for recipient');
      }

      // Upload encrypted document to server
      final uploadResult = await FileService.uploadEncryptedFile(
        encryptedData: encryptedDocumentData,
        messageId: messageId,
        conversationId: selectedConversation.conversationId,
        fileType: 'document',
        mimeType: mimeType,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
      );

      if (uploadResult == null) throw Exception('Document upload failed');

      final attachmentId = uploadResult['attachment_id'] as int;

      // IMPORTANT: Save sender's AES key locally so sender can view their own forwarded document
      final senderAesKeyB64 = aesKeyB64; // Raw AES key (not encrypted)

      // Cache the document for instant access
      final extension = mimeInfo['extension'] ?? '';
      await FileService.saveDocumentToPersistentStorage(documentBytes, attachmentId, extension);
      final savedPath = await FileService.getDocumentFilePath(attachmentId, extension);
      if (savedPath != null) {
        _documentCache[attachmentId] = savedPath;
      }

      // Create the complete message object and insert into local database
      final currentUser = FirebaseAuth.instance.currentUser;
      final forwardedMessage = Message(
        id: messageId,
        conversationId: selectedConversation.conversationId,
        username: currentUser?.displayName ?? 'You',
        content: '📄 $fileName',
        timestamp: DateTime.now().toUtc(),
        senderUid: currentUser?.uid ?? '',
        status: MessageStatus.sent,
        encryptedContent: encryptedMessage,
        isEncrypted: true,
        senderDeviceId: myDeviceId,
        recipientDeviceId: recipientDeviceId,
        hasAttachment: true,
        attachmentType: 'document',
        attachmentId: attachmentId,
        mediaEncryptionKey: encryptedAesKeyForRecipient,
        mediaEncryptionIv: base64.encode(aesIv),
        senderMediaEncryptionKey: senderAesKeyB64, // LOCAL ONLY
      );

      // Insert message into local database so it appears when user views the conversation
      await _dbService.insertMessage(forwardedMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document forwarded to ${selectedConversation.chatTitle}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to the conversation where document was forwarded
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      channel: widget.channel,
                      conversationInfo: selectedConversation,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }

      // print('[ChatScreen] ✅ Document forwarded successfully');
    } catch (e) {
      // print('[ChatScreen] Error forwarding document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to forward: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Share document
  Future<void> _shareDocument(Message message) async {
    if (message.attachmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document not available'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing document...'), duration: Duration(seconds: 2)),
        );
      }

      // Load document first (download and decrypt if needed)
      final documentPath = await _loadDocument(message);
      if (documentPath == null) {
        throw Exception('Failed to load document');
      }

      // Share the file
      await Share.shareXFiles(
        [XFile(documentPath)],
        text: 'Shared from Zarq Messenger',
      );

      // print('[ChatScreen] ✅ Document shared successfully');
    } catch (e) {
      // print('[ChatScreen] Error sharing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Load document (download and decrypt if needed)
  Future<String?> _loadDocument(Message message) async {
    final attachmentId = message.attachmentId;
    if (attachmentId == null) return null;

    // Extract filename and extension from message content
    final fileName = message.content.replaceFirst('📄 ', '');
    final extension = path.extension(fileName).toLowerCase();

    // print('[ChatScreen] 📄 Loading document $attachmentId');

    // Check cache
    if (_documentCache.containsKey(attachmentId)) {
      return _documentCache[attachmentId];
    }

    try {
      // Check persistent storage
      final cachedPath = await FileService.getDocumentFilePath(attachmentId, extension);
      if (cachedPath != null) {
        _documentCache[attachmentId] = cachedPath;
        return cachedPath;
      }

      // Download and decrypt
      // print('[ChatScreen] Downloading encrypted document $attachmentId...');
      final encryptedData = await FileService.downloadEncryptedFile(attachmentId);
      if (encryptedData == null) return null;

      Message workingMessage = message;
      if (message.mediaEncryptionKey == null || message.mediaEncryptionIv == null) {
        final metadata = await FileService.fetchAttachmentMetadata(attachmentId);
        if (metadata != null) {
          workingMessage = message.copyWith(
            mediaEncryptionKey: metadata['media_encryption_key'],
            mediaEncryptionIv: metadata['media_encryption_iv'],
            senderDeviceId: metadata['sender_device_id'] ?? message.senderDeviceId,
          );
        }
      }

      // Decrypt
      Uint8List decryptedData;
      if (workingMessage.mediaEncryptionKey != null && workingMessage.mediaEncryptionIv != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final isSender = currentUser?.uid == workingMessage.senderUid;

        // print('[ChatScreen] 🔐 Document decryption - isSender: $isSender');

        // Determine which encryption key to use
        String aesKeyB64;

        if (isSender && workingMessage.senderMediaEncryptionKey != null) {
          // Sender re-downloading their own document - key is stored as RAW base64
          // print('[ChatScreen] 🔐 SENDER RE-DOWNLOAD DOCUMENT - Using raw senderMediaEncryptionKey');
          aesKeyB64 = workingMessage.senderMediaEncryptionKey!;
        } else {
          // Recipient receiving document - key is encrypted with Signal or Sender Keys
          // print('[ChatScreen] 🔐 RECIPIENT RECEIVE DOCUMENT - Using encrypted recipientMediaEncryptionKey');
          final encryptedAesKeyB64 = workingMessage.mediaEncryptionKey!;
          final decryptionSenderUid = workingMessage.senderUid!;
          final decryptionDeviceId = workingMessage.senderDeviceId!;

          // CRITICAL: Check if this is a GROUP message (needs Sender Keys decryption)
          if (widget.conversationInfo.isGroup) {
            // print('[ChatScreen] 🔐 GROUP DOCUMENT - Decrypting AES key with Sender Keys Protocol');

            final decryptedAesKeyB64 = await GroupEncryptionService.decryptGroupMessage(
              senderUid: decryptionSenderUid,
              senderDeviceId: decryptionDeviceId,
              groupId: widget.conversationInfo.conversationId.toString(),
              ciphertext: encryptedAesKeyB64,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key with Sender Keys');

            // print('[ChatScreen] ✅ AES key decrypted with Sender Keys Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          } else {
            // print('[ChatScreen] 🔐 1-ON-1 DOCUMENT - Decrypting AES key with Signal Protocol');

            final decryptedAesKeyB64 = await SignalService.decryptMessage(
              senderUid: decryptionSenderUid,
              ciphertextB64: encryptedAesKeyB64,
              deviceId: decryptionDeviceId,
            );

            if (decryptedAesKeyB64 == null) throw Exception('Failed to decrypt AES key');

            // print('[ChatScreen] ✅ AES key decrypted with Signal Protocol');
            aesKeyB64 = decryptedAesKeyB64;
          }
        }

        final aesKey = base64.decode(aesKeyB64);
        final aesIv = base64.decode(workingMessage.mediaEncryptionIv!);

        decryptedData = FileService.decryptWithAES(
          encryptedData: encryptedData,
          key: aesKey,
          iv: aesIv,
        );

        // print('[ChatScreen] ✅ Document decrypted successfully');
      } else {
        decryptedData = encryptedData;
      }

      // Save to storage
      await FileService.saveDocumentToPersistentStorage(decryptedData, attachmentId, extension);
      final documentPath = await FileService.getDocumentFilePath(attachmentId, extension);

      if (documentPath != null) {
        _documentCache[attachmentId] = documentPath;
        return documentPath;
      }

      return null;
    } catch (e) {
      // print('[ChatScreen] Error loading document: $e');
      return null;
    }
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // With reverse: true, position 0 is the bottom (most recent message)
        if (instant) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _toggleMessageSelection(Message message) {
    // Allow selecting any message except deleted ones
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

  void _setReplyToMessage(Message message) {
    if (message.content == "This message was deleted") return;

    setState(() {
      _replyingToMessage = message;
    });

    // Focus on text field
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  void _handleMessageLongPress(Message message) {
    // Allow selecting any message except deleted ones
    if (message.content == "This message was deleted") return;

    if (_isMultiSelectionMode) {
      _toggleMessageSelection(message);
    } else {
      // Enter selection mode immediately
      setState(() {
        _selectedMessageIds.add(message.id);
        _isMultiSelectionMode = true;
      });
    }
  }

  void _showReactionPicker(int messageId) {
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    ReactionPicker.show(
      context,
      messageId,
      (emoji) {
        // Add reaction via WebSocket
        wsService.addReaction(messageId: messageId, emoji: emoji);
      },
    );
  }


  void _showMessageInfo(Message message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[50], // Changed from gradient to light gray
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00ACC1), Color(0xFF0097A7)], // Cyan to match AppBar
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.info_outline, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Message Info',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildInfoItem(
                Icons.send,
                'Sent',
                DateFormat('MMM dd, yyyy').format(message.timestamp.toLocal()),
                DateFormat('hh:mm a').format(message.timestamp.toLocal()),
              ),
              if (message.status == MessageStatus.delivered)
                _buildInfoItem(
                  Icons.done_all,
                  'Delivered',
                  DateFormat('MMM dd, yyyy').format(message.timestamp.add(const Duration(seconds: 30)).toLocal()),
                  DateFormat('hh:mm a').format(message.timestamp.add(const Duration(seconds: 30)).toLocal()),
                ),
              if (message.status == MessageStatus.read)
                _buildInfoItem(
                  Icons.visibility,
                  'Read',
                  DateFormat('MMM dd, yyyy').format(message.timestamp.add(const Duration(minutes: 2)).toLocal()),
                  DateFormat('hh:mm a').format(message.timestamp.add(const Duration(minutes: 2)).toLocal()),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String date, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF667EEA), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$date at $time',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }


  void _showDeleteDialog(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete message?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline, color: Colors.orange),
              title: const Text('Delete for me', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message, 'delete_for_me');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.group_outlined, color: Colors.red),
              title: const Text('Delete for everyone', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteForEveryoneConfirmation(message);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDeleteForEveryoneConfirmation(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete for everyone?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        content: const Text(
          'This message will be deleted for all participants.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message, 'delete_for_everyone');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
        await _dbService.markMessageAsDeletedForEveryone(message.id);
        _handleDeletedForEveryone(message.id);
      } else {
        await _dbService.markMessageAsDeletedForMe(message.id);
        _chatProvider.removeMessage(message.id);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  Future<void> _handleDeletedForEveryone(int messageId) async {
    final messageIndex = _chatProvider.messages.indexWhere((msg) => msg.id == messageId);
    if (messageIndex != -1) {
      final originalMessage = _chatProvider.messages[messageIndex];

      // Clear attachment from cache if it exists
      if (originalMessage.attachmentId != null) {
        _imageCache.remove(originalMessage.attachmentId);
      }

      final deletedMessage = _chatProvider.messages[messageIndex].copyWith(
        content: "This message was deleted",
        encryptedContent: null,
        isEncrypted: false,
      );

      // Manually create new message with cleared attachment fields
      // (copyWith can't set fields to null easily)
      final finalMessage = Message(
        id: deletedMessage.id,
        conversationId: deletedMessage.conversationId,
        username: deletedMessage.username,
        content: "This message was deleted",
        timestamp: deletedMessage.timestamp,
        senderUid: deletedMessage.senderUid,
        status: deletedMessage.status,
        encryptedContent: null,
        isEncrypted: false,
        senderDeviceId: deletedMessage.senderDeviceId,
        recipientDeviceId: deletedMessage.recipientDeviceId,
        isQuickReply: deletedMessage.isQuickReply,
        attachmentId: null, // Clear attachment
        attachmentType: null, // Clear attachment type
        hasAttachment: false, // No attachment anymore
        mediaEncryptionKey: null, // Clear encryption metadata
        mediaEncryptionIv: null, // Clear encryption metadata
      );

      _chatProvider.messages[messageIndex] = finalMessage;
      _chatProvider.notifyListeners();
      await _dbService.markMessageAsDeletedForEveryone(messageId);
    }
  }

  Future<void>
  _handleAttachmentUploaded(int messageId, int? attachmentId, Map<String, dynamic> data) async {
    // print('[ChatScreen] Updating message $messageId with attachment $attachmentId');
    // print('[ChatScreen] DEBUG WebSocket data: ${data.keys.toList()}');
    // print('[ChatScreen] DEBUG Full data: $data');

    var messageIndex = _chatProvider.messages.indexWhere((msg) => msg.id == messageId);

    // If message not in provider, try loading from database
    if (messageIndex == -1) {
      // print('[ChatScreen] ⚠️ Message $messageId not in provider - checking database...');
      final allMessages = await _dbService.getAllMessagesInConversation(widget.conversationInfo.conversationId);
      final messageFromDb = allMessages.where((msg) => msg.id == messageId).firstOrNull;

      if (messageFromDb != null && !await _dbService.isMessageDeletedForMe(messageId)) {
        // print('[ChatScreen] ✅ Found message $messageId in database - adding to provider');
        _chatProvider.addMessage(messageFromDb);
        messageIndex = _chatProvider.messages.indexWhere((msg) => msg.id == messageId);
      } else {
        // print('[ChatScreen] ❌ Message $messageId not found in database either - caching attachment data');
        // Cache the attachment data for when the message arrives later
        _pendingAttachments[messageId] = data;
        // print('[ChatScreen] 💾 Cached attachment data for message $messageId (pending count: ${_pendingAttachments.length})');
        return; // Exit early
      }
    }

    if (messageIndex != -1) {
      final originalMessage = _chatProvider.messages[messageIndex];

      // DEBUG: Log original message fields
      // print('[ChatScreen] DEBUG Original message before update:');
      // print('[ChatScreen]   - id: ${originalMessage.id}');
      // print('[ChatScreen]   - senderUid: ${originalMessage.senderUid}');
      // print('[ChatScreen]   - senderDeviceId: ${originalMessage.senderDeviceId}');
      // print('[ChatScreen]   - hasAttachment: ${originalMessage.hasAttachment}');

      // Extract encryption metadata from server response
      final mediaEncryptionKey = data['media_encryption_key'] as String?;
      final mediaEncryptionIv = data['media_encryption_iv'] as String?;
      final senderDeviceId = data['sender_device_id'] as int?;

      // print('[ChatScreen] DEBUG Extracted encryption metadata:');
      final extractedKeyPreview = mediaEncryptionKey != null
          ? mediaEncryptionKey.substring(0, math.min(20, mediaEncryptionKey.length))
          : 'null';
      // print('[ChatScreen]   - mediaEncryptionKey: $extractedKeyPreview...');
      // print('[ChatScreen]   - mediaEncryptionIv: $mediaEncryptionIv');
      // print('[ChatScreen]   - senderDeviceId from payload: $senderDeviceId');

      if (mediaEncryptionKey != null && mediaEncryptionIv != null) {
        // print('[ChatScreen] 🔐 Received encryption metadata for message $messageId');
      } else {
        // print('[ChatScreen] ⚠️ NO encryption metadata received for message $messageId');
      }

      final updatedMessage = originalMessage.copyWith(
        attachmentId: attachmentId,
        attachmentType: data['file_type'] as String?,
        hasAttachment: true,
        mediaEncryptionKey: mediaEncryptionKey,
        mediaEncryptionIv: mediaEncryptionIv,
        senderDeviceId: senderDeviceId ?? originalMessage.senderDeviceId, // Use from payload or keep existing
      );

      // Update in provider using updateMessage method to ensure proper notification
      _chatProvider.updateMessage(updatedMessage);
      // print('[ChatScreen] 📢 Message updated in provider - should trigger Consumer rebuild');

      // Force immediate UI refresh
      if (mounted) {
        setState(() {});
      }

      // Update in database
      await _dbService.insertMessage(updatedMessage);

      // print('[ChatScreen] ✅ Message updated with attachment${mediaEncryptionKey != null ? " and encryption metadata" : ""} in UI and DB');
      // print('[ChatScreen] 📊 Updated message summary:');
      // print('[ChatScreen]   - id: ${updatedMessage.id}');
      // print('[ChatScreen]   - attachmentId: ${updatedMessage.attachmentId}');
      // print('[ChatScreen]   - hasAttachment: ${updatedMessage.hasAttachment}');

      final updatedKeyPreview = updatedMessage.mediaEncryptionKey != null
          ? updatedMessage.mediaEncryptionKey!.substring(0, math.min(20, updatedMessage.mediaEncryptionKey!.length))
          : 'null';
      final updatedIvPreview = updatedMessage.mediaEncryptionIv != null
          ? updatedMessage.mediaEncryptionIv!.substring(0, math.min(20, updatedMessage.mediaEncryptionIv!.length))
          : 'null';

      // print('[ChatScreen]   - mediaEncryptionKey: $updatedKeyPreview...');
      // print('[ChatScreen]   - mediaEncryptionIv: $updatedIvPreview...');
      // print('[ChatScreen]   - senderDeviceId: ${updatedMessage.senderDeviceId}');

      final bubbleKeyEnc = updatedMessage.mediaEncryptionKey != null
          ? updatedMessage.mediaEncryptionKey!.substring(0, math.min(10, updatedMessage.mediaEncryptionKey!.length))
          : "none";
      // print('[ChatScreen] 🔑 Message bubble key will be: msg_${updatedMessage.id}_att_${updatedMessage.attachmentId}_enc_$bubbleKeyEnc');
    } else {
      // print('[ChatScreen] ⚠️ Message $messageId not found in provider messages list');
    }
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;

    // Check if ALL selected messages belong to current user
    final selectedMessages = _chatProvider.messages
        .where((msg) => _selectedMessageIds.contains(msg.id))
        .toList();
    final allOwnMessages = selectedMessages.every((msg) => msg.senderUid == _currentUserUid);

    final deletionType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete ${_selectedMessageIds.length} messages?',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline, color: Colors.orange),
              title: const Text('Delete for me', style: TextStyle(color: Colors.black87)),
              onTap: () => Navigator.of(context).pop('delete_for_me'),
            ),
            // Only show "Delete for everyone" if ALL selected messages are own messages
            if (allOwnMessages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined, color: Colors.red),
                title: const Text('Delete for everyone', style: TextStyle(color: Colors.black87)),
                onTap: () => Navigator.of(context).pop('delete_for_everyone'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (deletionType == null) return;

    if (deletionType == 'delete_for_everyone') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Delete for everyone?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          content: const Text(
            'These messages will be deleted for all participants.',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
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
          backgroundColor: successCount == idsToDelete.length ? const Color(0xFF00ACC1) : Colors.orange,
        ),
      );
    }
  }

  void _showDeletedMessageOptions(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove deleted message?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        content: const Text(
          'This will permanently remove this message from your view.',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeDeletedMessage(message.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
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
  }

  // Check if the selected message is a media message (image/video/document)
  bool _isSelectedMessageMedia() {
    if (_selectedMessageIds.isEmpty) return false;

    final message = _chatProvider.messages.firstWhere(
      (m) => m.id == _selectedMessageIds.first,
      orElse: () => Message(
        id: -1,
        conversationId: -1,
        username: '',
        content: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ),
    );

    return message.hasAttachment &&
           message.attachmentId != null &&
           (message.attachmentType == 'image' ||
            message.attachmentType == 'video' ||
            message.attachmentType == 'document');
  }

  // Share media message (image/video/document)
  Future<void> _shareMediaMessage(Message message) async {
    if (!message.hasAttachment || message.attachmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media to share'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing to share...'), duration: Duration(seconds: 2)),
        );
      }

      if (message.attachmentType == 'image') {
        // Share image
        final imageData = await _loadImage(message);
        if (imageData == null) {
          throw Exception('Failed to load image');
        }

        // Create temporary file
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(path.join(tempDir.path, 'zarq_share_${DateTime.now().millisecondsSinceEpoch}.jpg'));
        await tempFile.writeAsBytes(imageData);

        // Share the file
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'Shared from Zarq Messenger',
        );

        // Clean up temp file after a delay
        Future.delayed(const Duration(seconds: 5), () {
          tempFile.delete().catchError((e) {
            // print('[ChatScreen] Failed to delete temp file: $e');
            return tempFile; // Return the file object to satisfy the type
          });
        });
      } else if (message.attachmentType == 'video') {
        // Share video
        final videoPath = await _loadVideo(message);
        if (videoPath == null) {
          throw Exception('Failed to load video');
        }

        await Share.shareXFiles(
          [XFile(videoPath)],
          text: 'Shared from Zarq Messenger',
        );
      } else if (message.attachmentType == 'document') {
        // Share document
        await _shareDocument(message);
      }

      // print('[ChatScreen] ✅ Media shared successfully');
    } catch (e) {
      // print('[ChatScreen] Error sharing media: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
          content: Text('Message(s) copied'),
          backgroundColor: Color(0xFF1976D2), // Changed to blue
        ),
      );
    }
  }

  // Get status text for app bar subtitle
  String _getStatusText() {
    if (_establishingSession) {
      return 'Establishing...';
    }

    if (_isRecipientOnline) {
      return 'online';
    }

    if (_recipientLastSeen != null) {
      return 'last seen ${_formatLastSeen(_recipientLastSeen!)}';
    }

    if (_sessionEstablished) {
      return 'End-to-end encrypted';
    }

    return 'Tap to encrypt';
  }

  // Format last seen time in local timezone
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final localLastSeen = lastSeen.toLocal();
    final difference = now.difference(localLastSeen);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      // Show date for older timestamps
      return '${localLastSeen.day}/${localLastSeen.month}/${localLastSeen.year}';
    }
  }

  // Build highlighted text for search results
  Widget _buildHighlightedText(String text, bool isMe, String styleKey) {
    // Determine text color based on style
    final textColor = styleKey == 'modern_card'
        ? Colors.black87
        : (isMe ? Colors.white : Colors.black87);

    // If not searching or no query, show text with clickable links
    if (!_isSearching || _searchQuery.isEmpty) {
      return Linkify(
        onOpen: (link) async {
          final url = Uri.parse(link.url);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
        text: text,
        style: TextStyle(
          fontSize: 16,
          color: textColor,
        ),
        linkStyle: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.blue[100] : Colors.blue[700],
          decoration: TextDecoration.underline,
        ),
      );
    }

    // Build highlighted text with search matches
    // Note: When searching, we'll show highlighted text without linkify
    // This is a trade-off to avoid complexity of combining both features
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(_searchQuery, start);

      if (index == -1) {
        // No more matches, add remaining text
        spans.add(TextSpan(
          text: text.substring(start),
          style: TextStyle(
            fontSize: 16,
            color: textColor,
          ),
        ));
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: TextStyle(
            fontSize: 16,
            color: textColor,
          ),
        ));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + _searchQuery.length),
        style: TextStyle(
          fontSize: 16,
          color: textColor,
          backgroundColor: Colors.yellow.withOpacity(0.7),
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + _searchQuery.length;
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  // Build WhatsApp-style typing animation (three bouncing dots)
  Widget _buildTypingAnimation() {
    return AnimatedBuilder(
      animation: _typingAnimationController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, _typingDotAnimations[index].value),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // ============================================
  // Menu Actions Implementation
  // ============================================

  /// Toggle mute notifications
  Future<void> _toggleMuteNotifications() async {
    // TODO: Implement proper mute state storage
    final prefs = await SharedPreferences.getInstance();
    final key = 'muted_${widget.conversationInfo.conversationId}';
    final isMuted = prefs.getBool(key) ?? false;

    await prefs.setBool(key, !isMuted);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMuted ? 'Notifications unmuted' : 'Notifications muted'),
          backgroundColor: isMuted ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Load wallpaper from SharedPreferences
  Future<void> _loadWallpaper() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationId = widget.conversationInfo.conversationId;

      // Check for background image first
      final imagePath = prefs.getString('wallpaper_image_$conversationId');
      if (imagePath != null && File(imagePath).existsSync()) {
        setState(() {
          _chatBackgroundImage = imagePath;
        });
        return;
      }

      // If no image, check for color
      final colorValue = prefs.getInt('wallpaper_$conversationId');
      if (colorValue != null) {
        setState(() {
          _chatBackgroundColor = Color(colorValue);
        });
      }
    } catch (e) {
      // print('[ChatScreen] Error loading wallpaper: $e');
    }
  }

  /// Load blocked users from SharedPreferences
  Future<void> _loadBlockedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];

      setState(() {
        _blockedUsers = blockedUsers;
        _isUserBlocked = _recipientUid != null && blockedUsers.contains(_recipientUid);
      });
    } catch (e) {
      // print('[ChatScreen] Error loading blocked users: $e');
    }
  }

  /// Load encryption banner preference from SharedPreferences (per conversation)
  Future<void> _loadEncryptionBannerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationId = widget.conversationInfo.conversationId;
      final showBanner = prefs.getBool('show_encryption_banner_$conversationId') ?? true;
      setState(() {
        _showEncryptionBanner = showBanner;
      });
    } catch (e) {
      // print('[ChatScreen] Error loading encryption banner preference: $e');
    }
  }

  /// Save encryption banner preference to SharedPreferences (per conversation)
  Future<void> _saveEncryptionBannerPreference(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final conversationId = widget.conversationInfo.conversationId;
      await prefs.setBool('show_encryption_banner_$conversationId', show);
    } catch (e) {
      // print('[ChatScreen] Error saving encryption banner preference: $e');
    }
  }

  /// Show dialog to confirm banner removal
  void _showRemoveBannerDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final titleFontSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final contentFontSize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final buttonFontSize = (screenWidth * 0.035).clamp(13.0, 15.0);
    final iconSize = (screenWidth * 0.06).clamp(22.0, 26.0);
    final padding = (screenWidth * 0.04).clamp(16.0, 24.0);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.all(padding),
          title: Row(
            children: [
              Icon(Icons.lock, color: Colors.blue, size: iconSize),
              SizedBox(width: padding * 0.5),
              Expanded(
                child: Text(
                  'Hide Encryption Banner',
                  style: TextStyle(fontSize: titleFontSize),
                ),
              ),
            ],
          ),
          content: Text(
            'Do you want to hide the end-to-end encryption banner?\n\nYour messages will still remain encrypted.',
            style: TextStyle(fontSize: contentFontSize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(fontSize: buttonFontSize)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeBannerWithAnimation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('Hide', style: TextStyle(fontSize: buttonFontSize)),
            ),
          ],
        );
      },
    );
  }

  /// Remove banner with particle animation
  void _removeBannerWithAnimation() {
    setState(() {
      _isRemovingBanner = true;
    });

    // Wait for animation to complete before hiding banner
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showEncryptionBanner = false;
          _isRemovingBanner = false;
        });
        _saveEncryptionBannerPreference(false);
      }
    });
  }

  /// Show wallpaper picker dialog
  void _showWallpaperPicker() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final dialogPadding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final titleFontSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final descFontSize = (screenWidth * 0.035).clamp(12.0, 16.0);
    final galleryFontSize = (screenWidth * 0.038).clamp(14.0, 17.0);
    final iconSize = (screenWidth * 0.055).clamp(20.0, 26.0);
    final spacing1 = (screenHeight * 0.015).clamp(10.0, 16.0);
    final spacing2 = (screenHeight * 0.01).clamp(8.0, 12.0);
    final wrapSpacing = (screenWidth * 0.025).clamp(8.0, 12.0);
    final optionSize = (screenWidth * 0.18).clamp(65.0, 85.0);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Change Wallpaper',
          style: TextStyle(fontSize: titleFontSize),
        ),
        contentPadding: EdgeInsets.fromLTRB(dialogPadding, dialogPadding, dialogPadding, 0),
        content: SingleChildScrollView(
          child: SizedBox(
            width: screenWidth * 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a background for this chat',
                  style: TextStyle(fontSize: descFontSize),
                ),
                SizedBox(height: spacing1),
                // Gallery option
                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickWallpaperFromGallery();
                  },
                  child: Container(
                    padding: EdgeInsets.all(dialogPadding * 0.8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image, color: Colors.blue[700], size: iconSize),
                        SizedBox(width: spacing2),
                        Flexible(
                          child: Text(
                            'Choose from Gallery',
                            style: TextStyle(
                              fontSize: galleryFontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: spacing1),
                Text(
                  'Or choose a color:',
                  style: TextStyle(fontSize: descFontSize * 0.9, color: Colors.grey),
                ),
                SizedBox(height: spacing2),
                Wrap(
                  spacing: wrapSpacing,
                  runSpacing: wrapSpacing,
                  children: [
                    _buildWallpaperOption(const Color(0xFFECE5DD), 'Default', optionSize),
                    _buildWallpaperOption(const Color(0xFF000000), 'Dark Black', optionSize),
                    _buildWallpaperOption(const Color(0xFFE8F5E9), 'Green', optionSize),
                    _buildWallpaperOption(const Color(0xFFE3F2FD), 'Blue', optionSize),
                    _buildWallpaperOption(const Color(0xFFFFF3E0), 'Orange', optionSize),
                    _buildWallpaperOption(const Color(0xFFF3E5F5), 'Purple', optionSize),
                    _buildWallpaperOption(const Color(0xFFFFEBEE), 'Pink', optionSize),
                  ],
                ),
                SizedBox(height: spacing2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Pick wallpaper image from gallery
  Future<void> _pickWallpaperFromGallery() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      final prefs = await SharedPreferences.getInstance();
      final conversationId = widget.conversationInfo.conversationId;

      // Save image path and clear color setting
      await prefs.setString('wallpaper_image_$conversationId', pickedFile.path);
      await prefs.remove('wallpaper_$conversationId');

      if (mounted) {
        setState(() {
          _chatBackgroundImage = pickedFile.path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallpaper changed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // print('[ChatScreen] Error picking wallpaper: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set wallpaper: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildWallpaperOption(Color color, String name, double size) {
    final screenWidth = MediaQuery.of(context).size.width;
    final nameFontSize = (screenWidth * 0.028).clamp(9.0, 13.0);

    return InkWell(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final conversationId = widget.conversationInfo.conversationId;

        // Save color and remove image
        await prefs.setInt('wallpaper_$conversationId', color.value);
        await prefs.remove('wallpaper_image_$conversationId');

        if (mounted) {
          setState(() {
            _chatBackgroundColor = color;
            _chatBackgroundImage = null;
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wallpaper changed to $name'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!, width: 2),
        ),
        child: Center(
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: nameFontSize,
              fontWeight: FontWeight.w600,
              color: color.computeLuminance() < 0.5 ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  /// Show clear chat confirmation dialog
  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat'),
        content: const Text(
          'Are you sure you want to delete all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearChat();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChat() async {
    try {
      // Delete all messages from database
      await DatabaseService.deleteAllMessagesInConversation(
        widget.conversationInfo.conversationId,
      );

      // Clear from provider
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.clearMessages();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat cleared successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear chat: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show block user confirmation dialog
  void _showBlockUserDialog() {
    if (_recipientUid == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${widget.conversationInfo.chatTitle}? You will no longer receive messages from this user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _blockUser();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  Future<void> _blockUser() async {
    if (_recipientUid == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];
      if (!blockedUsers.contains(_recipientUid)) {
        blockedUsers.add(_recipientUid!);
        await prefs.setStringList('blocked_users', blockedUsers);
      }

      // Reload blocked users list
      await _loadBlockedUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.conversationInfo.chatTitle} has been blocked. You can unblock from menu.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        // Don't navigate away - let user unblock if they want
        setState(() {}); // Force rebuild to update menu
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to block user: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Unblock the current user
  Future<void> _unblockUser() async {
    if (_recipientUid == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];
      blockedUsers.remove(_recipientUid);
      await prefs.setStringList('blocked_users', blockedUsers);

      // Reload blocked users list and messages
      await _loadBlockedUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.conversationInfo.chatTitle} has been unblocked'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unblock user: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // AI Features
  void _showAIOptions(Message message) {
    // Don't show AI options for deleted messages or messages with only attachments
    if (message.content == "This message was deleted" ||
        message.content.isEmpty ||
        message.content == '[Image]' ||
        message.content == '[Video]' ||
        message.content == '[Voice message]') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot use AI on this message'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final handleWidth = (screenWidth * 0.1).clamp(35.0, 50.0);
    final handleHeight = (screenHeight * 0.005).clamp(3.0, 5.0);
    final spacing1 = (screenHeight * 0.015).clamp(10.0, 16.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: spacing1),
              // Drag handle
              Container(
                width: handleWidth,
                height: handleHeight,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // AI Options Cards
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing1),
                child: Column(
                  children: [
                    _buildAIActionCard(
                      icon: Icons.translate,
                      title: 'Translate',
                      subtitle: 'Translate to other languages',
                      color: const Color(0xFF4CAF50),
                      onTap: () {
                        Navigator.pop(context);
                        _showTranslateDialog(message);
                      },
                    ),
                    SizedBox(height: spacing1),
                    _buildAIActionCard(
                      icon: Icons.summarize,
                      title: 'Summarize',
                      subtitle: 'Get a brief summary',
                      color: const Color(0xFF2196F3),
                      onTap: () {
                        Navigator.pop(context);
                        _showLanguageSelectionDialog(message, 'summarize');
                      },
                    ),
                    SizedBox(height: spacing1),
                    _buildAIActionCard(
                      icon: Icons.lightbulb_outline,
                      title: 'Explain',
                      subtitle: 'Explain in simple terms',
                      color: const Color(0xFFFF9800),
                      onTap: () {
                        Navigator.pop(context);
                        _showLanguageSelectionDialog(message, 'explain');
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1),
              // Privacy warning
              Container(
                margin: EdgeInsets.symmetric(horizontal: spacing1),
                padding: EdgeInsets.all(spacing1 * 0.8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    SizedBox(width: spacing1 * 0.5),
                    Expanded(
                      child: Text(
                        'Message sent to Google AI (E2EE bypassed)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildAIActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final cardPadding = (screenWidth * 0.04).clamp(14.0, 20.0);
    final iconPadding = (screenWidth * 0.03).clamp(10.0, 14.0);
    final iconSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final titleSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final subtitleSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final arrowSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.04).clamp(12.0, 18.0);
    final spacing2 = (screenHeight * 0.0025).clamp(2.0, 4.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(iconPadding),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            SizedBox(width: spacing1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: spacing2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: subtitleSize,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: arrowSize),
          ],
        ),
      ),
    );
  }

  void _showTranslateDialog(Message message) {
    final languages = {
      'English': '🇬🇧',
      'Spanish': '🇪🇸',
      'French': '🇫🇷',
      'German': '🇩🇪',
      'Italian': '🇮🇹',
      'Portuguese': '🇵🇹',
      'Russian': '🇷🇺',
      'Chinese': '🇨🇳',
      'Japanese': '🇯🇵',
      'Korean': '🇰🇷',
      'Arabic': '🇸🇦',
      'Hindi': '🇮🇳',
      'Bengali': '🇧🇩',
      'Tamil': '🇮🇳',
      'Telugu': '🇮🇳',
      'Marathi': '🇮🇳',
    };

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing1 = (screenHeight * 0.015).clamp(12.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final bodySize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final emojiSize = (screenWidth * 0.08).clamp(28.0, 36.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: spacing1),
              // Handle bar
              Container(
                width: (screenWidth * 0.1).clamp(40.0, 50.0),
                height: (screenHeight * 0.005).clamp(4.0, 5.0),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Title with gradient background
              Container(
                margin: EdgeInsets.symmetric(horizontal: padding1),
                padding: EdgeInsets.all(padding1 * 0.8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF4CAF50).withOpacity(0.1), const Color(0xFF4CAF50).withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(spacing1 * 0.6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.translate, color: const Color(0xFF4CAF50), size: titleSize),
                    ),
                    SizedBox(width: spacing1),
                    Text(
                      'Select Language',
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Language grid
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: padding1),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: spacing1,
                    mainAxisSpacing: spacing1,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages.keys.elementAt(index);
                    final flag = languages[language]!;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 300 + (index * 30)),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 0.8 + (0.2 * value),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _processAI(message, 'translate', targetLanguage: language);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF4CAF50).withOpacity(0.08),
                                const Color(0xFF4CAF50).withOpacity(0.03),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF4CAF50).withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                flag,
                                style: TextStyle(fontSize: emojiSize),
                              ),
                              SizedBox(width: spacing1 * 0.75),
                              Flexible(
                                child: Text(
                                  language,
                                  style: TextStyle(
                                    fontSize: bodySize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
            ],
          ),
        ),
      ),
    );
  }

  // Show language selection dialog for Summarize/Explain
  void _showLanguageSelectionDialog(Message message, String action) {
    final languages = {
      'English': '🇬🇧',
      'Spanish': '🇪🇸',
      'French': '🇫🇷',
      'German': '🇩🇪',
      'Italian': '🇮🇹',
      'Portuguese': '🇵🇹',
      'Russian': '🇷🇺',
      'Chinese': '🇨🇳',
      'Japanese': '🇯🇵',
      'Korean': '🇰🇷',
      'Arabic': '🇸🇦',
      'Hindi': '🇮🇳',
      'Bengali': '🇧🇩',
      'Tamil': '🇮🇳',
      'Telugu': '🇮🇳',
      'Marathi': '🇮🇳',
    };

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing1 = (screenHeight * 0.015).clamp(12.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final bodySize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final emojiSize = (screenWidth * 0.08).clamp(28.0, 36.0);

    // Get title and icon based on action
    final actionTitle = action == 'summarize' ? 'Summarize' : 'Explain';
    final actionIcon = action == 'summarize' ? Icons.summarize : Icons.lightbulb_outline;
    final actionColor = action == 'summarize' ? const Color(0xFF2196F3) : const Color(0xFFFF9800);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: spacing1),
              // Handle bar
              Container(
                width: (screenWidth * 0.1).clamp(40.0, 50.0),
                height: (screenHeight * 0.005).clamp(4.0, 5.0),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Title with gradient background
              Container(
                margin: EdgeInsets.symmetric(horizontal: padding1),
                padding: EdgeInsets.all(padding1 * 0.8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [actionColor.withOpacity(0.1), actionColor.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: actionColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(spacing1 * 0.6),
                      decoration: BoxDecoration(
                        color: actionColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(actionIcon, color: actionColor, size: titleSize),
                    ),
                    SizedBox(width: spacing1),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actionTitle,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Select output language',
                          style: TextStyle(
                            fontSize: bodySize * 0.9,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Language grid
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: padding1),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: spacing1,
                    mainAxisSpacing: spacing1,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages.keys.elementAt(index);
                    final flag = languages[language]!;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 300 + (index * 30)),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 0.8 + (0.2 * value),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _processAI(message, action, targetLanguage: language);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                actionColor.withOpacity(0.08),
                                actionColor.withOpacity(0.03),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: actionColor.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                flag,
                                style: TextStyle(fontSize: emojiSize),
                              ),
                              SizedBox(width: spacing1 * 0.75),
                              Flexible(
                                child: Text(
                                  language,
                                  style: TextStyle(
                                    fontSize: bodySize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
            ],
          ),
        ),
      ),
    );
  }

  // Show language selection dialog for text enhance
  void _showEnhanceLanguageDialog(String style) {
    final languages = {
      'English': '🇬🇧',
      'Spanish': '🇪🇸',
      'French': '🇫🇷',
      'German': '🇩🇪',
      'Italian': '🇮🇹',
      'Portuguese': '🇵🇹',
      'Russian': '🇷🇺',
      'Chinese': '🇨🇳',
      'Japanese': '🇯🇵',
      'Korean': '🇰🇷',
      'Arabic': '🇸🇦',
      'Hindi': '🇮🇳',
      'Bengali': '🇧🇩',
      'Tamil': '🇮🇳',
      'Telugu': '🇮🇳',
      'Marathi': '🇮🇳',
    };

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing1 = (screenHeight * 0.015).clamp(12.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final bodySize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final emojiSize = (screenWidth * 0.08).clamp(28.0, 36.0);

    // Get style info
    final styleInfo = _getStyleInfo(style);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: spacing1),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Header
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padding1),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: styleInfo['color'].withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        styleInfo['icon'],
                        color: styleInfo['color'],
                        size: 32,
                      ),
                    ),
                    SizedBox(height: spacing1),
                    Text(
                      styleInfo['title'],
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: spacing1 * 0.5),
                    Text(
                      'Select output language',
                      style: TextStyle(
                        fontSize: bodySize,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Language grid
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: padding1),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: spacing1,
                    mainAxisSpacing: spacing1,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: languages.length,
                  itemBuilder: (context, index) {
                    final language = languages.keys.elementAt(index);
                    final flag = languages[language]!;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 300 + (index * 30)),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 0.8 + (0.2 * value),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          _enhanceInputText(style, targetLanguage: language);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                styleInfo['color'].withOpacity(0.08),
                                styleInfo['color'].withOpacity(0.03),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: styleInfo['color'].withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                flag,
                                style: TextStyle(fontSize: emojiSize),
                              ),
                              SizedBox(width: spacing1 * 0.75),
                              Flexible(
                                child: Text(
                                  language,
                                  style: TextStyle(
                                    fontSize: bodySize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to get style info
  Map<String, dynamic> _getStyleInfo(String style) {
    switch (style) {
      case 'formal':
        return {
          'title': 'Make Formal',
          'icon': Icons.business_center,
          'color': const Color(0xFF9C27B0),
        };
      case 'casual':
        return {
          'title': 'Make Casual',
          'icon': Icons.sentiment_satisfied,
          'color': const Color(0xFF00BCD4),
        };
      case 'concise':
        return {
          'title': 'Make Concise',
          'icon': Icons.compress,
          'color': const Color(0xFFFF5722),
        };
      case 'fix':
        return {
          'title': 'Fix Grammar',
          'icon': Icons.check_circle_outline,
          'color': const Color(0xFF4CAF50),
        };
      default:
        return {
          'title': 'Enhance',
          'icon': Icons.auto_awesome,
          'color': Colors.orange,
        };
    }
  }

  Future<void> _processAI(Message message, String action, {String? targetLanguage}) async {
    // Start particle animation
    setState(() {
      _isAIProcessing = true;
    });

    try {
      AIResponse response;

      switch (action) {
        case 'translate':
          response = await _aiService.translateMessage(message.content, targetLanguage!);
          break;
        case 'summarize':
          response = await _aiService.summarizeMessage(message.content, targetLanguage: targetLanguage);
          break;
        case 'explain':
          response = await _aiService.explainMessage(message.content, targetLanguage: targetLanguage);
          break;
        default:
          throw Exception('Unknown action');
      }

      // Stop particle animation
      if (mounted) {
        setState(() {
          _isAIProcessing = false;
        });
      }

      // Show result
      if (mounted) {
        _showAIResult(action, message.content, response);
      }
    } catch (e) {
      // Stop particle animation
      if (mounted) {
        setState(() {
          _isAIProcessing = false;
        });
      }

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showAIResult(String action, String originalText, AIResponse response) {
    String title;
    IconData icon;
    Color accentColor;

    switch (action) {
      case 'translate':
        title = 'Translation';
        icon = Icons.translate;
        accentColor = const Color(0xFF4CAF50);
        break;
      case 'summarize':
        title = 'Summary';
        icon = Icons.summarize;
        accentColor = const Color(0xFF2196F3);
        break;
      case 'explain':
        title = 'Explanation';
        icon = Icons.lightbulb_outline;
        accentColor = const Color(0xFFFF9800);
        break;
      default:
        title = 'AI Result';
        icon = Icons.auto_awesome;
        accentColor = const Color(0xFF667EEA);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing1 = (screenHeight * 0.015).clamp(12.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final bodySize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final labelSize = (screenWidth * 0.03).clamp(12.0, 14.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: spacing1),
              // Handle bar
              Container(
                width: (screenWidth * 0.1).clamp(40.0, 50.0),
                height: (screenHeight * 0.005).clamp(4.0, 5.0),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Title with gradient background
              Container(
                margin: EdgeInsets.symmetric(horizontal: padding1),
                padding: EdgeInsets.all(padding1 * 0.8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor.withOpacity(0.1), accentColor.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(spacing1 * 0.6),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accentColor, size: titleSize),
                    ),
                    SizedBox(width: spacing1),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: padding1),
                  children: [
                    // Original message card
                    Container(
                      padding: EdgeInsets.all(padding1 * 0.75),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.message, size: labelSize, color: Colors.grey[600]),
                              SizedBox(width: spacing1 * 0.5),
                              Text(
                                'Original Message',
                                style: TextStyle(
                                  fontSize: labelSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing1 * 0.75),
                          Text(
                            originalText,
                            style: TextStyle(fontSize: bodySize, height: 1.6, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing1 * 1.5),
                    // AI Result card with animation
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 400),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.all(padding1 * 0.75),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor.withOpacity(0.08), accentColor.withOpacity(0.03)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.auto_awesome, size: labelSize + 2, color: accentColor),
                                SizedBox(width: spacing1 * 0.5),
                                Text(
                                  'AI $title',
                                  style: TextStyle(
                                    fontSize: labelSize,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing1 * 0.75),
                            SelectableText(
                              response.content,
                              style: TextStyle(fontSize: bodySize, height: 1.6, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: spacing1 * 2),
                    // Copy button with modern style
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: response.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text('Copied to clipboard'),
                              ],
                            ),
                            backgroundColor: accentColor,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy Result'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: padding1 * 0.7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEnhanceOptions() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final handleWidth = (screenWidth * 0.1).clamp(35.0, 50.0);
    final handleHeight = (screenHeight * 0.005).clamp(3.0, 5.0);
    final spacing1 = (screenHeight * 0.015).clamp(10.0, 16.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: spacing1),
              // Drag handle
              Container(
                width: handleWidth,
                height: handleHeight,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Enhancement Options Cards
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing1),
                child: Column(
                  children: [
                    _buildAIActionCard(
                      icon: Icons.business_center,
                      title: 'Make Formal',
                      subtitle: 'Professional and polished tone',
                      color: const Color(0xFF9C27B0),
                      onTap: () {
                        Navigator.pop(context);
                        _showEnhanceLanguageDialog('formal');
                      },
                    ),
                    SizedBox(height: spacing1),
                    _buildAIActionCard(
                      icon: Icons.sentiment_satisfied,
                      title: 'Make Casual',
                      subtitle: 'Friendly and relaxed tone',
                      color: const Color(0xFF00BCD4),
                      onTap: () {
                        Navigator.pop(context);
                        _showEnhanceLanguageDialog('casual');
                      },
                    ),
                    SizedBox(height: spacing1),
                    _buildAIActionCard(
                      icon: Icons.compress,
                      title: 'Make Concise',
                      subtitle: 'Clear and to the point',
                      color: const Color(0xFFFF5722),
                      onTap: () {
                        Navigator.pop(context);
                        _showEnhanceLanguageDialog('concise');
                      },
                    ),
                    SizedBox(height: spacing1),
                    _buildAIActionCard(
                      icon: Icons.check_circle_outline,
                      title: 'Fix Grammar',
                      subtitle: 'Correct spelling and grammar',
                      color: const Color(0xFF4CAF50),
                      onTap: () {
                        Navigator.pop(context);
                        _showEnhanceLanguageDialog('fix');
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1),
              // Privacy warning
              Container(
                margin: EdgeInsets.symmetric(horizontal: spacing1),
                padding: EdgeInsets.all(spacing1 * 0.8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    SizedBox(width: spacing1 * 0.5),
                    Expanded(
                      child: Text(
                        'Text sent to Google AI',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enhanceInputText(String style, {String? targetLanguage}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Start particle animation
    setState(() {
      _isAIProcessing = true;
    });

    try {
      final response = await _aiService.enhanceMessage(text, style, targetLanguage: targetLanguage);

      // Stop particle animation
      if (mounted) {
        setState(() {
          _isAIProcessing = false;
        });
      }

      if (!response.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.error ?? 'Enhancement failed'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Show result with option to replace
      if (mounted) {
        _showEnhancedTextResult(text, response.content, style);
      }
    } catch (e) {
      // Stop particle animation
      if (mounted) {
        setState(() {
          _isAIProcessing = false;
        });
      }

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enhancement error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showEnhancedTextResult(String original, String enhanced, String style) {
    String styleName;
    IconData styleIcon;
    Color styleColor;

    switch (style) {
      case 'formal':
        styleName = 'Formal';
        styleIcon = Icons.business_center;
        styleColor = const Color(0xFF9C27B0);
        break;
      case 'casual':
        styleName = 'Casual';
        styleIcon = Icons.sentiment_satisfied;
        styleColor = const Color(0xFF00BCD4);
        break;
      case 'concise':
        styleName = 'Concise';
        styleIcon = Icons.compress;
        styleColor = const Color(0xFFFF5722);
        break;
      case 'fix':
        styleName = 'Fixed';
        styleIcon = Icons.check_circle_outline;
        styleColor = const Color(0xFF4CAF50);
        break;
      default:
        styleName = 'Enhanced';
        styleIcon = Icons.auto_fix_high;
        styleColor = const Color(0xFFFF6F00);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final spacing1 = (screenHeight * 0.015).clamp(12.0, 20.0);
    final padding1 = (screenWidth * 0.04).clamp(16.0, 24.0);
    final titleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final bodySize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final labelSize = (screenWidth * 0.03).clamp(12.0, 14.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: spacing1),
              // Handle bar
              Container(
                width: (screenWidth * 0.1).clamp(40.0, 50.0),
                height: (screenHeight * 0.005).clamp(4.0, 5.0),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Title with gradient background
              Container(
                margin: EdgeInsets.symmetric(horizontal: padding1),
                padding: EdgeInsets.all(padding1 * 0.8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [styleColor.withOpacity(0.1), styleColor.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: styleColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(spacing1 * 0.6),
                      decoration: BoxDecoration(
                        color: styleColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(styleIcon, color: styleColor, size: titleSize),
                    ),
                    SizedBox(width: spacing1),
                    Expanded(
                      child: Text(
                        '$styleName Version',
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing1 * 1.5),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: padding1),
                  children: [
                    // Original card
                    Container(
                      padding: EdgeInsets.all(padding1 * 0.75),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.edit_note, size: labelSize, color: Colors.grey[600]),
                              SizedBox(width: spacing1 * 0.5),
                              Text(
                                'Original',
                                style: TextStyle(
                                  fontSize: labelSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing1 * 0.75),
                          Text(
                            original,
                            style: TextStyle(fontSize: bodySize, height: 1.6, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing1 * 1.5),
                    // Enhanced card with animation
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 400),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.all(padding1 * 0.75),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [styleColor.withOpacity(0.08), styleColor.withOpacity(0.03)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: styleColor.withOpacity(0.3), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.auto_fix_high, size: labelSize + 2, color: styleColor),
                                SizedBox(width: spacing1 * 0.5),
                                Text(
                                  '$styleName Version',
                                  style: TextStyle(
                                    fontSize: labelSize,
                                    fontWeight: FontWeight.bold,
                                    color: styleColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing1 * 0.75),
                            SelectableText(
                              enhanced,
                              style: TextStyle(fontSize: bodySize, height: 1.6, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: spacing1 * 2),
                    // Action buttons with modern style
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: enhanced));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: 12),
                                      Text('Copied to clipboard'),
                                    ],
                                  ),
                                  backgroundColor: styleColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: styleColor, width: 1.5),
                              foregroundColor: styleColor,
                              padding: EdgeInsets.symmetric(vertical: padding1 * 0.7),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        SizedBox(width: spacing1),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              // Smooth text insertion with animation
                              Future.delayed(const Duration(milliseconds: 200), () {
                                _controller.text = enhanced;
                                _focusNode.requestFocus();
                                // Animate cursor to end
                                _controller.selection = TextSelection.fromPosition(
                                  TextPosition(offset: enhanced.length),
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.white),
                                      SizedBox(width: spacing1 * 0.75),
                                      const Expanded(child: Text('Text inserted smoothly')),
                                    ],
                                  ),
                                  backgroundColor: styleColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Use This'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: styleColor,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: padding1 * 0.7),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + spacing1),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}