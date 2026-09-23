import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_config.dart';
import '../home_screen.dart' show ConversationInfo;
import '../message_model.dart';
import '../models/chat_payloads.dart';
import '../providers/chat_provider.dart';
import '../services/SignalService.dart';
import '../services/global_call_manager.dart';
import '../services/user_settings_provider.dart';
import '../widgets/call_aware_screen.dart';
import '../widgets/opaque_chat_surfaces.dart';
import '../widgets/opaque_design.dart';
import '../widgets/opaque_toast.dart';
import '../services/safety_number_service.dart';

class ProfileInfoScreen extends StatefulWidget {
  final ConversationInfo conversationInfo;
  final String? recipientUid;
  final String? recipientAvatarUrl;
  final String? recipientUsername;
  final String? recipientDisplayName;
  final bool isRecipientOnline;
  final DateTime? recipientLastSeen;
  final bool isUserBlocked;
  final bool isNotificationsMuted;
  final WebSocketChannel? channel;
  final ValueChanged<bool>? onBlockChanged;
  final ValueChanged<bool>? onMuteChanged;
  final VoidCallback? onStartVoiceCall;
  final VoidCallback? onStartVideoCall;
  final VoidCallback? onClearChat;
  final VoidCallback? onSearchChat;
  final bool autoOpenSafetyNumberDialog;
  final String? recipientIdentityKey;

  const ProfileInfoScreen({
    super.key,
    required this.conversationInfo,
    this.recipientUid,
    this.recipientAvatarUrl,
    this.recipientUsername,
    this.recipientDisplayName,
    this.isRecipientOnline = false,
    this.recipientLastSeen,
    this.isUserBlocked = false,
    this.isNotificationsMuted = false,
    this.channel,
    this.onBlockChanged,
    this.onMuteChanged,
    this.onStartVoiceCall,
    this.onStartVideoCall,
    this.onClearChat,
    this.onSearchChat,
    this.autoOpenSafetyNumberDialog = false,
    this.recipientIdentityKey,
  });

  @override
  State<ProfileInfoScreen> createState() => _ProfileInfoScreenState();
}

class _ProfileInfoScreenState extends State<ProfileInfoScreen> {
  bool _isLoading = true;
  String? _resolvedUid;
  String _username = '';
  String _displayName = '';
  String? _avatarUrl;
  String? _phoneNumber;
  DateTime? _createdAt;
  bool _isFriend = false;
  bool _hasSentRequest = false;
  bool _hasReceivedRequest = false;
  late bool _isBlocked;
  late bool _isMuted;
  bool _hasSession = false;
  int _activeContentTab = 0; // 0: Media, 1: Docs, 2: Links, 3: Audio

  String? _localIdentityKey;
  String? _remoteIdentityKey;
  SafetyNumberResult? _safetyNumberResult;
  Future<void>? _loadSafetyNumberFuture;

  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _isBlocked = widget.isUserBlocked;
    _isMuted = widget.isNotificationsMuted;
    _resolvedUid = widget.recipientUid ?? widget.conversationInfo.partnerUid;
    _username = (widget.recipientUsername ?? widget.conversationInfo.username ?? '').trim();
    _displayName = (widget.recipientDisplayName ?? widget.conversationInfo.chatTitle).trim();
    _avatarUrl = widget.recipientAvatarUrl ?? widget.conversationInfo.avatarUrl;
    _phoneNumber = widget.conversationInfo.phoneNumber;
    _isFriend = widget.conversationInfo.isFriend;
    _remoteIdentityKey = widget.recipientIdentityKey;

    _checkSession();
    _loadSafetyNumber();
    _fetchUserProfile();

    if (widget.autoOpenSafetyNumberDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await (_loadSafetyNumberFuture ?? _loadSafetyNumber());
        if (mounted) {
          _showSafetyNumberDialog(OpaqueColors(context));
        }
      });
    }
  }

  Future<void> _loadSafetyNumber() {
    _loadSafetyNumberFuture = _doLoadSafetyNumber();
    return _loadSafetyNumberFuture!;
  }

  Future<void> _doLoadSafetyNumber() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'me';
    var partnerUid = _resolvedUid ?? _username;

    // 1. Get our local Signal Identity Key
    _localIdentityKey ??= await SignalService.getIdentityKey();

    // 2. If remote key is not yet known, fetch from server profile first
    if (_remoteIdentityKey == null || _remoteIdentityKey!.isEmpty) {
      final uid = _resolvedUid;
      final uname = _username;
      if ((uid != null && uid.isNotEmpty) || uname.isNotEmpty) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final token = await user.getIdToken();
            final uri = (uid != null && uid.isNotEmpty)
                ? Uri.parse('${AppConfig.baseUrl}/profiles/user/$uid')
                : Uri.parse('${AppConfig.baseUrl}/profiles/user?username=${Uri.encodeComponent(uname)}');
            final resp = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 5));
            if (resp.statusCode == 200) {
              final data = json.decode(resp.body) as Map<String, dynamic>;
              if (data['uid'] != null && (_resolvedUid == null || _resolvedUid!.isEmpty)) {
                _resolvedUid = data['uid'] as String?;
                partnerUid = _resolvedUid ?? partnerUid;
              }
              final key = data['identity_key_b64'] as String?;
              if (key != null && key.isNotEmpty) {
                _remoteIdentityKey = key;
              }
            }
          }
        } catch (_) {}
      }

      // Fallback to local native store only if server is unreachable
      if ((_remoteIdentityKey == null || _remoteIdentityKey!.isEmpty) &&
          _resolvedUid != null &&
          _resolvedUid!.isNotEmpty) {
        _remoteIdentityKey = await SignalService.getRemoteIdentityKey(_resolvedUid!);
      }
    }

    // 3. Compute deterministic Safety Number and check status
    final result = await SafetyNumberService.getSafetyNumber(
      localUid: myUid,
      localKeyB64: _localIdentityKey,
      remoteUid: _resolvedUid ?? partnerUid,
      remoteKeyB64: _remoteIdentityKey,
    );

    if (mounted) {
      setState(() {
        _safetyNumberResult = result;
      });
    }
  }

  Future<void> _checkSession() async {
    final uid = _resolvedUid;
    if (uid == null || uid.isEmpty) return;
    try {
      final valid = await SignalService.hasSession(recipientUid: uid);
      if (mounted) {
        setState(() {
          _hasSession = valid;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = _resolvedUid;
    final uname = _username;

    if (user == null || ((uid == null || uid.isEmpty) && uname.isEmpty)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final token = await user.getIdToken();
      final uri = (uid != null && uid.isNotEmpty)
          ? Uri.parse('${AppConfig.baseUrl}/profiles/user/$uid')
          : Uri.parse('${AppConfig.baseUrl}/profiles/user?username=${Uri.encodeComponent(uname)}');

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _resolvedUid = (data['uid'] as String?) ?? _resolvedUid;
          if ((data['username'] as String?)?.isNotEmpty == true) {
            _username = data['username'];
          }
          if ((data['display_name'] as String?)?.isNotEmpty == true) {
            _displayName = data['display_name'];
          }
          if (data['avatarUrl'] != null && (data['avatarUrl'] as String).isNotEmpty) {
            _avatarUrl = data['avatarUrl'];
          }
          if (data['createdAt'] != null) {
            _createdAt = DateTime.tryParse(data['createdAt'] as String);
          }
          if (data['isFriend'] != null) {
            _isFriend = data['isFriend'] == true;
          }
          if (data['hasSentRequest'] != null) {
            _hasSentRequest = data['hasSentRequest'] == true;
          }
          if (data['hasReceivedRequest'] != null) {
            _hasReceivedRequest = data['hasReceivedRequest'] == true;
          }
          if (data['identity_key_b64'] != null && (data['identity_key_b64'] as String).isNotEmpty) {
            _remoteIdentityKey = data['identity_key_b64'] as String;
          }
          _isLoading = false;
        });

        // Re-check safety number and session with fresh profile data
        _loadSafetyNumber();
        if (_resolvedUid != null && !_hasSession) {
          _checkSession();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMuteNotifications() async {
    final convoId = widget.conversationInfo.conversationId;
    final newMute = !_isMuted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('muted_$convoId', newMute);
      if (mounted) {
        setState(() {
          _isMuted = newMute;
        });
        widget.onMuteChanged?.call(newMute);
        OpaqueToast.show(
          context,
          newMute ? 'Notifications muted' : 'Notifications unmuted',
        );
      }
    } catch (e) {
      if (mounted) OpaqueToast.error(context, 'Failed to update notification settings');
    }
  }

  void _showBlockConfirmation() {
    final uid = _resolvedUid;
    if (uid == null) {
      OpaqueToast.error(context, 'User ID not available');
      return;
    }

    if (_isBlocked) {
      _unblockUser();
      return;
    }

    showDialog(
      context: context,
      builder: (context) => OpaqueChatConfirmation(
        icon: Icons.block_rounded,
        title: 'Block this person?',
        description: 'You will no longer receive messages or calls from ${_displayName.isNotEmpty ? _displayName : _username}.',
        note: 'You can unblock them anytime from this profile or chat menu.',
        actionLabel: 'Block user',
        onConfirm: () async {
          Navigator.pop(context);
          await _blockUser();
        },
      ),
    );
  }

  Future<void> _blockUser() async {
    final uid = _resolvedUid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];
      if (!blockedUsers.contains(uid)) {
        blockedUsers.add(uid);
        await prefs.setStringList('blocked_users', blockedUsers);
      }
      if (mounted) {
        setState(() {
          _isBlocked = true;
        });
        widget.onBlockChanged?.call(true);
        OpaqueToast.success(context, 'User blocked');
      }
    } catch (e) {
      if (mounted) OpaqueToast.error(context, 'Failed to block user');
    }
  }

  Future<void> _unblockUser() async {
    final uid = _resolvedUid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUsers = prefs.getStringList('blocked_users') ?? [];
      blockedUsers.remove(uid);
      await prefs.setStringList('blocked_users', blockedUsers);
      if (mounted) {
        setState(() {
          _isBlocked = false;
        });
        widget.onBlockChanged?.call(false);
        OpaqueToast.success(context, 'User unblocked');
      }
    } catch (e) {
      if (mounted) OpaqueToast.error(context, 'Failed to unblock user');
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_username.isEmpty) {
      OpaqueToast.error(context, 'Username not found');
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/friends/request');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'targetUsername': _username}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          setState(() {
            _hasSentRequest = true;
          });
          OpaqueToast.success(context, 'Friend request sent');
        }
      } else {
        if (mounted) {
          OpaqueToast.error(context, 'Failed to send friend request');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Network error sending request');
    }
  }

  Future<void> _removeFriend() async {
    if (_username.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/friends/remove');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'friendUsername': _username}),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _isFriend = false;
          _hasSentRequest = false;
          _hasReceivedRequest = false;
        });
        OpaqueToast.success(context, 'Friend removed');
      } else {
        if (mounted) OpaqueToast.error(context, 'Failed to remove friend');
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error removing friend');
    }
  }

  void _showClearChatConfirmation() {
    showDialog(
      context: context,
      builder: (context) => OpaqueChatConfirmation(
        icon: Icons.delete_sweep_outlined,
        title: 'Clear this chat?',
        description: 'Remove all message history for this conversation from this device.',
        note: 'This cannot be undone. Other participants keep their copies.',
        actionLabel: 'Clear chat',
        onConfirm: () {
          Navigator.pop(context);
          widget.onClearChat?.call();
        },
      ),
    );
  }

  void _showSafetyNumberDialog(OpaqueColors c) {
    final partnerUid = _resolvedUid ?? _username;
    final partnerName = _displayName.isNotEmpty ? _displayName : _username;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (_safetyNumberResult == null && _loadSafetyNumberFuture != null) {
            _loadSafetyNumberFuture!.then((_) {
              if (sheetContext.mounted) {
                setSheetState(() {});
              }
            });
          }

          final result = _safetyNumberResult;
          final blocks = result?.blocks ??
              ((_localIdentityKey != null && _remoteIdentityKey != null)
                  ? SafetyNumberService.computeDisplayFingerprint(
                      localUid: FirebaseAuth.instance.currentUser?.uid ?? 'me',
                      localKeyB64: _localIdentityKey,
                      remoteUid: _resolvedUid ?? partnerUid,
                      remoteKeyB64: _remoteIdentityKey,
                    ).split(' ')
                  : null);
          final isVerified = result?.isVerified ?? false;
          final hasChanged = result?.hasChanged ?? false;

          final Color iconColor = hasChanged
              ? const Color(0xFFF59E0B)
              : (isVerified ? const Color(0xFF22C55E) : c.blue);
          final IconData headerIcon = hasChanged
              ? Icons.warning_amber_rounded
              : (isVerified ? Icons.verified_user_rounded : Icons.shield_rounded);

          return Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: c.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withValues(alpha: .15),
                  ),
                  child: Icon(headerIcon, color: iconColor, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  'Verify Safety Number',
                  style: c.text(18, bold: true),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your end-to-end encrypted session with $partnerName is secured by Signal Protocol.',
                  textAlign: TextAlign.center,
                  style: c.text(12, muted: true).copyWith(height: 1.5),
                ),
                if (isVerified) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Verified Safety Number',
                          style: c.text(11, bold: true).copyWith(color: const Color(0xFF22C55E)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (hasChanged) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.soft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: c.dark
                            ? const Color(0xFFD97706).withValues(alpha: 0.5)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Safety number has changed. $partnerName may have reinstalled OPAQUE or switched devices.',
                            style: c.text(11.5).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: blocks != null
                      ? Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: blocks.map((b) => Text(
                            b,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: c.ink,
                            ),
                          )).toList(),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.blue),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Calculating safety number...',
                                  style: c.text(12, muted: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink,
                          side: BorderSide(color: c.line),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: blocks == null
                            ? null
                            : () {
                                final safetyString = blocks.join(' ');
                                Clipboard.setData(ClipboardData(text: safetyString));
                                OpaqueToast.success(context, 'Safety number copied');
                              },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy number'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: isVerified
                          ? OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                await SafetyNumberService.clearVerification(partnerUid: _resolvedUid ?? partnerUid);
                                await _loadSafetyNumber();
                                setSheetState(() {});
                                if (mounted) {
                                  OpaqueToast.show(context, 'Verification cleared');
                                }
                              },
                              child: const Text('Clear Verify'),
                            )
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                await SafetyNumberService.markVerified(
                                  partnerUid: _resolvedUid ?? partnerUid,
                                  currentRemoteKeyB64: _remoteIdentityKey,
                                );
                                await _loadSafetyNumber();
                                setSheetState(() {});
                                if (mounted) {
                                  OpaqueToast.success(context, 'Safety number verified');
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Mark Verified'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text('Close', style: c.text(13, muted: true)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAvatarViewer() {
    if (_avatarUrl == null || _avatarUrl!.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(_displayName.isNotEmpty ? _displayName : _username),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () {
                  Share.share('Contact: $_displayName ($_username)\nAvatar: $_avatarUrl');
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: _avatarUrl!,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatPresence() {
    if (widget.isRecipientOnline) {
      return 'Online';
    }
    final lastSeen = widget.recipientLastSeen;
    if (lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(lastSeen);
      if (diff.inMinutes < 1) {
        return 'Last seen just now';
      } else if (diff.inHours < 1) {
        return 'Last seen ${diff.inMinutes}m ago';
      } else if (diff.inDays == 0 && now.day == lastSeen.day) {
        return 'Last seen today at ${DateFormat('HH:mm').format(lastSeen)}';
      } else if (diff.inDays <= 1) {
        return 'Last seen yesterday at ${DateFormat('HH:mm').format(lastSeen)}';
      } else {
        return 'Last seen ${DateFormat('MMM d, yyyy').format(lastSeen)}';
      }
    }
    return 'Offline';
  }

  Widget _buildAvatarWidget(double radius, OpaqueColors c) {
    final initials = (_displayName.isNotEmpty ? _displayName : _username)
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();

    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      color: c.soft,
      alignment: Alignment.center,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w600,
                color: c.blue,
              ),
            )
          : Icon(Icons.person, color: c.muted, size: radius * 0.9),
    );

    return GestureDetector(
      onTap: _openAvatarViewer,
      child: Hero(
        tag: 'profile_avatar_${widget.conversationInfo.conversationId}',
        child: Container(
          width: radius * 2,
          height: radius * 2,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.line, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _avatarUrl?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: _avatarUrl!,
                  memCacheWidth: 200,
                  memCacheHeight: 200,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => fallback,
                  errorWidget: (_, __, ___) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required OpaqueColors c,
    bool disabled = false,
  }) {
    final isClickable = onTap != null && !disabled;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isClickable ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isClickable ? c.soft : c.soft.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isClickable ? c.line : c.line.withValues(alpha: .4),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isClickable ? c.blue : c.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: c.text(11, bold: true, muted: !isClickable),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContainer({required Widget child, required OpaqueColors c}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required OpaqueColors c,
    VoidCallback? onCopy,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: c.text(10, muted: true)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: c.text(13, bold: true),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (onCopy != null)
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 16, color: c.muted),
              tooltip: 'Copy $label',
              onPressed: onCopy,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildSharedContentSection(OpaqueColors c) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final allMessages = chatProvider.messages;

    final mediaMessages = allMessages.where((m) {
      if (!m.hasAttachment) return false;
      final type = m.attachmentType?.toLowerCase();
      return type == 'image' || type == 'video';
    }).toList();

    final docMessages = allMessages.where((m) {
      if (!m.hasAttachment) return false;
      final type = m.attachmentType?.toLowerCase();
      return type == 'document' || type == 'file';
    }).toList();

    final audioMessages = allMessages.where((m) {
      if (!m.hasAttachment) return false;
      final type = m.attachmentType?.toLowerCase();
      return type == 'audio' || type == 'voice';
    }).toList();

    final List<String> links = [];
    for (final m in allMessages) {
      if (!m.hasAttachment) {
        final matches = _urlRegex.allMatches(m.content);
        for (final match in matches) {
          final url = match.group(0);
          if (url != null && !links.contains(url)) {
            links.add(url);
          }
        }
      }
    }

    final int mediaCount = mediaMessages.length;
    final int docsCount = docMessages.length;
    final int linksCount = links.length;
    final int audioCount = audioMessages.length;

    return _buildCardContainer(
      c: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.perm_media_outlined, size: 17, color: c.blue),
                const SizedBox(width: 8),
                Text('SHARED IN THIS CHAT', style: c.text(10, bold: true, muted: true).copyWith(letterSpacing: 1.1)),
                const Spacer(),
                Text('${mediaCount + docsCount + linksCount + audioCount} items', style: c.text(10, muted: true)),
              ],
            ),
          ),
          // Content Tab Switcher
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildContentTabChip(0, 'Media ($mediaCount)', c),
                _buildContentTabChip(1, 'Docs ($docsCount)', c),
                _buildContentTabChip(2, 'Links ($linksCount)', c),
                _buildContentTabChip(3, 'Audio ($audioCount)', c),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Tab Content
          if (_activeContentTab == 0)
            _buildMediaTabContent(mediaMessages, c)
          else if (_activeContentTab == 1)
            _buildDocsTabContent(docMessages, c)
          else if (_activeContentTab == 2)
            _buildLinksTabContent(links, c)
          else
            _buildAudioTabContent(audioMessages, c),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildContentTabChip(int index, String label, OpaqueColors c) {
    final selected = _activeContentTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _activeContentTab = index),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? Colors.white : c.muted,
        ),
        selectedColor: c.blue,
        backgroundColor: c.soft,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? c.blue : c.line),
        ),
      ),
    );
  }

  Widget _buildMediaTabContent(List<Message> messages, OpaqueColors c) {
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('No media shared yet', style: c.text(12, muted: true)),
        ),
      );
    }

    return SizedBox(
      height: 90,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final m = messages[index];
          final isVideo = m.attachmentType == 'video';
          return Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                  color: c.muted,
                  size: 28,
                ),
                if (isVideo)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: .5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocsTabContent(List<Message> messages, OpaqueColors c) {
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('No documents shared yet', style: c.text(12, muted: true)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      itemCount: math.min(messages.length, 4),
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (context, index) {
        final m = messages[index];
        final rawName = m.content.replaceFirst('📄 ', '').replaceFirst('?? ', '').trim();
        final fileName = rawName.isNotEmpty && rawName != 'This message was deleted'
            ? rawName
            : 'Document ${m.id}';
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.insert_drive_file_rounded, color: c.blue, size: 18),
          ),
          title: Text(fileName, style: c.text(12, bold: true), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            DateFormat('MMM d, yyyy').format(m.timestamp),
            style: c.text(10, muted: true),
          ),
        );
      },
    );
  }

  Widget _buildLinksTabContent(List<String> links, OpaqueColors c) {
    if (links.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('No links shared yet', style: c.text(12, muted: true)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      itemCount: math.min(links.length, 4),
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (context, index) {
        final link = links[index];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.link_rounded, color: c.blue, size: 18),
          ),
          title: Text(link, style: c.text(12, bold: true), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.open_in_new_rounded, size: 15, color: c.muted),
          onTap: () async {
            final uri = Uri.tryParse(link);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        );
      },
    );
  }

  Widget _buildAudioTabContent(List<Message> messages, OpaqueColors c) {
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text('No audio messages shared yet', style: c.text(12, muted: true)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      itemCount: math.min(messages.length, 4),
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (context, index) {
        final m = messages[index];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.mic_rounded, color: c.blue, size: 18),
          ),
          title: Text('Voice Message', style: c.text(12, bold: true)),
          subtitle: Text(DateFormat('MMM d, yyyy · HH:mm').format(m.timestamp), style: c.text(10, muted: true)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final c = OpaqueColors(context);
    final isOnline = widget.isRecipientOnline;

    return CallAwareScreen(
      screenName: 'ProfileInfoScreen',
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          foregroundColor: c.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Contact info', style: c.text(18, bold: true)),
          centerTitle: true,
          actions: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: c.ink),
              color: c.surface,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.line),
              ),
              onSelected: (val) {
                if (val == 'share') {
                  Share.share('Contact: $_displayName (@$_username)');
                } else if (val == 'search') {
                  Navigator.pop(context);
                  widget.onSearchChat?.call();
                } else if (val == 'clear') {
                  _showClearChatConfirmation();
                } else if (val == 'block') {
                  _showBlockConfirmation();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 17, color: c.ink),
                      const SizedBox(width: 10),
                      Text('Share contact', style: c.text(13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 17, color: c.ink),
                      const SizedBox(width: 10),
                      Text('Search in chat', style: c.text(13)),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_sweep_outlined, size: 17, color: Colors.red),
                      const SizedBox(width: 10),
                      Text('Clear chat', style: c.text(13).copyWith(color: Colors.red)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        _isBlocked ? Icons.check_circle_outline : Icons.block_rounded,
                        size: 17,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isBlocked ? 'Unblock contact' : 'Block contact',
                        style: c.text(13).copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: c.line),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ─── HERO AVATAR & NAME ───
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                  child: Column(
                    children: [
                      _buildAvatarWidget(50, c),
                      const SizedBox(height: 14),
                      Text(
                        _displayName.isNotEmpty ? _displayName : _username,
                        textAlign: TextAlign.center,
                        style: c.text(22, bold: true).copyWith(letterSpacing: -.6),
                      ),
                      if (_username.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: '@$_username'));
                            OpaqueToast.success(context, 'Username copied');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.soft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.line),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('@$_username', style: c.text(12, bold: true).copyWith(color: c.blue)),
                                const SizedBox(width: 4),
                                Icon(Icons.copy_rounded, size: 12, color: c.muted),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Presence status indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF22C55E).withValues(alpha: .12) : c.soft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? const Color(0xFF22C55E) : c.muted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatPresence(),
                              style: c.text(11, muted: !isOnline).copyWith(
                                color: isOnline ? const Color(0xFF22C55E) : null,
                                fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── QUICK ACTION BAR ───
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickActionItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message',
                        onTap: () => Navigator.pop(context),
                        c: c,
                      ),
                      Consumer<GlobalCallManager>(
                        builder: (context, callManager, _) => _buildQuickActionItem(
                          icon: Icons.call_outlined,
                          label: 'Audio',
                          disabled: callManager.isInCall || _isBlocked,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onStartVoiceCall?.call();
                          },
                          c: c,
                        ),
                      ),
                      Consumer<GlobalCallManager>(
                        builder: (context, callManager, _) => _buildQuickActionItem(
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          disabled: callManager.isInCall || _isBlocked,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onStartVideoCall?.call();
                          },
                          c: c,
                        ),
                      ),
                      _buildQuickActionItem(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSearchChat?.call();
                        },
                        c: c,
                      ),
                    ],
                  ),
                ),

                if (_safetyNumberResult?.hasChanged == true) ...[
                  _buildCardContainer(
                    c: c,
                    child: InkWell(
                      onTap: () => _showSafetyNumberDialog(c),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: c.dark
                                ? const Color(0xFFD97706).withValues(alpha: 0.5)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.dark
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                                    : const Color(0xFFFEF3C7),
                              ),
                              child: const Icon(
                                Icons.security_update_warning_rounded,
                                color: Color(0xFFD97706),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Safety Number Changed',
                                    style: c.text(14, bold: true),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'The encryption key for this contact has changed. Tap to verify the new safety number.',
                                    style: c.text(11.5, muted: true).copyWith(height: 1.45),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: c.dark
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: c.dark
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                      : const Color(0xFFFCD34D),
                                ),
                              ),
                              child: Text(
                                'Verify',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.dark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),

                // ─── USER DETAILS CARD ───
                _buildCardContainer(
                  c: c,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(
                          'INFO',
                          style: c.text(10, bold: true, muted: true).copyWith(letterSpacing: 1.1),
                        ),
                      ),
                      if (_username.isNotEmpty)
                        _buildInfoRow(
                          icon: Icons.alternate_email_rounded,
                          label: 'Username',
                          value: '@$_username',
                          c: c,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: '@$_username'));
                            OpaqueToast.success(context, 'Username copied');
                          },
                        ),
                      if (_displayName.isNotEmpty && _displayName != _username) ...[
                        Divider(height: 1, color: c.line, indent: 48),
                        _buildInfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Display Name',
                          value: _displayName,
                          c: c,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: _displayName));
                            OpaqueToast.success(context, 'Display name copied');
                          },
                        ),
                      ],
                      if (_phoneNumber != null && _phoneNumber!.isNotEmpty) ...[
                        Divider(height: 1, color: c.line, indent: 48),
                        _buildInfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone Number',
                          value: _phoneNumber!,
                          c: c,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: _phoneNumber!));
                            OpaqueToast.success(context, 'Phone number copied');
                          },
                        ),
                      ],
                      if (_createdAt != null) ...[
                        Divider(height: 1, color: c.line, indent: 48),
                        _buildInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Member since',
                          value: DateFormat('MMMM yyyy').format(_createdAt!),
                          c: c,
                        ),
                      ],
                      Divider(height: 1, color: c.line, indent: 48),
                      // Friendship status row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.people_outline_rounded, size: 18, color: c.muted),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Relationship', style: c.text(10, muted: true)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isFriend
                                        ? 'Friends'
                                        : _hasSentRequest
                                            ? 'Friend Request Sent'
                                            : _hasReceivedRequest
                                                ? 'Incoming Friend Request'
                                                : 'Not in friends list',
                                    style: c.text(13, bold: true),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isFriend && !_hasSentRequest && !_hasReceivedRequest)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: c.blue,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _sendFriendRequest,
                                icon: const Icon(Icons.person_add_outlined, size: 15),
                                label: const Text('Add'),
                              )
                            else if (_isFriend)
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _removeFriend,
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── SECURITY & ENCRYPTION CARD ───
                _buildCardContainer(
                  c: c,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF22C55E), size: 20),
                        ),
                        title: Text('End-to-End Encrypted', style: c.text(13, bold: true)),
                        subtitle: Text(
                          'Messages and calls are secured with Signal Protocol. Neither OPAQUE nor third parties can read them.',
                          style: c.text(11, muted: true).copyWith(height: 1.4),
                        ),
                      ),
                      Divider(height: 1, color: c.line, indent: 16, endIndent: 16),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        leading: Icon(
                          _safetyNumberResult?.hasChanged == true
                              ? Icons.warning_amber_rounded
                              : (_safetyNumberResult?.isVerified == true
                                  ? Icons.verified_user_rounded
                                  : (_hasSession ? Icons.shield_rounded : Icons.shield_outlined)),
                          color: _safetyNumberResult?.hasChanged == true
                              ? const Color(0xFFF59E0B)
                              : (_safetyNumberResult?.isVerified == true
                                  ? const Color(0xFF22C55E)
                                  : (_hasSession ? const Color(0xFF22C55E) : c.blue)),
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Text('Verify Safety Number', style: c.text(13, bold: true)),
                            if (_safetyNumberResult?.isVerified == true) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Verified',
                                  style: c.text(10, bold: true).copyWith(color: const Color(0xFF22C55E)),
                                ),
                              ),
                            ] else if (_safetyNumberResult?.hasChanged == true) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Changed',
                                  style: c.text(10, bold: true).copyWith(color: const Color(0xFFF59E0B)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          _safetyNumberResult?.hasChanged == true
                              ? 'Safety number has changed • Tap to inspect'
                              : (_safetyNumberResult?.isVerified == true
                                  ? 'Verified cryptographic safety number'
                                  : (_hasSession ? 'Active Signal E2EE Session' : 'Tap to inspect safety numbers')),
                          style: c.text(11, muted: _safetyNumberResult?.hasChanged != true).copyWith(
                            color: _safetyNumberResult?.hasChanged == true ? const Color(0xFFF59E0B) : null,
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
                        onTap: () => _showSafetyNumberDialog(c),
                      ),
                    ],
                  ),
                ),

                // ─── SHARED MEDIA & CONTENT SECTION ───
                _buildSharedContentSection(c),

                // ─── CHAT SETTINGS CARD ───
                _buildCardContainer(
                  c: c,
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        secondary: Icon(
                          _isMuted ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                          color: _isMuted ? c.muted : c.blue,
                          size: 20,
                        ),
                        title: Text('Mute notifications', style: c.text(13, bold: true)),
                        subtitle: Text(
                          _isMuted ? 'Notifications are turned off for this chat' : 'Play sounds and show alerts',
                          style: c.text(11, muted: true),
                        ),
                        value: _isMuted,
                        activeColor: c.blue,
                        onChanged: (_) => _toggleMuteNotifications(),
                      ),
                    ],
                  ),
                ),

                // ─── DANGER ZONE ACTIONS ───
                _buildCardContainer(
                  c: c,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 20),
                        title: Text('Clear chat history', style: c.text(13, bold: true).copyWith(color: Colors.red)),
                        subtitle: Text('Deletes messages on this device only', style: c.text(11, muted: true)),
                        onTap: _showClearChatConfirmation,
                      ),
                      Divider(height: 1, color: c.line, indent: 16, endIndent: 16),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        leading: Icon(
                          _isBlocked ? Icons.check_circle_outline : Icons.block_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                        title: Text(
                          _isBlocked ? 'Unblock user' : 'Block user',
                          style: c.text(13, bold: true).copyWith(color: Colors.red),
                        ),
                        subtitle: Text(
                          _isBlocked
                              ? 'Allow receiving messages and calls'
                              : 'Block incoming messages and calls from this user',
                          style: c.text(11, muted: true),
                        ),
                        onTap: _showBlockConfirmation,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
