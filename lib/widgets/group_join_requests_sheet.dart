import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../app_config.dart';
import 'notes_design.dart';
import 'opaque_toast.dart';

class GroupJoinRequestItem {
  final int id;
  final int groupId;
  final String profileUid;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String requestedBy;
  final String status;
  final DateTime createdAt;

  GroupJoinRequestItem({
    required this.id,
    required this.groupId,
    required this.profileUid,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.requestedBy,
    required this.status,
    required this.createdAt,
  });

  factory GroupJoinRequestItem.fromJson(Map<String, dynamic> json) {
    return GroupJoinRequestItem(
      id: json['id'] ?? 0,
      groupId: json['groupId'] ?? 0,
      profileUid: json['profileUid'] ?? '',
      username: json['username'] ?? 'Unknown',
      displayName: json['displayName'],
      avatarUrl: json['avatarUrl'],
      requestedBy: json['requestedBy'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get displayNameOrUsername =>
      displayName?.trim().isNotEmpty == true ? displayName! : username;
}

class GroupJoinRequestsSheet extends StatefulWidget {
  final int groupId;
  final String groupName;
  final VoidCallback? onRequestsUpdated;

  const GroupJoinRequestsSheet({
    super.key,
    required this.groupId,
    required this.groupName,
    this.onRequestsUpdated,
  });

  @override
  State<GroupJoinRequestsSheet> createState() => _GroupJoinRequestsSheetState();
}

class _GroupJoinRequestsSheetState extends State<GroupJoinRequestsSheet> {
  bool _isLoading = true;
  List<GroupJoinRequestItem> _requests = [];
  final Set<int> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/join-requests'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final list = json.decode(response.body) as List? ?? [];
        setState(() {
          _requests = list
              .map((item) => GroupJoinRequestItem.fromJson(item as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
        OpaqueToast.error(context, 'Failed to fetch join requests');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        OpaqueToast.error(context, 'Error loading requests');
      }
    }
  }

  Future<void> _reviewRequest(GroupJoinRequestItem req, String action) async {
    setState(() => _processingIds.add(req.id));
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/join-requests/${req.id}/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'action': action}),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _requests.removeWhere((item) => item.id == req.id);
          _processingIds.remove(req.id);
        });
        widget.onRequestsUpdated?.call();
        if (action == 'approve') {
          OpaqueToast.success(context, '${req.displayNameOrUsername} approved');
        } else {
          OpaqueToast.info(context, '${req.displayNameOrUsername} rejected');
        }
      } else if (mounted) {
        setState(() => _processingIds.remove(req.id));
        OpaqueToast.error(context, 'Failed to $action request');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(req.id));
        OpaqueToast.error(context, 'Network error');
      }
    }
  }

  bool _isBatchProcessing = false;

  Future<void> _batchReview(String action) async {
    setState(() => _isBatchProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await user.getIdToken();

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/groups/${widget.groupId}/join-requests/batch'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'action': action}),
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _requests.clear();
          _isBatchProcessing = false;
        });
        widget.onRequestsUpdated?.call();
        if (action == 'approve_all') {
          OpaqueToast.success(context, 'All requests approved');
        } else {
          OpaqueToast.info(context, 'All requests denied');
        }
      } else if (mounted) {
        setState(() => _isBatchProcessing = false);
        OpaqueToast.error(context, 'Failed to process requests');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBatchProcessing = false);
        OpaqueToast.error(context, 'Network error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NotesColors(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Sheet Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pending join requests', style: c.text(16, bold: true)),
                        const SizedBox(height: 2),
                        Text(
                          '${_requests.length} participant(s) waiting for approval',
                          style: c.text(12, muted: true),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: c.blue, strokeWidth: 2))
                  : _requests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.how_to_reg_outlined, size: 44, color: c.muted),
                              const SizedBox(height: 10),
                              Text('No pending requests', style: c.text(14, bold: true)),
                              const SizedBox(height: 4),
                              Text(
                                'New requests to join ${widget.groupName} will appear here.',
                                style: c.text(12, muted: true),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            if (_requests.length > 1) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: _isBatchProcessing ? null : () => _batchReview('reject_all'),
                                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
                                      label: Text('Deny All', style: c.text(12, bold: true).copyWith(color: Colors.red)),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: _isBatchProcessing ? null : () => _batchReview('approve_all'),
                                      icon: Icon(Icons.done_all_rounded, size: 16, color: c.blue),
                                      label: Text('Approve All', style: c.text(12, bold: true).copyWith(color: c.blue)),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(height: 1, color: c.line),
                            ],
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: _requests.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
                                itemBuilder: (context, index) {
                                  final req = _requests[index];
                                  final isProcessing = _processingIds.contains(req.id);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: c.soft,
                                          backgroundImage: req.avatarUrl != null && req.avatarUrl!.isNotEmpty
                                              ? CachedNetworkImageProvider(req.avatarUrl!)
                                              : null,
                                          child: req.avatarUrl == null || req.avatarUrl!.isEmpty
                                              ? Text(
                                                  req.displayNameOrUsername.isNotEmpty
                                                      ? req.displayNameOrUsername[0].toUpperCase()
                                                      : '?',
                                                  style: c.text(14, bold: true),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),

                                        // Name and requested by
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                req.displayNameOrUsername,
                                                style: c.text(14, bold: true),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '@${req.username} · Added by ${req.requestedBy}',
                                                style: c.text(11, muted: true),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Action buttons
                                        if (isProcessing)
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(color: c.blue, strokeWidth: 2),
                                          )
                                        else
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Reject Button
                                              IconButton(
                                                icon: const Icon(Icons.close_rounded, size: 20, color: Colors.red),
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _reviewRequest(req, 'reject'),
                                                tooltip: 'Reject',
                                              ),
                                              const SizedBox(width: 4),
                                              // Approve Button
                                              IconButton(
                                                icon: const Icon(Icons.check_rounded, size: 20, color: Colors.green),
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _reviewRequest(req, 'approve'),
                                                tooltip: 'Approve',
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  );
                                },
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
