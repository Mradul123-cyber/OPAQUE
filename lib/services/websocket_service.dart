import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'SignalService.dart';
import 'database_service.dart';
import 'global_call_manager.dart';
import 'webrtc_service.dart';
import 'package:zarq_messenger/message_model.dart';
import 'key_rotation_service.dart';
import 'sent_message_service.dart';
import 'navigation_handler.dart';
import 'group_encryption_service.dart';
import 'device_service.dart';
import 'package:zarq_messenger/app_config.dart';

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

  QueuedMessage copyWith({int? attemptCount, DateTime? timestamp}) {
    return QueuedMessage(
      id: id,
      data: data,
      timestamp: timestamp ?? this.timestamp,
      attemptCount: attemptCount ?? this.attemptCount,
      maxAttempts: maxAttempts,
      timeout: timeout,
    );
  }

  bool get isExpired => DateTime.now().toUtc().difference(timestamp) > timeout;
  bool get hasRetriesLeft => attemptCount < maxAttempts;
}

class WebSocketService with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _lastToken;
  StreamSubscription? _streamSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10; // ✅ Increased from 5 to 10
  bool _isReconnecting = false;

  // ✅ Network connectivity monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasDisconnectedDueToNetwork = false;

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

  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  static const MethodChannel _signalChannel = MethodChannel('com.zarq/signal');

  StreamSubscription? _sentMessageSubscription;
  final Set<int> _localSentMessageIds = {};

  // Global call manager for routing call signals
  GlobalCallManager? _globalCallManager;

  Stream<dynamic> get stream => _streamController.stream;
  WebSocketChannel? get channel => _channel;
  bool get isConnected => _isConnected;

  DateTime? _lastStatusSyncTime;
  final _statusSyncDebounce = Duration(seconds: 5);

  final Map<int, DateTime> _lastMarkReadTimePerMessage = {};
  final _markReadDebounce = Duration(seconds: 10);

  // Set global call manager
  void setGlobalCallManager(GlobalCallManager callManager) {
    _globalCallManager = callManager;
    // Setup callback for sending call signals
    _globalCallManager?.onSendSignal = (signalData) {
      final message = jsonEncode(signalData);
      _channel?.sink.add(message);
      // print('[WebSocketService] Sent call signal: ${signalData['type']}');
    };
  }

  Future<void> connect(String? token) async {
    if (token == null) {
      // print("[WebSocketService] Connection attempted with no token.");
      return;
    }

    if (_isConnected && _channel != null) {
      return;
    }

    if (_isReconnecting) {
      return;
    }

    if (_channel != null) {
      await disconnect(stopMonitoring: false);
    }

    _lastToken = token;
    _isReconnecting = true;
    // print("[WebSocketService] Connecting... (Attempt: ${_reconnectAttempts + 1})");

    _initializeSentMessageListener();

    final completer = Completer<void>();

    try {
      final baseUri = Uri.parse(AppConfig.baseUrl);
      final isSecure = baseUri.scheme == 'https';
      final uri = Uri(
        scheme: isSecure ? 'wss' : 'ws',
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        path: '/ws',
        queryParameters: {'token': token},
      );
      print("===== BIG DEBUG =====");
      print("Attempting to connect to WebSocket at: $uri");
      print("=======================");
      _channel = WebSocketChannel.connect(uri);

      // Wait for socket handshake to complete before declaring success
      await _channel!.ready;

      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _wasDisconnectedDueToNetwork = false;
      notifyListeners();
      // print("[WebSocketService] ✅ Connection established");

      // Start heartbeat and queue processing
      _startHeartbeat();
      _startQueueProcessor();

      // ✅ Start monitoring network connectivity
      _startConnectivityMonitoring();

      if (!completer.isCompleted) completer.complete();

      final subscription = _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
          _streamController.add(message);
        },
        onDone: () {
          // print("[WebSocketService] Connection closed");
          if (!completer.isCompleted) {
            completer.completeError(
              Exception("Connection closed before it could be established."),
            );
          }
          _handleDisconnection();
        },
        onError: (error, stack) {
          // print("[WebSocketService] Connection error: $error");
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
          _handleDisconnection();
        },
        cancelOnError: true,
      );

      _streamSubscription = subscription;
    } catch (e, st) {
      // print("[WebSocketService] Failed to connect: $e");
      _isReconnecting = false;
      _isConnected = false;
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = null;
      if (!completer.isCompleted) completer.completeError(e);
      _handleDisconnection();
    }

    return completer.future;
  }

  // HEARTBEAT SYSTEM
  void _startHeartbeat() {
    _stopHeartbeat();

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
      return;
    }

    if (_waitingForPong) {
      // print("[WebSocketService] Previous ping still waiting for pong - connection may be dead");
      _handleSilentDisconnection();
      return;
    }

    try {
      final pingMessage = {
        'type': 'ping',
        'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
      };

      _channel!.sink.add(jsonEncode(pingMessage));
      _waitingForPong = true;

      // Set timeout for pong response
      _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
        if (_waitingForPong) {
          // print("[WebSocketService] Pong timeout - connection appears dead");
          _handleSilentDisconnection();
        }
      });
    } catch (e) {
      // print("[WebSocketService] Error sending ping: $e");
      _handleSilentDisconnection();
    }
  }

  void _handlePong() {
    _waitingForPong = false;
    _lastPongReceived = DateTime.now().toUtc();
    _heartbeatTimeoutTimer?.cancel();
  }

  void _handleSilentDisconnection() {
    // print("[WebSocketService] Silent disconnection detected via heartbeat");
    _waitingForPong = false;
    _heartbeatTimeoutTimer?.cancel();

    // Force reconnection
    _handleDisconnection();
  }

  // MESSAGE QUEUE SYSTEM
  void _startQueueProcessor() {
    _stopQueueProcessor();

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

    final expiredMessages = <String>[];
    final retryMessages = <String>[];

    for (final entry in _messageQueue.entries) {
      final messageId = entry.key;
      final queuedMsg = entry.value;

      if (queuedMsg.isExpired) {
        // print("[WebSocketService] Message $messageId expired after ${queuedMsg.attemptCount} attempts");
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
      _channel!.sink.add(jsonEncode(queuedMsg.data));

      // Update attempt count
      _messageQueue[messageId] = queuedMsg.copyWith(
        attemptCount: queuedMsg.attemptCount + 1,
        timestamp: DateTime.now().toUtc(),
      );
    } catch (e) {
      // print("[WebSocketService] Error retrying message $messageId: $e");
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

          // print("[WebSocketService] Message $messageId marked as failed");
        }
      }
    } catch (e) {
      // print("[WebSocketService] Error updating failed message status: $e");
    }
  }

  // RELIABLE MESSAGE SENDING
  Future<bool> sendMessageReliably(Map<String, dynamic> messageData) async {
    if (!_isConnected || _channel == null) {
      // print("[WebSocketService] Cannot send message reliably - not connected");
      return false;
    }

    final messageId =
        messageData['message_id']?.toString() ??
        'msg_${DateTime.now().toUtc()..millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    // Add to queue immediately
    final queuedMessage = QueuedMessage(
      id: messageId,
      data: messageData,
      timestamp: DateTime.now().toUtc(),
    );

    _messageQueue[messageId] = queuedMessage;

    // Create completer for delivery confirmation
    final completer = Completer<bool>();
    _messageCompleters[messageId] = completer;

    try {
      // Send immediately
      _channel!.sink.add(jsonEncode(messageData));

      // Wait for confirmation or timeout
      final delivered = await completer.future.timeout(
        queuedMessage.timeout,
        onTimeout: () {
          return false;
        },
      );

      return delivered;
    } catch (e) {
      // print("[WebSocketService] Error sending message reliably: $e");
      _messageCompleters.remove(messageId);
      return false;
    } finally {
      // Clean up queue and completer
      _messageQueue.remove(messageId);
      _messageCompleters.remove(messageId);
    }
  }

  void _confirmMessageDelivery(String messageId) {
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
      // print("[WebSocketService] Error loading sent messages: $e");
      return [];
    }
  }

  Future<void> syncMessageStatuses(int conversationId) async {
    if (_lastStatusSyncTime != null &&
        DateTime.now().difference(_lastStatusSyncTime!) < _statusSyncDebounce) {
      return;
    }

    _lastStatusSyncTime = DateTime.now();

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      final dbService = DatabaseService.instance;
      final messages = await dbService.getMessages(conversationId);

      final sentMessages = messages
          .where(
            (msg) =>
                msg.senderUid == currentUser.uid &&
                msg.status == MessageStatus.sent,
          )
          .toList();

      if (sentMessages.isEmpty) {
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
      }
    } catch (e) {
      // print("[WebSocketService] Error syncing message statuses: $e");
    }
  }

  void _initializeSentMessageListener() {
    _sentMessageSubscription?.cancel();
    _sentMessageSubscription = SentMessageService.sentMessageStream.listen((
      message,
    ) {
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
    } catch (e) {
      // print("[WebSocketService] Error handling local sent message: $e");
    }
  }

  void _handleIncomingMessage(dynamic rawMessage) {
    try {
      final messageData = jsonDecode(rawMessage.toString());
      final messageType = messageData['type'] ?? '';

      // DEBUG: Log all incoming messages
      // print("[WebSocketService] 📥 Incoming message - Type: $messageType, Data: $messageData");

      switch (messageType) {
        case 'pong':
          _handlePong();
          break;
        case 'new_message':
          _handleNewMessage(messageData);
          break;
        case 'message_status':
          _handleMessageStatus(messageData);
          break;
        case 'message_deleted':
          _handleMessageDeletion(
            messageData,
          ); // Fire and forget - async processing
          break;
        case 'message_edited':
          _handleMessageEdited(messageData);
          break;
        case 'attachment_uploaded':
          _handleAttachmentUploaded(messageData);
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
        case 'presence_status':
          _handlePresenceStatus(messageData);
          break;
        case 'conversation_update':
          _handleConversationUpdate(messageData);
          break;
        case 'group_deleted':
          _handleGroupDeleted(messageData);
          break;
        case 'reaction_added':
          _handleReactionAdded(messageData);
          break;
        case 'reaction_removed':
          _handleReactionRemoved(messageData);
          break;
        case 'call_offer':
        case 'call_answer':
        case 'ice_candidate':
        case 'call_rejected':
        case 'call_ended':
        case 'call_failed':
          // Route call signals to global call manager
          _handleCallSignaling(messageData);
          // Also forward to stream for backward compatibility (chat_screen)
          _streamController.add(messageData);
          break;
        case 'session_reset_required':
          _handleSessionResetRequired(messageData);
          break;
        default:
        // print("[WebSocketService] Unknown message type: $messageType");
      }
    } catch (e, st) {
      // print("[WebSocketService] Error handling message: $e");
    }
  }

  Future<void> _handleMessageDeletion(Map<String, dynamic> deletionData) async {
    try {
      final messageId = deletionData['message_id'] as int?;
      final deletionType = deletionData['deletion_type'] as String?;
      final conversationId = deletionData['conversation_id'] as int?;

      if (messageId == null || deletionType == null || conversationId == null) {
        // print('[WebSocketService] Invalid deletion data: $deletionData');
        return;
      }

      final dbService = DatabaseService.instance;

      // Update local database immediately
      if (deletionType == 'delete_for_everyone') {
        await dbService.markMessageAsDeletedForEveryone(messageId);
        // print('[WebSocketService] ✅ Marked message $messageId as deleted for everyone in local DB');
      } else if (deletionType == 'delete_for_me') {
        await dbService.markMessageAsDeletedForMe(messageId);
        // print('[WebSocketService] ✅ Marked message $messageId as deleted for me in local DB');
      }

      // Also notify UI via stream (for real-time updates if chat is open)
      _streamController.add({
        'type': 'message_deleted',
        'message_id': messageId,
        'deletion_type': deletionType,
        'conversation_id': conversationId,
      });
    } catch (e) {
      // print('[WebSocketService] Error handling message deletion: $e');
    }
  }

  Future<void> _handleMessageEdited(Map<String, dynamic> editData) async {
    try {
      final messageId = editData['message_id'] is int
          ? editData['message_id'] as int
          : int.tryParse(editData['message_id']?.toString() ?? '');
      final conversationId = editData['conversation_id'] is int
          ? editData['conversation_id'] as int
          : int.tryParse(editData['conversation_id']?.toString() ?? '');
      final senderUid = editData['sender_uid'] as String?;
      final contentB64 = editData['content_b64'] as String?;
      final editedAtStr = editData['edited_at'] as String?;
      final editedAt = (editedAtStr != null ? DateTime.tryParse(editedAtStr)?.toUtc() : null) ??
          DateTime.now().toUtc();

      if (messageId == null || conversationId == null || contentB64 == null) {
        return;
      }

      final dbService = DatabaseService.instance;
      final existingMessage = await dbService.getMessageById(messageId);

      int? senderDeviceId = editData['sender_device_id'] is int
          ? editData['sender_device_id'] as int
          : int.tryParse(editData['sender_device_id']?.toString() ?? '');
      if (senderDeviceId == null || senderDeviceId <= 0) {
        senderDeviceId = existingMessage?.senderDeviceId;
      }
      if (senderDeviceId == null || senderDeviceId <= 0) {
        senderDeviceId = await DeviceService.getActiveDeviceId(senderUid ?? '');
      }
      final resolvedSenderDeviceId = (senderDeviceId != null && senderDeviceId > 0) ? senderDeviceId : 1;

      String? decryptedText;
      final currentUser = FirebaseAuth.instance.currentUser;
      final isMe = currentUser != null && currentUser.uid == senderUid;

      if (!isMe && senderUid != null) {
        final isGroup = editData['is_group'] as bool? ?? false;
        if (isGroup) {
          try {
            decryptedText = await GroupEncryptionService.decryptGroupMessage(
              groupId: conversationId.toString(),
              ciphertext: contentB64,
              senderUid: senderUid,
              senderDeviceId: resolvedSenderDeviceId,
            );
          } catch (e) {
            debugPrint('[WebSocketService] Group decrypt error: $e');
          }
        } else {
          try {
            decryptedText = await SignalService.decryptMessage(
              senderUid: senderUid,
              ciphertextB64: contentB64,
              deviceId: resolvedSenderDeviceId,
            );
          } catch (e) {
            debugPrint('[WebSocketService] 1-on-1 Signal decrypt error: $e');
          }
        }

        // If primary attempt failed to return a string, try the alternate mode
        if (decryptedText == null || decryptedText.isEmpty) {
          if (isGroup) {
            try {
              decryptedText = await SignalService.decryptMessage(
                senderUid: senderUid,
                ciphertextB64: contentB64,
                deviceId: resolvedSenderDeviceId,
              );
            } catch (_) {}
          } else {
            try {
              decryptedText = await GroupEncryptionService.decryptGroupMessage(
                groupId: conversationId.toString(),
                ciphertext: contentB64,
                senderUid: senderUid,
                senderDeviceId: resolvedSenderDeviceId,
              );
            } catch (_) {}
          }
        }
      }

      if (decryptedText != null && decryptedText.isNotEmpty) {
        if (existingMessage != null) {
          await dbService.updateMessageContent(
            messageId,
            decryptedText,
            encryptedContent: contentB64,
            editedAt: editedAt,
          );
        } else {
          await dbService.insertMessage(
            Message(
              id: messageId,
              conversationId: conversationId,
              username: editData['sender_username'] as String? ?? 'User',
              senderUid: senderUid ?? '',
              senderDeviceId: resolvedSenderDeviceId,
              content: decryptedText,
              encryptedContent: contentB64,
              isEdited: true,
              editedAt: editedAt,
              timestamp: editedAt,
              status: MessageStatus.delivered,
              isEncrypted: true,
            ),
          );
        }
      } else if (existingMessage != null) {
        await dbService.updateMessageContent(
          messageId,
          existingMessage.content,
          encryptedContent: contentB64,
          editedAt: editedAt,
        );
      }

      // Forward to UI stream
      _streamController.add({
        'type': 'message_edited',
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_uid': senderUid,
        'new_content': decryptedText ?? (isMe ? existingMessage?.content : null),
        'content_b64': contentB64,
        'edited_at': editedAtStr ?? editedAt.toIso8601String(),
      });
    } catch (e) {
      debugPrint('[WebSocketService] Error handling message_edited: $e');
    }
  }

  Future<void> _handleAttachmentUploaded(
    Map<String, dynamic> attachmentData,
  ) async {
    // print('[WebSocketService] Attachment uploaded notification: $attachmentData');

    // Extract data
    final messageId = attachmentData['message_id'] as int?;
    final attachmentId = attachmentData['attachment_id'] as int?;
    final conversationId = attachmentData['conversation_id'] as int?;

    if (messageId != null && attachmentId != null && conversationId != null) {
      // Update message in database immediately (even if chat screen is not open)
      try {
        final dbService = DatabaseService.instance;

        // Get the existing message from database
        final messages = await dbService.getAllMessagesInConversation(
          conversationId,
        );
        final existingMessage = messages
            .where((msg) => msg.id == messageId)
            .firstOrNull;

        if (existingMessage != null) {
          // Update the message with attachment metadata
          final updatedMessage = existingMessage.copyWith(
            attachmentId: attachmentId,
            attachmentType: attachmentData['file_type'] as String?,
            hasAttachment: true,
            mediaEncryptionKey:
                attachmentData['media_encryption_key'] as String?,
            mediaEncryptionIv: attachmentData['media_encryption_iv'] as String?,
            senderDeviceId:
                attachmentData['sender_device_id'] as int? ??
                existingMessage.senderDeviceId,
          );

          // Save updated message to database
          await dbService.insertMessage(updatedMessage);
          // print('[WebSocketService] ✅ Updated message $messageId in database with attachment $attachmentId');
        }
      } catch (e) {
        // print('[WebSocketService] ❌ Error updating message in database: $e');
      }
    }

    // Forward ALL data to UI via stream (for chat screen if it's open)
    _streamController.add(attachmentData);
  }

  final Set<int> _processedMessageIds = {};

  // ✅ PERFORMANCE FIX: Track recently processed status updates to prevent duplicates
  final Map<String, DateTime> _recentStatusUpdates =
      {}; // "messageId_status" -> timestamp

  Future<void> _handleNewMessage(Map<String, dynamic> messageData) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      final messageId = messageData['message_id'] is int
          ? messageData['message_id'] as int
          : int.tryParse(messageData['message_id']?.toString() ?? '') ?? -1;

      // Skip if already processed
      if (_processedMessageIds.contains(messageId)) {
        // print('[DEBUG] Message $messageId already processed, skipping');
        return;
      }
      _processedMessageIds.add(messageId);

      final conversationId = messageData['conversation_id'] is int
          ? messageData['conversation_id'] as int
          : int.tryParse(messageData['conversation_id']?.toString() ?? '') ??
                -1;
      final senderUid = messageData['sender_uid'] as String?;
      final senderDeviceId = messageData['sender_device_id'] as int? ?? 1;
      final contentB64 = messageData['content_b64'] as String?;
      final createdAt = messageData['created_at'] as String?;
      final senderUsername =
          messageData['sender_username'] as String? ?? 'Unknown';
      final messageType = messageData['message_type'] as String? ?? 'chat';
      final isGroup = messageData['is_group'] as bool? ?? false;

      // print('[WebSocketService] DEBUG: Received message - conversationId: $conversationId, isGroup: $isGroup');

      // Extract attachment metadata
      final attachmentId = messageData['attachment_id'] as int?;
      final attachmentType = messageData['attachment_type'] as String?;
      final hasAttachment =
          (messageData['has_attachment'] as int?) == 1 || attachmentId != null;

      if (attachmentId != null) {
        // print('[WebSocketService] Message has attachment: id=$attachmentId, type=$attachmentType');
      }

      if (messageId <= 0 ||
          conversationId <= 0 ||
          senderUid == null ||
          contentB64 == null) {
        return;
      }

      if (senderUid == currentUser.uid &&
          messageData['from_offline_queue'] != true) {
        return; // Only skip if not from offline queue
      }

      String decryptedContent;

      // IMPORTANT: Check if this is a quick reply message BEFORE attempting decryption
      // Quick replies are encrypted for recipient, so we need to get plaintext from local storage
      bool isQuickReply = false;
      if (senderUid == currentUser.uid &&
          messageData['from_offline_queue'] == true) {
        try {
          final result = await _signalChannel.invokeMethod(
            'getLocalSentMessage',
            {'messageId': messageId},
          );
          if (result != null) {
            isQuickReply = true;
            decryptedContent = result as String;
            // print("[WebSocketService] ✅ Retrieved quick reply message $messageId from local storage");

            // Save to database and skip decryption
            await _saveMessageToDatabase(
              messageId: messageId,
              conversationId: conversationId,
              senderUid: senderUid,
              username: senderUsername,
              content: decryptedContent,
              createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
              attachmentId: attachmentId,
              attachmentType: attachmentType,
              hasAttachment: hasAttachment,
            );

            _streamController.add({
              'type': 'local_message_saved',
              'message_id': messageId,
              'conversation_id': conversationId,
            });

            await _markMessageAsDelivered(messageId, conversationId);
            return; // Done processing quick reply
          }
        } catch (e) {
          // print("[WebSocketService] Error retrieving quick reply: $e");
        }
      }

      // Check if message is deleted - skip decryption
      if (messageType == 'deleted') {
        try {
          decryptedContent = utf8.decode(base64Decode(contentB64));
          // print("[WebSocketService] ✅ Deleted message, skipped decryption");
        } catch (e) {
          decryptedContent = "This message was deleted";
        }
      } else if (isGroup) {
        // GROUP MESSAGE DECRYPTION - Use Sender Keys
        try {
          // print("[WebSocketService] 🔐 Decrypting group message from $senderUid:$senderDeviceId");

          final groupDecrypted =
              await GroupEncryptionService.decryptGroupMessage(
                senderUid: senderUid,
                senderDeviceId: senderDeviceId,
                groupId: conversationId.toString(),
                ciphertext: contentB64,
              );

          if (groupDecrypted == null) {
            throw Exception('Group decryption returned null');
          }

          decryptedContent = groupDecrypted;
          // print("[WebSocketService] ✅ Group message decrypted successfully");
        } catch (e) {
          // print("[WebSocketService] ❌ Group decryption failed: $e");
          // print("[WebSocketService] 🔄 Attempting to fetch missing sender key...");

          // Try to fetch and process sender keys for this group
          try {
            final keysFetched =
                await GroupEncryptionService.fetchAndProcessGroupSenderKeys(
                  groupId: conversationId.toString(),
                );

            if (keysFetched) {
              // print("[WebSocketService] ✅ Fetched sender keys, retrying decryption...");

              // Retry decryption
              final retryDecrypted =
                  await GroupEncryptionService.decryptGroupMessage(
                    senderUid: senderUid,
                    senderDeviceId: senderDeviceId,
                    groupId: conversationId.toString(),
                    ciphertext: contentB64,
                  );

              if (retryDecrypted != null) {
                decryptedContent = retryDecrypted;
                // print("[WebSocketService] ✅ Group message decrypted after fetching keys");
              } else {
                throw Exception('Decryption still failed after fetching keys');
              }
            } else {
              throw Exception('Failed to fetch sender keys');
            }
          } catch (retryError) {
            // print("[WebSocketService] ❌ Retry decryption failed: $retryError");
            // SECURITY: Do NOT fallback to plaintext!
            // This group message cannot be decrypted - skip saving it (don't clutter UI)
            // print("[WebSocketService] ⚠️ Group message cannot be decrypted - skipping save to keep UI clean");
            return; // Skip saving undecryptable group messages
          }
        }
      } else {
        // 1-ON-1 MESSAGE DECRYPTION - Use Signal Protocol
        try {
          final result = await _signalChannel.invokeMethod('decryptMessage', {
            'myUid': currentUser.uid,
            'senderUid': senderUid,
            'ciphertextB64': contentB64,
            'senderDeviceId': senderDeviceId,
          });

          if (result == null) {
            throw Exception('Decryption returned null');
          }

          decryptedContent = result as String;
          // print("[WebSocketService] ✅ Signal decryption successful");

          // Threshold check after successful decryption (debounced and async)
          final currentUserDeviceId = await SignalService.getDeviceId();
          if (currentUserDeviceId != null) {
            unawaited(KeyRotationService.checkThresholdAfterKeyConsumption(
              currentUserUid: currentUser.uid,
              deviceId: currentUserDeviceId,
            ));
          }
        } on PlatformException catch (pe) {
          if (pe.code == 'DUPLICATE_MESSAGE') {
            debugPrint('[WebSocketService] ℹ️ Duplicate message $messageId from $senderUid already decrypted - acknowledging and skipping without resetting session');
            try {
              final existingMsg = await DatabaseService.instance.getMessageById(messageId);
              if (existingMsg != null) {
                _streamController.add({
                  'type': 'local_message_saved',
                  'message_id': messageId,
                  'conversation_id': conversationId,
                });
              }
            } catch (e) {
              debugPrint('[WebSocketService] Error checking existing message for duplicate: $e');
            }
            await _markMessageAsDelivered(messageId, conversationId);
            return; // Exit cleanly — do NOT reset session!
          }

          // Real decryption failure:
          try {
            await SignalService.resetSessionDueToDecryptionFailure(
              senderUid: senderUid,
              senderDeviceId: senderDeviceId,
            );
          } catch (_) {}

          final myActiveDeviceId = await SignalService.getDeviceId();
          try {
            final sessionResetNotification = {
              'type': 'session_reset_required',
              'target_uid': senderUid,
              'target_device_id': senderDeviceId,
              'recipient_uid': senderUid,
              'sender_uid': currentUser.uid,
              'sender_device_id': myActiveDeviceId,
              'reason': 'decryption_failed',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            };
            await sendMessageReliably(sessionResetNotification);
          } catch (_) {}
          return;
        } catch (e) {
          // print("[WebSocketService] ❌ Signal decryption failed: $e");

          // CRITICAL: Reset stale session to force re-establishment
          // This handles the case when sender reinstalled with new keys
          try {
            await SignalService.resetSessionDueToDecryptionFailure(
              senderUid: senderUid,
              senderDeviceId: senderDeviceId,
            );
            // print("[WebSocketService] 🔄 Stale session reset - will re-establish on next message");
          } catch (resetError) {
            // print("[WebSocketService] ⚠️ Session reset failed: $resetError");
          }

          // Notify sender that their session is invalid and needs to be reset
          try {
            final myActiveDeviceId = await SignalService.getDeviceId();
            final sessionResetNotification = {
              'type': 'session_reset_required',
              'target_uid': senderUid,
              'target_device_id': senderDeviceId,
              'recipient_uid': senderUid,
              'sender_uid': currentUser.uid,
              'sender_device_id': myActiveDeviceId,
              'reason': 'decryption_failed',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            };

            await sendMessageReliably(sessionResetNotification);
            // print("[WebSocketService] 📤 Sent session reset notification to sender");
          } catch (notifyError) {
            // print("[WebSocketService] ⚠️ Failed to notify sender about session reset: $notifyError");
          }

          // SECURITY: Do NOT fallback to plaintext!
          // This message cannot be decrypted - skip saving it (don't clutter UI)
          // print("[WebSocketService] ⚠️ Message cannot be decrypted - skipping save to keep UI clean");
          return; // Skip saving undecryptable messages
        }
      }

      await _saveMessageToDatabase(
        messageId: messageId,
        conversationId: conversationId,
        senderUid: senderUid,
        username: senderUsername,
        content: decryptedContent,
        createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
        attachmentId: attachmentId,
        attachmentType: attachmentType,
        hasAttachment: hasAttachment,
      );

      _streamController.add({
        'type': 'local_message_saved',
        'message_id': messageId,
        'conversation_id': conversationId,
      });

      await _markMessageAsDelivered(messageId, conversationId);
    } catch (e, st) {
      // print("[WebSocketService] Error processing new message: $e");
    }
  }

  Future<void> _saveMessageToDatabase({
    required int messageId,
    required int conversationId,
    required String senderUid,
    required String username,
    required String content,
    required String createdAt,
    int? attachmentId,
    String? attachmentType,
    bool hasAttachment = false,
  }) async {
    try {
      final dbService = DatabaseService.instance;
      final currentUser = FirebaseAuth.instance.currentUser;

      // Check if current user has deleted this message
      final isDeleted = await dbService.isMessageDeletedForMe(messageId);
      if (isDeleted) {
        return;
      }

      // NEW: Check if this is a quick reply message BEFORE creating Message object
      bool isQuickReply = false;
      if (currentUser != null && senderUid == currentUser.uid) {
        try {
          const platform = MethodChannel('com.zarq/signal');
          final result = await platform.invokeMethod('getLocalSentMessage', {
            'messageId': messageId,
          });
          isQuickReply = result != null;
          if (isQuickReply) {
            // print("[WebSocketService] Message $messageId is a quick reply");
          }
        } catch (e) {
          // print("[WebSocketService] Error checking quick reply: $e");
        }
      }

      final message = Message(
        id: messageId,
        conversationId: conversationId,
        username: username,
        content: content,
        timestamp: DateTime.parse(createdAt).toUtc(),
        senderUid: senderUid,
        status: MessageStatus.sent,
        isQuickReply: isQuickReply,
        attachmentId: attachmentId,
        attachmentType: attachmentType,
        hasAttachment: hasAttachment,
      );

      await dbService.insertMessage(message);

      _notifyUIAboutNewMessage(message, conversationId);
    } catch (e, st) {
      // print("[WebSocketService] Error saving message to database: $e");
    }
  }

  void _notifyUIAboutNewMessage(Message message, int conversationId) {
    _streamController.add({
      'type': 'local_message_saved',
      'message': message.toJson(),
      'conversation_id': conversationId,
    });
  }

  Future<void> _handleMessageStatus(Map<String, dynamic> statusData) async {
    try {
      final messageId = statusData['message_id'] as int?;
      final newStatus = statusData['status'] as String?;
      final conversationId = statusData['conversation_id'] as int?;

      if (messageId != null && newStatus != null) {
        // ✅ PERFORMANCE FIX: Check if we recently processed this exact status update
        final statusKey = '${messageId}_$newStatus';
        final lastUpdate = _recentStatusUpdates[statusKey];

        if (lastUpdate != null &&
            DateTime.now().difference(lastUpdate) < Duration(seconds: 5)) {
          // print("[WebSocketService] ⏭️ Skipping duplicate status update for message $messageId ($newStatus)");
          return;
        }

        // Track this status update
        _recentStatusUpdates[statusKey] = DateTime.now();

        // Clean up old entries (keep only last 2 minutes)
        _recentStatusUpdates.removeWhere(
          (key, time) => DateTime.now().difference(time) > Duration(minutes: 2),
        );

        MessageStatus? status;
        try {
          status = MessageStatus.values.firstWhere(
            (s) => s.toString().split('.').last == newStatus,
          );
        } catch (e) {
          return;
        }

        final wasUpdated = await _updateMessageStatusInDatabase(messageId, status);
        if (!wasUpdated) {
          // Status in DB is already same or higher (e.g. read) - do not downgrade in UI
          return;
        }

        _streamController.add({
          'type': 'message_status_update',
          'message_id': messageId,
          'status': newStatus,
          'conversation_id': conversationId,
        });
      }
    } catch (e) {
      // print("[WebSocketService] Error handling status update: $e");
    }
  }

  Future<bool> _updateMessageStatusInDatabase(
    int messageId,
    MessageStatus status,
  ) async {
    try {
      final dbService = DatabaseService.instance;
      return await dbService.updateMessageStatus(messageId, status);
    } catch (e) {
      return false;
    }
  }

  Future<void> sendStatusUpdate({
    required int messageId,
    required String status,
    required int conversationId,
  }) async {
    // print('[DEBUG] sendStatusUpdate called for message $messageId, status: $status');
    // print('[DEBUG] Stack: ${StackTrace.current}');
    if (!_isConnected || _channel == null) {
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
    } catch (e) {
      // print("[WebSocketService] Error sending status update: $e");
    }
  }

  // Send typing indicator
  void sendTypingIndicator({
    required int conversationId,
    required bool isTyping,
  }) {
    if (!_isConnected || _channel == null) {
      // print("[WebSocketService] ❌ Cannot send typing - not connected (isConnected=$_isConnected, channel=${_channel != null})");
      return;
    }

    try {
      final typingMessage = {
        'type': 'typing',
        'conversation_id': conversationId,
        'is_typing': isTyping,
      };

      _channel!.sink.add(jsonEncode(typingMessage));
      // print("[WebSocketService] ✅ Sent typing indicator: conversationId=$conversationId, isTyping=$isTyping");
    } catch (e) {
      // print("[WebSocketService] ❌ Error sending typing indicator: $e");
    }
  }

  // Send reaction to backend
  void addReaction({required int messageId, required String emoji}) {
    if (!_isConnected || _channel == null) {
      // print("[WebSocketService] ❌ Cannot add reaction - not connected");
      return;
    }

    try {
      final reactionMessage = {
        'type': 'add_reaction',
        'message_id': messageId,
        'emoji': emoji,
      };

      _channel!.sink.add(jsonEncode(reactionMessage));
      // print("[WebSocketService] ✅ Sent add_reaction: messageId=$messageId, emoji=$emoji");
    } catch (e) {
      // print("[WebSocketService] ❌ Error adding reaction: $e");
    }
  }

  void removeReaction({required int messageId, required String emoji}) {
    if (!_isConnected || _channel == null) {
      // print("[WebSocketService] ❌ Cannot remove reaction - not connected");
      return;
    }

    try {
      final reactionMessage = {
        'type': 'remove_reaction',
        'message_id': messageId,
        'emoji': emoji,
      };

      _channel!.sink.add(jsonEncode(reactionMessage));
      // print("[WebSocketService] ✅ Sent remove_reaction: messageId=$messageId, emoji=$emoji");
    } catch (e) {
      // print("[WebSocketService] ❌ Error removing reaction: $e");
    }
  }

  // Query user presence status
  void queryPresenceStatus(String targetUid) {
    if (!_isConnected || _channel == null) {
      return;
    }

    try {
      final presenceQuery = {'type': 'presence_query', 'target_uid': targetUid};

      _channel!.sink.add(jsonEncode(presenceQuery));
      // print("[WebSocketService] Queried presence for $targetUid");
    } catch (e) {
      // print("[WebSocketService] Error querying presence: $e");
    }
  }

  Future<void> _markMessageAsDelivered(
    int messageId,
    int conversationId,
  ) async {
    // If message is already marked as read in local DB, do not send delivered!
    final existing = await DatabaseService.instance.getMessageById(messageId);
    if (existing != null && existing.status == MessageStatus.read) {
      return;
    }

    // Check if we already marked this message as delivered recently
    final prefs = await SharedPreferences.getInstance();
    final deliveredKey = 'delivered_$messageId';
    final lastDeliveredTimestamp = prefs.getInt(deliveredKey);

    if (lastDeliveredTimestamp != null) {
      final lastDelivered = DateTime.fromMillisecondsSinceEpoch(
        lastDeliveredTimestamp,
      );
      if (DateTime.now().difference(lastDelivered) < Duration(hours: 1)) {
        // print('[DEBUG] Skipping delivered status for message $messageId - already sent recently');
        return;
      }
    }

    // Mark as delivered
    await prefs.setInt(deliveredKey, DateTime.now().millisecondsSinceEpoch);

    // ✅ FIX: Update local database before sending to backend
    await DatabaseService.instance.updateMessageStatus(
      messageId,
      MessageStatus.delivered,
    );

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
      final unreadMessages = messages
          .where(
            (msg) =>
                msg.senderUid != currentUser.uid &&
                (msg.status == MessageStatus.sent ||
                    msg.status == MessageStatus.delivered),
          )
          .toList();

      if (unreadMessages.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      for (final message in unreadMessages) {
        // Check persistent debounce
        final lastReadKey = 'last_read_${message.id}';
        final lastReadTimestamp = prefs.getInt(lastReadKey);

        if (lastReadTimestamp != null) {
          final lastRead = DateTime.fromMillisecondsSinceEpoch(
            lastReadTimestamp,
          );
          if (now.difference(lastRead) < _markReadDebounce) {
            // print('[DEBUG] Skipping message ${message.id} - already marked read recently');
            continue;
          }
        }

        // Store timestamp
        await prefs.setInt(lastReadKey, now.millisecondsSinceEpoch);

        await dbService.updateMessageStatus(message.id, MessageStatus.read);

        await sendStatusUpdate(
          messageId: message.id,
          status: 'read',
          conversationId: conversationId,
        );
      }

      // print("[WebSocketService] Marked ${unreadMessages.length} messages as read");
    } catch (e) {
      // print("[WebSocketService] Error marking messages as read: $e");
    }
  }

  /// Wait for ICE candidates to arrive before auto-accepting call
  Future<void> _waitForIceCandidatesAndAccept(String callerUid) async {
    const int maxWaitMs = 0; // TEST: No delay - testing immediate answer
    const int checkIntervalMs = 100; // Check every 100ms
    const int minCandidates = 5; // Wait for at least 5 candidates

    int elapsedMs = 0;

    while (elapsedMs < maxWaitMs) {
      // Check if we have buffered candidates
      final bufferedCount = _globalCallManager!.getBufferedCandidatesCount();

      if (bufferedCount >= minCandidates) {
        print(
          '[WebSocketService] ✅ Got $bufferedCount buffered ICE candidates after ${elapsedMs}ms - accepting call now',
        );
        await _globalCallManager!.acceptIncomingCall();
        print('[WebSocketService] ✅ Auto-accept completed!');
        return;
      }

      // Wait a bit before checking again
      await Future.delayed(const Duration(milliseconds: checkIntervalMs));
      elapsedMs += checkIntervalMs;
    }

    // Timeout reached - accept anyway (better to try than fail)
    final bufferedCount = _globalCallManager!.getBufferedCandidatesCount();
    print(
      '[WebSocketService] ⚠️ Timeout reached after ${maxWaitMs}ms with only $bufferedCount candidates - accepting anyway',
    );
    await _globalCallManager!.acceptIncomingCall();
    print('[WebSocketService] ✅ Auto-accept completed!');
  }

  Future<void> _handleCallSignaling(Map<String, dynamic> messageData) async {
    if (_globalCallManager == null) {
      // print('[WebSocketService] ❌ GlobalCallManager not set, ignoring call signal');
      return;
    }

    final type = messageData['type'] as String;
    // print('[WebSocketService] 📞 Handling call signal: $type');
    // print('[WebSocketService] 📞 Full message data: $messageData');

    switch (type) {
      case 'call_offer':
        final callerUid = messageData['sender_uid'] as String?;
        // 🔧 FIX: Use display_name instead of username for incoming calls
        final callerName =
            messageData['sender_display_name'] as String? ??
            messageData['sender_username'] as String?;
        final callTypeStr = messageData['callType'] as String?;
        var sdp = messageData['sdp'] as String?;
        final conversationId = messageData['conversation_id'] as int?;
        final avatarUrl = messageData['avatar_url'] as String?;
        final encrypted = messageData['encrypted'] as bool?;
        final senderDeviceId = messageData['sender_device_id'] as int?;

        // print('[WebSocketService] 📞 call_offer details:');
        // print('  - callerUid: $callerUid');
        // print('  - callerName: $callerName');
        // print('  - callType: $callTypeStr');
        // print('  - conversationId: $conversationId');
        // print('  - encrypted: $encrypted');
        // print('  - sdp length: ${sdp?.length}');

        // Decrypt SDP if encrypted
        if (encrypted == true && sdp != null && callerUid != null) {
          print('[WebSocketService] 🔓 Decrypting call_offer SDP...');
          final decryptedSdp = await SignalService.decryptMessage(
            senderUid: callerUid,
            ciphertextB64: sdp,
            deviceId: senderDeviceId ?? 1,
          );
          if (decryptedSdp != null) {
            sdp = decryptedSdp;
            print('[WebSocketService] ✅ Successfully decrypted call_offer SDP');
          } else {
            print('[WebSocketService] ⚠️ Failed to decrypt SDP');
          }
        }

        if (callerUid != null &&
            callerName != null &&
            callTypeStr != null &&
            sdp != null &&
            conversationId != null) {
          final callType = callTypeStr == 'video'
              ? CallType.video
              : CallType.voice;

          // Check if this is a renegotiation (offer during active call)
          final isInCall = _globalCallManager!.isInCall;
          final activeCallUid = _globalCallManager!.activeCall?.callerUid;
          final isRenegotiation = isInCall && activeCallUid == callerUid;

          if (isRenegotiation) {
            // This is a renegotiation (e.g., screen sharing in voice call)
            // print('[WebSocketService] 🔄 Received renegotiation offer from $callerName (screen share?)');
            await _globalCallManager!.handleRenegotiationOffer(sdp);
            // print('[WebSocketService] ✅ Renegotiation handled');
          } else {
            // This is a new incoming call
            // print('[WebSocketService] ✅ All required fields present, calling setIncomingCall');

            final callInfo = CallInfo(
              callerUid: callerUid,
              callerName: callerName,
              callType: callType,
              sdp: sdp,
              conversationId: conversationId,
              avatarUrl: avatarUrl,
            );

            // Check if we should auto-answer this call (from notification)
            final shouldAutoAnswer = NavigationHandler.shouldAutoAnswer(
              callerUid,
            );

            if (shouldAutoAnswer) {
              print(
                '[WebSocketService] 🎯 Auto-answering call from notification - waiting for ICE candidates',
              );

              // Set the incoming call (required for acceptance)
              _globalCallManager!.setIncomingCall(callInfo);

              // 🔧 CRITICAL: Wait for caller's ICE candidates to arrive
              // Poll the buffered candidates count until we have at least some candidates
              // This ensures we don't accept too early (before candidates arrive)
              _waitForIceCandidatesAndAccept(callerUid);
            } else {
              // Normal flow - show incoming call dialog
              // print('[WebSocketService] ✅ Showing incoming call dialog for $callerName');
              _globalCallManager!.setIncomingCall(callInfo);
            }

            // print('[WebSocketService] ✅ Incoming ${callType.name} call from $callerName (autoAnswer: $shouldAutoAnswer)');
          }
        } else {
          // print('[WebSocketService] ❌ Missing required fields for call_offer');
        }
        break;

      case 'call_answer':
        final sdp = messageData['sdp'] as String?;
        final avatarUrl = messageData['avatar_url'] as String?;
        final encrypted = messageData['encrypted'] as bool?;
        final senderUid = messageData['sender_uid'] as String?;
        final senderDeviceId = messageData['sender_device_id'] as int?;

        if (sdp != null) {
          _globalCallManager!.handleCallAnswer(
            sdp,
            avatarUrl: avatarUrl,
            encrypted: encrypted,
            senderUid: senderUid,
            senderDeviceId: senderDeviceId,
          );
          // print('[WebSocketService] Received call answer (encrypted: $encrypted)');
        }
        break;

      case 'ice_candidate':
        print('[WebSocketService] 📥 Received ICE candidate from remote peer');
        _globalCallManager!.handleIceCandidate(messageData);
        break;

      case 'call_rejected':
        _globalCallManager!.handleCallRejected();
        // print('[WebSocketService] Call was rejected');
        break;

      case 'call_ended':
        _globalCallManager!.handleCallEnded();
        // print('[WebSocketService] Call ended by remote');
        break;

      case 'call_failed':
        final reason = messageData['reason'] as String?;
        _globalCallManager!.handleCallFailed(reason ?? 'unknown');
        // print('[WebSocketService] Call failed: $reason');
        break;
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> typingData) {
    // print("[WebSocketService] 📨 Typing indicator received: $typingData");
    // Forward to stream so chat_screen can handle it
    _streamController.add(typingData);
  }

  void _handlePresenceStatus(Map<String, dynamic> presenceData) {
    // print("[WebSocketService] 👤 Presence status received: $presenceData");
    // Forward to stream so chat_screen can handle it
    _streamController.add(presenceData);
  }

  Future<void> _handleSessionResetRequired(
    Map<String, dynamic> resetData,
  ) async {
    try {
      // The peer who could not decrypt our message is sender_uid (or failed_user_uid)
      final remoteUid = (resetData['sender_uid'] ?? resetData['failed_user_uid']) as String?;
      final remoteDeviceId = (resetData['sender_device_id'] ?? resetData['failed_device_id']) as int?;
      final reason = resetData['reason'] as String? ?? 'unknown';

      if (remoteUid == null) {
        debugPrint("[WebSocketService] ⚠️ Invalid session reset data: missing remoteUid");
        return;
      }

      debugPrint("[WebSocketService] 🔄 Session reset required for remote contact $remoteUid:$remoteDeviceId (reason: $reason)");

      // Reset the stale session on our side for the remote peer (wipes all sessions for remoteUid)
      await SignalService.resetSessionDueToDecryptionFailure(
        senderUid: remoteUid,
        senderDeviceId: (remoteDeviceId != null && remoteDeviceId > 0) ? remoteDeviceId : 1,
      );

      // Invalidate active device ID cache to force fresh lookup on next send
      DeviceService.invalidateActiveDeviceIdCache(remoteUid);
      if (remoteDeviceId != null && remoteDeviceId > 0) {
        DeviceService.cacheActiveDeviceId(remoteUid, remoteDeviceId);
      }

      // Notify UI (e.g. ChatScreen) so it can clear in-memory caches and re-establish session
      _streamController.add({
        'type': 'session_reset_completed',
        'remote_uid': remoteUid,
        'remote_device_id': remoteDeviceId,
      });

      debugPrint("[WebSocketService] ✅ Session reset complete for $remoteUid - will fetch fresh PreKeys on next send");
    } catch (e) {
      debugPrint("[WebSocketService] ❌ Error handling session reset: $e");
    }
  }

  void _handleConversationUpdate(Map<String, dynamic> updateData) {
    // print("[WebSocketService] 🔄 Conversation update received: $updateData");

    // Debug all fields
    // print("[WebSocketService] 🔍 key_rotation_required: ${updateData['key_rotation_required']}");
    // print("[WebSocketService] 🔍 conversation_id: ${updateData['conversation_id']}");
    // print("[WebSocketService] 🔍 reason: ${updateData['reason']}");

    // Check if key rotation is required
    if (updateData['key_rotation_required'] == true) {
      final conversationId = updateData['conversation_id'];
      final reason = updateData['reason'] ?? 'unknown';
      // print("[WebSocketService] 🔐 Key rotation required for conversation $conversationId (reason: $reason)");

      // Trigger automatic key re-establishment
      _handleKeyRotation(conversationId, reason);
    } else {
      // print("[WebSocketService] ⚠️ No key rotation required or key_rotation_required is not true");
    }

    // Forward to stream so home_screen can refresh conversations
    _streamController.add(updateData);
  }

  Future<void> _handleKeyRotation(dynamic conversationId, String reason) async {
    try {
      // print("[WebSocketService] 🔄 Auto re-establishing keys for conversation $conversationId");

      // Rotate and re-establish group encryption after member change
      final reEstablished = await GroupEncryptionService.rotateSenderKey(
        groupId: conversationId.toString(),
      );

      if (reEstablished) {
        // print("[WebSocketService] ✅ Keys rotated and re-established successfully after rotation ($reason)");
      } else {
        // print("[WebSocketService] ⚠️ Failed to re-establish keys after rotation");
      }
    } catch (e) {
      // print("[WebSocketService] ❌ Error during key rotation: $e");
    }
  }

  void _handleGroupDeleted(Map<String, dynamic> deleteData) {
    // print("[WebSocketService] 🗑️ Group deleted: $deleteData");
    // Forward to stream so home_screen can remove the group
    _streamController.add(deleteData);
  }

  void _handleReactionAdded(Map<String, dynamic> reactionData) {
    try {
      // print("[WebSocketService] 👍 Reaction added: $reactionData");

      // Forward to stream for UI update
      _streamController.add({
        'type': 'reaction_added',
        'message_id': reactionData['message_id'],
        'user_uid': reactionData['user_uid'],
        'username': reactionData['username'],
        'emoji': reactionData['emoji'],
      });
    } catch (e) {
      // print("[WebSocketService] Error handling reaction_added: $e");
    }
  }

  void _handleReactionRemoved(Map<String, dynamic> reactionData) {
    try {
      // print("[WebSocketService] 👎 Reaction removed: $reactionData");

      // Forward to stream for UI update
      _streamController.add({
        'type': 'reaction_removed',
        'message_id': reactionData['message_id'],
        'user_uid': reactionData['user_uid'],
        'emoji': reactionData['emoji'],
      });
    } catch (e) {
      // print("[WebSocketService] Error handling reaction_removed: $e");
    }
  }

  // ✅ CONNECTIVITY MONITORING
  void _startConnectivityMonitoring() {
    if (_connectivitySubscription != null) return;

    // print("[WebSocketService] 📡 Starting connectivity monitoring");

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        // print("[WebSocketService] ❌ Connectivity monitoring error: $error");
      },
    );
  }

  void _stopConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasConnection = results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );

    if (!hasConnection) {
      // Lost network connection - immediately teardown dead socket
      debugPrint("[WebSocketService] [CONNECTIVITY] ⚠️ Network connection lost (results: $results) - tearing down dead socket");
      _wasDisconnectedDueToNetwork = true;
      _stopHeartbeat();
      _stopQueueProcessor();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = null;
      _streamSubscription?.cancel();
      _streamSubscription = null;
      if (_isConnected) {
        _isConnected = false;
        notifyListeners();
      }
    } else {
      // 🛡️ GUARD 1: If socket is already active and healthy, ignore event
      if (_isConnected && _channel != null) {
        return;
      }

      // 🛡️ GUARD 2: Only trigger network restoration reconnect if we actually lost network
      if (!_wasDisconnectedDueToNetwork) {
        return;
      }

      // Network came back after being lost!
      debugPrint("[WebSocketService] [CONNECTIVITY] ✅ Network restored (results: $results) - preparing immediate reconnection");
      _wasDisconnectedDueToNetwork = false;
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      // Allow brief moment for OS network routing, DHCP, and DNS resolution to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          debugPrint("[WebSocketService] [CONNECTIVITY] 🔄 Reconnecting WebSocket after network restored...");
          final token = await user.getIdToken();
          await connect(token);
          debugPrint("[WebSocketService] [CONNECTIVITY] ✅ Reconnected successfully after network restoration");
        } else {
          debugPrint("[WebSocketService] [CONNECTIVITY] ℹ️ Network restored but currentUser is null");
        }
      } catch (e) {
        debugPrint("[WebSocketService] [CONNECTIVITY] ❌ Immediate reconnection failed: $e - scheduling retry timer");
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delays = [1, 2, 5, 10, 30];
      final delaySec = delays.length >= _reconnectAttempts
          ? delays[_reconnectAttempts - 1]
          : 30;

      debugPrint("[WebSocketService] [RECONNECT] ⏱️ Scheduling reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delaySec}s");

      _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint("[WebSocketService] [RECONNECT] 🔄 Executing scheduled reconnect attempt $_reconnectAttempts...");
            final token = await user.getIdToken();
            await connect(token);
            debugPrint("[WebSocketService] [RECONNECT] ✅ Scheduled reconnect attempt $_reconnectAttempts succeeded");
          }
        } catch (e) {
          debugPrint("[WebSocketService] [RECONNECT] ❌ Scheduled reconnect attempt $_reconnectAttempts failed: $e");
          _scheduleReconnect();
        }
      });
    } else {
      debugPrint("[WebSocketService] [RECONNECT] ⚠️ Max reconnection attempts reached");
    }
  }

  void _handleDisconnection() {
    debugPrint("[WebSocketService] ⚠️ Disconnection detected (isConnected=$_isConnected, isReconnecting=$_isReconnecting)");
    final wasConnected = _isConnected;
    _isConnected = false;
    _isReconnecting = false;

    // Stop heartbeat and queue processing
    _stopHeartbeat();
    _stopQueueProcessor();

    if (wasConnected) {
      notifyListeners();
    }

    _scheduleReconnect();
  }

  /// Ensures WebSocket is connected and functional (called on app resume or network return)
  Future<void> ensureConnected() async {
    if (!_isConnected || _channel == null) {
      await reconnect();
    } else {
      _sendPing();
    }
  }

  Future<void> reconnect() async {
    _reconnectAttempts = 0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint("[WebSocketService] [RECONNECT] 🔄 Manual reconnect with fresh token...");
        final token = await user.getIdToken();
        if (_channel != null) {
          await disconnect(stopMonitoring: false);
        }
        await connect(token);
        debugPrint("[WebSocketService] [RECONNECT] ✅ Manual reconnect succeeded");
      } else {
        debugPrint("[WebSocketService] [RECONNECT] ⚠️ No user logged in for manual reconnect");
      }
    } catch (e) {
      debugPrint("[WebSocketService] [RECONNECT] ❌ Manual reconnect failed: $e");
      _scheduleReconnect();
    }
  }

  Future<void> disconnect({bool stopMonitoring = true}) async {
    _lastToken = null;
    _isReconnecting = false;

    // Stop all timers and monitoring
    _stopHeartbeat();
    _stopQueueProcessor();
    if (stopMonitoring) {
      _stopConnectivityMonitoring();
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    try {
      await _channel?.sink.close(1000, 'Normal closure');
    } catch (e) {
      // print("[WebSocketService] Error closing WebSocket: $e");
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
    _stopConnectivityMonitoring();
    _reconnectTimer?.cancel();
    _sentMessageSubscription?.cancel();
    disconnect();
    _streamController.close();
    super.dispose();
  }
}
