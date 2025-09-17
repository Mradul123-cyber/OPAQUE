// lib/message_model.dart

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

class Message {
  final int id;
  final int conversationId;
  final String username;
  final String content;
  final DateTime timestamp;
  final String? senderUid;
  final MessageStatus status;

  Message({
    required this.id,
    required this.conversationId,
    required this.username,
    required this.content,
    required this.timestamp,
    this.senderUid,
    this.status = MessageStatus.sent, // Default to sent for received messages
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final int parsedId = json['id'] as int;
    final int parsedConversationId = json['conversationId'] as int? ??
        json['conversation_id'] as int? ?? 0;

    final dynamic usernameValue = json['username'];
    final String parsedUsername = (usernameValue is String) ? usernameValue : 'Unknown User';

    // Handle encrypted content - prioritize content_b64 over content
    final String? encryptedContentB64 = json['content_b64'] as String?;
    final String? plaintextContent = json['content'] as String?;

    String parsedContent;
    if (encryptedContentB64 != null && encryptedContentB64.isNotEmpty) {
      // This is encrypted content - mark it for decryption
      parsedContent = encryptedContentB64;
    } else if (plaintextContent != null) {
      // This is already decrypted content (for sent messages)
      parsedContent = plaintextContent;
    } else {
      parsedContent = '--- Invalid Content ---';
    }

    final dynamic timestampValue = json['timestamp'];
    DateTime parsedTimestamp;
    if (timestampValue is String) {
      try {
        parsedTimestamp = DateTime.parse(timestampValue);
      } catch (e) {
        print("WARNING: Message.fromJson - Invalid timestamp format for message ID $parsedId: $timestampValue. Using current time. Error: $e");
        parsedTimestamp = DateTime.now();
      }
    } else {
      print("WARNING: Message.fromJson - 'timestamp' is null or not a String for message ID $parsedId. Value: $timestampValue. Using current time.");
      parsedTimestamp = DateTime.now();
    }

    final String? parsedSenderUid = json['senderUid'] as String? ??
        json['sender_uid'] as String?;
    if (parsedSenderUid == null) {
      print('WARNING: Message.fromJson - "senderUid" is missing for message ID $parsedId.');
    }

    // Parse status from JSON or default to sent
    MessageStatus parsedStatus = MessageStatus.sent;
    final String? statusString = json['status'] as String?;
    if (statusString != null) {
      try {
        parsedStatus = MessageStatus.values.firstWhere(
              (status) => status.toString().split('.').last == statusString,
        );
      } catch (e) {
        print('WARNING: Unknown message status: $statusString, defaulting to sent');
      }
    }

    return Message(
      id: parsedId,
      conversationId: parsedConversationId,
      username: parsedUsername,
      content: parsedContent, // This will be either encrypted B64 or plaintext
      timestamp: parsedTimestamp,
      senderUid: parsedSenderUid,
      status: parsedStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'username': username,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'senderUid': senderUid,
      'status': status.toString().split('.').last,
    };
  }

  Message copyWith({
    int? id,
    int? conversationId,
    String? username,
    String? content,
    DateTime? timestamp,
    String? senderUid,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      username: username ?? this.username,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      senderUid: senderUid ?? this.senderUid,
      status: status ?? this.status,
    );
  }

  // Helper methods for status checks
  bool get isPending => status == MessageStatus.sending;
  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isRead => status == MessageStatus.read;
  bool get isFailed => status == MessageStatus.failed;
}