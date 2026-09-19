import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../chat_screen.dart';
import '../home_screen.dart';
import '../services/websocket_service.dart';
import '../providers/home_provider.dart';
import 'package:zarq_messenger/app_config.dart';

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
      joinedAt: DateTime.parse(json['joinedAt']),
    );
  }

  String get displayNameOrUsername => displayName ?? username;
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
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      members: (json['members'] as List?)
              ?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

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
  String _memberSearchQuery = '';
  final TextEditingController _memberSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    _fetchGroupInfo();
    _memberSearchController.addListener(() {
      setState(() {
        _memberSearchQuery = _memberSearchController.text;
      });
    });
  }

  @override
  void dispose() {
    _memberSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGroupInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final token = await user.getIdToken();

    try {
      final url = Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/info');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        final groupInfo = GroupInfo.fromJson(data);

        // Find current user's role
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load group info: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading group info: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(String memberUid, String memberUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    try {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$memberUsername removed from group'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchGroupInfo(); // Refresh the member list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove member: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRemoveMemberDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.displayNameOrUsername} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMember(member.uid, member.username);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  bool _canManageMembers() {
    return _currentUserRole == 'owner' || _currentUserRole == 'admin';
  }

  bool _canRemoveMember(GroupMember member) {
    if (!_canManageMembers()) return false;
    if (member.uid == _currentUserUid) return false; // Cannot remove self
    if (member.role == 'owner') return false; // Cannot remove owner
    // Only owner can remove admin
    if (member.role == 'admin' && _currentUserRole != 'owner') return false;
    return true;
  }

  Future<void> _showAddMembersDialog() async {
    // Get current member usernames to exclude them
    final currentMemberUsernames = _groupInfo?.members.map((m) => m.username).toSet() ?? {};

    // Fetch friends list
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    try {
      final url = Uri.parse('${AppConfig.baseUrl}/friends/list');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load friends');
      }

      final List<dynamic> friendsJson = json.decode(response.body);

      // Filter out friends who are already in the group (by username)
      final availableFriends = friendsJson
          .where((f) {
            final username = f['username'] as String?;
            return username != null && !currentMemberUsernames.contains(username);
          })
          .map((f) => {
                'username': f['username'] ?? 'Unknown',
                'avatarUrl': f['avatarUrl'],
              })
          .toList();

      if (availableFriends.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All your friends are already in this group'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Show selection dialog
      if (!mounted) return;
      final selectedUsernames = await showDialog<List<String>>(
        context: context,
        builder: (context) => _AddMembersDialog(friends: availableFriends),
      );

      if (selectedUsernames != null && selectedUsernames.isNotEmpty) {
        await _addMembers(selectedUsernames);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading friends: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addMembers(List<String> usernames) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    try {
      final url = Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/members/add');
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
          final data = json.decode(response.body);
          final count = data['added_count'] ?? usernames.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$count member(s) added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchGroupInfo(); // Refresh member list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add members: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding members: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _changeRole(String memberUid, String newRole, String memberUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();

    try {
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
          final action = newRole == 'admin' ? 'promoted to admin' : 'demoted to member';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$memberUsername $action'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchGroupInfo(); // Refresh the member list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to change role: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing role: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMemberOptionsDialog(GroupMember member) {
    final canPromote = member.role == 'member';
    final canDemote = member.role == 'admin';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(member.displayNameOrUsername),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPromote)
              ListTile(
                leading: const Icon(Icons.arrow_upward, color: Colors.blue),
                title: const Text('Promote to Admin'),
                onTap: () {
                  Navigator.pop(context);
                  _changeRole(member.uid, 'admin', member.username);
                },
              ),
            if (canDemote)
              ListTile(
                leading: const Icon(Icons.arrow_downward, color: Colors.orange),
                title: const Text('Demote to Member'),
                onTap: () {
                  Navigator.pop(context);
                  _changeRole(member.uid, 'member', member.username);
                },
              ),
            if (_canRemoveMember(member))
              ListTile(
                leading: const Icon(Icons.person_remove, color: Colors.red),
                title: const Text('Remove from Group'),
                onTap: () {
                  Navigator.pop(context);
                  _showRemoveMemberDialog(member);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  bool _canChangeRole(GroupMember member) {
    if (_currentUserRole != 'owner') return false; // Only owner can change roles
    if (member.uid == _currentUserUid) return false; // Cannot change own role
    if (member.role == 'owner') return false; // Cannot change owner
    return true;
  }

  Future<void> _leaveGroup() async {
    // Owner cannot leave group
    if (_currentUserRole == 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group owner cannot leave. Transfer ownership or delete the group.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${_groupInfo?.groupName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/leave');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have left the group'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back to home
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        throw Exception('Failed to leave group: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error leaving group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteGroup() async {
    if (_currentUserRole != 'owner') return;

    // Show confirmation dialog with group name verification
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will permanently delete the group and all its messages. This action cannot be undone.',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            Text('Group: "${_groupInfo?.groupName}"'),
            const SizedBox(height: 8),
            Text('Members: ${_groupInfo?.members.length ?? 0}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await user.getIdToken();
      final url = Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/delete');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back to home
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        throw Exception('Failed to delete group: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditGroupDialog() async {
    if (_currentUserRole != 'owner' && _currentUserRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only owner and admins can edit group info'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: _groupInfo?.groupName ?? '');
    final descController = TextEditingController(text: _groupInfo?.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'Enter group name',
              ),
              maxLength: 50,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Enter group description',
              ),
              maxLines: 3,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _updateGroupInfo(nameController.text, descController.text);
    }

    nameController.dispose();
    descController.dispose();
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

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group info updated successfully')),
        );
        _fetchGroupInfo(); // Refresh group info
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update group info: ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating group info: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _changeGroupAvatar() async {
    if (_currentUserRole != 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the group owner can change the avatar'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
    );

    if (pickedFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Color(0xFF00ACC1)),
              SizedBox(width: 20),
              Text('Uploading avatar...'),
            ],
          ),
        ),
      );

      // Upload to Firebase Storage (same as profile avatars)
      final storageRef = FirebaseStorage.instance.ref().child(
        'group_avatars/${widget.groupId}/avatar.jpg',
      );

      String downloadUrl;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        final uploadTask = storageRef.putData(bytes);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        final file = File(pickedFile.path);
        final uploadTask = storageRef.putFile(file);
        final snapshot = await uploadTask.whenComplete(() => {});
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      // Update group avatar via backend API
      final token = await user.getIdToken();
      final updateUrl = Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/avatar');
      final updateResponse = await http.post(
        updateUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'avatarUrl': downloadUrl}),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (updateResponse.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group avatar updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchGroupInfo(); // Refresh to show new avatar
      } else {
        throw Exception('Failed to update avatar: ${updateResponse.body}');
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog if still open
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating avatar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getRoleBadgeText(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return '';
    }
  }

  Color _getRoleBadgeColor(String role) {
    switch (role) {
      case 'owner':
        return Colors.white;
      case 'admin':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showMemberActionsBottomSheet(GroupMember member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // User info header
            Row(
              children: [
                _buildAvatar(
                  member.displayNameOrUsername,
                  member.avatarUrl,
                  radius: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayNameOrUsername,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${member.username}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action buttons
            _buildActionCard(
              icon: Icons.person_add,
              title: 'Add Friend',
              subtitle: 'Send friend request',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _sendFriendRequest(member);
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              icon: Icons.chat_bubble,
              title: 'Send Message',
              subtitle: 'Start a conversation',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                _openConversation(member);
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(GroupMember member) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final url = Uri.parse('${AppConfig.baseUrl}/friends/request');

    try {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Friend request sent to ${member.displayNameOrUsername}!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openConversation(GroupMember member) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // print('[GroupInfo] User not logged in');
        return;
      }

      // Get WebSocket service
      final websocketService = Provider.of<WebSocketService>(context, listen: false);
      if (!websocketService.isConnected || websocketService.channel == null) {
        // print('[GroupInfo] WebSocket not connected');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connecting... Please wait a moment.')),
        );
        return;
      }

      // print('[GroupInfo] Starting conversation with ${member.username}');

      // Start or get conversation
      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/conversations/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUsername': member.username}),
      );

      // print('[GroupInfo] Response status: ${response.statusCode}');
      // print('[GroupInfo] Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final conversationId = data['conversationId'] as int;

        // print('[GroupInfo] Conversation ID: $conversationId');

        // Create ConversationInfo directly from available data
        final conversation = ConversationInfo(
          conversationId: conversationId,
          chatTitle: member.displayNameOrUsername,
          isGroup: false,
          partnerUid: member.uid,
          avatarUrl: member.avatarUrl,
        );

        // print('[GroupInfo] Created conversation info, navigating...');

        // Refresh home provider in background (don't wait)
        final homeProvider = Provider.of<HomeProvider>(context, listen: false);
        homeProvider.fetchInitialConversations();

        // Navigate to chat screen immediately
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                channel: websocketService.channel!,
                conversationInfo: conversation,
              ),
            ),
          );
        }
      } else {
        // print('[GroupInfo] Failed with status ${response.statusCode}: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open conversation: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      // print('[GroupInfo] Exception: $e');
      // print('[GroupInfo] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAvatar(String username, String? avatarUrl, {double radius = 30}) {
    final hasImage = avatarUrl != null && avatarUrl.isNotEmpty;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final color = Color(username.hashCode | 0xFF000000).withOpacity(1.0);
    final fontSize = radius * 0.9; // Scale font size with radius

    if (hasImage) {
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
          backgroundColor: Colors.transparent,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          backgroundColor: color,
          child: SizedBox(
            width: radius * 0.8,
            height: radius * 0.8,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: radius,
          backgroundColor: color,
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final appBarTitleSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final iconSize = (screenWidth * 0.05).clamp(18.0, 24.0);
    final menuIconSize = (screenWidth * 0.045).clamp(16.0, 20.0);
    final menuTextSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final spacing1 = (screenWidth * 0.02).clamp(6.0, 10.0);

    // Additional responsive sizes for body content
    final headerPadding = (screenWidth * 0.06).clamp(20.0, 28.0);
    final avatarRadius = (screenWidth * 0.11).clamp(40.0, 50.0);
    final cameraIconPadding = (screenWidth * 0.015).clamp(5.0, 8.0);
    final cameraIconSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final groupNameSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final descriptionSize = (screenWidth * 0.035).clamp(13.0, 16.0);
    final createdDateSize = (screenWidth * 0.03).clamp(11.0, 14.0);
    final sectionTitleSize = (screenWidth * 0.04).clamp(15.0, 19.0);
    final sectionIconSize = (screenWidth * 0.06).clamp(22.0, 28.0);
    final spacing2 = (screenWidth * 0.04).clamp(14.0, 20.0);
    final spacing3 = (screenWidth * 0.03).clamp(10.0, 14.0);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              title: Text(
                'Group Info',
                style: TextStyle(color: Colors.black, fontSize: appBarTitleSize),
              ),
              backgroundColor: Colors.white.withOpacity(0.7),
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.black, size: iconSize),
              actions: [
          // Menu for owner/admin, leave button for members
          if (_currentUserRole == 'owner' || _currentUserRole == 'admin')
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: iconSize),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditGroupDialog();
                } else if (value == 'delete') {
                  _deleteGroup();
                } else if (value == 'leave') {
                  _leaveGroup();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: menuIconSize),
                      SizedBox(width: spacing1),
                      Text('Edit Group Info', style: TextStyle(fontSize: menuTextSize)),
                    ],
                  ),
                ),
                if (_currentUserRole == 'owner')
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, color: Colors.red, size: menuIconSize),
                        SizedBox(width: spacing1),
                        Text('Delete Group', style: TextStyle(color: Colors.red, fontSize: menuTextSize)),
                      ],
                    ),
                  ),
                if (_currentUserRole == 'admin')
                  PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, size: menuIconSize),
                        SizedBox(width: spacing1),
                        Text('Leave Group', style: TextStyle(fontSize: menuTextSize)),
                      ],
                    ),
                  ),
              ],
            )
          else if (_currentUserRole != null)
            IconButton(
              icon: Icon(Icons.exit_to_app, size: iconSize),
              tooltip: 'Leave Group',
              onPressed: _leaveGroup,
            ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _canManageMembers()
          ? Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: FloatingActionButton.extended(
                onPressed: _showAddMembersDialog,
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                elevation: 4,
                icon: Icon(Icons.person_add, size: (screenWidth * 0.055).clamp(20.0, 26.0)),
                label: Text(
                  'Add Members',
                  style: TextStyle(
                    fontSize: (screenWidth * 0.0375).clamp(14.0, 17.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular((screenWidth * 0.04).clamp(14.0, 18.0)),
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00ACC1),
              ),
            )
          : _groupInfo == null
              ? const Center(
                  child: Text('Failed to load group information'),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Group Header
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(headerPadding),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              children: [
                                _buildAvatar(
                                  _groupInfo!.groupName,
                                  _groupInfo!.avatarUrl,
                                  radius: avatarRadius,
                                ),
                                if (_currentUserRole == 'owner')
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: _changeGroupAvatar,
                                      child: Container(
                                        padding: EdgeInsets.all(cameraIconPadding),
                                        decoration: BoxDecoration(
                                          color: Colors.cyan,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: cameraIconSize,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: spacing2),
                            Text(
                              _groupInfo!.groupName,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: groupNameSize,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_groupInfo!.description != null &&
                                _groupInfo!.description!.isNotEmpty) ...[
                              SizedBox(height: spacing1),
                              Text(
                                _groupInfo!.description!,
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: descriptionSize,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            SizedBox(height: spacing3),
                            Text(
                              'Created ${DateFormat('MMM d, yyyy').format(_groupInfo!.createdAt)}',
                              style: TextStyle(
                                color: Colors.black45,
                                fontSize: createdDateSize,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Members Section
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with total member count
                          Padding(
                            padding: EdgeInsets.fromLTRB(spacing2, spacing2, spacing2, spacing1),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.people,
                                  color: Colors.deepOrange,
                                  size: sectionIconSize,
                                ),
                                SizedBox(width: spacing1),
                                Text(
                                  'MEMBERS — ${_groupInfo!.members.length}',
                                  style: TextStyle(
                                    fontSize: sectionTitleSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Search bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: TextField(
                              controller: _memberSearchController,
                              style: const TextStyle(color: Colors.black87, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search members...',
                                hintStyle: TextStyle(color: Colors.grey[700], fontSize: 14),
                                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.amber),
                                suffixIcon: _memberSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: () {
                                          _memberSearchController.clear();
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.yellow[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.yellow[800]!, width: 1.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.yellow[800]!, width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.yellow[900]!, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                isDense: true,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Build role-based sections
                          ..._buildRoleSections(),
                        ],
                      ),
                      // Add bottom padding to prevent overlap with FAB and system buttons
                      SizedBox(
                        height: (_canManageMembers() ? 80 : 16) +
                                MediaQuery.of(context).padding.bottom,
                      ),
                    ],
                  ),
                ),
    );
  }

  // Build members organized by role (Discord-style)
  List<Widget> _buildRoleSections() {
    // Filter members by search query
    final filteredMembers = _groupInfo!.members.where((member) {
      if (_memberSearchQuery.isEmpty) return true;
      final query = _memberSearchQuery.toLowerCase();
      return member.displayNameOrUsername.toLowerCase().contains(query) ||
             member.username.toLowerCase().contains(query);
    }).toList();

    // Separate by role
    final owners = filteredMembers.where((m) => m.role == 'owner').toList();
    final admins = filteredMembers.where((m) => m.role == 'admin').toList();
    final members = filteredMembers.where((m) => m.role == 'member').toList();

    List<Widget> sections = [];

    // Owner section
    if (owners.isNotEmpty) {
      sections.add(_buildRoleSection('OWNER', owners, Colors.black));
    }

    // Admins section
    if (admins.isNotEmpty) {
      sections.add(_buildRoleSection('ADMINS', admins, Colors.blue));
    }

    // Members section
    if (members.isNotEmpty) {
      sections.add(_buildRoleSection('MEMBERS', members, Colors.grey));
    }

    if (sections.isEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              'No members found',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return sections;
  }

  Widget _buildRoleSection(String roleTitle, List<GroupMember> members, Color color) {
    // Determine background color and border based on role title
    Color backgroundColor;
    Color borderColor;
    if (roleTitle == 'OWNER') {
      backgroundColor = Colors.red[50]!;
      borderColor = Colors.red[700]!;
    } else if (roleTitle == 'ADMINS') {
      backgroundColor = Colors.green[50]!;
      borderColor = Colors.green[700]!;
    } else {
      backgroundColor = Colors.blue[50]!;
      borderColor = Colors.blue[700]!;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '$roleTitle — ${members.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Members in this role
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: members.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 60),
            itemBuilder: (context, index) {
            final member = members[index];
            final isCurrentUser = member.uid == _currentUserUid;
            final roleBadge = _getRoleBadgeText(member.role);

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              onTap: (_canChangeRole(member) || _canRemoveMember(member))
                  ? () => _showMemberOptionsDialog(member)
                  : (!isCurrentUser ? () => _showMemberActionsBottomSheet(member) : null),
              onLongPress: !isCurrentUser
                  ? () => _showMemberActionsBottomSheet(member)
                  : null,
              leading: _buildAvatar(
                member.displayNameOrUsername,
                member.avatarUrl,
                radius: 20,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      member.displayNameOrUsername,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isCurrentUser
                            ? const Color(0xFF00ACC1)
                            : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '(You)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00ACC1),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: roleBadge.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: member.role == 'owner'
                            ? Colors.white
                            : _getRoleBadgeColor(member.role).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: member.role == 'owner'
                              ? Colors.black
                              : _getRoleBadgeColor(member.role),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        roleBadge,
                        style: TextStyle(
                          color: member.role == 'owner'
                              ? Colors.black
                              : _getRoleBadgeColor(member.role),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : null,
            );
          },
        ),
        ],
      ),
    );
  }
}

// Rest of the existing code continues here...
class _AddMembersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> friends;

  const _AddMembersDialog({required this.friends});

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final Set<String> _selectedUsernames = {};
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredFriends = widget.friends.where((friend) {
      final username = friend['username'] as String;
      return username.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_add, size: 24, color: Colors.grey[800]),
                  const SizedBox(width: 12),
                  const Text(
                    'Add Members',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedUsernames.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_selectedUsernames.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[700]),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Friends list
            Flexible(
              child: filteredFriends.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'No friends found',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredFriends.length,
                      itemBuilder: (context, index) {
                        final friend = filteredFriends[index];
                        final username = friend['username'] as String;
                        final avatarUrl = friend['avatarUrl'] as String?;
                        final displayName = friend['displayName'] ?? username;
                        final isSelected = _selectedUsernames.contains(username);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedUsernames.remove(username);
                              } else {
                                _selectedUsernames.add(username);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Color(username.hashCode | 0xFF000000),
                                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(avatarUrl)
                                      : null,
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? Text(
                                          username.isNotEmpty
                                              ? username[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (displayName != username)
                                        Text(
                                          '@$username',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white70,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: isSelected,
                                  onChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedUsernames.add(username);
                                      } else {
                                        _selectedUsernames.remove(username);
                                      }
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedUsernames.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selectedUsernames.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
