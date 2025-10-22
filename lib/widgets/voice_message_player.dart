// lib/widgets/voice_message_player.dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';

class VoiceMessagePlayer extends StatefulWidget {
  final String audioPath;
  final int durationSeconds;
  final bool isSentByMe;

  const VoiceMessagePlayer({
    Key? key,
    required this.audioPath,
    required this.durationSeconds,
    required this.isSentByMe,
  }) : super(key: key);

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      // Set audio source
      await _audioPlayer.setFilePath(widget.audioPath);

      // Get duration
      _totalDuration = _audioPlayer.duration ?? Duration(seconds: widget.durationSeconds);

      // Listen to position changes
      _positionSubscription = _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
      });

      // Listen to player state changes
      _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });

          // Auto-reset when playback completes
          if (state.processingState == ProcessingState.completed) {
            _audioPlayer.seek(Duration.zero);
            _audioPlayer.pause();
            setState(() {
              _currentPosition = Duration.zero;
              _isPlaying = false;
            });
          }
        }
      });
    } catch (e) {
      // print('[VoicePlayer] Error initializing player: $e');
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      // print('[VoicePlayer] Error toggling play/pause: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalDuration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSentByMe ? Colors.blue[700] : Colors.grey[800],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              onPressed: _togglePlayPause,
            ),
          ),

          const SizedBox(width: 12),

          // Waveform visualization (simplified progress bar)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar with waveform appearance
                Stack(
                  children: [
                    // Background waveform
                    Container(
                      height: 32,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(20, (index) {
                          final heights = [8.0, 16.0, 12.0, 20.0, 10.0, 18.0, 14.0, 22.0, 11.0, 19.0,
                                         15.0, 24.0, 13.0, 17.0, 9.0, 21.0, 12.0, 16.0, 10.0, 14.0];
                          final isActive = (index / 20) <= progress;

                          return Container(
                            width: 2,
                            height: heights[index],
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Duration
                Text(
                  _isPlaying || _currentPosition.inSeconds > 0
                      ? _formatDuration(_currentPosition)
                      : _formatDuration(_totalDuration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

            const SizedBox(width: 8),
          ],
        ),
      ),
      ],
    );
  }
}
