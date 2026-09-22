import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import your services and models
import '../services/conversation_service.dart';
import '../services/websocket_service.dart';
import '../services/database_service.dart';
import '../home_screen.dart'; // For ConversationInfo model

import 'package:firebase_core/firebase_core.dart';
import '../services/app_storage.dart';

// Enum to represent the state of the home screen
enum HomeState { Idle, Loading, Error, Success }

class HomeProvider with ChangeNotifier {
  ConversationService _conversationService;
  WebSocketService _webSocketService;
  StreamSubscription? _webSocketSubscription;
  Timer? _wsRefreshDebounce;
  bool _refreshing = false;

  // Private state variables
  List<ConversationInfo> _conversations = [];
  HomeState _state = HomeState.Idle;
  String? _errorMessage;

  // Cache for conversations
  List<ConversationInfo>? _cachedConversations;
  DateTime? _lastCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  static const Set<String> _homeRefreshEventTypes = {
    'local_message_saved',
    'new_message',
    'message_edited',
    'message_deleted',
    'conversation_update',
    'group_deleted',
    'attachment_uploaded',
  };

  String get _diskCacheKey {
    final uid = (Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null)
        ?? AppStorage.cachedUid
        ?? 'anon';
    return 'opaque_cached_convos_$uid';
  }

  // Public getters for the UI to access the state
  List<ConversationInfo> get conversations => _conversations;
  HomeState get state => _state;
  String? get errorMessage => _errorMessage;

  /// Check if we have cached conversations
  bool get hasCachedConversations {
    if (_cachedConversations == null || _lastCacheTime == null) return false;
    final isExpired = DateTime.now().difference(_lastCacheTime!) > _cacheExpiry;
    return !isExpired;
  }

  HomeProvider({
    required ConversationService conversationService,
    required WebSocketService webSocketService,
  })  : _conversationService = conversationService,
        _webSocketService = webSocketService {
    _listenToWebSocket();
    // 🚀 INSTANT LOCAL-FIRST: Pre-populate conversations from disk immediately
    _loadDiskCache();
  }

