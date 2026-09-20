import 'dart:async';
import 'package:flutter/material.dart';

// Import your services and models
import '../services/conversation_service.dart';
import '../services/websocket_service.dart';
import '../home_screen.dart'; // For ConversationInfo model

// Enum to represent the state of the home screen
enum HomeState { Idle, Loading, Error, Success }

class HomeProvider with ChangeNotifier {
  ConversationService _conversationService;
  WebSocketService _webSocketService;
  StreamSubscription? _webSocketSubscription;

  // Private state variables
  List<ConversationInfo> _conversations = [];
  HomeState _state = HomeState.Idle;
  String? _errorMessage;

  // Cache for conversations
  List<ConversationInfo>? _cachedConversations;
  DateTime? _lastCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 5);

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
  }

  // ### START OF FIX ###
  // This new method allows the ProxyProvider to update both services safely.
  void updateServices(ConversationService newConversationService, WebSocketService newWebSocketService) {
    _conversationService = newConversationService;
    _webSocketService = newWebSocketService;
    _webSocketSubscription?.cancel(); // Cancel the old subscription
    _listenToWebSocket(); // Start listening to the new service
  }
  // ### END OF FIX ###

  // Fetches the initial list of conversations
  Future<void> fetchInitialConversations() async {
    if (_state == HomeState.Loading) return;

    // 🚀 INSTANT LOADING: Show cached conversations immediately
    if (hasCachedConversations) {
      _conversations = List.from(_cachedConversations!);
      _state = HomeState.Success;
      notifyListeners();

      // Background refresh
      _refreshConversationsInBackground();
      return;
    }

    // No cache: Load from server
    Future.microtask(() {
      _state = HomeState.Loading;
      notifyListeners();
    });

    try {
      _conversations = await _conversationService.fetchConversations();
      _cachedConversations = List.from(_conversations);
      _lastCacheTime = DateTime.now();
      _state = HomeState.Success;
    } catch (e) {
      // 🚀 OFFLINE MODE: fetchConversations() now has offline fallback
      // So this will return offline data instead of throwing error
      // If we still get error, it means truly no data available
      _conversations = []; // Empty list instead of error state
      _state = HomeState.Success; // Show empty state, not error
      _errorMessage = null;
      // print('[HomeProvider] ⚠️ Using offline mode or no conversations: $e');
    }
    notifyListeners();
  }

  /// Background refresh for conversations
  Future<void> _refreshConversationsInBackground() async {
    try {
      final conversations = await _conversationService.fetchConversations();
      _conversations = conversations;
      _cachedConversations = List.from(conversations);
      _lastCacheTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      // Silently fail - user already sees cached data
      // print('[HomeProvider] Background refresh failed: $e');
    }
  }

  // Listens for real-time updates from the server
  void _listenToWebSocket() {
    _webSocketSubscription = _webSocketService.stream.listen((message) {
      // print("HomeProvider received a WebSocket signal. Refreshing data.");
      fetchInitialConversations();
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
    // print('[HomeProvider] Removed conversation $conversationId from list');
  }

  // Clean up the subscription when the provider is disposed
  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    super.dispose();
  }
}
