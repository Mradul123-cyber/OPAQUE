import 'package:flutter/material.dart';
import 'package:zarq_messenger/models/moment_model.dart';
import 'package:zarq_messenger/services/moments_service.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MomentsGlobalFeedScreen extends StatefulWidget {
  const MomentsGlobalFeedScreen({Key? key}) : super(key: key);

  @override
  State<MomentsGlobalFeedScreen> createState() => _MomentsGlobalFeedScreenState();
}

class _MomentsGlobalFeedScreenState extends State<MomentsGlobalFeedScreen> {
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
      final moments = await MomentsService.getGlobalMoments(limit: 50);
      setState(() {
        _moments = moments;
        _isLoading = false;
      });
    } catch (e) {
      print('[GlobalMomentsFeed] Error loading moments: $e');
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
          title: Text('Global Moments', style: TextStyle(color: Colors.black)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.public_off, color: Colors.grey, size: 64),
              SizedBox(height: 16),
              Text(
                'No global moments yet',
                style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Check back later!',
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
          return GlobalMomentViewer(
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

class GlobalMomentViewer extends StatefulWidget {
  final MomentModel moment;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  const GlobalMomentViewer({
    Key? key,
    required this.moment,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  }) : super(key: key);

  @override
  State<GlobalMomentViewer> createState() => _GlobalMomentViewerState();
}

class _GlobalMomentViewerState extends State<GlobalMomentViewer> with AutomaticKeepAliveClientMixin {
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
      if (widget.moment.mediaType == 'video' && widget.moment.mediaUrl != null) {
        _videoController = VideoPlayerController.network(widget.moment.mediaUrl!)
          ..initialize().then((_) {
            if (mounted) {
              setState(() {});
              _videoController!.play();
              _videoController!.setLooping(true);
            }
          });
      }

      // Mark as viewed
      if (!_hasMarkedAsViewed) {
        await MomentsService.markMomentAsViewed(widget.moment.id);
        _hasMarkedAsViewed = true;
      }
    } catch (e) {
      print('[GlobalMomentViewer] Error loading media: $e');
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
                  _buildBottomInfo(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    if (widget.moment.mediaType == 'video') {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return VideoPlayer(_videoController!);
      } else {
        return Center(child: CircularProgressIndicator(color: Colors.white));
      }
    } else {
      // Image
      if (widget.moment.mediaUrl != null) {
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
                Row(
                  children: [
                    Text(
                      widget.moment.displayName ?? widget.moment.username,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple, width: 1),
                      ),
                      child: Text(
                        'GLOBAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildBottomInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text(
            '${widget.moment.viewCount} ${widget.moment.viewCount == 1 ? 'view' : 'views'}',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
