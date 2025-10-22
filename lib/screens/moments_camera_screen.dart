import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:zarq_messenger/services/moments_service.dart';

class MomentsCameraScreen extends StatefulWidget {
  final List<String> friendsList;

  const MomentsCameraScreen({Key? key, required this.friendsList}) : super(key: key);

  @override
  State<MomentsCameraScreen> createState() => _MomentsCameraScreenState();
}

class _MomentsCameraScreenState extends State<MomentsCameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isLoading = true;
  bool _isFrontCamera = false;

  File? _capturedMedia;
  String? _mediaType;
  VideoPlayerController? _videoController;

  String _visibility = 'friends';
  TextEditingController _captionController = TextEditingController();

  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      _cameraController = CameraController(
        _cameras![_isFrontCamera ? 1 : 0],
        ResolutionPreset.high,
        enableAudio: true,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('[MomentsCamera] Error initializing camera: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _switchCamera() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isLoading = true;
    });

    await _cameraController?.dispose();
    await _initializeCamera();
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      setState(() {
        _capturedMedia = File(image.path);
        _mediaType = 'image';
      });
    } catch (e) {
      print('[MomentsCamera] Error capturing photo: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture photo')),
      );
    }
  }

  Future<void> _recordVideo() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      if (_cameraController!.value.isRecordingVideo) {
        final video = await _cameraController!.stopVideoRecording();
        setState(() {
          _capturedMedia = File(video.path);
          _mediaType = 'video';
        });
        _initializeVideoPlayer();
      } else {
        await _cameraController!.startVideoRecording();
        setState(() {});
      }
    } catch (e) {
      print('[MomentsCamera] Error recording video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record video')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final screenWidth = MediaQuery.of(context).size.width;
      final fontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
      final iconSize = (screenWidth * 0.06).clamp(22.0, 28.0);

      final pickedFile = await showDialog<XFile?>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Choose Media', style: TextStyle(fontSize: fontSize * 1.2)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.image, size: iconSize),
                title: Text('Image', style: TextStyle(fontSize: fontSize)),
                onTap: () async {
                  final file = await picker.pickImage(source: ImageSource.gallery);
                  Navigator.pop(context, file);
                },
              ),
              ListTile(
                leading: Icon(Icons.video_library, size: iconSize),
                title: Text('Video', style: TextStyle(fontSize: fontSize)),
                onTap: () async {
                  final file = await picker.pickVideo(source: ImageSource.gallery);
                  Navigator.pop(context, file);
                },
              ),
            ],
          ),
        ),
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);
        final isVideo = pickedFile.path.toLowerCase().endsWith('.mp4') ||
            pickedFile.path.toLowerCase().endsWith('.mov');

        setState(() {
          _capturedMedia = file;
          _mediaType = isVideo ? 'video' : 'image';
        });

        if (isVideo) {
          _initializeVideoPlayer();
        }
      }
    } catch (e) {
      print('[MomentsCamera] Error picking from gallery: $e');
    }
  }

  void _initializeVideoPlayer() {
    if (_capturedMedia != null && _mediaType == 'video') {
      _videoController = VideoPlayerController.file(_capturedMedia!)
        ..initialize().then((_) {
          setState(() {});
          _videoController!.play();
          _videoController!.setLooping(true);
        });
    }
  }

  Future<void> _uploadMoment() async {
    if (_capturedMedia == null || _mediaType == null) return;

    if (_visibility == 'friends' && widget.friendsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You need friends to share moments with them')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final result = await MomentsService.createMoment(
        mediaFile: _capturedMedia!,
        mediaType: _mediaType!,
        visibility: _visibility,
        caption: _captionController.text.trim().isNotEmpty ? _captionController.text.trim() : null,
        friendsList: _visibility == 'friends' ? widget.friendsList : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moment shared successfully!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('[MomentsCamera] Error uploading moment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share moment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _discardMedia() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _capturedMedia = null;
      _mediaType = null;
      _captionController.clear();
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_capturedMedia != null) {
      return _buildPreviewScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _cameraController == null || !_cameraController!.value.isInitialized
              ? Center(child: Text('Camera not available', style: TextStyle(color: Colors.white)))
              : Stack(
                  children: [
                    Positioned.fill(
                      child: CameraPreview(_cameraController!),
                    ),
                    SafeArea(
                      child: Column(
                        children: [
                          _buildTopBar(),
                          Spacer(),
                          _buildBottomControls(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTopBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.075).clamp(26.0, 34.0);
    final padding = (screenWidth * 0.04).clamp(12.0, 20.0);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: iconSize),
            onPressed: () => Navigator.pop(context),
          ),
          Spacer(),
          IconButton(
            icon: Icon(Icons.flip_camera_android, color: Colors.white, size: iconSize),
            onPressed: _switchCamera,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final isRecording = _cameraController?.value.isRecordingVideo ?? false;
    final screenWidth = MediaQuery.of(context).size.width;

    final iconSize = (screenWidth * 0.08).clamp(28.0, 36.0);
    final captureButtonSize = (screenWidth * 0.18).clamp(60.0, 80.0);
    final borderWidth = (screenWidth * 0.01).clamp(3.0, 5.0);
    final padding = (screenWidth * 0.04).clamp(12.0, 20.0);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(Icons.photo_library, color: Colors.white, size: iconSize),
            onPressed: _pickFromGallery,
          ),
          GestureDetector(
            onTap: _capturePhoto,
            child: Container(
              width: captureButtonSize,
              height: captureButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: borderWidth),
                color: Colors.transparent,
              ),
              child: Icon(Icons.camera_alt, color: Colors.white, size: iconSize * 0.7),
            ),
          ),
          IconButton(
            icon: Icon(
              isRecording ? Icons.stop_circle : Icons.videocam,
              color: isRecording ? Colors.red : Colors.white,
              size: iconSize,
            ),
            onPressed: _recordVideo,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _mediaType == 'video' && _videoController != null && _videoController!.value.isInitialized
                ? VideoPlayer(_videoController!)
                : Image.file(_capturedMedia!, fit: BoxFit.contain),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildPreviewTopBar(),
                Spacer(),
                _buildPreviewControls(),
              ],
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewTopBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = (screenWidth * 0.075).clamp(26.0, 34.0);
    final fontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final padding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final spacing = (screenWidth * 0.02).clamp(6.0, 10.0);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: Colors.white, size: iconSize),
            onPressed: _isUploading ? null : _discardMedia,
          ),
          Spacer(),
          Text(
            _visibility == 'friends' ? 'Friends Only' : 'Everyone',
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold),
          ),
          SizedBox(width: spacing),
        ],
      ),
    );
  }

  Widget _buildPreviewControls() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final fontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final padding = (screenWidth * 0.04).clamp(12.0, 20.0);
    final spacing = (screenHeight * 0.02).clamp(12.0, 20.0);
    final buttonPaddingH = (screenWidth * 0.08).clamp(24.0, 40.0);
    final buttonPaddingV = (screenHeight * 0.015).clamp(10.0, 16.0);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _captionController,
            style: TextStyle(color: Colors.white, fontSize: fontSize),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: TextStyle(color: Colors.white54, fontSize: fontSize),
              border: InputBorder.none,
            ),
            maxLines: 2,
            enabled: !_isUploading,
          ),
          SizedBox(height: spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ChoiceChip(
                label: Text('Friends', style: TextStyle(fontSize: fontSize)),
                selected: _visibility == 'friends',
                onSelected: _isUploading ? null : (selected) {
                  if (selected) setState(() => _visibility = 'friends');
                },
                selectedColor: Colors.blue,
                backgroundColor: Colors.grey[800],
                labelStyle: TextStyle(color: Colors.white),
              ),
              ChoiceChip(
                label: Text('Global', style: TextStyle(fontSize: fontSize)),
                selected: _visibility == 'global',
                onSelected: _isUploading ? null : (selected) {
                  if (selected) setState(() => _visibility = 'global');
                },
                selectedColor: Colors.purple,
                backgroundColor: Colors.grey[800],
                labelStyle: TextStyle(color: Colors.white),
              ),
            ],
          ),
          SizedBox(height: spacing),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadMoment,
            icon: Icon(Icons.send, size: fontSize),
            label: Text(_isUploading ? 'Sharing...' : 'Share Moment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: EdgeInsets.symmetric(horizontal: buttonPaddingH, vertical: buttonPaddingV),
              textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
