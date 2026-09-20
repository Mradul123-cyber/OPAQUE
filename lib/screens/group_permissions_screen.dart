import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../widgets/opaque_design.dart';
import '../widgets/opaque_toast.dart';
import '../widgets/group_join_requests_sheet.dart';
import 'group_info_screen.dart';

class GroupPermissionsScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final bool isOwner;

  const GroupPermissionsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.isOwner,
  });

  @override
  State<GroupPermissionsScreen> createState() => _GroupPermissionsScreenState();
}

class _GroupPermissionsScreenState extends State<GroupPermissionsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Permissions state
  bool _editGroupInfo = true;
  bool _sendMessages = true;
  bool _addMembers = true;
  bool _requireAdminApproval = false;

  // Pending requests count
  int _pendingRequestsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadPendingRequestsCount();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/permissions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _editGroupInfo =
              (data['editGroupInfoPermission'] ?? 'all_members') ==
              'all_members';
          _sendMessages =
              (data['sendMessagesPermission'] ?? 'all_members') ==
              'all_members';
          _addMembers =
              (data['addMembersPermission'] ?? 'all_members') == 'all_members';
          _requireAdminApproval = data['requireAdminApproval'] ?? false;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
        OpaqueToast.error(context, 'Failed to load group permissions');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        OpaqueToast.error(context, 'Error loading permissions');
      }
    }
  }

  Future<void> _loadPendingRequestsCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/join-requests',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final list = json.decode(response.body) as List?;
        setState(() {
          _pendingRequestsCount = list?.length ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _updatePermission({
    bool? editGroupInfo,
    bool? sendMessages,
    bool? addMembers,
    bool? requireAdminApproval,
  }) async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final body = <String, dynamic>{};
      if (editGroupInfo != null) {
        body['editGroupInfoPermission'] = editGroupInfo
            ? 'all_members'
            : 'only_admins';
      }
      if (sendMessages != null) {
        body['sendMessagesPermission'] = sendMessages
            ? 'all_members'
            : 'only_admins';
      }
      if (addMembers != null) {
        body['addMembersPermission'] = addMembers
            ? 'all_members'
            : 'only_admins';
      }
      if (requireAdminApproval != null) {
        body['requireAdminApproval'] = requireAdminApproval;
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/permissions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          if (editGroupInfo != null) _editGroupInfo = editGroupInfo;
          if (sendMessages != null) _sendMessages = sendMessages;
          if (addMembers != null) _addMembers = addMembers;
          if (requireAdminApproval != null)
            _requireAdminApproval = requireAdminApproval;
          _isSaving = false;
        });
        OpaqueToast.success(context, 'Permissions updated');
      } else if (mounted) {
        setState(() => _isSaving = false);
        String errorMsg = 'Failed to update permissions';
        try {
          final errBody = response.body.trim();
          if (errBody.isNotEmpty) {
            errorMsg = errBody;
          }
        } catch (_) {}
        OpaqueToast.error(context, errorMsg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        OpaqueToast.error(context, 'Network error updating permissions');
      }
    }
  }

  void _onToggleRequireAdminApproval(bool val) {
    if (!val && _pendingRequestsCount > 0) {
      _showPendingRequestsWarningDialog();
    } else {
      _updatePermission(requireAdminApproval: val);
    }
  }

  void _showPendingRequestsWarningDialog() {
    final c = OpaqueColors(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: c.blue, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pending Join Requests',
                style: c.text(16, bold: true),
              ),
            ),
          ],
        ),
        content: Text(
          'You cannot disable admin approval while there are $_pendingRequestsCount pending request(s) waiting for review.\n\nPlease sort out the pending list or choose an action below:',
          style: c.text(13, muted: true).copyWith(height: 1.45),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openJoinRequestsSheet();
                },
                child: Text(
                  'Review list',
                  style: c.text(12, bold: true).copyWith(color: c.blue),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: c.text(12, muted: true)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _batchReviewRequests(
                      action: 'reject_all',
                      disableApproval: true,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'Deny All',
                    style: c.text(12, bold: true).copyWith(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _batchReviewRequests(
                      action: 'approve_all',
                      disableApproval: true,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: c.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text(
                    'Approve All',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _batchReviewRequests({
    required String action,
    required bool disableApproval,
  }) async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/groups/${widget.groupId}/join-requests/batch',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': action,
          'disableApproval': disableApproval,
        }),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _pendingRequestsCount = 0;
          if (disableApproval) {
            _requireAdminApproval = false;
          }
          _isSaving = false;
        });
        final actionText = action == 'approve_all'
            ? 'All requests approved'
            : 'All requests denied';
        OpaqueToast.success(context, '$actionText and approval disabled');
      } else if (mounted) {
        setState(() => _isSaving = false);
        OpaqueToast.error(
          context,
          response.body.isNotEmpty
              ? response.body
              : 'Failed to process requests',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        OpaqueToast.error(context, 'Network error processing requests');
      }
    }
  }

  void _openJoinRequestsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GroupJoinRequestsSheet(
        groupId: widget.groupId,
        groupName: widget.groupName,
        onRequestsUpdated: _loadPendingRequestsCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: c.ink),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group permissions', style: c.text(16, bold: true)),
            Text(widget.groupName, style: c.text(11, muted: true)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: c.line),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: c.blue, strokeWidth: 2),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              children: [
                // Header Note
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 20, color: c.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Admins can always edit group settings, send messages, and add members. Choose what other participants are allowed to do.',
                          style: c.text(12, muted: true).copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── SECTION 1: MEMBERS CAN ──
                Text(
                  'MEMBERS CAN',
                  style: c
                      .text(11, muted: true, bold: true)
                      .copyWith(letterSpacing: 0.8),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        c: c,
                        title: 'Edit group settings',
                        subtitle: 'Change name, avatar, and description',
                        value: _editGroupInfo,
                        onChanged: _isSaving
                            ? null
                            : (val) => _updatePermission(editGroupInfo: val),
                      ),
                      Divider(
                        height: 1,
                        color: c.line,
                        indent: 16,
                        endIndent: 16,
                      ),
                      _buildSwitchTile(
                        c: c,
                        title: 'Send messages',
                        subtitle: _sendMessages
                            ? 'All participants can send messages'
                            : 'Announcement mode: Only admins can send messages',
                        value: _sendMessages,
                        onChanged: _isSaving
                            ? null
                            : (val) => _updatePermission(sendMessages: val),
                      ),
                      Divider(
                        height: 1,
                        color: c.line,
                        indent: 16,
                        endIndent: 16,
                      ),
                      _buildSwitchTile(
                        c: c,
                        title: 'Add other members',
                        subtitle: 'Invite or add new participants to this chat',
                        value: _addMembers,
                        onChanged: _isSaving
                            ? null
                            : (val) => _updatePermission(addMembers: val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── SECTION 2: ADMINS CAN ──
                Text(
                  'ADMINS CAN',
                  style: c
                      .text(11, muted: true, bold: true)
                      .copyWith(letterSpacing: 0.8),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        c: c,
                        title: 'Approve new members',
                        subtitle:
                            'When turned on, new participants must be approved by an admin before joining',
                        value: _requireAdminApproval,
                        onChanged: _isSaving
                            ? null
                            : (val) => _onToggleRequireAdminApproval(val),
                      ),
                      if (_requireAdminApproval) ...[
                        Divider(
                          height: 1,
                          color: c.line,
                          indent: 16,
                          endIndent: 16,
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Icon(
                            Icons.person_pin_outlined,
                            color: c.blue,
                            size: 22,
                          ),
                          title: Text(
                            'Pending join requests',
                            style: c.text(14, bold: true),
                          ),
                          subtitle: Text(
                            _pendingRequestsCount > 0
                                ? '$_pendingRequestsCount request(s) waiting for review'
                                : 'No pending requests',
                            style: c.text(12, muted: true),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_pendingRequestsCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.blue,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$_pendingRequestsCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: c.muted,
                                size: 20,
                              ),
                            ],
                          ),
                          onTap: _openJoinRequestsSheet,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile({
    required OpaqueColors c,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: c.text(14, bold: true)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: c.text(12, muted: true).copyWith(height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: c.blue,
          ),
        ],
      ),
    );
  }
}
