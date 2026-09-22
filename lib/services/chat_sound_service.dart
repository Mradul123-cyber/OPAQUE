import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Lightweight service to play audio cues for sent and incoming messages
class ChatSoundService {
  static final ChatSoundService instance = ChatSoundService._internal();
  factory ChatSoundService() => instance;
  ChatSoundService._internal();

  AudioPlayer? _sendPlayer;
  AudioPlayer? _receivePlayer;
  bool _initialized = false;

  /// Preload sound assets for zero-latency playback
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _sendPlayer = AudioPlayer();
      await _sendPlayer!.setAsset('assets/sounds/message_sent.wav');
      await _sendPlayer!.setVolume(0.65);

      _receivePlayer = AudioPlayer();
      await _receivePlayer!.setAsset('assets/sounds/message_received.wav');
      await _receivePlayer!.setVolume(0.65);

      _initialized = true;
    } catch (e) {
      debugPrint('[ChatSoundService] Error initializing audio players: $e');
    }
  }

  /// Play message sent chime
  Future<void> playMessageSent() async {
    try {
      if (_sendPlayer == null || !_initialized) {
        await initialize();
      }
      if (_sendPlayer != null) {
        await _sendPlayer!.seek(Duration.zero);
        await _sendPlayer!.play();
      }
    } catch (e) {
      debugPrint('[ChatSoundService] Error playing sent sound: $e');
    }
  }

  /// Play incoming message chime
  Future<void> playMessageReceived() async {
    try {
      if (_receivePlayer == null || !_initialized) {
        await initialize();
      }
      if (_receivePlayer != null) {
        await _receivePlayer!.seek(Duration.zero);
        await _receivePlayer!.play();
      }
    } catch (e) {
      debugPrint('[ChatSoundService] Error playing received sound: $e');
    }
  }

  void dispose() {
    _sendPlayer?.dispose();
    _receivePlayer?.dispose();
    _sendPlayer = null;
    _receivePlayer = null;
    _initialized = false;
  }
}
