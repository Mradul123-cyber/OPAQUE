import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../home_screen.dart';
import '../providers/home_provider.dart';
import '../providers/chat_provider.dart';
import '../services/share_service.dart';
import '../services/websocket_service.dart';
import '../services/device_service.dart';
import '../services/file_service.dart';
import '../services/SignalService.dart';
import '../services/group_encryption_service.dart';
import '../services/database_service.dart';
import '../services/user_settings_provider.dart';
import '../message_model.dart';
import '../widgets/opaque_toast.dart';

class ShareConversationPickerScreen extends StatefulWidget {
  final SharedContent sharedContent;

  const ShareConversationPickerScreen({super.key, required this.sharedContent});

  @override
  State<ShareConversationPickerScreen> createState() =>
      _ShareConversationPickerScreenState();
}

class _ShareConversationPickerScreenState
    extends State<ShareConversationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ConversationInfo> _filteredConversations = [];
  bool _isSearching = false;
  final Set<int> _selectedConversationIds = {}; // Track selected conversations
  bool _isSending = false; // Track if currently sending

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterConversations);

    // Load conversations if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      if (homeProvider.conversations.isEmpty) {
        homeProvider.fetchInitialConversations();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterConversations() {
    final homeProvider = Provider.of<HomeProvider>(context, listen: false);
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredConversations = homeProvider.conversations;
        _isSearching = false;
      } else {
        _filteredConversations = homeProvider.conversations
            .where((conv) => conv.chatTitle.toLowerCase().contains(query))
            .toList();
        _isSearching = true;
      }
    });
  }

  String _getShareDescription() {
    switch (widget.sharedContent.type) {
      case 'text':
        return 'Share text message';
      case 'image':
        return 'Share image';
      case 'video':
        return 'Share video';
      case 'file':
        return 'Share file';
      case 'images':
        return 'Share ${widget.sharedContent.uris?.length ?? 0} images';
      case 'videos':
        return 'Share ${widget.sharedContent.uris?.length ?? 0} videos';
      default:
        return 'Share content';
    }
  }

  void _toggleConversationSelection(ConversationInfo conversation) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔵 [SharePicker] _toggleConversationSelection called');
    debugPrint('🔵 Conversation: ${conversation.chatTitle}');
    debugPrint('🔵 Current selected IDs: $_selectedConversationIds');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    setState(() {
      if (_selectedConversationIds.contains(conversation.conversationId)) {
        _selectedConversationIds.remove(conversation.conversationId);
        debugPrint('🔵 REMOVED from selection');
      } else {
        _selectedConversationIds.add(conversation.conversationId);
        debugPrint('🔵 ADDED to selection');
      }
    });

    debugPrint('🔵 New selected IDs: $_selectedConversationIds');
  }

  Future<void> _sendToSelectedConversations() async {
    if (_selectedConversationIds.isEmpty) {
      OpaqueToast.warning(context, 'Please select at least one conversation');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final homeProvider = Provider.of<HomeProvider>(context, listen: false);
      final websocketService = Provider.of<WebSocketService>(
        context,
        listen: false,
      );
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Check internet connection
      if (!websocketService.isConnected) {
        throw Exception('No internet connection');
      }

      // Get all selected conversations
      final selectedConversations = homeProvider.conversations
          .where(
            (conv) => _selectedConversationIds.contains(conv.conversationId),
          )
          .toList();

      debugPrint(
        '[SharePicker] Sending to ${selectedConversations.length} conversations',
      );

      int successCount = 0;
      int failCount = 0;

      // Send to each conversation
      for (final conversation in selectedConversations) {
        try {
          await _sendContentToConversation(
            conversation,
            currentUser,
            dbService,
          );
          successCount++;
        } catch (e) {
          debugPrint(
            '[SharePicker] Failed to send to ${conversation.chatTitle}: $e',
          );
          failCount++;
        }

        // Small delay between sends
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // After all sends, pop back to previous screen
      if (mounted) {
        Navigator.of(context).pop();

        if (failCount == 0) {
          OpaqueToast.success(context, 'Shared to $successCount conversation(s)');
        } else {
          OpaqueToast.warning(context, 'Shared to $successCount, failed: $failCount');
        }
      }
    } catch (e) {
      debugPrint('[SharePicker] Error sending: $e');
      if (mounted) {
        OpaqueToast.error(context, 'Failed to share: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _sendContentToConversation(
    ConversationInfo conversation,
    User currentUser,
    DatabaseService dbService,
  ) async {
    final sharedContent = widget.sharedContent;

    switch (sharedContent.type) {
      case 'text':
        if (sharedContent.text != null) {
          await _sendTextMessage(
            conversation,
            sharedContent.text!,
            currentUser,
            dbService,
          );
        }
        break;

      case 'image':
        if (sharedContent.uri != null) {
          await _sendImageMessage(
            conversation,
            sharedContent.uri!,
            currentUser,
            dbService,
          );
        }
        break;

      case 'images':
        if (sharedContent.uris != null) {
          for (final uri in sharedContent.uris!) {
            await _sendImageMessage(conversation, uri, currentUser, dbService);
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        break;

      case 'video':
        if (sharedContent.uri != null) {
          await _sendVideoMessage(
            conversation,
            sharedContent.uri!,
            currentUser,
            dbService,
          );
        }
        break;

      case 'videos':
        if (sharedContent.uris != null) {
          for (final uri in sharedContent.uris!) {
            await _sendVideoMessage(conversation, uri, currentUser, dbService);
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        break;

      case 'file':
        if (sharedContent.uri != null) {
          await _sendFileMessage(
            conversation,
            sharedContent.uri!,
            currentUser,
            dbService,
          );
        }
        break;

      default:
        throw Exception('Unknown content type: ${sharedContent.type}');
    }
  }

  Future<void> _sendTextMessage(
    ConversationInfo conversation,
    String text,
    User currentUser,
    DatabaseService dbService,
  ) async {
    final currentUserUid = currentUser.uid;
    final currentUserName = currentUser.displayName ?? 'User';

    // Encrypt message
    String? encryptedMessage;
    int? myDeviceId;
    int? recipientDeviceId;

    if (conversation.isGroup) {
      encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: text,
      );
      myDeviceId = await SignalService.getDeviceId();
    } else {
      if (conversation.partnerUid == null) {
        throw Exception('No partner UID for 1-on-1 chat');
      }

      recipientDeviceId = await _getRecipientDeviceId(conversation.partnerUid!);
      if (recipientDeviceId == null) throw Exception('No recipient device ID');

      myDeviceId = await SignalService.getDeviceId();
      if (myDeviceId == null) throw Exception('No device ID');

      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: text,
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedMessage = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: text,
          deviceId: recipientDeviceId,
        );
      }
    }

    if (encryptedMessage == null) throw Exception('Encryption failed');

    // Send message
    final response = await DeviceService.sendMessage(
      conversationId: conversation.conversationId,
      contentB64: encryptedMessage,
    );

    final messageId = response['message_id'];
    if (messageId == null) throw Exception('Failed to create message');

    // Save to local database
    final message = Message(
      id: messageId,
      conversationId: conversation.conversationId,
      username: currentUserName,
      content: text,
      timestamp: DateTime.now().toUtc(),
      senderUid: currentUserUid,
      status: MessageStatus.sent,
      encryptedContent: encryptedMessage,
      isEncrypted: true,
      senderDeviceId: myDeviceId,
      recipientDeviceId: recipientDeviceId,
      isQuickReply: false,
    );

    await dbService.insertMessage(message);
    debugPrint('[SharePicker] Text message sent to ${conversation.chatTitle}');
  }

  Future<void> _sendImageMessage(
    ConversationInfo conversation,
    String uriString,
    User currentUser,
    DatabaseService dbService,
  ) async {
    // Handle content:// URIs from other apps
    File file;

    if (uriString.startsWith('content://')) {
      debugPrint('[SharePicker] Content URI detected, copying to temp file...');

      // Copy content URI to temporary file
      file = await _copyContentUriToTempFile(uriString);

      debugPrint('[SharePicker] Content copied to: ${file.path}');
    } else {
      // Direct file path
      final uri = Uri.parse(uriString);
      final filePath = uri.path;
      file = File(filePath);

      if (!await file.exists()) {
        throw Exception('Image file not found at: $filePath');
      }
    }

    final currentUserUid = currentUser.uid;
    final currentUserName = currentUser.displayName ?? 'User';

    // Step 1: Send placeholder message
    final myDeviceId = await SignalService.getDeviceId();
    if (myDeviceId == null) throw Exception('No device ID');

    String? encryptedMessage;
    int? recipientDeviceId;

    if (conversation.isGroup) {
      encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: '[Image]',
      );
    } else {
      if (conversation.partnerUid == null) {
        throw Exception('No partner UID');
      }

      recipientDeviceId = await _getRecipientDeviceId(conversation.partnerUid!);
      if (recipientDeviceId == null) throw Exception('No recipient device ID');

      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: '[Image]',
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedMessage = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: '[Image]',
          deviceId: recipientDeviceId,
        );
      }
    }

    if (encryptedMessage == null) throw Exception('Encryption failed');

    final response = await DeviceService.sendMessage(
      conversationId: conversation.conversationId,
      contentB64: encryptedMessage,
    );

    final messageId = response['message_id'];
    if (messageId == null) throw Exception('Failed to create message');

    // Step 2: Process image
    final dimensions = await FileService.getImageDimensions(file.path);
    final compressedData = await FileService.compressImage(file.path);
    if (compressedData == null) throw Exception('Compression failed');

    // Step 3: Encrypt image
    final encryptionResult = FileService.encryptImageData(
      imageData: compressedData,
    );
    final encryptedImageData = encryptionResult['encryptedData'] as Uint8List;
    final aesKey = encryptionResult['key'] as Uint8List;
    final aesIv = encryptionResult['iv'] as Uint8List;

    final aesKeyB64 = base64.encode(aesKey);
    String? encryptedAesKey;

    if (conversation.isGroup) {
      encryptedAesKey = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: aesKeyB64,
      );
    } else {
      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId!,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedAesKey = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedAesKey = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          deviceId: recipientDeviceId!,
        );
      }
    }

    if (encryptedAesKey == null) throw Exception('Failed to encrypt AES key');

    // Step 4: Upload image
    final result = await FileService.uploadEncryptedFile(
      encryptedData: encryptedImageData,
      messageId: messageId,
      conversationId: conversation.conversationId,
      fileType: 'image',
      mimeType: 'image/jpeg',
      width: dimensions?['width'],
      height: dimensions?['height'],
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
    );

    if (result == null) throw Exception('Failed to upload image');

    final attachmentId = result['attachment_id'] as int;

    // Save image locally
    await FileService.saveImageToPersistentStorage(
      compressedData,
      attachmentId,
    );

    // Step 5: Save message to database
    final message = Message(
      id: messageId,
      conversationId: conversation.conversationId,
      username: currentUserName,
      content: '[Image]',
      timestamp: DateTime.now().toUtc(),
      senderUid: currentUserUid,
      status: MessageStatus.sent,
      encryptedContent: encryptedMessage,
      isEncrypted: true,
      senderDeviceId: myDeviceId,
      recipientDeviceId: recipientDeviceId,
      hasAttachment: true,
      attachmentId: attachmentId,
      attachmentType: 'image',
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
      senderMediaEncryptionKey: aesKeyB64,
      encryptedMediaKey: encryptedAesKey,
      mediaEncryptionType: conversation.isGroup ? 'sender_keys' : 'signal',
      mediaRecipientUid: conversation.isGroup ? null : conversation.partnerUid,
      mediaRecipientDeviceId: conversation.isGroup ? null : recipientDeviceId,
      mediaGroupId: conversation.isGroup
          ? conversation.conversationId.toString()
          : null,
      mediaSenderUid: currentUserUid,
      mediaSenderDeviceId: myDeviceId,
    );

    await dbService.insertMessage(message);
    debugPrint('[SharePicker] Image sent to ${conversation.chatTitle}');
  }

  Future<void> _sendVideoMessage(
    ConversationInfo conversation,
    String uriString,
    User currentUser,
    DatabaseService dbService,
  ) async {
    // Handle content:// URIs from other apps
    File file;

    if (uriString.startsWith('content://')) {
      debugPrint(
        '[SharePicker] Content URI detected, copying video to temp file...',
      );
      file = await _copyContentUriToTempFile(uriString);
      debugPrint('[SharePicker] Video copied to: ${file.path}');
    } else {
      final uri = Uri.parse(uriString);
      final filePath = uri.path;
      file = File(filePath);

      if (!await file.exists()) {
        throw Exception('Video file not found at: $filePath');
      }
    }

    final currentUserUid = currentUser.uid;
    final currentUserName = currentUser.displayName ?? 'User';

    // Step 1: Send placeholder message
    final myDeviceId = await SignalService.getDeviceId();
    if (myDeviceId == null) throw Exception('No device ID');

    String? encryptedMessage;
    int? recipientDeviceId;

    if (conversation.isGroup) {
      encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: '[Video]',
      );
    } else {
      if (conversation.partnerUid == null) {
        throw Exception('No partner UID');
      }

      recipientDeviceId = await _getRecipientDeviceId(conversation.partnerUid!);
      if (recipientDeviceId == null) throw Exception('No recipient device ID');

      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: '[Video]',
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedMessage = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: '[Video]',
          deviceId: recipientDeviceId,
        );
      }
    }

    if (encryptedMessage == null) throw Exception('Encryption failed');

    final response = await DeviceService.sendMessage(
      conversationId: conversation.conversationId,
      contentB64: encryptedMessage,
    );

    final messageId = response['message_id'];
    if (messageId == null) throw Exception('Failed to create message');

    // Step 2: Compress video
    final compressedVideoFile = await FileService.compressVideo(file.path);
    if (compressedVideoFile == null) {
      throw Exception('Video compression failed');
    }

    // Check compressed video size
    final compressedSize = await compressedVideoFile.length();
    if (compressedSize > FileService.maxCompressedVideoSize) {
      throw Exception(
        'Video too large after compression: ${(compressedSize / (1024 * 1024)).toStringAsFixed(1)}MB. '
        'Maximum allowed: ${(FileService.maxCompressedVideoSize / (1024 * 1024)).toStringAsFixed(0)}MB',
      );
    }

    // Get metadata
    final metadata = await FileService.getVideoMetadata(
      compressedVideoFile.path,
    );

    // Read video bytes
    final videoBytes = await compressedVideoFile.readAsBytes();

    // Step 3: Encrypt video with AES
    final encryptionResult = FileService.encryptWithAES(data: videoBytes);
    final encryptedVideoData = encryptionResult['encryptedData'] as Uint8List;
    final aesKey = encryptionResult['key'] as Uint8List;
    final aesIv = encryptionResult['iv'] as Uint8List;

    final aesKeyB64 = base64.encode(aesKey);
    String? encryptedAesKey;

    if (conversation.isGroup) {
      encryptedAesKey = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: aesKeyB64,
      );
    } else {
      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId!,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedAesKey = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedAesKey = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          deviceId: recipientDeviceId!,
        );
      }
    }

    if (encryptedAesKey == null) throw Exception('Failed to encrypt AES key');

    // Step 4: Upload video
    final result = await FileService.uploadEncryptedFile(
      encryptedData: encryptedVideoData,
      messageId: messageId,
      conversationId: conversation.conversationId,
      fileType: 'video',
      mimeType: 'video/mp4',
      width: metadata?['width'],
      height: metadata?['height'],
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
    );

    if (result == null) throw Exception('Failed to upload video');

    final attachmentId = result['attachment_id'] as int;

    // Save video locally
    await FileService.saveVideoToPersistentStorage(videoBytes, attachmentId);

    // Step 5: Save message to database
    final message = Message(
      id: messageId,
      conversationId: conversation.conversationId,
      username: currentUserName,
      content: '[Video]',
      timestamp: DateTime.now().toUtc(),
      senderUid: currentUserUid,
      status: MessageStatus.sent,
      encryptedContent: encryptedMessage,
      isEncrypted: true,
      senderDeviceId: myDeviceId,
      recipientDeviceId: recipientDeviceId,
      hasAttachment: true,
      attachmentId: attachmentId,
      attachmentType: 'video',
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
      senderMediaEncryptionKey: aesKeyB64,
      encryptedMediaKey: encryptedAesKey,
      mediaEncryptionType: conversation.isGroup ? 'sender_keys' : 'signal',
      mediaRecipientUid: conversation.isGroup ? null : conversation.partnerUid,
      mediaRecipientDeviceId: conversation.isGroup ? null : recipientDeviceId,
      mediaGroupId: conversation.isGroup
          ? conversation.conversationId.toString()
          : null,
      mediaSenderUid: currentUserUid,
      mediaSenderDeviceId: myDeviceId,
    );

    await dbService.insertMessage(message);
    debugPrint('[SharePicker] Video sent to ${conversation.chatTitle}');
  }

  Future<void> _sendFileMessage(
    ConversationInfo conversation,
    String uriString,
    User currentUser,
    DatabaseService dbService,
  ) async {
    // Handle content:// URIs from other apps
    File file;
    String? fileName;

    if (uriString.startsWith('content://')) {
      debugPrint('[SharePicker] Content URI detected, copying file to temp...');

      // Use platform channel to read content URI
      const platform = MethodChannel('com.zarq/share');
      final result = await platform.invokeMethod('readContentUri', {
        'uri': uriString,
      });

      if (result == null || result['data'] == null) {
        throw Exception('Failed to read content URI');
      }

      final Uint8List fileData = result['data'] as Uint8List;
      fileName = result['fileName'] as String?;

      // Create temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFileName = fileName ?? 'shared_file_$timestamp';
      file = File(path.join(tempDir.path, tempFileName));
      await file.writeAsBytes(fileData);

      debugPrint('[SharePicker] File copied to: ${file.path}');
    } else {
      final uri = Uri.parse(uriString);
      final filePath = uri.path;
      file = File(filePath);
      fileName = path.basename(filePath);

      if (!await file.exists()) {
        throw Exception('File not found at: $filePath');
      }
    }

    // Check file size (max 100MB for generic files)
    final fileSize = await file.length();
    const maxFileSize = 100 * 1024 * 1024; // 100MB
    if (fileSize > maxFileSize) {
      throw Exception(
        'File too large: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB. '
        'Maximum allowed: ${(maxFileSize / (1024 * 1024)).toStringAsFixed(0)}MB',
      );
    }

    final currentUserUid = currentUser.uid;
    final currentUserName = currentUser.displayName ?? 'User';

    // Get MIME type
    final mimeInfo = FileService.getFileMimeType(file.path);
    final mimeType = mimeInfo['mimeType'] ?? 'application/octet-stream';

    // Step 1: Send placeholder message
    final myDeviceId = await SignalService.getDeviceId();
    if (myDeviceId == null) throw Exception('No device ID');

    String? encryptedMessage;
    int? recipientDeviceId;

    if (conversation.isGroup) {
      encryptedMessage = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: '[File: $fileName]',
      );
    } else {
      if (conversation.partnerUid == null) {
        throw Exception('No partner UID');
      }

      recipientDeviceId = await _getRecipientDeviceId(conversation.partnerUid!);
      if (recipientDeviceId == null) throw Exception('No recipient device ID');

      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedMessage = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: '[File: $fileName]',
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedMessage = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: '[File: $fileName]',
          deviceId: recipientDeviceId,
        );
      }
    }

    if (encryptedMessage == null) throw Exception('Encryption failed');

    final response = await DeviceService.sendMessage(
      conversationId: conversation.conversationId,
      contentB64: encryptedMessage,
    );

    final messageId = response['message_id'];
    if (messageId == null) throw Exception('Failed to create message');

    // Step 2: Read file bytes
    final fileBytes = await file.readAsBytes();

    // Step 3: Encrypt file with AES
    final encryptionResult = FileService.encryptWithAES(data: fileBytes);
    final encryptedFileData = encryptionResult['encryptedData'] as Uint8List;
    final aesKey = encryptionResult['key'] as Uint8List;
    final aesIv = encryptionResult['iv'] as Uint8List;

    final aesKeyB64 = base64.encode(aesKey);
    String? encryptedAesKey;

    if (conversation.isGroup) {
      encryptedAesKey = await GroupEncryptionService.encryptGroupMessage(
        groupId: conversation.conversationId.toString(),
        plaintext: aesKeyB64,
      );
    } else {
      bool hasValidSession = await SignalService.isSessionValidForSending(
        recipientUid: conversation.partnerUid!,
        deviceId: recipientDeviceId!,
      );

      if (!hasValidSession) {
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: conversation.partnerUid!,
          deviceId: recipientDeviceId,
        );
        if (prekeyBundle == null) throw Exception('No prekey bundle');

        encryptedAesKey = await SignalService.encryptMessageWithSessionSetup(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          prekeyBundle: prekeyBundle,
          deviceId: recipientDeviceId,
        );
      } else {
        encryptedAesKey = await SignalService.encryptMessage(
          recipientUid: conversation.partnerUid!,
          plaintext: aesKeyB64,
          deviceId: recipientDeviceId!,
        );
      }
    }

    if (encryptedAesKey == null) throw Exception('Failed to encrypt AES key');

    // Step 4: Upload file
    final result = await FileService.uploadEncryptedFile(
      encryptedData: encryptedFileData,
      messageId: messageId,
      conversationId: conversation.conversationId,
      fileType: 'file',
      mimeType: mimeType,
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
    );

    if (result == null) throw Exception('Failed to upload file');

    final attachmentId = result['attachment_id'] as int;

    // Step 5: Save message to database
    final message = Message(
      id: messageId,
      conversationId: conversation.conversationId,
      username: currentUserName,
      content: '[File: $fileName]',
      timestamp: DateTime.now().toUtc(),
      senderUid: currentUserUid,
      status: MessageStatus.sent,
      encryptedContent: encryptedMessage,
      isEncrypted: true,
      senderDeviceId: myDeviceId,
      recipientDeviceId: recipientDeviceId,
      hasAttachment: true,
      attachmentId: attachmentId,
      attachmentType: 'file',
      mediaEncryptionKey: encryptedAesKey,
      mediaEncryptionIv: base64.encode(aesIv),
      senderMediaEncryptionKey: aesKeyB64,
      encryptedMediaKey: encryptedAesKey,
      mediaEncryptionType: conversation.isGroup ? 'sender_keys' : 'signal',
      mediaRecipientUid: conversation.isGroup ? null : conversation.partnerUid,
      mediaRecipientDeviceId: conversation.isGroup ? null : recipientDeviceId,
      mediaGroupId: conversation.isGroup
          ? conversation.conversationId.toString()
          : null,
      mediaSenderUid: currentUserUid,
      mediaSenderDeviceId: myDeviceId,
    );

    await dbService.insertMessage(message);
    debugPrint(
      '[SharePicker] File "$fileName" sent to ${conversation.chatTitle}',
    );
  }

  Future<int?> _getRecipientDeviceId(String recipientUid) async {
    try {
      final deviceId = await DeviceService.getActiveDeviceId(recipientUid);
      debugPrint(
        '[SharePicker] Got active device ID: $deviceId for user $recipientUid',
      );
      return deviceId;
    } catch (e) {
      debugPrint('[SharePicker] Error getting recipient device ID: $e');
      return null;
    }
  }

  // Copy content URI to temporary file
  Future<File> _copyContentUriToTempFile(String contentUri) async {
    try {
      // Use platform channel to read content URI
      const platform = MethodChannel('com.zarq/share');

      final result = await platform.invokeMethod('readContentUri', {
        'uri': contentUri,
      });

      if (result == null || result['data'] == null) {
        throw Exception('Failed to read content URI');
      }

      // Get file data and filename
      final Uint8List fileData = result['data'] as Uint8List;
      final String? fileName = result['fileName'] as String?;

      // Create temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFileName = fileName ?? 'shared_image_$timestamp.jpg';
      final tempFile = File(path.join(tempDir.path, tempFileName));

      // Write data to temp file
      await tempFile.writeAsBytes(fileData);

      debugPrint(
        '[SharePicker] Copied ${fileData.length} bytes to ${tempFile.path}',
      );

      return tempFile;
    } catch (e) {
      debugPrint('[SharePicker] Error copying content URI: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '📱 [SharePicker] Building screen, selected: ${_selectedConversationIds.length}',
    );

    return Consumer<UserSettingsProvider>(
      builder: (context, userSettings, child) {
        // Get theme (exact same as HomeScreen)
        final isDarkTheme = userSettings.isDarkMode;

        // Responsive sizing (exact same as HomeScreen)
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final searchPadding = EdgeInsets.fromLTRB(
          screenWidth * 0.04,
          screenHeight * 0.01,
          screenWidth * 0.04,
          screenHeight * 0.01,
        );
        final searchFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
        final searchIconSize = (screenWidth * 0.06).clamp(20.0, 26.0);
        final titleFontSize = (screenWidth * 0.05).clamp(18.0, 24.0);

        // Theme colors (exact same as HomeScreen)
        final Color searchBgColor = isDarkTheme
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFF0F2F5);
        final Color searchTextColor = isDarkTheme
            ? Colors.white
            : Colors.black87;
        final Color searchHintColor = isDarkTheme
            ? Colors.grey.shade400
            : Colors.grey.shade500;
        final Color searchIconColor = isDarkTheme
            ? Colors.grey.shade400
            : Colors.grey.shade600;
        final Color noResultsColor = isDarkTheme
            ? Colors.grey.shade400
            : Colors.grey.shade600;
        final Color textColor = isDarkTheme ? Colors.white : Colors.black87;
        final Color iconColor = isDarkTheme ? Colors.white : Colors.black87;
        final Color appBarBgColor = isDarkTheme
            ? const Color(0xFF0a1128)
            : Colors.white;

        return Scaffold(
          backgroundColor: isDarkTheme ? const Color(0xFF121212) : Colors.white,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: Container(
              decoration: BoxDecoration(color: appBarBgColor),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                titleTextStyle: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: titleFontSize,
                    ),
                iconTheme: IconThemeData(color: iconColor),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getShareDescription(),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: titleFontSize,
                      ),
                    ),
                    if (_selectedConversationIds.isNotEmpty)
                      Text(
                        '${_selectedConversationIds.length} selected',
                        style: TextStyle(
                          fontSize: titleFontSize * 0.5,
                          fontWeight: FontWeight.normal,
                          color: textColor.withOpacity(0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar (exact same styling as HomeScreen)
              Padding(
                padding: searchPadding,
                child: Container(
                  decoration: BoxDecoration(
                    color: searchBgColor,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: Colors.transparent),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: searchTextColor,
                      fontSize: searchFontSize,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search chats...',
                      hintStyle: TextStyle(
                        color: searchHintColor,
                        fontSize: searchFontSize,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: searchIconColor,
                        size: searchIconSize,
                      ),
                      suffixIcon: _isSearching
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: searchIconColor,
                                size: searchIconSize,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                FocusScope.of(context).unfocus();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.05,
                        vertical: screenHeight * 0.017,
                      ),
                    ),
                  ),
                ),
              ),

              // Conversations list
              Expanded(
                child: Consumer<HomeProvider>(
                  builder: (context, homeProvider, child) {
                    final conversations = _isSearching
                        ? _filteredConversations
                        : homeProvider.conversations;

                    if (homeProvider.state == HomeState.Loading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (conversations.isEmpty) {
                      return Center(
                        child: Text(
                          _isSearching
                              ? "No results found for '${_searchController.text}'"
                              : "You have no conversations yet.",
                          style: TextStyle(
                            color: noResultsColor,
                            fontSize: searchFontSize,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        return _buildConversationTile(
                          conversation,
                          isDarkTheme,
                          screenWidth,
                          screenHeight,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: _selectedConversationIds.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _isSending ? null : _sendToSelectedConversations,
                  backgroundColor: _isSending ? Colors.grey : Colors.green,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                  label: Text(
                    _isSending
                        ? 'Sending...'
                        : 'Send to ${_selectedConversationIds.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildConversationTile(
    ConversationInfo conversation,
    bool isDarkTheme,
    double screenWidth,
    double screenHeight,
  ) {
    final isSelected = _selectedConversationIds.contains(
      conversation.conversationId,
    );

    // Responsive sizing (exact same as HomeScreen)
    final listItemMargin = EdgeInsets.symmetric(
      horizontal: screenWidth * 0.03,
      vertical: screenHeight * 0.008,
    );
    final listItemTitleSize = (screenWidth * 0.04).clamp(14.0, 18.0);

    // Theme colors (exact same as HomeScreen)
    final Color cardBgColor = isDarkTheme
        ? const Color(0xFF1E1E1E)
        : Colors.lightBlue[50]!;
    final Color cardBorderColor = isDarkTheme
        ? Colors.cyanAccent.withOpacity(0.3)
        : Colors.lightBlue[200]!;
    final Color titleColor = isDarkTheme ? Colors.white : Colors.black;

    return Container(
      margin: listItemMargin,
      decoration: BoxDecoration(
        color: isSelected
            ? (isDarkTheme ? Colors.green.withOpacity(0.3) : Colors.green[100])
            : cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.green : cardBorderColor,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  conversation.avatarUrl != null &&
                      conversation.avatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(conversation.avatarUrl!)
                  : null,
              child:
                  conversation.avatarUrl == null ||
                      conversation.avatarUrl!.isEmpty
                  ? Text(
                      conversation.chatTitle.isNotEmpty
                          ? conversation.chatTitle[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            // Green checkmark overlay when selected (like create group screen)
            if (isSelected)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
        title: Text(
          conversation.chatTitle,
          style: TextStyle(
            color: isSelected
                ? (isDarkTheme ? Colors.green[300] : Colors.green[900])
                : titleColor,
            fontWeight: FontWeight.bold,
            fontSize: listItemTitleSize,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          conversation.isGroup ? 'Group' : 'Private Chat',
          style: TextStyle(
            fontSize: listItemTitleSize * 0.875, // Slightly smaller than title
            color: isSelected
                ? (isDarkTheme ? Colors.green[300] : Colors.green[700])
                : (isDarkTheme ? Colors.grey[400] : Colors.grey[600]),
          ),
        ),
        onTap: () {
          debugPrint(
            '🟡 [SharePicker] ListTile.onTap fired: ${conversation.chatTitle}',
          );
          _toggleConversationSelection(conversation);
        },
      ),
    );
  }
}
