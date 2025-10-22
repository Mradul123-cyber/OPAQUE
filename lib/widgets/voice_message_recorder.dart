// lib/widgets/voice_message_recorder.dart
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class VoiceMessageRecorder extends StatefulWidget {
  final Function(String audioPath, int duration) onRecordingComplete;
  final VoidCallback onCancel;

  const VoiceMessageRecorder({
    Key? key,
    required this.onRecordingComplete,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<VoiceMessageRecorder> createState() => _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends State<VoiceMessageRecorder> {
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        // print('[VoiceRecorder] Microphone permission denied');
        widget.onCancel();
        return;
      }

      // Initialize recorder
      await _audioRecorder.openRecorder();

      // Get temp directory for recording
      final tempDir = await getTemporaryDirectory();
      _audioPath = path.join(tempDir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.aac');

      // Start recording (16kHz for Vosk transcription compatibility)
      await _audioRecorder.startRecorder(
        toFile: _audioPath,
        codec: Codec.aacADTS,
        bitRate: 64000,
        sampleRate: 16000,  // Match Vosk's expected sample rate
      );

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });

      // Start duration timer
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        setState(() {
          _recordDuration++;
        });

        // Auto-stop at 5 minutes (300 seconds)
        if (_recordDuration >= 300) {
          _stopRecording();
        }
      });
    } catch (e) {
      // print('[VoiceRecorder] Error starting recording: $e');
      widget.onCancel();
    }
  }

  Future<void> _stopRecording() async {
    try {
      _timer?.cancel();

      final recordedPath = await _audioRecorder.stopRecorder();

      setState(() {
        _isRecording = false;
      });

      if (recordedPath != null) {
        print('[VoiceRecorder] Recording saved: $recordedPath (${_recordDuration}s)');

        widget.onRecordingComplete(recordedPath, _recordDuration);
      } else {
        print('[VoiceRecorder] Recording failed - no path');
        widget.onCancel();
      }
    } catch (e) {
      print('[VoiceRecorder] Error stopping recording: $e');
      widget.onCancel();
    }
  }

  void _cancelRecording() async {
    try {
      _timer?.cancel();
      await _audioRecorder.stopRecorder();
      setState(() {
        _isRecording = false;
      });
      widget.onCancel();
    } catch (e) {
      // print('[VoiceRecorder] Error canceling recording: $e');
      widget.onCancel();
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          // Cancel button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _cancelRecording,
          ),

          const SizedBox(width: 8),

          // Recording indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: _isRecording
                  ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),

          const SizedBox(width: 12),

          // Duration (removed live transcription display)
          Expanded(
            child: Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Waveform animation (simple pulsing circles)
          if (_isRecording) ...[
            _buildPulsingCircle(0),
            const SizedBox(width: 4),
            _buildPulsingCircle(100),
            const SizedBox(width: 4),
            _buildPulsingCircle(200),
            const SizedBox(width: 16),
          ],

          // Send button
          Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _isRecording ? _stopRecording : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingCircle(int delay) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 800 + delay),
      builder: (context, value, child) {
        return Container(
          width: 4,
          height: 16 + (value * 16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
      onEnd: () {
        if (mounted && _isRecording) {
          setState(() {}); // Restart animation
        }
      },
    );
  }
}
