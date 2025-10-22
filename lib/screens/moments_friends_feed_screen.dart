import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zarq_messenger/models/moment_model.dart';
import 'package:zarq_messenger/services/moments_service.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MomentsFriendsFeedScreen extends StatefulWidget {
  const MomentsFriendsFeedScreen({Key? key}) : super(key: key);

  @override
  State<MomentsFriendsFeedScreen> createState() => _MomentsFriendsFeedScreenState();
}

class _MomentsFriendsFeedScreenState extends State<MomentsFriendsFeedScreen> {
  List<MomentModel> _moments = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  int _currentIndex = 0;
  PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadMoments();
  }

  Future<void> _loadMoments() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final moments = await MomentsService.getFriendsMoments(limit: 50);
      setState(() {
        _moments = moments;
        _isLoading = false;
      });
    } catch (e) {
      print('[FriendsMomentsFeed] Error loading moments: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _nextMoment() {
    if (_currentIndex < _moments.length - 1) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _previousMoment() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Colors.purple),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 16),
              Text(
                'Failed to load moments',
                style: TextStyle(color: Colors.black, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                _errorMessage ?? '',
                style: TextStyle(color: Colors.black54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadMoments,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_moments.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 64),
              SizedBox(height: 16),
              Text(
                'No moments yet',
                style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Be the first to share a moment!',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _moments.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          return MomentViewer(
            moment: _moments[index],
            onNext: _nextMoment,
            onPrevious: _previousMoment,
            onClose: () => Navigator.pop(context),
          );
        },
      ),
    );
  }
}

class MomentViewer extends StatefulWidget {
  final MomentModel moment;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  const MomentViewer({
    Key? key,
    required this.moment,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  }) : super(key: key);

