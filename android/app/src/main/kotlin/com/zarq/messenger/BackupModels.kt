package com.zarq.messenger

import com.google.gson.annotations.SerializedName

/**
 * Main backup data structure
 * Matches Flutter BackupData class for compatibility
 */
data class BackupData(
    @SerializedName("version")
    val version: String,

    @SerializedName("timestamp")
    val timestamp: Long,

    @SerializedName("userUid")
    val userUid: String,

    @SerializedName("deviceId")
    val deviceId: String,

    @SerializedName("messages")
    val messages: List<Map<String, Any?>>,

    @SerializedName("conversations")
    val conversations: List<Conversation>,

    @SerializedName("signalProtocolState")
    val signalProtocolState: SignalProtocolState,

    @SerializedName("attachments")
    val attachments: List<Any> // Always empty for local auto-backup
)

/**
 * Message data structure
 */
data class Message(
    @SerializedName("id")
    val id: Int,

    @SerializedName("conversationId")
    val conversationId: Long,

    @SerializedName("senderUid")
    val senderUid: String,

    @SerializedName("username")
    val username: String,

    @SerializedName("content")
    val content: String,

    @SerializedName("timestamp")
    val timestamp: String,

    @SerializedName("status")
    val status: String,

    @SerializedName("has_attachment")
    val hasAttachment: Int,

    @SerializedName("attachment_id")
    val attachmentId: Int?,

    @SerializedName("attachment_type")
    val attachmentType: String?,

    @SerializedName("reply_to_message_id")
    val replyToMessageId: Int?,

    @SerializedName("reply_to_message_content")
    val replyToMessageContent: String?,

    @SerializedName("reply_to_sender_username")
    val replyToSenderUsername: String?,

    @SerializedName("encrypted_media_key")
    val encryptedMediaKey: String?,

    @SerializedName("media_encryption_iv")
    val mediaEncryptionIv: String?,

    @SerializedName("media_encryption_type")
    val mediaEncryptionType: String?,

    @SerializedName("group_id")
    val groupId: String?,

    @SerializedName("recipient_uid")
    val recipientUid: String?,

    @SerializedName("recipient_device_id")
    val recipientDeviceId: Int?,

    @SerializedName("sender_device_id")
    val senderDeviceId: Int?
)

/**
 * Conversation data structure
 * Derived from messages
 */
data class Conversation(
    @SerializedName("conversationId")
    val conversationId: Long,

    @SerializedName("lastMessageTimestamp")
    val lastMessageTimestamp: String,

    @SerializedName("username")
    val username: String,

    @SerializedName("senderUid")
    val senderUid: String
)

/**
 * Signal Protocol state structure
 */
data class SignalProtocolState(
    @SerializedName("data")
    val data: String,

    @SerializedName("exported_at")
    val exportedAt: String
)
