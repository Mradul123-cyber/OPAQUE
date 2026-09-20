enum MessageStatus {
  sending,        // Encrypting and sending
  sent,           // Successfully encrypted and sent
  delivered,      // Delivered to recipient
  read,          // Read by recipient
  failed,        // Encryption or sending failed
  decrypting,    // Currently decrypting received message
  decryptFailed, // Failed to decrypt received message
}

class Message {
  final int id;
  final int conversationId;
  final String username;
  final String content;
  final DateTime timestamp;
  final String? senderUid;
  final MessageStatus status;

  // Encryption metadata
  final String? encryptedContent;
  final bool isEncrypted;
  final int? senderDeviceId;
  final int? recipientDeviceId;

  // Quick reply flag
  final bool isQuickReply;

  // Attachment metadata
  final int? attachmentId;
  final String? attachmentType; // 'image', 'video', 'audio', 'document', etc.
  final bool hasAttachment;
  final int? videoDuration; // Video duration in seconds (for video attachments)
  final int? audioDuration; // Audio duration in seconds (for audio voice messages)

  // Media encryption metadata (for end-to-end encrypted media)
  final String? mediaEncryptionKey; // AES key encrypted with recipient's Signal Protocol (base64)
  final String? mediaEncryptionIv;  // AES IV in base64 (can be plaintext)
  final String? senderMediaEncryptionKey; // AES key encrypted with sender's Signal Protocol (base64) - for re-download

  // E2EE Backup metadata - stores Signal/Sender Keys encrypted AES key
  final String? encryptedMediaKey; // AES key encrypted with Signal/Sender Keys (for E2EE backup)
  final String? mediaEncryptionType; // 'signal' or 'sender_keys'
  final String? mediaRecipientUid;
  final int? mediaRecipientDeviceId;
  final String? mediaGroupId;
  final String? mediaSenderUid;
  final int? mediaSenderDeviceId;

  // Reply metadata
  final int? replyToMessageId; // ID of the message being replied to
  final String? repliedMessageContent; // Content of replied message (for display)
  final String? repliedMessageSenderName; // Name of replied message sender

  // Reactions
  final List<dynamic>? reactions; // List of MessageReaction objects

  // Edit metadata
  final bool isEdited;
  final DateTime? editedAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.username,
    required this.content,
    required this.timestamp,
    this.senderUid,
    this.status = MessageStatus.sent,
    this.encryptedContent,
    this.isEncrypted = true,
    this.senderDeviceId,
    this.recipientDeviceId,
    this.isQuickReply = false,
    this.attachmentId,
    this.attachmentType,
    this.hasAttachment = false,
    this.videoDuration,
    this.audioDuration,
    this.mediaEncryptionKey,
    this.mediaEncryptionIv,
    this.senderMediaEncryptionKey,
    this.encryptedMediaKey,
    this.mediaEncryptionType,
    this.mediaRecipientUid,
    this.mediaRecipientDeviceId,
    this.mediaGroupId,
    this.mediaSenderUid,
    this.mediaSenderDeviceId,
    this.replyToMessageId,
    this.repliedMessageContent,
    this.repliedMessageSenderName,
    this.reactions,
    this.isEdited = false,
    this.editedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final int parsedId = json['id'] as int;
    final int parsedConversationId = json['conversationId'] as int? ??
        json['conversation_id'] as int? ?? 0;

    final dynamic usernameValue = json['username'];
    final String parsedUsername = (usernameValue is String) ? usernameValue : 'Unknown User';

    final String? decryptedContent = json['content'] as String?;
    final String? encryptedContentB64 = json['content_b64'] as String? ?? json['encryptedContent'] as String?;

    String parsedContent;
    bool isEncrypted = false;

    if (decryptedContent != null && !decryptedContent.startsWith('ENCRYPTED:')) {
      parsedContent = decryptedContent;
      isEncrypted = encryptedContentB64 != null;
    } else if (encryptedContentB64 != null) {
      parsedContent = 'Decrypting message...';
      isEncrypted = true;
    } else {
      parsedContent = '--- Invalid Content ---';
    }

    final dynamic timestampValue = json['timestamp'] ?? json['created_at'];
    DateTime parsedTimestamp;
    if (timestampValue is String) {
      try {
        parsedTimestamp = DateTime.parse(timestampValue);
      } catch (e) {
        parsedTimestamp = DateTime.now();
      }
    } else {
      parsedTimestamp = DateTime.now();
    }

