import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';

class TaskCameraScreen extends StatefulWidget {
  final Map<String, dynamic> task;

  const TaskCameraScreen({super.key, required this.task});

  @override
  State<TaskCameraScreen> createState() => _TaskCameraScreenState();
}

class _TaskCameraScreenState extends State<TaskCameraScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isCameraInitialized = false;
  File? _capturedFile;
  String? _capturedMediaType; // 'image' or 'video'
  VideoPlayerController? _videoPlayerController;
  bool _isUploading = false;
  String _selectedVisibility = 'friends'; // 'global' or 'friends' - default to friends
  bool _requiresVerification = false;

  @override
  void initState() {
    super.initState();
    _requiresVerification = widget.task['require_verification'] ?? false;
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: true,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      print('[TaskCameraScreen] Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      setState(() {
        _capturedFile = File(image.path);
        _capturedMediaType = 'image';
      });
    } catch (e) {
      print('[TaskCameraScreen] Error taking picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking picture: $e')),
        );
      }
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      print('[TaskCameraScreen] Error starting video recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting video: $e')),
        );
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      final video = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _capturedFile = File(video.path);
        _capturedMediaType = 'video';
      });

      // Initialize video player for preview
      _videoPlayerController = VideoPlayerController.file(_capturedFile!)
        ..initialize().then((_) {
          setState(() {});
          _videoPlayerController!.play();
          _videoPlayerController!.setLooping(true);
        });
    } catch (e) {
      print('[TaskCameraScreen] Error stopping video recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping video: $e')),
        );
      }
    }
  }

  Future<void> _pickFromGallery(String type) async {
    final picker = ImagePicker();

    if (type == 'image') {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _capturedFile = File(pickedFile.path);
          _capturedMediaType = 'image';
        });
      }
    } else if (type == 'video') {
      final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _capturedFile = File(pickedFile.path);
          _capturedMediaType = 'video';
        });

        // Initialize video player for preview
        _videoPlayerController = VideoPlayerController.file(_capturedFile!)
          ..initialize().then((_) {
            setState(() {});
            _videoPlayerController!.play();
            _videoPlayerController!.setLooping(true);
          });
      }
    }
  }

  Future<void> _submitTask() async {
    if (_capturedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture or select a photo/video first')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final token = await user.getIdToken();

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://zarqmessenger.com/tasks/submit'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['task_id'] = widget.task['id'].toString();
      request.fields['is_task_submission'] = 'true';
      request.fields['media_type'] = _capturedMediaType!;
      request.fields['visibility'] = _selectedVisibility;

      // Add file
      final fileStream = http.ByteStream(_capturedFile!.openRead());
      final fileLength = await _capturedFile!.length();
      final multipartFile = http.MultipartFile(
        'media',
        fileStream,
        fileLength,
        filename: _capturedFile!.path.split('/').last,
      );
      request.files.add(multipartFile);

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (mounted) {
        setState(() => _isUploading = false);

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Success - parse submission ID
          final responseData = json.decode(response.body);
          final submissionId = responseData['submission_id'] as String?;

          if (_requiresVerification && submissionId != null) {
            _checkVerificationResult(submissionId);
          } else {
            _showSuccessDialog(verified: true, points: 0);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('[TaskCameraScreen] Error submitting task: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkVerificationResult(String submissionId) async {
    // Show loading dialog
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 24),
            const Text(
              'AI Verification in Progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Our AI is checking if you completed the task correctly...',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    // Wait for AI to process (5 seconds)
    await Future.delayed(const Duration(seconds: 5));

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final token = await user.getIdToken();
      final response = await http.get(
        Uri.parse('https://zarqmessenger.com/tasks/submissions/$submissionId/status'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final verified = data['ai_verified'] as bool;
          final points = data['points_earned'] as int;
          final confidence = data['ai_verification_confidence'] as int;

          _showSuccessDialog(
            verified: verified,
            points: points,
            confidence: confidence,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not fetch verification result')),
          );
          Navigator.of(context).pop(); // Return to tasks screen
        }
      }
    } catch (e) {
      print('[TaskCameraScreen] Error checking verification: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        Navigator.of(context).pop(); // Return to tasks screen
      }
    }
  }

  void _showSuccessDialog({
    required bool verified,
    required int points,
    int confidence = 0,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              verified ? Icons.check_circle : Icons.cancel,
              color: verified ? Colors.green : Colors.red,
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              verified ? 'Task Completed!' : 'Task Failed',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              verified
                  ? 'AI verified your submission successfully!'
                  : 'AI could not verify the task. Please try again with the correct content.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (verified && points > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.cyanAccent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '+$points Points',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (confidence > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Confidence: $confidence%',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Return to tasks screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: verified ? Colors.cyanAccent : Colors.grey[700],
                foregroundColor: verified ? Colors.black : Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.task['title_en'] ?? 'Complete Task',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _capturedFile == null
          ? _buildCameraView()
          : _buildPreviewView(),
    );
  }

  Widget _buildCameraView() {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      );
    }

    return Stack(
      children: [
        // Camera preview
        Positioned.fill(
          child: CameraPreview(_cameraController!),
        ),

        // Task info overlay (top)
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.task['description_en'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.task['description_hi'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.task['description_hi'],
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Controls (bottom)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.9),
                  Colors.black.withOpacity(0.0),
                ],
              ),
            ),
            child: Column(
              children: [
                // Gallery buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildGalleryButton('Photo', Icons.photo_library, () => _pickFromGallery('image')),
                    _buildGalleryButton('Video', Icons.video_library, () => _pickFromGallery('video')),
                  ],
                ),
                const SizedBox(height: 24),
                // Capture buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Photo button
                    FloatingActionButton(
                      onPressed: _takePicture,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.camera_alt, color: Colors.black, size: 32),
                    ),
                    // Video button
                    FloatingActionButton(
                      onPressed: _isRecording ? _stopVideoRecording : _startVideoRecording,
                      backgroundColor: _isRecording ? Colors.red : Colors.white,
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.videocam,
                        color: _isRecording ? Colors.white : Colors.black,
                        size: 32,
                      ),
                    ),
                  ],
                ),
                if (_isRecording) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Recording...',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    return Stack(
      children: [
        // Preview
        Positioned.fill(
          child: _capturedMediaType == 'image'
              ? Image.file(_capturedFile!, fit: BoxFit.contain)
              : _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoPlayerController!.value.aspectRatio,
                      child: VideoPlayer(_videoPlayerController!),
                    )
                  : const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        ),

        // Controls overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.9),
                  Colors.black.withOpacity(0.0),
                ],
              ),
            ),
            child: Column(
              children: [
                // Visibility selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Who can see this?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildVisibilityOption(
                              'Global',
                              'Everyone',
                              Icons.public,
                              'global',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildVisibilityOption(
                              'Friends',
                              'Friends only',
                              Icons.people,
                              'friends',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _capturedFile = null;
                            _capturedMediaType = null;
                            _videoPlayerController?.dispose();
                            _videoPlayerController = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _submitTask,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(_isUploading ? 'Uploading...' : 'Submit'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilityOption(String title, String subtitle, IconData icon, String value) {
    final isSelected = _selectedVisibility == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedVisibility = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.grey[700]!,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.cyanAccent : Colors.grey[400],
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.cyanAccent : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
