import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../app_config.dart';
import '../chat_screen.dart';
import '../home_screen.dart';
import '../providers/home_provider.dart';
import '../services/user_settings_provider.dart';
import '../services/websocket_service.dart';
import '../widgets/backup_design.dart';
import '../widgets/call_aware_screen.dart';
import '../widgets/notes_design.dart';
import '../widgets/opaque_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class GroupMember {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? displayName;
  final String role;
  final DateTime joinedAt;

  GroupMember({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.displayName,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      uid: json['uid'] ?? '',
      username: json['username'] ?? 'Unknown',
      avatarUrl: json['avatarUrl'],
      displayName: json['displayName'],
      role: json['role'] ?? 'member',
      joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get displayNameOrUsername =>
      displayName?.trim().isNotEmpty == true ? displayName! : username;
}

class GroupInfo {
  final int conversationId;
  final String groupName;
  final String? description;
  final String creatorUid;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GroupMember> members;

  GroupInfo({
    required this.conversationId,
    required this.groupName,
    this.description,
    required this.creatorUid,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.members,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> json) {
    return GroupInfo(
      conversationId: json['conversationId'] ?? 0,
      groupName: json['groupName'] ?? 'Unnamed Group',
      description: json['description'],
      creatorUid: json['creatorUid'] ?? '',
      avatarUrl: json['avatarUrl'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      members: (json['members'] as List?)
              ?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class GroupInfoScreen extends StatefulWidget {
  final int groupId;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  GroupInfo? _groupInfo;
  bool _isLoading = true;
  String? _currentUserUid;
  String? _currentUserRole;
  final TextEditingController _memberSearchController = TextEditingController();
  final FocusNode _memberSearchFocusNode = FocusNode();
  String _memberSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    _fetchGroupInfo();
    _memberSearchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _memberSearchQuery = _memberSearchController.text.trim();
      });
    }
  }

  @override
  void dispose() {
    _memberSearchController.dispose();
    _memberSearchFocusNode.dispose();
    super.dispose();
  }

  // ─── API Methods ──────────────────────────────────────────────────────────

  Future<void> _fetchGroupInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/info');
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final groupInfo = GroupInfo.fromJson(data);

        final currentMember = groupInfo.members.firstWhere(
          (m) => m.uid == _currentUserUid,
          orElse: () => GroupMember(
            uid: '',
            username: '',
            role: 'member',
            joinedAt: DateTime.now(),
          ),
        );

        setState(() {
          _groupInfo = groupInfo;
          _currentUserRole = currentMember.role;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          OpaqueToast.error(context, 'Failed to load group info');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        OpaqueToast.error(context, 'Error loading group info');
      }
    }
  }

  bool _canManageMembers() =>
      _currentUserRole == 'owner' || _currentUserRole == 'admin';

  bool _canRemoveMember(GroupMember member) {
    if (!_canManageMembers()) return false;
    if (member.uid == _currentUserUid) return false;
    if (member.role == 'owner') return false;
    if (member.role == 'admin' && _currentUserRole != 'owner') return false;
    return true;
  }

  bool _canChangeRole(GroupMember member) {
    if (_currentUserRole != 'owner') return false;
    if (member.uid == _currentUserUid) return false;
    if (member.role == 'owner') return false;
    return true;
  }

  Future<void> _removeMember(String memberUid, String memberUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/members/remove');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'memberUid': memberUid}),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          OpaqueToast.success(context, 'Removed @$memberUsername');
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to remove member');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error removing member');
    }
  }

  Future<void> _confirmRemoveMember(GroupMember member) async {
    final confirmed = await showNotesConfirmation(
      context,
      title: 'Remove member?',
      body: 'Remove ${member.displayNameOrUsername} (@${member.username}) from this group?',
      confirm: 'Remove',
      danger: true,
      icon: Icons.person_remove_outlined,
    );

    if (confirmed) {
      await _removeMember(member.uid, member.username);
    }
  }

  Future<void> _changeRole(
      String memberUid, String newRole, String memberUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/members/role');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'memberUid': memberUid,
          'newRole': newRole,
        }),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          OpaqueToast.success(
            context,
            newRole == 'admin'
                ? '@$memberUsername is now an Admin'
                : '@$memberUsername is now a Member',
          );
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to change role');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error changing role');
    }
  }

  Future<void> _updateGroupInfo(String newName, String newDescription) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/update');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'groupName': newName.trim(),
          'description': newDescription.trim(),
        }),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          OpaqueToast.success(context, 'Group details updated');
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to update group info');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error updating group info');
    }
  }

  Future<void> _leaveGroup() async {
    if (_currentUserRole == 'owner') {
      OpaqueToast.warning(
        context,
        'Group owner cannot leave. Transfer ownership or delete the group.',
      );
      return;
    }

    final confirmed = await showNotesConfirmation(
      context,
      title: 'Leave group?',
      body: 'Are you sure you want to leave "${_groupInfo?.groupName}"? You will stop receiving messages.',
      confirm: 'Leave',
      danger: true,
      icon: Icons.exit_to_app_rounded,
    );

    if (!confirmed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/leave');
      final response = await http.post(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mounted) {
        if (response.statusCode == 200) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          OpaqueToast.error(context, 'Failed to leave group');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error leaving group');
    }
  }

  Future<void> _deleteGroup() async {
    if (_currentUserRole != 'owner') return;

    final confirmed = await showNotesConfirmation(
      context,
      title: 'Delete group?',
      body: 'Permanently delete "${_groupInfo?.groupName}" and all its messages for all ${_groupInfo?.members.length ?? 0} members? This action cannot be undone.',
      confirm: 'Delete group',
      danger: true,
      icon: Icons.delete_forever_outlined,
    );

    if (!confirmed) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}');
      final response = await http.delete(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mounted) {
        if (response.statusCode == 200) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          OpaqueToast.error(context, 'Failed to delete group');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error deleting group');
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 600,
        maxHeight: 600,
      );

      if (pickedFile == null) return;

      if (!mounted) return;
      OpaqueToast.info(context, 'Uploading photo...');

      final oldAvatarUrl = _groupInfo?.avatarUrl;
      if (oldAvatarUrl != null &&
          oldAvatarUrl.contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(oldAvatarUrl).delete();
        } catch (_) {}
      }

      final avatarId = const Uuid().v4();
      final storageRef =
          FirebaseStorage.instance.ref().child('group_avatars/$avatarId.jpg');
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      );

      String downloadUrl;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        final uploadTask = storageRef.putData(bytes, metadata);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        final file = File(pickedFile.path);
        final uploadTask = storageRef.putFile(file, metadata);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      final token = await user.getIdToken();
      final updateUrl =
          Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/avatar');
      final updateResponse = await http.post(
        updateUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatarUrl': downloadUrl}),
      );

      if (mounted) {
        if (updateResponse.statusCode == 200) {
          OpaqueToast.success(context, 'Group photo updated');
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to update avatar');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error uploading photo');
    }
  }

  Future<void> _removeGroupAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final oldAvatarUrl = _groupInfo?.avatarUrl;
      if (oldAvatarUrl != null &&
          oldAvatarUrl.contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(oldAvatarUrl).delete();
        } catch (_) {}
      }

      final token = await user.getIdToken();
      final updateUrl =
          Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/avatar');
      final updateResponse = await http.post(
        updateUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatarUrl': null}),
      );

      if (mounted) {
        if (updateResponse.statusCode == 200) {
          OpaqueToast.success(context, 'Photo removed');
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to remove photo');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error removing photo');
    }
  }

  Future<void> _openConversation(GroupMember member) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final websocketService =
          Provider.of<WebSocketService>(context, listen: false);
      if (!websocketService.isConnected || websocketService.channel == null) {
        OpaqueToast.info(context, 'Connecting... Please wait a moment.');
        return;
      }

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/conversations/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': member.username}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final conversationId = data['conversationId'] as int;

        final conversation = ConversationInfo(
          conversationId: conversationId,
          chatTitle: member.displayNameOrUsername,
          isGroup: false,
          partnerUid: member.uid,
          avatarUrl: member.avatarUrl,
        );

        if (!mounted) return;
        Provider.of<HomeProvider>(context, listen: false)
            .fetchInitialConversations();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              channel: websocketService.channel!,
              conversationInfo: conversation,
            ),
          ),
        );
      } else {
        if (mounted) OpaqueToast.error(context, 'Failed to open conversation');
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error opening conversation');
    }
  }

  Future<void> _sendFriendRequest(GroupMember member) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/friends/request');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': member.username}),
      );

      if (mounted) {
        if (response.statusCode == 201) {
          OpaqueToast.success(
              context, 'Friend request sent to @${member.username}');
        } else {
          OpaqueToast.error(context, 'Failed to send friend request');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error sending friend request');
    }
  }

  // ─── Modal Sheets & Dialogs ───────────────────────────────────────────────

  void _showAvatarPickerSheet() {
    final c = NotesColors(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: c.line)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Group photo', style: c.text(16, bold: true)),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: c.blue),
                title: Text('Choose from Gallery', style: c.text(14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: c.blue),
                title: Text('Take Photo', style: c.text(14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              if (_groupInfo?.avatarUrl?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    'Remove Photo',
                    style: c.text(14).copyWith(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeGroupAvatar();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditGroupDialog() async {
    final nameController =
        TextEditingController(text: _groupInfo?.groupName ?? '');
    final descController =
        TextEditingController(text: _groupInfo?.description ?? '');
    final nameFocusNode = FocusNode();
    final descFocusNode = FocusNode();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = NotesColors(ctx);
        return NotesDialog(
          title: 'Edit group info',
          icon: Icons.edit_outlined,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GROUP NAME', style: c.text(10, muted: true)),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                focusNode: nameFocusNode,
                onTapOutside: (_) => nameFocusNode.unfocus(),
                onTap: () {
                  if (!nameFocusNode.hasFocus) {
                    nameFocusNode.requestFocus();
                  }
                },
                maxLength: 50,
                style: c.text(14, bold: true),
                decoration: c.field('Enter group name').copyWith(counterText: ''),
              ),
              const SizedBox(height: 14),
              Text('DESCRIPTION', style: c.text(10, muted: true)),
              const SizedBox(height: 6),
              TextField(
                controller: descController,
                focusNode: descFocusNode,
                onTapOutside: (_) => descFocusNode.unfocus(),
                onTap: () {
                  if (!descFocusNode.hasFocus) {
                    descFocusNode.requestFocus();
                  }
                },
                minLines: 2,
                maxLines: 4,
                maxLength: 250,
                style: c.text(13),
                decoration:
                    c.field('What’s this group about?').copyWith(counterText: ''),
              ),
            ],
          ),
          actions: [
            NotesButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            NotesButton(
              label: 'Save',
              primary: true,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      await _updateGroupInfo(nameController.text, descController.text);
    }

    nameController.dispose();
    descController.dispose();
    nameFocusNode.dispose();
    descFocusNode.dispose();
  }

  void _showMemberActionsBottomSheet(GroupMember member) {
    final isCurrentUser = member.uid == _currentUserUid;
    final c = NotesColors(context);
    final canPromote = _currentUserRole == 'owner' && member.role == 'member';
    final canDemote = _currentUserRole == 'owner' && member.role == 'admin';
    final canRemove = _canRemoveMember(member);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: c.line)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              // Member header info
              Row(
                children: [
                  _buildAvatarWidget(
                    name: member.displayNameOrUsername,
                    avatarUrl: member.avatarUrl,
                    radius: 24,
                    c: c,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayNameOrUsername,
                          style: c.text(16, bold: true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${member.username}',
                          style: c.text(12, muted: true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildRoleBadge(member.role, c),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: c.line),
              const SizedBox(height: 8),

              // Action list
              if (!isCurrentUser) ...[
                ListTile(
                  leading: Icon(Icons.chat_bubble_outline_rounded, color: c.blue),
                  title: Text('Send message', style: c.text(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openConversation(member);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.person_add_outlined, color: c.blue),
                  title: Text('Add friend', style: c.text(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendFriendRequest(member);
                  },
                ),
              ],
              if (canPromote)
                ListTile(
                  leading: Icon(Icons.verified_user_outlined, color: c.blue),
                  title: Text('Make group admin', style: c.text(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeRole(member.uid, 'admin', member.username);
                  },
                ),
              if (canDemote)
                ListTile(
                  leading: Icon(Icons.shield_outlined, color: c.muted),
                  title: Text('Dismiss as admin', style: c.text(14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _changeRole(member.uid, 'member', member.username);
                  },
                ),
              if (canRemove)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                  title: Text(
                    'Remove from group',
                    style: c.text(14).copyWith(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmRemoveMember(member);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddMembersSheet() async {
    final currentMemberUsernames =
        _groupInfo?.members.map((m) => m.username).toSet() ?? {};

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/friends/list');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Failed to load friends');
      }

      final List<dynamic> friendsJson = json.decode(response.body);
      final availableFriends = friendsJson
          .where((f) {
            final username = f['username'] as String?;
            return username != null && !currentMemberUsernames.contains(username);
          })
          .map((f) => {
                'username': f['username'] ?? 'Unknown',
                'displayName': f['displayName'],
                'avatarUrl': f['avatarUrl'],
              })
          .toList();

      if (!mounted) return;

      if (availableFriends.isEmpty) {
        OpaqueToast.info(context, 'All your friends are already in this group');
        return;
      }

      final selected = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _AddMembersSheet(friends: availableFriends),
      );

      if (selected != null && selected.isNotEmpty) {
        await _addMembers(selected);
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error loading friends');
    }
  }

  Future<void> _addMembers(List<String> usernames) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url =
          Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/members/add');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'memberUsernames': usernames}),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          OpaqueToast.success(
            context,
            'Added ${usernames.length} member${usernames.length > 1 ? 's' : ''}',
          );
          _fetchGroupInfo();
        } else {
          OpaqueToast.error(context, 'Failed to add members');
        }
      }
    } catch (_) {
      if (mounted) OpaqueToast.error(context, 'Error adding members');
    }
  }

  // ─── Helpers & Widgets ───────────────────────────────────────────────────

  Widget _buildAvatarWidget({
    required String name,
    required String? avatarUrl,
    required double radius,
    required NotesColors c,
  }) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();

    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: c.text(radius * 0.7, bold: true, muted: true),
      ),
    );

    return Container(
      width: radius * 2,
      height: radius * 2,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.soft),
      child: avatarUrl?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }

  Widget _buildRoleBadge(String role, NotesColors c) {
    if (role == 'owner') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Owner',
          style: c.text(9, bold: true).copyWith(color: c.surface),
        ),
      );
    } else if (role == 'admin') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.blue.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Admin',
          style: c.text(9, bold: true).copyWith(color: c.blue),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final neutralDark = context.read<UserSettingsProvider>().isDarkMode;
    final selectedSurface =
        neutralDark ? const Color(0xFFE3E5E9) : const Color(0xFF303238);
    final selectedInk =
        neutralDark ? const Color(0xFF25272C) : const Color(0xFFF8F8FA);
    final c = NotesColors(context);

    return CallAwareScreen(
      screenName: 'GroupInfoScreen',
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
          title: Text('Group info', style: c.text(18, bold: true)),
          centerTitle: true,
          actions: [
            if (_groupInfo != null)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: c.ink),
                color: c.surface,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.line),
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditGroupDialog();
                  } else if (value == 'add') {
                    _showAddMembersSheet();
                  } else if (value == 'leave') {
                    _leaveGroup();
                  } else if (value == 'delete') {
                    _deleteGroup();
                  }
                },
                itemBuilder: (context) => [
                  if (_canManageMembers())
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16, color: c.ink),
                          const SizedBox(width: 10),
                          Text('Edit info', style: c.text(13)),
                        ],
                      ),
                    ),
                  if (_canManageMembers())
                    PopupMenuItem(
                      value: 'add',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_outlined, size: 16, color: c.ink),
                          const SizedBox(width: 10),
                          Text('Add members', style: c.text(13)),
                        ],
                      ),
                    ),
                  if (_currentUserRole != 'owner')
                    PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          const Icon(Icons.exit_to_app_rounded,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 10),
                          Text('Leave group',
                              style: c.text(13).copyWith(color: Colors.red)),
                        ],
                      ),
                    ),
                  if (_currentUserRole == 'owner')
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 10),
                          Text('Delete group',
                              style: c.text(13).copyWith(color: Colors.red)),
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
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: c.blue,
                      strokeWidth: 2,
                    ),
                  )
                : _groupInfo == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Failed to load group info.',
                              style: c.text(13, muted: true),
                            ),
                            const SizedBox(height: 12),
                            NotesButton(
                              label: 'Try again',
                              onPressed: _fetchGroupInfo,
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ─── HERO PROFILE HEADER ───
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                              child: Column(
                                children: [
                                  Stack(
                                    children: [
                                      _buildAvatarWidget(
                                        name: _groupInfo!.groupName,
                                        avatarUrl: _groupInfo!.avatarUrl,
                                        radius: 46,
                                        c: c,
                                      ),
                                      if (_currentUserRole == 'owner')
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: _showAvatarPickerSheet,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: c.blue,
                                                border: Border.all(
                                                  color: c.surface,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.camera_alt_rounded,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    _groupInfo!.groupName,
                                    textAlign: TextAlign.center,
                                    style: c
                                        .text(22, bold: true)
                                        .copyWith(letterSpacing: -.6),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.soft,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_groupInfo!.members.length} members · Created ${DateFormat('MMM d, yyyy').format(_groupInfo!.createdAt)}',
                                      style: c.text(11, muted: true),
                                    ),
                                  ),
                                  if (_groupInfo!.description?.trim().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: c.soft,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: c.line),
                                      ),
                                      child: Text(
                                        _groupInfo!.description!.trim(),
                                        textAlign: TextAlign.center,
                                        style: c.text(12, muted: true).copyWith(
                                              height: 1.5,
                                            ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  // Quick Action Buttons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_canManageMembers())
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: FilledButton.icon(
                                            onPressed: _showAddMembersSheet,
                                            icon: const Icon(
                                                Icons.person_add_rounded,
                                                size: 15),
                                            label: const Text('Add members'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: selectedSurface,
                                              foregroundColor: selectedInk,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                              textStyle: c.text(12, bold: true),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_canManageMembers())
                                        OutlinedButton.icon(
                                          onPressed: _showEditGroupDialog,
                                          icon: Icon(Icons.edit_outlined,
                                              size: 15, color: c.ink),
                                          label: Text('Edit',
                                              style: c.text(12, bold: true)),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: c.line),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: c.line),

                            // ─── MEMBERS SEARCH & LIST ───
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(22, 16, 22, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'MEMBERS',
                                        style: c
                                            .text(9, muted: true)
                                            .copyWith(letterSpacing: 1.2),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${_groupInfo!.members.length} members',
                                        style: c.text(10, muted: true),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 38,
                                    child: TextField(
                                      controller: _memberSearchController,
                                      focusNode: _memberSearchFocusNode,
                                      onTapOutside: (_) =>
                                          _memberSearchFocusNode.unfocus(),
                                      style: c.text(12),
                                      decoration: InputDecoration(
                                        hintText: 'Search members',
                                        hintStyle: c.text(12, muted: true),
                                        filled: true,
                                        fillColor: c.soft,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search,
                                          size: 16,
                                          color: c.muted,
                                        ),
                                        suffixIcon: _memberSearchQuery.isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: 'Clear search',
                                                onPressed: () {
                                                  _memberSearchController.clear();
                                                },
                                                icon: Icon(
                                                  Icons.close,
                                                  size: 16,
                                                  color: c.muted,
                                                ),
                                              ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(19),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(19),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(19),
                                          borderSide: BorderSide(color: c.blue),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Render sections for Owner, Admins, and Members
                            ..._buildRoleSections(c),

                            const SizedBox(height: 24),

                            // ─── DANGER ZONE ACTIONS ───
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 22),
                              child: Divider(height: 1, color: c.line),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_currentUserRole != 'owner')
                                    InkWell(
                                      onTap: _leaveGroup,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        child: Row(
                                          children: [
                                            const Icon(
                                                Icons.exit_to_app_rounded,
                                                color: Colors.red,
                                                size: 20),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Leave group',
                                              style: c.text(14, bold: true)
                                                  .copyWith(color: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_currentUserRole == 'owner')
                                    InkWell(
                                      onTap: _deleteGroup,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        child: Row(
                                          children: [
                                            const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.red,
                                                size: 20),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Delete group',
                                              style: c.text(14, bold: true)
                                                  .copyWith(color: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRoleSections(NotesColors c) {
    final query = _memberSearchQuery.toLowerCase();
    final filtered = _groupInfo!.members.where((member) {
      if (query.isEmpty) return true;
      return member.displayNameOrUsername.toLowerCase().contains(query) ||
          member.username.toLowerCase().contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
          child: Center(
            child: Text(
              'No matching members found',
              style: c.text(12, muted: true),
            ),
          ),
        )
      ];
    }

    final owners = filtered.where((m) => m.role == 'owner').toList();
    final admins = filtered.where((m) => m.role == 'admin').toList();
    final members = filtered.where((m) => m.role == 'member').toList();

    return [
      if (owners.isNotEmpty) _buildRoleGroup('OWNER', owners, c),
      if (admins.isNotEmpty) _buildRoleGroup('ADMINS', admins, c),
      if (members.isNotEmpty) _buildRoleGroup('MEMBERS', members, c),
    ];
  }

  Widget _buildRoleGroup(
      String title, List<GroupMember> groupMembers, NotesColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
          child: Text(
            '$title · ${groupMembers.length}',
            style: c.text(9, muted: true).copyWith(letterSpacing: 1.1),
          ),
        ),
        for (final member in groupMembers) _buildMemberRow(member, c),
      ],
    );
  }

  Widget _buildMemberRow(GroupMember member, NotesColors c) {
    final isCurrentUser = member.uid == _currentUserUid;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMemberActionsBottomSheet(member),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Row(
            children: [
              _buildAvatarWidget(
                name: member.displayNameOrUsername,
                avatarUrl: member.avatarUrl,
                radius: 19,
                c: c,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.displayNameOrUsername,
                            style: c.text(13, bold: true),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(You)',
                            style: c.text(11, muted: true),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${member.username}',
                      style: c.text(10, muted: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _buildRoleBadge(member.role, c),
              const SizedBox(width: 8),
              Icon(Icons.more_horiz_rounded, size: 18, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD MEMBERS BOTTOM SHEET (MATCHING OPAQUE DESIGN & GREEN TICKS)
// ─────────────────────────────────────────────────────────────────────────────

class _AddMembersSheet extends StatefulWidget {
  final List<Map<String, dynamic>> friends;

  const _AddMembersSheet({required this.friends});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final Set<String> _selectedUsernames = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggle(String username) {
    setState(() {
      if (!_selectedUsernames.remove(username)) {
        _selectedUsernames.add(username);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = NotesColors(context);
    final neutralDark = context.read<UserSettingsProvider>().isDarkMode;
    final selectedSurface =
        neutralDark ? const Color(0xFFE3E5E9) : const Color(0xFF303238);
    final selectedInk =
        neutralDark ? const Color(0xFF25272C) : const Color(0xFFF8F8FA);

    final filtered = widget.friends.where((friend) {
      final username = (friend['username'] as String).toLowerCase();
      final displayName = ((friend['displayName'] as String?) ?? '').toLowerCase();
      return username.contains(_searchQuery) || displayName.contains(_searchQuery);
    }).toList();

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            children: [
              // Top drag bar
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                child: Row(
                  children: [
                    Text('Add members', style: c.text(18, bold: true)),
                    const Spacer(),
                    if (_selectedUsernames.isNotEmpty)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selectedUsernames.length} selected',
                          style: c.text(11, bold: true).copyWith(
                                color: const Color(0xFF16A34A),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              // Search input
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onTapOutside: (_) => _searchFocusNode.unfocus(),
                    style: c.text(12),
                    decoration: InputDecoration(
                      hintText: 'Search friends',
                      hintStyle: c.text(12, muted: true),
                      filled: true,
                      fillColor: c.soft,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      prefixIcon: Icon(Icons.search, size: 16, color: c.muted),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: _searchController.clear,
                              icon: Icon(Icons.close, size: 16, color: c.muted),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(19),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: c.line),

              // Friends list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No friends found',
                          style: c.text(12, muted: true),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final friend = filtered[index];
                          final username = friend['username'] as String;
                          final displayName = friend['displayName'] as String?;
                          final avatarUrl = friend['avatarUrl'] as String?;
                          final name = displayName?.trim().isNotEmpty == true
                              ? displayName!
                              : username;
                          final isSelected =
                              _selectedUsernames.contains(username);

                          return Material(
                            color: isSelected
                                ? (neutralDark
                                    ? const Color(0xFF16A34A).withOpacity(0.12)
                                    : const Color(0xFF16A34A).withOpacity(0.08))
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggle(username),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: c.line,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _buildAvatar(name, avatarUrl, c),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: c.text(13, bold: isSelected),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@$username',
                                            style: c.text(10, muted: true),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? const Color(0xFF16A34A)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF16A34A)
                                              : c.line,
                                          width: 1.4,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 12,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Bottom Add Action Bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  22,
                  isKeyboardOpen ? 8 : 12,
                  22,
                  isKeyboardOpen ? 6 : 10,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedUsernames.isNotEmpty
                        ? () => Navigator.pop(
                            context, _selectedUsernames.toList())
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: selectedSurface,
                      foregroundColor: selectedInk,
                      disabledBackgroundColor: c.soft,
                      disabledForegroundColor: c.muted,
                      minimumSize: const Size.fromHeight(44),
                      textStyle: c.text(13, bold: true),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _selectedUsernames.isNotEmpty
                          ? 'Add (${_selectedUsernames.length})'
                          : 'Select members to add',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, String? avatarUrl, NotesColors c) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first.toUpperCase())
        .join();

    final fallback = Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: c.text(12, bold: true, muted: true),
      ),
    );

    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.soft),
      child: avatarUrl?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}
