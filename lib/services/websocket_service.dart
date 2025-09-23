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

// Message queue item for reliable delivery
class QueuedMessage {
  final String id;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int attemptCount;
  final int maxAttempts;
  final Duration timeout;

  QueuedMessage({
    required this.id,
    required this.data,
    required this.timestamp,
    this.attemptCount = 0,
    this.maxAttempts = 3,
    this.timeout = const Duration(seconds: 30),
  });

  QueuedMessage copyWith({
    int? attemptCount,
    DateTime? timestamp,
  }) {
    return QueuedMessage(
      id: id,
      data: data,
      timestamp: timestamp ?? this.timestamp,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts,
      timeout: timeout,
    );
  }

  bool get isExpired => DateTime.now().difference(timestamp) > timeout;
  bool get hasRetriesLeft => attemptCount < maxAttempts;
}

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _lastToken;
  StreamSubscription? _streamSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _isReconnecting = false;

  // Heartbeat system
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _heartbeatTimeout = Duration(seconds: 10);
  DateTime? _lastPongReceived;
  bool _waitingForPong = false;

  // Message delivery queue
  final Map<String, QueuedMessage> _messageQueue = {};
  final Map<String, Completer<bool>> _messageCompleters = {};
  Timer? _queueProcessTimer;
  static const Duration _queueProcessInterval = Duration(seconds: 5);

  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();
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

    if (_isConnected && _channel != null && token == _lastToken) {
      print("[WebSocketService] Already connected. No action needed.");
      return;
    }

    if (_isReconnecting) {
      print("[WebSocketService] Reconnection already in progress, skipping");
      return;
    }

    if (_channel != null) {
      print("[WebSocketService] A new connection was requested. Disconnecting the old one first...");
      await disconnect();
    }

    _lastToken = token;
    _isReconnecting = true;
    print("[WebSocketService] Attempting to connect... (Attempt: ${_reconnectAttempts + 1})");

    _initializeSentMessageListener();

    final completer = Completer<void>();

    try {
      final String host = kIsWeb ? 'ws://192.168.29.81:8080/ws' : 'ws://192.168.29.81:8080/ws';
      final uri = Uri.parse('$host?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      notifyListeners();
      print("[WebSocketService] Connection established successfully (channel opened).");

      // Start heartbeat and queue processing
      _startHeartbeat();
      _startQueueProcessor();

      if (!completer.isCompleted) completer.complete();

      final subscription = _channel!.stream.listen(
            (message) {
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

  // HEARTBEAT SYSTEM
  void _startHeartbeat() {
    _stopHeartbeat();
    print("[WebSocketService] Starting heartbeat system");

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _sendPing();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
    _waitingForPong = false;
  }

  void _sendPing() {
    if (!_isConnected || _channel == null) {
      print("[WebSocketService] Cannot send ping - not connected");
      return;
    }

    if (_waitingForPong) {
      print("[WebSocketService] Previous ping still waiting for pong - connection may be dead");
      _handleSilentDisconnection();
      return;
    }

    try {
      final pingMessage = {
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _channel!.sink.add(jsonEncode(pingMessage));
      _waitingForPong = true;

      print("[WebSocketService] Ping sent, waiting for pong...");

      // Set timeout for pong response
      _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
        if (_waitingForPong) {
          print("[WebSocketService] Pong timeout - connection appears dead");
          _handleSilentDisconnection();
        }
      });
    } catch (e) {
      print("[WebSocketService] Error sending ping: $e");
      _handleSilentDisconnection();
    }
  }

  void _handlePong() {
    print("[WebSocketService] Pong received - connection alive");
    _waitingForPong = false;
    _lastPongReceived = DateTime.now();
    _heartbeatTimeoutTimer?.cancel();
  }

  void _handleSilentDisconnection() {
    print("[WebSocketService] Silent disconnection detected via heartbeat");
    _waitingForPong = false;
    _heartbeatTimeoutTimer?.cancel();

    // Force reconnection
    _handleDisconnection();
  }

  // MESSAGE QUEUE SYSTEM
  void _startQueueProcessor() {
    _stopQueueProcessor();
    print("[WebSocketService] Starting message queue processor");

    _queueProcessTimer = Timer.periodic(_queueProcessInterval, (timer) {
      _processMessageQueue();
    });
  }

  void _stopQueueProcessor() {
    _queueProcessTimer?.cancel();
    _queueProcessTimer = null;
  }

  Future<void> _processMessageQueue() async {
    if (_messageQueue.isEmpty || !_isConnected) return;

    print("[WebSocketService] Processing message queue (${_messageQueue.length} items)");

    final expiredMessages = <String>[];
    final retryMessages = <String>[];

    for (final entry in _messageQueue.entries) {
      final messageId = entry.key;
      final queuedMsg = entry.value;

      if (queuedMsg.isExpired) {
        print("[WebSocketService] Message $messageId expired after ${queuedMsg.attemptCount} attempts");
        expiredMessages.add(messageId);

        // Complete with failure
        final completer = _messageCompleters.remove(messageId);
        completer?.complete(false);

        // Update message status to failed
        await _updateMessageStatusToFailed(queuedMsg);

      } else if (queuedMsg.hasRetriesLeft) {
        retryMessages.add(messageId);
      }
    }

    // Remove expired messages
    for (final id in expiredMessages) {
      _messageQueue.remove(id);
    }

    // Retry pending messages
    for (final id in retryMessages) {
      await _retryQueuedMessage(id);
    }
  }

  Future<void> _retryQueuedMessage(String messageId) async {
    final queuedMsg = _messageQueue[messageId];
    if (queuedMsg == null || !_isConnected || _channel == null) return;

    try {
      print("[WebSocketService] Retrying message $messageId (attempt ${queuedMsg.attemptCount + 1})");

      _channel!.sink.add(jsonEncode(queuedMsg.data));

      // Update attempt count
      _messageQueue[messageId] = queuedMsg.copyWith(
        attemptCount: queuedMsg.attemptCount + 1,
        timestamp: DateTime.now(),
      );

    } catch (e) {
      print("[WebSocketService] Error retrying message $messageId: $e");
    }
  }

  Future<void> _updateMessageStatusToFailed(QueuedMessage queuedMsg) async {
    try {
      // Extract message info from queued data
      final messageData = queuedMsg.data;
      if (messageData['type'] == 'new_message') {
        final messageId = messageData['message_id'] as int?;
        if (messageId != null) {
          final dbService = DatabaseService.instance;
          await dbService.updateMessageStatus(messageId, MessageStatus.failed);

          // Notify UI
          _streamController.add({
            'type': 'message_status_update',
            'message_id': messageId,
            'status': 'failed',
            'conversation_id': messageData['conversation_id'],
          });

          print("[WebSocketService] Message $messageId marked as failed");
        }
      }
    } catch (e) {
      print("[WebSocketService] Error updating failed message status: $e");
    }
  }

  // RELIABLE MESSAGE SENDING
  Future<bool> sendMessageReliably(Map<String, dynamic> messageData) async {
    if (!_isConnected || _channel == null) {
      print("[WebSocketService] Cannot send message reliably - not connected");
      return false;
    }

    final messageId = messageData['message_id']?.toString() ??
        'msg_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    print("[WebSocketService] Sending message reliably: $messageId");

    // Add to queue immediately
    final queuedMessage = QueuedMessage(
      id: messageId,
      data: messageData,
      timestamp: DateTime.now(),
    );

    _messageQueue[messageId] = queuedMessage;

    // Create completer for delivery confirmation
    final completer = Completer<bool>();
    _messageCompleters[messageId] = completer;

    try {
      // Send immediately
      _channel!.sink.add(jsonEncode(messageData));
      print("[WebSocketService] Message sent to WebSocket: $messageId");

      // Wait for confirmation or timeout
      final delivered = await completer.future.timeout(
        queuedMessage.timeout,
        onTimeout: () {
          print("[WebSocketService] Message delivery timeout: $messageId");
          return false;
        },
      );

      return delivered;

    } catch (e) {
      print("[WebSocketService] Error sending message reliably: $e");
      _messageCompleters.remove(messageId);
      return false;
    } finally {
      // Clean up queue and completer
      _messageQueue.remove(messageId);
      _messageCompleters.remove(messageId);
    }
  }

  void _confirmMessageDelivery(String messageId) {
    print("[WebSocketService] Confirming delivery for message: $messageId");

    // Remove from queue
    _messageQueue.remove(messageId);

    // Complete the delivery promise
    final completer = _messageCompleters.remove(messageId);
    completer?.complete(true);
  }

  // UPDATE EXISTING METHODS
  Future<List<Message>> getLocalSentMessages(int conversationId) async {
    try {
      return [];
    } catch (e) {
      print("[WebSocketService] Error loading sent messages: $e");
      return [];
    }
  }

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

      final dbService = DatabaseService.instance;
      final messages = await dbService.getMessages(conversationId);

      final myMessages = messages.where((msg) => msg.senderUid == currentUser.uid).toList();
      print("[WebSocketService] 🔍 Found ${myMessages.length} messages from current user:");
      for (final msg in myMessages) {
        print("[WebSocketService]   Message ID: ${msg.id}, Status: ${msg.status}, Content: '${msg.content}'");
      }

      final sentMessages = messages.where((msg) =>
      msg.senderUid == currentUser.uid &&
          msg.status == MessageStatus.sent
      ).toList();

      print("[WebSocketService] 🔍 Messages needing status sync: ${sentMessages.length}");

      if (sentMessages.isEmpty) {
        print("[WebSocketService] No sent messages needing status sync");
        return;
      }

      // Use reliable sending for status requests
      for (final message in sentMessages) {
        final statusMessage = {
          'type': 'status_request',
          'message_id': message.id,
          'conversation_id': conversationId,
        };

        await sendMessageReliably(statusMessage);
        print("[WebSocketService] Requested status for message ${message.id}");
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
      _localSentMessageIds.add(sentMessage.id);

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
          _handlePong();
          break;
        case 'new_message':
          print("[WebSocketService] *** PROCESSING NEW MESSAGE ***");
          _handleNewMessage(messageData);
          break;
        case 'message_status':
          print("[WebSocketService] Message status update: $messageData");
          _handleMessageStatus(messageData);
          break;
        case 'message_deleted':  // ADD THIS CASE
          print("[WebSocketService] Message deletion: $messageData");
          _handleMessageDeletion(messageData);
          break;    
        case 'message_ack':
        // Server acknowledges message receipt
          final ackMessageId = messageData['message_id']?.toString();
          if (ackMessageId != null) {
            _confirmMessageDelivery(ackMessageId);
          }
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

  void _handleMessageDeletion(Map<String, dynamic> deletionData) {
  _streamController.add({
    'type': 'message_deleted',
    'message_id': deletionData['message_id'],
    'deletion_type': deletionData['deletion_type'],
    'conversation_id': deletionData['conversation_id'],
  });
}

  Future<void> _handleNewMessage(Map<String, dynamic> messageData) async {
    try {
      print("[WebSocketService] Processing new message...");

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("[WebSocketService] No authenticated user, ignoring message");
        return;
      }

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

      if (senderUid == currentUser.uid) {
        print("[WebSocketService] Ignoring own message");
        return;
      }

      print("[WebSocketService] Decrypting message from $senderUid...");

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

        try {
          final base64Decoded = utf8.decode(base64Decode(contentB64));
          print("[WebSocketService] Base64 decode result: '$base64Decoded'");
          decryptedContent = base64Decoded;
          print("[WebSocketService] ✅ Using base64 decoded content");
        } catch (e2) {
          print("[WebSocketService] ❌ Base64 decode also failed: $e2");
          print("[WebSocketService] Saving encrypted content as-is for debugging");
          decryptedContent = "ENCRYPTED: $contentB64";
        }
      }

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

      // Check if current user has deleted this message
      final isDeleted = await dbService.isMessageDeletedForMe(messageId);
      if (isDeleted) {
        print("[WebSocketService] Skipping save - message $messageId was deleted by current user");
        return;
      }

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

  void _handleMessageStatus(Map<String, dynamic> statusData) {
    print("[WebSocketService] Message status update: $statusData");

    try {
      final messageId = statusData['message_id'] as int?;
      final newStatus = statusData['status'] as String?;
      final conversationId = statusData['conversation_id'] as int?;

      if (messageId != null && newStatus != null) {
        MessageStatus? status;
        try {
          status = MessageStatus.values.firstWhere(
                (s) => s.toString().split('.').last == newStatus,
          );
        } catch (e) {
          print("[WebSocketService] Unknown status: $newStatus");
          return;
        }

        _updateMessageStatusInDatabase(messageId, status);

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

  Future<void> _updateMessageStatusInDatabase(int messageId, MessageStatus status) async {
    try {
      final dbService = DatabaseService.instance;
      await dbService.updateMessageStatus(messageId, status);
      print("[WebSocketService] Updated message $messageId status to $status");
    } catch (e) {
      print("[WebSocketService] Error updating message status: $e");
    }
  }

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

      await sendMessageReliably(statusMessage);
      print("[WebSocketService] Sent status update: $statusMessage");
    } catch (e) {
      print("[WebSocketService] Error sending status update: $e");
    }
  }

  Future<void> _markMessageAsDelivered(int messageId, int conversationId) async {
    await sendStatusUpdate(
      messageId: messageId,
      status: 'delivered',
      conversationId: conversationId,
    );
  }

  Future<void> markMessagesAsRead(int conversationId) async {
    try {
      final dbService = DatabaseService.instance;

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final messages = await dbService.getMessages(conversationId);
      final unreadMessages = messages.where((msg) =>
      msg.senderUid != currentUser.uid &&
          (msg.status == MessageStatus.sent || msg.status == MessageStatus.delivered)
      ).toList();

      for (final message in unreadMessages) {
        await dbService.updateMessageStatus(message.id, MessageStatus.read);

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

  void _handleTypingIndicator(Map<String, dynamic> typingData) {
    print("[WebSocketService] Typing indicator: $typingData");
  }

  void _handleDisconnection() {
    if (!_isConnected && !_isReconnecting) return;

    print("[WebSocketService] ⚠️ DISCONNECTION DETECTED ⚠️ at ${DateTime.now()}");
    _isConnected = false;
    _isReconnecting = false;

    // Stop heartbeat and queue processing
    _stopHeartbeat();
    _stopQueueProcessor();

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    notifyListeners();

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

  Future<void> reconnect() async {
    _reconnectAttempts = 0;
    if (_lastToken != null) {
      await connect(_lastToken);
    }
  }

  Future<void> disconnect() async {
    print("[WebSocketService] Disconnect() called at ${DateTime.now()} — stacktrace:\n${StackTrace.current}");

    _lastToken = null;
    _isReconnecting = false;

    // Stop all timers
    _stopHeartbeat();
    _stopQueueProcessor();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

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
    _stopHeartbeat();
    _stopQueueProcessor();
    _reconnectTimer?.cancel();
    _sentMessageSubscription?.cancel();
    disconnect();
    _streamController.close();
    super.dispose();
  }
}