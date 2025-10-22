import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

class TaskGlobalFeedScreen extends StatefulWidget {
  const TaskGlobalFeedScreen({super.key});

  @override
  State<TaskGlobalFeedScreen> createState() => _TaskGlobalFeedScreenState();
}

class _TaskGlobalFeedScreenState extends State<TaskGlobalFeedScreen> {
  List<Map<String, dynamic>> _submissions = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadFeed({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _offset = 0;
        _submissions = [];
        _hasMore = true;
      });
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('https://zarqmessenger.com/tasks/feed/global?limit=$_limit&offset=$_offset'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> newSubmissions = data['submissions'] ?? [];

        setState(() {
          if (refresh) {
            _submissions = List<Map<String, dynamic>>.from(newSubmissions);
          } else {
            _submissions.addAll(List<Map<String, dynamic>>.from(newSubmissions));
          }
          _hasMore = newSubmissions.length == _limit;
          _offset += newSubmissions.length;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error loading feed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    await _loadFeed();
  }

  Future<void> _reactToSubmission(String submissionId, String reactionType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();

      // Get current reaction state
      final index = _submissions.indexWhere((s) => s['id'] == submissionId);
      if (index == -1) return;

      final oldReaction = _submissions[index]['user_reaction'];
      final hadReaction = oldReaction != null;

      final response = await http.post(
        Uri.parse('https://zarqmessenger.com/tasks/submissions/$submissionId/react'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'reaction_type': reactionType}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Update local state - replace reaction, not add
        setState(() {
          // Update user's reaction
          _submissions[index]['user_reaction'] = reactionType;

          // Update reactions breakdown
          var reactions = Map<String, dynamic>.from(
              _submissions[index]['reactions'] as Map<String, dynamic>? ?? {});

          // If user had a previous reaction, decrement it
          if (hadReaction && oldReaction != null) {
            reactions[oldReaction] = (reactions[oldReaction] ?? 1) - 1;
            if (reactions[oldReaction] <= 0) {
              reactions.remove(oldReaction);
            }
          }

          // Increment new reaction
          reactions[reactionType] = (reactions[reactionType] ?? 0) + 1;

          _submissions[index]['reactions'] = reactions;

          // Only increment total count if user didn't have a reaction before
          if (!hadReaction) {
            _submissions[index]['reaction_count'] = (_submissions[index]['reaction_count'] ?? 0) + 1;
          }
        });
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error reacting: $e');
    }
  }

  Future<void> _removeReaction(String submissionId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();

      // Get current reaction to remove
      final index = _submissions.indexWhere((s) => s['id'] == submissionId);
      if (index == -1) return;

      final oldReaction = _submissions[index]['user_reaction'];
      if (oldReaction == null) return;

      final response = await http.delete(
        Uri.parse('https://zarqmessenger.com/tasks/submissions/$submissionId/react'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        // Update local state
        setState(() {
          // Remove user's reaction
          _submissions[index]['user_reaction'] = null;

          // Update reactions breakdown
          var reactions = Map<String, dynamic>.from(
              _submissions[index]['reactions'] as Map<String, dynamic>? ?? {});

          // Decrement the old reaction count
          reactions[oldReaction] = (reactions[oldReaction] ?? 1) - 1;
          if (reactions[oldReaction] <= 0) {
            reactions.remove(oldReaction);
          }

          _submissions[index]['reactions'] = reactions;

          // Decrement total count
          _submissions[index]['reaction_count'] = (_submissions[index]['reaction_count'] ?? 1) - 1;
        });
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error removing reaction: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _submissions.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    if (_submissions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.feed_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No submissions yet',
              style: TextStyle(color: Colors.grey[700], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to complete a task!',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadFeed(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFeed(refresh: true),
      color: Colors.blue,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _submissions.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _submissions.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(color: Colors.blue),
              ),
            );
          }

          final submission = _submissions[index];
          return _buildSubmissionCard(submission);
        },
      ),
    );
  }