  @override
  State<MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends State<MomentViewer> with AutomaticKeepAliveClientMixin {
  Uint8List? _decryptedMedia;
  bool _isDecrypting = true;
  VideoPlayerController? _videoController;
  bool _hasMarkedAsViewed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      print('[MomentViewer] Loading moment: ${widget.moment.id}, creator: ${widget.moment.userId}');
      print('[MomentViewer] Moment data:');
      print('[MomentViewer]   visibility: ${widget.moment.visibility}');
      print('[MomentViewer]   mediaUrl: ${widget.moment.mediaUrl}');
      print('[MomentViewer]   encryptedMediaUrl: ${widget.moment.encryptedMediaUrl}');
      print('[MomentViewer]   encryptedMediaKey: ${widget.moment.encryptedMediaKey}');
      print('[MomentViewer]   encryptedMediaIv: ${widget.moment.encryptedMediaIv}');

      // Decrypt media if it's friends-only
      if (widget.moment.visibility == 'friends') {
        if (widget.moment.encryptedMediaUrl == null) {
          print('[MomentViewer] Missing encrypted media URL!');
          throw Exception('Missing encrypted media URL');
        }

        // For creator's own moments, encrypted keys won't be in the response (we use local storage)
        // For friends' moments, keys should be present
        print('[MomentViewer] Starting decryption...');
        final decrypted = await MomentsService.decryptMomentMedia(
          momentId: widget.moment.id,
          encryptedMediaUrl: widget.moment.encryptedMediaUrl!,
          encryptedMediaKey: widget.moment.encryptedMediaKey ?? '',
          encryptedMediaIv: widget.moment.encryptedMediaIv ?? '',
          creatorUid: widget.moment.userId,
        );

        if (decrypted == null) {
          print('[MomentViewer] Decryption returned null');
          throw Exception('Failed to decrypt media');
        }

        print('[MomentViewer] Decryption successful, size: ${decrypted.length} bytes');

        setState(() {
          _decryptedMedia = decrypted;
          _isDecrypting = false;
        });

        // Initialize video player for decrypted video
        if (widget.moment.mediaType == 'video') {
          print('[MomentViewer] Initializing video player for decrypted video');
          await _initializeDecryptedVideo(decrypted);
        }
      } else {
        // Global moment - no decryption needed
        setState(() => _isDecrypting = false);

        if (widget.moment.mediaType == 'video' && widget.moment.mediaUrl != null) {
          _videoController = VideoPlayerController.network(widget.moment.mediaUrl!)
            ..initialize().then((_) {
              setState(() {});
              _videoController!.play();
              _videoController!.setLooping(true);
            });
        }
      }

      // Mark as viewed
      if (!_hasMarkedAsViewed) {
        await MomentsService.markMomentAsViewed(widget.moment.id);
        _hasMarkedAsViewed = true;
      }
    } catch (e) {
      print('[MomentViewer] Error loading media: $e');
      setState(() => _isDecrypting = false);
    }
  }

  Future<void> _initializeDecryptedVideo(Uint8List videoData) async {
    try {
      // Save decrypted video to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/decrypted_video_${widget.moment.id}.mp4');

      print('[MomentViewer] Saving decrypted video to: ${tempFile.path}');
      await tempFile.writeAsBytes(videoData);

      // Initialize video player with temp file
      _videoController = VideoPlayerController.file(tempFile)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController!.play();
            _videoController!.setLooping(true);
            print('[MomentViewer] Video player initialized and playing');
          }
        }).catchError((error) {
          print('[MomentViewer] Error initializing video player: $error');
        });
    } catch (e) {
      print('[MomentViewer] Error in _initializeDecryptedVideo: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: Colors.black,
      child: GestureDetector(
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            widget.onPrevious();
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            widget.onNext();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildMediaContent(),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black54,
                    ],
                    stops: [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Spacer(),
                  if (widget.moment.caption != null && widget.moment.caption!.isNotEmpty)
                    _buildCaption(),
                  _buildInteractionBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    if (_isDecrypting) {
      return Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (widget.moment.mediaType == 'video') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        final screenWidth = MediaQuery.of(context).size.width;
        final playIconSize = (screenWidth * 0.2).clamp(60.0, 100.0);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
            });
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_videoController!),
              if (!_videoController!.value.isPlaying)
                Icon(Icons.play_circle_outline, color: Colors.white, size: playIconSize),
            ],
          ),
        );
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                widget.moment.visibility == 'friends' ? 'Decrypting video...' : 'Loading video...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        );
      }
    } else {
      // Image
      if (widget.moment.visibility == 'friends') {
        if (_decryptedMedia != null) {
          print('[MomentViewer] Showing decrypted image, size: ${_decryptedMedia!.length} bytes');
          return Image.memory(
            _decryptedMedia!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              print('[MomentViewer] Error displaying image: $error');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, color: Colors.white, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Failed to display image',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              );
            },
          );
        } else {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.white, size: 64),
                SizedBox(height: 16),
                Text(
                  'Failed to decrypt',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          );
        }
      } else if (widget.moment.mediaUrl != null) {
        return CachedNetworkImage(
          imageUrl: widget.moment.mediaUrl!,
          fit: BoxFit.contain,
          placeholder: (context, url) => Center(child: CircularProgressIndicator(color: Colors.white)),
          errorWidget: (context, url, error) => Center(
            child: Icon(Icons.error, color: Colors.white, size: 64),
          ),
        );
      } else {
        return Center(
          child: Icon(Icons.broken_image, color: Colors.white, size: 64),
        );
      }
    }
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: widget.moment.userAvatarUrl != null
                ? CachedNetworkImageProvider(widget.moment.userAvatarUrl!)
                : null,
            child: widget.moment.userAvatarUrl == null
                ? Text(widget.moment.username[0].toUpperCase())
                : null,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.moment.displayName ?? widget.moment.username,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.moment.timeAgo,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildCaption() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      child: Text(
        widget.moment.caption!,
        style: TextStyle(color: Colors.white, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildInteractionBar() {
    final isOwnMoment = widget.moment.userId == FirebaseAuth.instance.currentUser?.uid;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Delete button (only for own moments)
          if (isOwnMoment)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.white, size: 28),
              onPressed: () => _showDeleteDialog(),
            ),

          // View count (only for own moments)
          if (isOwnMoment) ...[
            SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showViewersDialog(),
              child: Row(
                children: [
                  Icon(Icons.visibility, color: Colors.white, size: 24),
                  SizedBox(width: 6),
                  Text(
                    '${widget.moment.viewCount}',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],

          Spacer(),

          // React button
          IconButton(
            icon: Icon(Icons.favorite_border, color: Colors.white, size: 28),
            onPressed: () => _showReactionsBottomSheet(),
          ),
          SizedBox(width: 8),

          // Comment button
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 28),
            onPressed: () => _showCommentsBottomSheet(),
          ),
          SizedBox(width: 8),

          // Reply button
          IconButton(
            icon: Icon(Icons.send, color: Colors.white, size: 28),
            onPressed: () => _showReplyDialog(),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Moment?'),
        content: Text('This moment will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await MomentsService.deleteMoment(widget.moment.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Moment deleted')),
                );
                widget.onClose();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete moment')),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showViewersDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Viewed by',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              '${widget.moment.viewCount} ${widget.moment.viewCount == 1 ? "person" : "people"}',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            SizedBox(height: 16),
            // TODO: Add list of viewers when API is ready
            Text('Viewer list coming soon', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showReactionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'React to this moment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _reactionButton('❤️', 'Love'),
                _reactionButton('🔥', 'Fire'),
                _reactionButton('😂', 'Laugh'),
                _reactionButton('😮', 'Wow'),
                _reactionButton('😢', 'Sad'),
                _reactionButton('👏', 'Clap'),
              ],
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _reactionButton(String emoji, String label) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        // TODO: Send reaction to server
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reacted with $emoji'), duration: Duration(seconds: 1)),
        );
      },
      child: Column(
        children: [
          Text(emoji, style: TextStyle(fontSize: 32)),
          SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet() {
    final TextEditingController commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Comments',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              // TODO: Display existing comments when API is ready
              Text('No comments yet', style: TextStyle(color: Colors.grey)),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send, color: Colors.purple),
                    onPressed: () {
                      if (commentController.text.trim().isNotEmpty) {
                        // TODO: Send comment to server
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Comment posted!')),
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showReplyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reply to ${widget.moment.displayName ?? widget.moment.username}'),
        content: TextField(
          decoration: InputDecoration(hintText: 'Type your message...'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Send reply as direct message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reply sent!')),
              );
            },
            child: Text('Send'),
          ),
        ],
      ),
    );
  }
}