    final String? parsedSenderUid = json['senderUid'] as String? ??
        json['sender_uid'] as String?;

    MessageStatus parsedStatus = MessageStatus.sent;
    final String? statusString = json['status'] as String?;
    if (statusString != null) {
      try {
        parsedStatus = MessageStatus.values.firstWhere(
              (status) => status.toString().split('.').last == statusString,
        );
      } catch (e) {
        if (encryptedContentB64 != null && decryptedContent == null) {
          parsedStatus = MessageStatus.decrypting;
        }
      }
    }

    return Message(
      id: parsedId,
      conversationId: parsedConversationId,
      username: parsedUsername,
      content: parsedContent,
      timestamp: parsedTimestamp,
      senderUid: parsedSenderUid,
      status: parsedStatus,
      encryptedContent: encryptedContentB64,
      isEncrypted: isEncrypted,
      senderDeviceId: json['sender_device_id'] as int? ?? json['senderDeviceId'] as int?,
      recipientDeviceId: json['recipient_device_id'] as int? ?? json['recipientDeviceId'] as int?,
      isQuickReply: (json['is_quick_reply'] as int?) == 1,
      attachmentId: json['attachment_id'] as int?,
      attachmentType: json['attachment_type'] as String?,
      hasAttachment: (json['has_attachment'] as int?) == 1 || json['attachment_id'] != null,
      videoDuration: json['video_duration'] as int?,
      audioDuration: json['audio_duration'] as int?,
      mediaEncryptionKey: json['media_encryption_key'] as String?,
      mediaEncryptionIv: json['media_encryption_iv'] as String?,
      senderMediaEncryptionKey: json['sender_media_encryption_key'] as String?,
      encryptedMediaKey: json['encrypted_media_key'] as String?,
      mediaEncryptionType: json['media_encryption_type'] as String?,
      mediaRecipientUid: json['media_recipient_uid'] as String?,
      mediaRecipientDeviceId: json['media_recipient_device_id'] as int?,
      mediaGroupId: json['media_group_id'] as String?,
      mediaSenderUid: json['media_sender_uid'] as String?,
      mediaSenderDeviceId: json['media_sender_device_id'] as int?,
      replyToMessageId: json['reply_to_message_id'] as int?,
      repliedMessageContent: json['replied_message_content'] as String?,
      repliedMessageSenderName: json['replied_message_sender_name'] as String?,
      reactions: json['reactions'] as List<dynamic>?,
      isEdited: (json['is_edited'] == 1 ||
          json['is_edited'] == '1' ||
          json['is_edited'] == true ||
          json['isEdited'] == true),
      editedAt: (json['edited_at'] ?? json['editedAt']) is DateTime
          ? ((json['edited_at'] ?? json['editedAt']) as DateTime).toUtc()
          : (json['edited_at'] ?? json['editedAt']) is String
              ? DateTime.tryParse((json['edited_at'] ?? json['editedAt']) as String)?.toUtc()
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    final json = {
      'id': id,
      'conversationId': conversationId,
      'username': username,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'senderUid': senderUid,
      'status': status.toString().split('.').last,
      'isEncrypted': isEncrypted,
      'isQuickReply': isQuickReply,  // NEW
      'is_edited': isEdited ? 1 : 0,
    };

    if (editedAt != null) json['edited_at'] = editedAt!.toUtc().toIso8601String();
    if (encryptedContent != null) json['encryptedContent'] = encryptedContent;
    if (senderDeviceId != null) json['senderDeviceId'] = senderDeviceId;
    if (recipientDeviceId != null) json['recipientDeviceId'] = recipientDeviceId;
    if (attachmentId != null) json['attachment_id'] = attachmentId;
    if (attachmentType != null) json['attachment_type'] = attachmentType;
    json['has_attachment'] = hasAttachment;
    if (videoDuration != null) json['video_duration'] = videoDuration;
    if (audioDuration != null) json['audio_duration'] = audioDuration;
    if (mediaEncryptionKey != null) json['media_encryption_key'] = mediaEncryptionKey;
    if (mediaEncryptionIv != null) json['media_encryption_iv'] = mediaEncryptionIv;
    if (senderMediaEncryptionKey != null) json['sender_media_encryption_key'] = senderMediaEncryptionKey;
    if (encryptedMediaKey != null) json['encrypted_media_key'] = encryptedMediaKey;
    if (mediaEncryptionType != null) json['media_encryption_type'] = mediaEncryptionType;
    if (mediaRecipientUid != null) json['media_recipient_uid'] = mediaRecipientUid;
    if (mediaRecipientDeviceId != null) json['media_recipient_device_id'] = mediaRecipientDeviceId;
    if (mediaGroupId != null) json['media_group_id'] = mediaGroupId;
    if (mediaSenderUid != null) json['media_sender_uid'] = mediaSenderUid;
    if (mediaSenderDeviceId != null) json['media_sender_device_id'] = mediaSenderDeviceId;
    if (replyToMessageId != null) json['reply_to_message_id'] = replyToMessageId;
    if (repliedMessageContent != null) json['replied_message_content'] = repliedMessageContent;
    if (repliedMessageSenderName != null) json['replied_message_sender_name'] = repliedMessageSenderName;
    if (reactions != null) json['reactions'] = reactions;

    return json;
  }

