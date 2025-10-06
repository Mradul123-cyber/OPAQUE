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

  // Public getters for the UI to access the state
  List<ConversationInfo> get conversations => _conversations;
  HomeState get state => _state;
  String? get errorMessage => _errorMessage;

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

    // Safe way to update during potential build phase
    Future.microtask(() {
      _state = HomeState.Loading;
      notifyListeners();
    });

    try {
      _conversations = await _conversationService.fetchConversations();
      _state = HomeState.Success;
    } catch (e) {
      _state = HomeState.Error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  // Listens for real-time updates from the server
  void _listenToWebSocket() {
    _webSocketSubscription = _webSocketService.stream.listen((message) {
      // print("HomeProvider received a WebSocket signal. Refreshing data.");
      fetchInitialConversations();
    });
  }

  void markConversationAsRead(int conversationId) {
    final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index != -1) {
      _conversations[index] = ConversationInfo(
        conversationId: _conversations[index].conversationId,
        chatTitle: _conversations[index].chatTitle,
        isGroup: _conversations[index].isGroup,
        creatorUid: _conversations[index].creatorUid,
        avatarUrl: _conversations[index].avatarUrl,
        partnerUid: _conversations[index].partnerUid,
        hasUnreadMessages: false, // Clear the green dot
      );
      notifyListeners();
      // print('[HomeProvider] Cleared unread indicator for conversation $conversationId');
    }
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