  Widget _buildSubmissionCard(Map<String, dynamic> submission) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isVideo = submission['media_type'] == 'video';
    final mediaUrl = submission['media_url'] ?? '';
    final thumbnailUrl = submission['thumbnail_url'];
    final username = submission['username'] ?? 'anonymous';
    final displayName = submission['display_name'] ?? username;
    final avatarUrl = submission['user_avatar_url'];
    final taskTitle = submission['task_title'] ?? 'Task';
    final pointsEarned = submission['points_earned'] ?? 0;
    final aiVerified = submission['ai_verified'] ?? false;
    final userReaction = submission['user_reaction'];
    final reactionCount = submission['reaction_count'] ?? 0;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.04,
        vertical: screenWidth * 0.03,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: User info
          Padding(
            padding: EdgeInsets.all(screenWidth * 0.03),
            child: Row(
              children: [
                // Avatar
                avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        imageBuilder: (context, imageProvider) => CircleAvatar(
                          backgroundImage: imageProvider,
                          radius: screenWidth * 0.05,
                        ),
                        placeholder: (context, url) => CircleAvatar(
                          radius: screenWidth * 0.05,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (context, url, error) => CircleAvatar(
                          radius: screenWidth * 0.05,
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            displayName[0].toUpperCase(),
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                      )
                    : CircleAvatar(
                        radius: screenWidth * 0.05,
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          displayName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                SizedBox(width: screenWidth * 0.03),
                // User info - flexible to prevent overflow
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display name (primary)
                      Text(
                        displayName,
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: (screenWidth * 0.04).clamp(14.0, 16.0),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: screenHeight * 0.002),
                      // Username (secondary) + Task title
                      Row(
                        children: [
                          Text(
                            '@$username',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: (screenWidth * 0.03).clamp(10.0, 12.0),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.015),
                          Text(
                            '•',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: (screenWidth * 0.03).clamp(10.0, 12.0),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.015),
                          Flexible(
                            child: Text(
                              taskTitle,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: (screenWidth * 0.03).clamp(10.0, 12.0),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (aiVerified) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth * 0.015,
                                vertical: screenHeight * 0.002,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified, color: Colors.green, size: (screenWidth * 0.03).clamp(10.0, 12.0)),
                                  const SizedBox(width: 2),
                                  Text(
                                    '+$pointsEarned',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: (screenWidth * 0.025).clamp(9.0, 10.0),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // More options icon
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.grey[600], size: (screenWidth * 0.06).clamp(20.0, 24.0)),
                  onPressed: () => _showSubmissionOptions(submission),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Media
          if (isVideo)
            _buildVideoThumbnail(mediaUrl, thumbnailUrl)
          else
            _buildImageContent(mediaUrl),

          // Reactions and Comments bar
          Padding(
            padding: EdgeInsets.all(screenWidth * 0.03),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reactions row (wrappable)
                Wrap(
                  spacing: screenWidth * 0.02,
                  runSpacing: screenWidth * 0.02,
                  children: [
                    // Add reaction button (always shows 😊)
                    GestureDetector(
                      onTap: () => _showReactionPicker(submission),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenWidth * 0.015,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '😊',
                              style: TextStyle(
                                fontSize: (screenWidth * 0.05).clamp(18.0, 20.0),
                              ),
                            ),
                            SizedBox(width: screenWidth * 0.015),
                            Icon(
                              Icons.add,
                              size: (screenWidth * 0.04).clamp(14.0, 16.0),
                              color: Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Display all reaction types with counts
                    ..._buildReactionBadges(submission, screenWidth),
                  ],
                ),
                SizedBox(height: screenWidth * 0.02),
                // Comment button row
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showCommentsBottomSheet(submission),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.02,
                          vertical: screenWidth * 0.01,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.comment_outlined,
                              color: Colors.grey[600],
                              size: (screenWidth * 0.05).clamp(18.0, 20.0),
                            ),
                            SizedBox(width: screenWidth * 0.015),
                            Text(
                              'View ${submission['comment_count'] ?? 0} comments',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: (screenWidth * 0.035).clamp(12.0, 14.0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(String mediaUrl) {
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = (screenHeight * 0.4).clamp(250.0, 400.0);

    return GestureDetector(
      onTap: () {
        // TODO: Open full-screen view
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: mediaUrl,
          width: double.infinity,
          height: imageHeight,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: imageHeight,
            color: Colors.grey.shade100,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            height: imageHeight,
            color: Colors.grey.shade100,
            child: const Center(
              child: Icon(Icons.error, color: Colors.red, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(String videoUrl, String? thumbnailUrl) {
    final screenHeight = MediaQuery.of(context).size.height;
    final videoHeight = (screenHeight * 0.4).clamp(250.0, 400.0);

    return GestureDetector(
      onTap: () {
        // TODO: Play video
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: thumbnailUrl,
                width: double.infinity,
                height: videoHeight,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: videoHeight,
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: videoHeight,
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: Icon(Icons.videocam_off, color: Colors.red, size: 48),
                  ),
                ),
              )
            else
              Container(
                height: videoHeight,
                color: Colors.grey.shade100,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.grey, size: 64),
                ),
              ),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
            ),
          ],
        ),
      ),
    );
  }

  String _getReactionEmoji(String reactionType) {
    switch (reactionType) {
      case 'love':
        return '❤️';
      case 'fire':
        return '🔥';
      case 'clap':
        return '👏';
      case 'like':
        return '👍';
      case 'wow':
        return '😮';
      default:
        return '😊';
    }
  }

  List<Widget> _buildReactionBadges(Map<String, dynamic> submission, double screenWidth) {
    final reactions = submission['reactions'] as Map<String, dynamic>?;
    final userReaction = submission['user_reaction'];
    final badges = <Widget>[];

    if (reactions != null && reactions.isNotEmpty) {
      reactions.forEach((type, count) {
        if (count > 0) {
          final isUserReaction = userReaction == type;
          badges.add(
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.025,
                vertical: screenWidth * 0.015,
              ),
              decoration: BoxDecoration(
                color: isUserReaction
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isUserReaction
                      ? Colors.blue
                      : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getReactionEmoji(type),
                    style: TextStyle(
                      fontSize: (screenWidth * 0.045).clamp(16.0, 18.0),
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.01),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: (screenWidth * 0.03).clamp(11.0, 13.0),
                      fontWeight: FontWeight.w600,
                      color: isUserReaction ? Colors.blue : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      });
    }

    return badges;
  }

  void _showReactionPicker(Map<String, dynamic> submission) {
    final submissionId = submission['id'];
    final userReaction = submission['user_reaction'];

    // Find the position of the reaction button
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: () => overlayEntry?.remove(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned(
              left: MediaQuery.of(context).size.width * 0.05,
              bottom: MediaQuery.of(context).size.height * 0.35,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFloatingReactionOption('❤️', 'love', userReaction, submissionId, overlayEntry),
                      const SizedBox(width: 4),
                      _buildFloatingReactionOption('🔥', 'fire', userReaction, submissionId, overlayEntry),
                      const SizedBox(width: 4),
                      _buildFloatingReactionOption('👏', 'clap', userReaction, submissionId, overlayEntry),
                      const SizedBox(width: 4),
                      _buildFloatingReactionOption('👍', 'like', userReaction, submissionId, overlayEntry),
                      const SizedBox(width: 4),
                      _buildFloatingReactionOption('😮', 'wow', userReaction, submissionId, overlayEntry),
                      if (userReaction != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            _removeReaction(submissionId);
                            overlayEntry?.remove();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.red,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  Widget _buildFloatingReactionOption(
      String emoji, String reactionType, String? userReaction, String submissionId, OverlayEntry? overlayEntry) {
    final isActive = userReaction == reactionType;

    return GestureDetector(
      onTap: () {
        if (!isActive) {
          _reactToSubmission(submissionId, reactionType);
        }
        overlayEntry?.remove();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
          border: isActive ? Border.all(color: Colors.blue, width: 2) : null,
        ),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }

  void _showSubmissionOptions(Map<String, dynamic> submission) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.orange),
              title: const Text('Report', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _reportSubmission(submission['id']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text('View Profile', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to user profile
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.blue),
              title: const Text('Share', style: TextStyle(color: Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _shareSubmission(submission);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportSubmission(String submissionId) async {
    final reason = await _showReportDialog();
    if (reason == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('https://zarqmessenger.com/tasks/submissions/$submissionId/report'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'reason': reason}),
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Report submitted. Thank you!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to report: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error reporting: $e');
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

  Future<String?> _showReportDialog() async {
    String? selectedReason;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report Submission', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReportOption('Inappropriate content', (value) => selectedReason = value),
            _buildReportOption('Spam', (value) => selectedReason = value),
            _buildReportOption('Fake/misleading', (value) => selectedReason = value),
            _buildReportOption('Offensive', (value) => selectedReason = value),
            _buildReportOption('Other', (value) => selectedReason = value),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selectedReason),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportOption(String label, Function(String) onSelect) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.black87)),
      onTap: () {
        onSelect(label);
        Navigator.pop(context, label);
      },
    );
  }

  void _showCommentsBottomSheet(Map<String, dynamic> submission) {
    final TextEditingController commentController = TextEditingController();
    List<Map<String, dynamic>> comments = [];
    bool isLoadingComments = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Load comments when modal opens
          if (isLoadingComments) {
            _loadComments(submission['id']).then((loadedComments) {
              setModalState(() {
                comments = loadedComments;
                isLoadingComments = false;
              });
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Comments',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Comments list
                    Expanded(
                      child: isLoadingComments
                          ? const Center(
                              child: CircularProgressIndicator(color: Colors.blue),
                            )
                          : comments.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No comments yet.\nBe the first to comment!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: comments.length,
                                  itemBuilder: (context, index) {
                                    final comment = comments[index];
                                    final currentUserId =
                                        FirebaseAuth.instance.currentUser?.uid;
                                    final isOwnComment =
                                        comment['user_id'] == currentUserId;

                                    final avatarUrl = comment['user_avatar_url'];
                                    final commentUsername = comment['username'] ?? 'anonymous';
                                    final commentDisplayName = comment['display_name'] ?? commentUsername;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 6),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // User avatar
                                          avatarUrl != null && avatarUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: avatarUrl,
                                                  imageBuilder: (context, imageProvider) => CircleAvatar(
                                                    backgroundImage: imageProvider,
                                                    radius: 16,
                                                  ),
                                                  placeholder: (context, url) => CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: Colors.blue.shade100,
                                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                                  ),
                                                  errorWidget: (context, url, error) => CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: Colors.blue.shade100,
                                                    child: Text(
                                                      commentDisplayName[0].toUpperCase(),
                                                      style: const TextStyle(
                                                          color: Colors.blue, fontSize: 12),
                                                    ),
                                                  ),
                                                )
                                              : CircleAvatar(
                                                  backgroundColor: Colors.blue.shade100,
                                                  radius: 16,
                                                  child: Text(
                                                    commentDisplayName[0].toUpperCase(),
                                                    style: const TextStyle(
                                                        color: Colors.blue, fontSize: 12),
                                                  ),
                                                ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: GestureDetector(
                                              onLongPress: isOwnComment ? () {
                                                _showCommentOptions(context, comment['id'].toString(), setModalState, comments, index, submission);
                                              } : null,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isOwnComment
                                                      ? Colors.blue.shade50
                                                      : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // Display name and username
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: RichText(
                                                            text: TextSpan(
                                                              children: [
                                                                TextSpan(
                                                                  text: commentDisplayName,
                                                                  style: const TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 13,
                                                                    color: Colors.black87,
                                                                  ),
                                                                ),
                                                                const TextSpan(text: ' '),
                                                                TextSpan(
                                                                  text: '@$commentUsername',
                                                                  style: TextStyle(
                                                                    fontSize: 11,
                                                                    color: Colors.grey[600],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (isOwnComment)
                                                          GestureDetector(
                                                            onTap: () {
                                                              _showCommentOptions(context, comment['id'].toString(), setModalState, comments, index, submission);
                                                            },
                                                            child: Container(
                                                              padding: const EdgeInsets.all(4),
                                                              child: Icon(
                                                                Icons.more_horiz,
                                                                size: 16,
                                                                color: Colors.grey[600],
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Comment text
                                                    Text(
                                                      comment['comment_text'] ?? '',
                                                      style: const TextStyle(
                                                        color: Colors.black87,
                                                        fontSize: 14,
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Timestamp
                                                    Text(
                                                      _formatCommentTime(comment['created_at']),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),

                    // Comment input
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 100),
                                child: TextField(
                                  controller: commentController,
                                  decoration: InputDecoration(
                                    hintText: 'Write a comment...',
                                    hintStyle: TextStyle(
                                        color: Colors.grey[400], fontSize: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide:
                                          BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide:
                                          BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: const BorderSide(
                                          color: Colors.blue, width: 2),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    isDense: true,
                                  ),
                                  style: const TextStyle(
                                      color: Colors.black87, fontSize: 14),
                                  maxLength: 500,
                                  maxLines: null,
                                  textInputAction: TextInputAction.newline,
                                  buildCounter: (context,
                                          {required currentLength,
                                          required isFocused,
                                          maxLength}) =>
                                      null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  if (commentController.text.trim().isEmpty) return;

                                  final newComment = await _postComment(
                                    submission['id'],
                                    commentController.text.trim(),
                                  );

                                  if (newComment != null) {
                                    setModalState(() {
                                      comments.add(newComment);
                                    });
                                    setState(() {
                                      final submissionIndex = _submissions
                                          .indexWhere(
                                              (s) => s['id'] == submission['id']);
                                      if (submissionIndex != -1) {
                                        _submissions[submissionIndex]
                                                ['comment_count'] =
                                            (_submissions[submissionIndex]
                                                        ['comment_count'] ??
                                                    0) +
                                                1;
                                      }
                                    });
                                    commentController.clear();
                                  }
                                },
                                icon: const Icon(Icons.send,
                                    color: Colors.white, size: 20),
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadComments(String submissionId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse(
            'https://zarqmessenger.com/tasks/submissions/$submissionId/comments'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['comments'] ?? []);
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error loading comments: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> _postComment(
      String submissionId, String commentText) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse(
            'https://zarqmessenger.com/tasks/submissions/$submissionId/comments'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'comment_text': commentText}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error posting comment: $e');
    }
    return null;
  }

  Future<bool> _deleteComment(String commentId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final token = await user.getIdToken();
      final response = await http.delete(
        Uri.parse('https://zarqmessenger.com/tasks/comments/$commentId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[TaskGlobalFeedScreen] Error deleting comment: $e');
      return false;
    }
  }

  Future<void> _shareSubmission(Map<String, dynamic> submission) async {
    final username = submission['username'] ?? 'Someone';
    final displayName = submission['display_name'] ?? username;
    final taskTitle = submission['task_title'] ?? 'a task';
    final pointsEarned = submission['points_earned'] ?? 0;
    final caption = submission['caption'] ?? '';
    final mediaUrl = submission['media_url'] as String?;

    final shareText = '''
🎯 Zarq Tasks Challenge!

$displayName (@$username) just completed "$taskTitle" and earned $pointsEarned points! 💪

${caption.isNotEmpty ? '$caption\n\n' : ''}Join the challenge and complete daily tasks on Zarq Messenger!

Download Zarq Messenger to participate! 🚀
    '''.trim();

    // If there's an image, download and share with text
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      try {
        // Download the image
        final response = await http.get(Uri.parse(mediaUrl));
        if (response.statusCode == 200) {
          // Get temporary directory
          final tempDir = await getTemporaryDirectory();
          final fileName = 'zarq_task_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${tempDir.path}/$fileName');

          // Write image to file
          await file.writeAsBytes(response.bodyBytes);

          // Share image with text
          await Share.shareXFiles(
            [XFile(file.path)],
            text: shareText,
            subject: 'Check out this task completion on Zarq!',
          );

          return;
        }
      } catch (e) {
        print('[TaskGlobalFeedScreen] Error sharing image: $e');
        // Fall through to text-only share
      }
    }

    // Fallback to text-only share
    Share.share(
      shareText,
      subject: 'Check out this task completion on Zarq!',
    );
  }

  String _formatCommentTime(dynamic timestamp) {
    try {
      DateTime commentTime = timestamp is String
          ? DateTime.parse(timestamp)
          : timestamp as DateTime;

      // Convert to local time
      final localTime = commentTime.toLocal();

      // Format: 2:45 PM or 10:30 AM
      final hour = localTime.hour;
      final minute = localTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

      return '$displayHour:$minute $period';
    } catch (e) {
      return '';
    }
  }

  void _showCommentOptions(
    BuildContext context,
    String commentId,
    StateSetter setModalState,
    List<Map<String, dynamic>> comments,
    int index,
    Map<String, dynamic> submission,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: screenHeight * 0.02,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Delete Card
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(screenWidth * 0.04),
                elevation: 2,
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(context);

                    // Show confirmation dialog with responsive sizing
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(screenWidth * 0.05),
                        ),
                        contentPadding: EdgeInsets.all(screenWidth * 0.06),
                        title: Column(
                          children: [
                            Container(
                              width: screenWidth * 0.16,
                              height: screenWidth * 0.16,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.delete_rounded,
                                color: Colors.red,
                                size: screenWidth * 0.08,
                              ),
                            ),
                            SizedBox(height: screenHeight * 0.02),
                            Text(
                              'Delete Comment?',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.055,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        content: Text(
                          'This action cannot be undone. Are you sure you want to delete this comment?',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: screenWidth * 0.04,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        actions: [
                          // Cancel button
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.018),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                                  side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: screenWidth * 0.04,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.03),
                          // Delete button
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.018),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                                ),
                              ),
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: screenWidth * 0.04,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                        actionsPadding: EdgeInsets.fromLTRB(
                          screenWidth * 0.06,
                          0,
                          screenWidth * 0.06,
                          screenWidth * 0.04,
                        ),
                      ),
                    );

                    if (confirmed == true) {
                      final success = await _deleteComment(commentId);
                      if (success) {
                        setModalState(() {
                          comments.removeAt(index);
                        });
                        setState(() {
                          final submissionIndex =
                              _submissions.indexWhere((s) => s['id'] == submission['id']);
                          if (submissionIndex != -1) {
                            _submissions[submissionIndex]['comment_count'] =
                                (_submissions[submissionIndex]['comment_count'] ?? 1) - 1;
                          }
                        });

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Comment deleted',
                                style: TextStyle(fontSize: screenWidth * 0.04),
                              ),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.all(screenWidth * 0.04),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(screenWidth * 0.02),
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(screenWidth * 0.04),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.05,
                      vertical: screenHeight * 0.02,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: screenWidth * 0.12,
                          height: screenWidth * 0.12,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(screenWidth * 0.03),
                          ),
                          child: Icon(
                            Icons.delete_rounded,
                            color: Colors.red,
                            size: screenWidth * 0.06,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.04),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delete Comment',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: screenWidth * 0.045,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.004),
                              Text(
                                'Remove this comment permanently',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: screenWidth * 0.035,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey[400],
                          size: screenWidth * 0.06,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.015),
              // Cancel Card
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(screenWidth * 0.04),
                elevation: 2,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(screenWidth * 0.04),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                    alignment: Alignment.center,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: screenWidth * 0.045,
                        fontWeight: FontWeight.w600,
                      ),
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
}