  Message copyWith({
    int? id,
    int? conversationId,
    String? username,
    String? content,
    DateTime? timestamp,
    String? senderUid,
    MessageStatus? status,
    String? encryptedContent,
    bool? isEncrypted,
    int? senderDeviceId,
    int? recipientDeviceId,
    bool? isQuickReply,
    int? attachmentId,
    String? attachmentType,
    bool? hasAttachment,
    int? videoDuration,
    int? audioDuration,
    String? mediaEncryptionKey,
    String? mediaEncryptionIv,
    String? senderMediaEncryptionKey,
    String? encryptedMediaKey,
    String? mediaEncryptionType,
    String? mediaRecipientUid,
    int? mediaRecipientDeviceId,
    String? mediaGroupId,
    String? mediaSenderUid,
    int? mediaSenderDeviceId,
    int? replyToMessageId,
    String? repliedMessageContent,
    String? repliedMessageSenderName,
    List<dynamic>? reactions,
    bool? isEdited,
    DateTime? editedAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      username: username ?? this.username,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      senderUid: senderUid ?? this.senderUid,
      status: status ?? this.status,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      isQuickReply: isQuickReply ?? this.isQuickReply,
      attachmentId: attachmentId ?? this.attachmentId,
      attachmentType: attachmentType ?? this.attachmentType,
      hasAttachment: hasAttachment ?? this.hasAttachment,
      videoDuration: videoDuration ?? this.videoDuration,
      audioDuration: audioDuration ?? this.audioDuration,
      mediaEncryptionKey: mediaEncryptionKey ?? this.mediaEncryptionKey,
      mediaEncryptionIv: mediaEncryptionIv ?? this.mediaEncryptionIv,
      senderMediaEncryptionKey: senderMediaEncryptionKey ?? this.senderMediaEncryptionKey,
      encryptedMediaKey: encryptedMediaKey ?? this.encryptedMediaKey,
      mediaEncryptionType: mediaEncryptionType ?? this.mediaEncryptionType,
      mediaRecipientUid: mediaRecipientUid ?? this.mediaRecipientUid,
      mediaRecipientDeviceId: mediaRecipientDeviceId ?? this.mediaRecipientDeviceId,
      mediaGroupId: mediaGroupId ?? this.mediaGroupId,
      mediaSenderUid: mediaSenderUid ?? this.mediaSenderUid,
      mediaSenderDeviceId: mediaSenderDeviceId ?? this.mediaSenderDeviceId,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      repliedMessageContent: repliedMessageContent ?? this.repliedMessageContent,
      repliedMessageSenderName: repliedMessageSenderName ?? this.repliedMessageSenderName,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
    );
  }

  bool get isPending => status == MessageStatus.sending;
  bool get isSent => status == MessageStatus.sent;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isRead => status == MessageStatus.read;
  bool get isFailed => status == MessageStatus.failed;
  bool get isDecrypting => status == MessageStatus.decrypting;
  bool get isDecryptFailed => status == MessageStatus.decryptFailed;
  bool get needsDecryption => isEncrypted && encryptedContent != null &&
      (status == MessageStatus.decrypting || content == 'Decrypting message...');
}