  Future<void> _loadDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => ConversationInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty && _conversations.isEmpty) {
          _conversations = list;
          _cachedConversations = List.from(list);
          _state = HomeState.Success;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveDiskCache(List<ConversationInfo> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(list.map((c) => c.toJson()).toList());
      await prefs.setString(_diskCacheKey, raw);
    } catch (_) {}
  }

  // This method allows the ProxyProvider to update both services safely.
  void updateServices(ConversationService newConversationService, WebSocketService newWebSocketService) {
    _conversationService = newConversationService;
    _webSocketService = newWebSocketService;
    _webSocketSubscription?.cancel();
    _wsRefreshDebounce?.cancel();
    _listenToWebSocket();
  }

  // Fetches the initial list of conversations - LOCAL FIRST
  Future<void> fetchInitialConversations() async {
    if (_state == HomeState.Loading) return;

    // 🚀 1. INSTANT: If already populated (from disk cache or memory), show immediately
    if (_conversations.isNotEmpty) {
      _state = HomeState.Success;
      notifyListeners();
      _refreshConversationsInBackground();
      return;
    }

    // Try loading disk cache if not yet loaded
    await _loadDiskCache();
    if (_conversations.isNotEmpty) {
      _state = HomeState.Success;
      notifyListeners();
      _refreshConversationsInBackground();
      return;
    }

    // 2. No local data found (fresh account): Load from server
    _state = HomeState.Loading;
    notifyListeners();

    try {
      final convos = await _conversationService.fetchConversations();
      _conversations = convos;
      _cachedConversations = List.from(convos);
      _lastCacheTime = DateTime.now();
      _state = HomeState.Success;
      _saveDiskCache(convos);
    } catch (e) {
      _conversations = [];
      _state = HomeState.Success;
      _errorMessage = null;
    }
    notifyListeners();
  }

  /// Background refresh for conversations without blocking UI
  Future<void> _refreshConversationsInBackground() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final conversations = await _conversationService.fetchConversations();
      _conversations = _mergePreferringNewerPreviews(conversations);
      _cachedConversations = List.from(_conversations);
      _lastCacheTime = DateTime.now();
      notifyListeners();
      _saveDiskCache(_conversations);
    } catch (_) {
      // Silently fail in background - user already sees cached local data
    } finally {
      _refreshing = false;
    }
  }

  /// Keep a fresher optimistic/local preview if a network refresh is stale.
  List<ConversationInfo> _mergePreferringNewerPreviews(
    List<ConversationInfo> incoming,
  ) {
    if (_conversations.isEmpty) return incoming;
    final existingById = {
      for (final c in _conversations) c.conversationId: c,
    };

    final merged = incoming.map((incomingConvo) {
      final existing = existingById[incomingConvo.conversationId];
      if (existing == null) return incomingConvo;

      final existingTs = existing.lastMessageTimestamp;
      final incomingTs = incomingConvo.lastMessageTimestamp;
      final keepExistingPreview = existingTs != null &&
          (incomingTs == null || existingTs.isAfter(incomingTs));

      if (!keepExistingPreview) return incomingConvo;

      return ConversationInfo(
        conversationId: incomingConvo.conversationId,
        chatTitle: incomingConvo.chatTitle,
        isGroup: incomingConvo.isGroup,
        creatorUid: incomingConvo.creatorUid,
        avatarUrl: incomingConvo.avatarUrl,
        partnerUid: incomingConvo.partnerUid,
        isFriend: incomingConvo.isFriend,
        hasUnreadMessages: incomingConvo.hasUnreadMessages,
        unreadCount: incomingConvo.unreadCount,
        lastMessageTimestamp: existingTs,
        lastMessage: existing.lastMessage,
        isTyping: incomingConvo.isTyping,
        isOnline: incomingConvo.isOnline,
      );
    }).toList();

    merged.sort((a, b) {
      final aTs = a.lastMessageTimestamp;
      final bTs = b.lastMessageTimestamp;
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });
    return merged;
  }

  /// Instantly update a conversation's last-message preview (optimistic / local).
  void updateConversationPreview({
    required int conversationId,
    required String lastMessage,
    required DateTime timestamp,
  }) {
    ConversationInfo withPreview(ConversationInfo c) => ConversationInfo(
          conversationId: c.conversationId,
          chatTitle: c.chatTitle,
          isGroup: c.isGroup,
          creatorUid: c.creatorUid,
          avatarUrl: c.avatarUrl,
          partnerUid: c.partnerUid,
          isFriend: c.isFriend,
          hasUnreadMessages: c.hasUnreadMessages,
          unreadCount: c.unreadCount,
          lastMessageTimestamp: timestamp.toUtc(),
          lastMessage: lastMessage,
          isTyping: false,
          isOnline: c.isOnline,
        );

    final index =
        _conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index == -1) return;

    final existingTs = _conversations[index].lastMessageTimestamp;
    if (existingTs != null && existingTs.isAfter(timestamp.toUtc())) return;

    _conversations[index] = withPreview(_conversations[index]);
    _conversations.sort((a, b) {
      final aTs = a.lastMessageTimestamp;
      final bTs = b.lastMessageTimestamp;
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });

    final cached = _cachedConversations;
    if (cached != null) {
      final cachedIndex =
          cached.indexWhere((c) => c.conversationId == conversationId);
      if (cachedIndex != -1) {
        cached[cachedIndex] = withPreview(cached[cachedIndex]);
      }
    }

    _lastCacheTime = DateTime.now();
    notifyListeners();
    unawaited(_saveDiskCache(_conversations));
  }

  /// Refresh one conversation preview from SQLite only (no HTTP).
  Future<void> refreshConversationPreviewFromDb(int conversationId) async {
    try {
      final lastMsg =
          await DatabaseService.instance.getLastMessage(conversationId);
      if (lastMsg == null || lastMsg.content.isEmpty) return;
      updateConversationPreview(
        conversationId: conversationId,
        lastMessage: lastMsg.content,
        timestamp: lastMsg.timestamp,
      );
    } catch (_) {}
  }

  // Listens for real-time updates from the server
  void _listenToWebSocket() {
    _webSocketSubscription = _webSocketService.stream.listen((message) {
      // Stream can emit raw WebSocket strings as well as parsed maps.
      if (message is! Map) return;
      final type = message['type']?.toString();
      if (type == null || !_homeRefreshEventTypes.contains(type)) return;

      _wsRefreshDebounce?.cancel();
      _wsRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
        _refreshConversationsInBackground();
      });
    });
  }

  void markConversationAsRead(int conversationId) {
    // Reading a conversation changes only its unread state. Keep the message
    // preview and presence fields intact during the chat route transition.
    ConversationInfo asRead(ConversationInfo conversation) => ConversationInfo(
      conversationId: conversation.conversationId,
      chatTitle: conversation.chatTitle,
      isGroup: conversation.isGroup,
      creatorUid: conversation.creatorUid,
      avatarUrl: conversation.avatarUrl,
      partnerUid: conversation.partnerUid,
      isFriend: conversation.isFriend,
      hasUnreadMessages: false,
      unreadCount: 0,
      lastMessageTimestamp: conversation.lastMessageTimestamp,
      lastMessage: conversation.lastMessage,
      isTyping: conversation.isTyping,
      isOnline: conversation.isOnline,
    );

    final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index == -1) return;
    _conversations[index] = asRead(_conversations[index]);
    // A cache-backed refresh must not restore the old unread indicator.
    final cached = _cachedConversations;
    if (cached != null) {
      final cachedIndex = cached.indexWhere((c) => c.conversationId == conversationId);
      if (cachedIndex != -1) cached[cachedIndex] = asRead(cached[cachedIndex]);
    }
    notifyListeners();
  }

  void markFriendRemoved(String uid) {
    ConversationInfo update(ConversationInfo chat) {
      if (chat.partnerUid != uid || chat.isGroup) return chat;
      return ConversationInfo(
        conversationId: chat.conversationId, chatTitle: chat.chatTitle,
        isGroup: chat.isGroup, creatorUid: chat.creatorUid,
        avatarUrl: chat.avatarUrl, partnerUid: chat.partnerUid, isFriend: false,
        hasUnreadMessages: chat.hasUnreadMessages, unreadCount: chat.unreadCount,
        lastMessageTimestamp: chat.lastMessageTimestamp, lastMessage: chat.lastMessage,
        isTyping: chat.isTyping, isOnline: chat.isOnline);
    }
    _conversations = _conversations.map(update).toList();
    _cachedConversations = _cachedConversations?.map(update).toList();
    notifyListeners();
  }

  void removeConversation(int conversationId) {
    _conversations.removeWhere((c) => c.conversationId == conversationId);
    notifyListeners();
  }

  // Clean up the subscription when the provider is disposed
  @override
  void dispose() {
    _wsRefreshDebounce?.cancel();
    _webSocketSubscription?.cancel();
    super.dispose();
  }
}
