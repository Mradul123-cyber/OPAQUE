// lib/services/ringtone_service.dart
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';

enum RingtoneType {
  incoming,
  outgoing,
  connecting,
}

class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  AudioPlayer? _player;
  RingtoneType? _currentRingtone;

  /// Initialize the ringtone service
  Future<void> initialize() async {
    _player = AudioPlayer();
    print('[RingtoneService] Initialized');
  }

  /// Play incoming call ringtone (loops until stopped)
  Future<void> playIncomingRingtone() async {
    if (_player == null) {
      print('[RingtoneService] ⚠️ Player not initialized');
      return;
    }

    try {
      // Stop any currently playing ringtone
      await stop();

      _currentRingtone = RingtoneType.incoming;

      // Use default system ringtone for incoming calls
      // This plays a looping ringtone sound
      await _player!.setAsset('assets/ringtones/incoming.mp3');
      await _player!.setLoopMode(LoopMode.one); // Loop the ringtone
      await _player!.setVolume(0.8); // 80% volume
      await _player!.play();

      print('[RingtoneService] 📞 Playing incoming call ringtone (looping)');
    } catch (e) {
      // Fallback: Use system notification sound via platform channel
      print('[RingtoneService] ⚠️ Could not play incoming ringtone asset: $e');
      print('[RingtoneService] 📞 Using system ringtone as fallback');
      await _playSystemRingtone();
    }
  }

  /// Play outgoing call ringtone (ringback tone)
  Future<void> playOutgoingRingtone() async {
    if (_player == null) {
      print('[RingtoneService] ⚠️ Player not initialized');
      return;
    }

    try {
      // Stop any currently playing ringtone
      await stop();

      _currentRingtone = RingtoneType.outgoing;

      // Play ringback tone (the beep-beep sound you hear when calling someone)
      await _player!.setAsset('assets/ringtones/outgoing.mp3');
      await _player!.setLoopMode(LoopMode.one); // Loop the tone
      await _player!.setVolume(0.6); // Lower volume for outgoing tone
      await _player!.play();

      print('[RingtoneService] 📲 Playing outgoing call ringtone (looping)');
    } catch (e) {
      print('[RingtoneService] ⚠️ Could not play outgoing ringtone asset: $e');
      // Fallback: play a simple beep pattern
      await _playBeepPattern();
    }
  }

  /// Play connecting tone (short notification that call is connecting)
  Future<void> playConnectingTone() async {
    if (_player == null) {
      print('[RingtoneService] ⚠️ Player not initialized');
      return;
    }

    try {
      // Stop any currently playing ringtone
      await stop();

      _currentRingtone = RingtoneType.connecting;

      // Play a short connecting tone (plays once, no loop)
      await _player!.setAsset('assets/ringtones/connecting.mp3');
      await _player!.setLoopMode(LoopMode.off); // Play once
      await _player!.setVolume(0.5); // Medium volume
      await _player!.play();

      print('[RingtoneService] 🔗 Playing connecting tone (once)');
    } catch (e) {
      print('[RingtoneService] ⚠️ Could not play connecting tone asset: $e');
    }
  }

  /// Stop all ringtones
  Future<void> stop() async {
    if (_player == null) return;

    try {
      await _player!.stop();
      _currentRingtone = null;
      print('[RingtoneService] ⏹️ Stopped ringtone');
    } catch (e) {
      print('[RingtoneService] ⚠️ Error stopping ringtone: $e');
    }
  }

  /// Check if a ringtone is currently playing
  bool get isPlaying => _player?.playing ?? false;

  /// Get the current ringtone type
  RingtoneType? get currentRingtone => _currentRingtone;

  /// Fallback: Use Android system ringtone via platform channel
  Future<void> _playSystemRingtone() async {
    try {
      const platform = MethodChannel('com.zarq/ringtone');
      await platform.invokeMethod('playRingtone');
    } catch (e) {
      print('[RingtoneService] ⚠️ Could not play system ringtone: $e');
    }
  }

  /// Fallback: Generate a simple beep pattern for outgoing calls
  Future<void> _playBeepPattern() async {
    // This is a fallback - ideally we use the asset
    // For now just log that we're using fallback
    print('[RingtoneService] 📞 Using fallback beep pattern for outgoing call');
  }

  /// Dispose the service
  void dispose() {
    _player?.dispose();
    _player = null;
    _currentRingtone = null;
    print('[RingtoneService] Disposed');
  }
}
