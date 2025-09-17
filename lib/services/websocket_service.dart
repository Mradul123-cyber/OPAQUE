// lib/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'database_service.dart';
import 'package:zarq_messenger/message_model.dart';
import 'sent_message_service.dart';

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _lastToken;
  StreamSubscription? _streamSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _isReconnecting = false;

  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();
  // MethodChannel to call native Signal methods
  static const MethodChannel _signalChannel = MethodChannel('com.zarq/signal');

  StreamSubscription? _sentMessageSubscription;
  final Set<int> _localSentMessageIds = {};


  Stream<dynamic> get stream => _streamController.stream;
  WebSocketChannel? get channel => _channel;
  bool get isConnected => _isConnected;

  Future<void> connect(String? token) async {
    if (token == null) {
      print("[WebSocketService] Connection attempted with no token.");
      return;
    }

    // If already connected with same token, nothing to do
    if (_isConnected && _channel != null && token == _lastToken) {
      print("[WebSocketService] Already connected. No action needed.");
      return;
    }

    // Avoid overlapping reconnection attempts
    if (_isReconnecting) {
      print("[WebSocketService] Reconnection already in progress, skipping");
      return;
    }

    // Close any existing connection first
    if (_channel != null) {
      print("[WebSocketService] A new connection was requested. Disconnecting the old one first...");
      await disconnect();
    }

    _lastToken = token;
    _isReconnecting = true;
    print("[WebSocketService] Attempting to connect... (Attempt: ${_reconnectAttempts + 1})");

    // Initialize sent message listener when connecting
    _initializeSentMessageListener();

    final completer = Completer<void>();

    try {
      final String host = kIsWeb ? 'ws://192.168.29.81:8080/ws' : 'ws://192.168.29.81:8080/ws';
      final uri = Uri.parse('$host?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // Mark connected immediately once the channel is created
      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      notifyListeners();
      print("[WebSocketService] Connection established successfully (channel opened).");
      if (!completer.isCompleted) completer.complete();

      // Set up listener
      final subscription = _channel!.stream.listen(
            (message) {
          // Handle incoming message (ignoring own messages as before)
          _handleIncomingMessage(message);
          _streamController.add(message);
        },
        onDone: () {
          print("[WebSocketService] onDone called at ${DateTime.now()} — channel closed.");
          if (!completer.isCompleted) {
            completer.completeError(Exception("Connection closed before it could be established."));
          }
          _handleDisconnection();
        },
        onError: (error, stack) {
          print("[WebSocketService] onError called at ${DateTime.now()}: $error");
          print("[WebSocketService] onError stack: $stack");
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          _handleDisconnection();
        },
        cancelOnError: true,
      );

      _streamSubscription = subscription;
    } catch (e, st) {
      print("[WebSocketService] Failed to connect: $e\n$st");
      _isReconnecting = false;
      if (!completer.isCompleted) completer.completeError(e);
      _handleDisconnection();
    }

    return completer.future;
  }

  // ADD: Method to get sent messages for a conversation
  Future<List<Message>> getLocalSentMessages(int conversationId) async {
    try {
      // This would typically load from SharedPreferences or local storage
      // For now, return empty list - the real implementation would load from Android SharedPreferences
      return [];
    } catch (e) {
      print("[WebSocketService] Error loading sent messages: $e");
      return [];
    }
  }

  /// Sync message statuses for recent sent messages
  Future<void> syncMessageStatuses(int conversationId) async {
    print("[WebSocketService] 🔍 syncMessageStatuses CALLED for conversation $conversationId");
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("[WebSocketService] ❌ No current user for status sync");
        return;
      }

      print("[WebSocketService] ✅ User authenticated: ${currentUser.uid}");
      print("[WebSocketService] Syncing message statuses for conversation $conversationId");

      // Get recent sent messages that might need status updates
      final dbService = DatabaseService.instance;
      final messages = await dbService.getMessages(conversationId);

      final myMessages = messages.where((msg) => msg.senderUid == currentUser.uid).toList();
      print("[WebSocketService] 🔍 Found ${myMessages.length} messages from current user:");
      for (final msg in myMessages) {
        print("[WebSocketService]   Message ID: ${msg.id}, Status: ${msg.status}, Content: '${msg.content}'");
      }

      // Find messages sent by current user with 'sent' status
      final sentMessages = messages.where((msg) =>
      msg.senderUid == currentUser.uid &&
          msg.status == MessageStatus.sent
      ).toList();

      print("[WebSocketService] 🔍 Messages needing status sync: ${sentMessages.length}");

      if (sentMessages.isEmpty) {
        print("[WebSocketService] No sent messages needing status sync");
        return;
      }

      // Request status updates from server
      for (final message in sentMessages) {
        final statusMessage = {
          'type': 'status_request',
          'message_id': message.id,
          'conversation_id': conversationId,
        };

        if (_isConnected && _channel != null) {
          _channel!.sink.add(jsonEncode(statusMessage));
          print("[WebSocketService] Requested status for message ${message.id}");
        }
      }

      print("[WebSocketService] Requested status updates for ${sentMessages.length} messages");

    } catch (e) {
      print("[WebSocketService] Error syncing message statuses: $e");
    }
  }


  void _initializeSentMessageListener() {
    _sentMessageSubscription?.cancel();
    _sentMessageSubscription = SentMessageService.sentMessageStream.listen((message) {
      print("[WebSocketService] Received local sent message: ${message.content}");
      _handleLocalSentMessage(message);
    });
  }


  void _handleLocalSentMessage(Message sentMessage) {
    try {
      // Add to cache to avoid duplicates
      _localSentMessageIds.add(sentMessage.id);

      // Notify UI about the sent message
      _streamController.add({
        'type': 'local_sent_message',
        'message': sentMessage.toJson(),
        'conversation_id': sentMessage.conversationId,
      });

      print("[WebSocketService] Broadcasted local sent message to UI");

    } catch (e) {
      print("[WebSocketService] Error handling local sent message: $e");
    }
  }

  /// Handle incoming WebSocket messages
  void _handleIncomingMessage(dynamic rawMessage) {
    try {
      print("[WebSocketService] === RAW INCOMING MESSAGE ===");
      print("[WebSocketService] Raw: $rawMessage");

      final messageData = jsonDecode(rawMessage.toString());
      final messageType = messageData['type'] ?? '';

      print("[WebSocketService] PARSED MESSAGE TYPE: $messageType");
      print("[WebSocketService] Full parsed data: $messageData");

      switch (messageType) {
        case 'pong':
          break;
        case 'new_message':
          print("[WebSocketService] *** PROCESSING NEW MESSAGE ***");
          _handleNewMessage(messageData);
          break;
        case 'message_status':
          print("[WebSocketService] Message status update: $messageData");
          _handleMessageStatus(messageData);
          break;
        case 'typing':
          _handleTypingIndicator(messageData);
          break;
        default:
          print("[WebSocketService] Unknown message type: $messageType");
          print("[WebSocketService] Unknown message data: $messageData");
      }
    } catch (e, st) {
      print("[WebSocketService] Error handling message: $e\n$st");
    }
  }

  /// Handle new message from WebSocket (process own messages too)
  Future<void> _handleNewMessage(Map<String, dynamic> messageData) async {
    try {
      print("[WebSocketService] Processing new message...");

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("[WebSocketService] No authenticated user, ignoring message");
        return;
      }

      // Extract message details
      final messageId = messageData['message_id'] is int
          ? messageData['message_id'] as int
          : int.tryParse(messageData['message_id']?.toString() ?? '') ?? -1;
      final conversationId = messageData['conversation_id'] is int
          ? messageData['conversation_id'] as int
          : int.tryParse(messageData['conversation_id']?.toString() ?? '') ?? -1;
      final senderUid = messageData['sender_uid'] as String?;
      final senderDeviceId = messageData['sender_device_id'] as int? ?? 1;
      final contentB64 = messageData['content_b64'] as String?;
      final createdAt = messageData['created_at'] as String?;
      final senderUsername = messageData['sender_username'] as String? ?? 'Unknown';

      if (messageId <= 0 || conversationId <= 0 || senderUid == null || contentB64 == null) {
        print("[WebSocketService] Missing required message fields");
        return;
      }

      // ORIGINAL BEHAVIOR: Ignore own messages
      if (senderUid == currentUser.uid) {
        print("[WebSocketService] Ignoring own message");
        return;
      }

      print("[WebSocketService] Decrypting message from $senderUid...");

      // Decrypt if possible, else fallback to base64 decode
      String decryptedContent;
      try {
        print("[WebSocketService] Attempting Signal Protocol decryption...");
        final result = await _signalChannel.invokeMethod('decryptMessage', {
          'myUid': currentUser.uid,
          'senderUid': senderUid,
          'ciphertextB64': contentB64,
          'senderDeviceId': senderDeviceId,
        });

        if (result == null) {
          print("[WebSocketService] Decryption returned null");
          throw Exception('Decryption returned null');
        }

        decryptedContent = result as String;
        print("[WebSocketService] ✅ Signal decryption successful: '$decryptedContent'");
      } catch (e) {
        print("[WebSocketService] ❌ Signal decryption failed: $e");

        // Check if it's already plain text (for debugging)
        try {
          final base64Decoded = utf8.decode(base64Decode(contentB64));
          print("[WebSocketService] Base64 decode result: '$base64Decoded'");

          // If base64 decode gives readable text, use it
          decryptedContent = base64Decoded;
          print("[WebSocketService] ✅ Using base64 decoded content");
        } catch (e2) {
          print("[WebSocketService] ❌ Base64 decode also failed: $e2");
          print("[WebSocketService] Saving encrypted content as-is for debugging");
          decryptedContent = "ENCRYPTED: $contentB64";
        }
      }

      // Save message to database
      await _saveMessageToDatabase(
        messageId: messageId,
        conversationId: conversationId,
        senderUid: senderUid,
        username: senderUsername,
        content: decryptedContent,
        createdAt: createdAt ?? DateTime.now().toIso8601String(),
      );

      _streamController.add({
        'type': 'local_message_saved',
        'message_id': messageId,
        'conversation_id': conversationId,
      });

      print("[WebSocketService] Notified UI about new message: $messageId");

      await _markMessageAsDelivered(messageId, conversationId);
      print("[WebSocketService] Message saved to database and marked as delivered");

    } catch (e, st) {
      print("[WebSocketService] Error processing new message: $e\n$st");
    }
  }

  /// Save message to local database
  Future<void> _saveMessageToDatabase({
    required int messageId,
    required int conversationId,
    required String senderUid,
    required String username,
    required String content,
    required String createdAt,
  }) async {
    try {
      final dbService = DatabaseService.instance;
      final message = Message(
        id: messageId,
        conversationId: conversationId,
        username: username,
        content: content,
        timestamp: DateTime.parse(createdAt),
        senderUid: senderUid,
        status: MessageStatus.sent,
      );
      await dbService.insertMessage(message);
      print("[WebSocketService] Message saved to database: ${message.content}");

      // Notify UI about new message
      _notifyUIAboutNewMessage(message, conversationId);
    } catch (e, st) {
      print("[WebSocketService] Error saving message to database: $e\n$st");
    }
  }

  void _notifyUIAboutNewMessage(Message message, int conversationId) {
    _streamController.add({
      'type': 'local_message_saved',
      'message': message.toJson(),
      'conversation_id': conversationId,
    });
  }

  /// Handle message status updates (delivered, read, etc.)
  // Replace your existing _handleMessageStatus method and add these new methods to websocket_service.dart

  /// Handle message status updates (delivered, read, etc.)
  void _handleMessageStatus(Map<String, dynamic> statusData) {
    print("[WebSocketService] Message status update: $statusData");

    try {
      final messageId = statusData['message_id'] as int?;
      final newStatus = statusData['status'] as String?;
      final conversationId = statusData['conversation_id'] as int?;

      if (messageId != null && newStatus != null) {
        // Parse status string to enum
        MessageStatus? status;
        try {
          status = MessageStatus.values.firstWhere(
                (s) => s.toString().split('.').last == newStatus,
          );
        } catch (e) {
          print("[WebSocketService] Unknown status: $newStatus");
          return;
        }

        // Update database
        _updateMessageStatusInDatabase(messageId, status);

        // Notify UI about status change
        _streamController.add({
          'type': 'message_status_update',
          'message_id': messageId,
          'status': newStatus,
          'conversation_id': conversationId,
        });
        print("[WebSocketService] Sent message_status_update event to UI for message $messageId");
      }
    } catch (e) {
      print("[WebSocketService] Error handling status update: $e");
    }
  }

  /// Update message status in database
  Future<void> _updateMessageStatusInDatabase(int messageId, MessageStatus status) async {
    try {
      final dbService = DatabaseService.instance;
      await dbService.updateMessageStatus(messageId, status);
      print("[WebSocketService] Updated message $messageId status to $status");
    } catch (e) {
      print("[WebSocketService] Error updating message status: $e");
    }
  }

  /// Send status update to server via WebSocket
  Future<void> sendStatusUpdate({
    required int messageId,
    required String status,
    required int conversationId,
  }) async {
    if (!_isConnected || _channel == null) {
      print("[WebSocketService] Cannot send status update - not connected");
      return;
    }

    try {
      final statusMessage = {
        'type': 'message_status',
        'message_id': messageId,
        'status': status,
        'conversation_id': conversationId,
      };

      _channel!.sink.add(jsonEncode(statusMessage));
      print("[WebSocketService] Sent status update: $statusMessage");
    } catch (e) {
      print("[WebSocketService] Error sending status update: $e");
    }
  }

  /// Mark messages as delivered when received
  Future<void> _markMessageAsDelivered(int messageId, int conversationId) async {
    await sendStatusUpdate(
      messageId: messageId,
      status: 'delivered',
      conversationId: conversationId,
    );
  }

  /// Mark messages as read when chat is opened
  Future<void> markMessagesAsRead(int conversationId) async {
    try {
      final dbService = DatabaseService.instance;

      // Get all unread messages in this conversation from other users
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final messages = await dbService.getMessages(conversationId);
      final unreadMessages = messages.where((msg) =>
      msg.senderUid != currentUser.uid &&
          (msg.status == MessageStatus.sent || msg.status == MessageStatus.delivered)
      ).toList();

      // Mark as read in database and send to server
      for (final message in unreadMessages) {
        await dbService.updateMessageStatus(message.id, MessageStatus.read);

        // Send read status to server
        await sendStatusUpdate(
          messageId: message.id,
          status: 'read',
          conversationId: conversationId,
        );
      }

      if (unreadMessages.isNotEmpty) {
        print("[WebSocketService] Marked ${unreadMessages.length} messages as read");
      }
    } catch (e) {
      print("[WebSocketService] Error marking messages as read: $e");
    }
  }

  /// Handle typing indicators
  void _handleTypingIndicator(Map<String, dynamic> typingData) {
    print("[WebSocketService] Typing indicator: $typingData");
    // TODO: Update UI to show typing indicator
  }

  void _handleDisconnection() {
    if (!_isConnected && !_isReconnecting) return;

    print("[WebSocketService] ⚠️ DISCONNECTION DETECTED ⚠️ at ${DateTime.now()}");
    _isConnected = false;
    _isReconnecting = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    notifyListeners();

    // Attempt automatic reconnection with exponential backoff
    if (_lastToken != null && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delays = [1, 2, 5, 10, 30];
      final delaySec = delays.length >= _reconnectAttempts ? delays[_reconnectAttempts - 1] : 30;

      print("[WebSocketService] Attempting reconnect in ${delaySec}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)");

      _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
        try {
          await connect(_lastToken);
        } catch (e) {
          print("[WebSocketService] Reconnection attempt failed: $e");
        }
      });
    } else if (_reconnectAttempts >= _maxReconnectAttempts) {
      print("[WebSocketService] Max reconnection attempts reached. Manual intervention required.");
    }
  }

  /// Manually trigger reconnection
  Future<void> reconnect() async {
    _reconnectAttempts = 0;
    if (_lastToken != null) {
      await connect(_lastToken);
    }
  }

  Future<void> disconnect() async {
    print("[WebSocketService] Disconnect() called at ${DateTime.now()} — stacktrace:\n${StackTrace.current}");

    _lastToken = null;
    _reconnectAttempts = 0;
    _isReconnecting = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    // Close WebSocket connection
    try {
      await _channel?.sink.close(1000, 'Normal closure');
    } catch (e) {
      print("[WebSocketService] Error closing WebSocket: $e");
    }
    _channel = null;

    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sentMessageSubscription?.cancel(); // ADD: Cancel sent message subscription
    disconnect();
    _streamController.close();
    super.dispose();
  }
}
