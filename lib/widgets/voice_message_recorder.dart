import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'opaque_toast.dart';

enum _RecordingPhase { preparing, recording, saving, sending, discarding }

class VoiceMessageRecorder extends StatefulWidget {
  final Future<void> Function(String audioPath, int duration)
  onRecordingComplete;
  final VoidCallback onCancel;

  const VoiceMessageRecorder({
    super.key,
    required this.onRecordingComplete,
    required this.onCancel,
  });

  @override
  State<VoiceMessageRecorder> createState() => _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends State<VoiceMessageRecorder> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final Stopwatch _elapsed = Stopwatch();
  final List<double> _levels = List.filled(36, .08, growable: true);
  _RecordingPhase _phase = _RecordingPhase.preparing;
  StreamSubscription? _levelsSubscription;
  Timer? _timer;
  late final Future<void> _startup;
  Future<void>? _finishing;
  String? _audioPath;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startup = _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    _levelsSubscription?.cancel();
    unawaited(_closeRecorder());
    super.dispose();
  }

  Future<void> _closeRecorder() async {
    // Avoid closing the native recorder while permission/start/stop is pending.
    await _startup;
    await _finishing;
    try {
      await _recorder.closeRecorder();
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    try {
      final permission = await Permission.microphone.request();
      if (!mounted) return;
      if (!permission.isGranted) {
        OpaqueToast.warning(
          context,
          'Allow microphone access to record a voice message.',
        );
        widget.onCancel();
        return;
      }
      await _recorder.openRecorder();
      if (!mounted) return;
      final directory = await getTemporaryDirectory();
      if (!mounted) return;
      _audioPath = path.join(
        directory.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.aac',
      );
      await _recorder.setSubscriptionDuration(
        const Duration(milliseconds: 100),
      );
      if (!mounted) return;
      _levelsSubscription = _recorder.onProgress?.listen((event) {
        if (!mounted || _phase != _RecordingPhase.recording) return;
        final level = ((event.decibels ?? 0) / 100).clamp(.08, 1.0).toDouble();
        setState(() {
          _levels.removeAt(0);
          _levels.add(level);
        });
      });
      await _recorder.startRecorder(
        toFile: _audioPath,
        codec: Codec.aacADTS,
        bitRate: 64000,
        sampleRate: 16000,
      );
      if (!mounted) return;
      _elapsed.start();
      setState(() => _phase = _RecordingPhase.recording);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds = _elapsed.elapsed.inSeconds.clamp(0, 300));
        if (_seconds >= 300) _finish(send: true);
      });
    } catch (_) {
      if (!mounted) return;
      OpaqueToast.error(
        context,
        'Could not start recording. Please try again.',
      );
      widget.onCancel();
    }
  }

  void _finish({required bool send}) {
    if (_phase != _RecordingPhase.recording) return;
    _timer?.cancel();
    _elapsed.stop();
    setState(
      () => _phase = send ? _RecordingPhase.saving : _RecordingPhase.discarding,
    );
    _finishing = _finishRecording(send: send);
  }

  Future<void> _finishRecording({required bool send}) async {
    try {
      final recordedPath = await _recorder.stopRecorder();
      await _levelsSubscription?.cancel();
      if (!send) {
        final discardedPath = recordedPath ?? _audioPath;
        if (discardedPath != null) {
          try {
            await File(discardedPath).delete();
          } catch (_) {}
        }
        if (mounted) widget.onCancel();
        return;
      }
      if (!mounted) return;
      if (recordedPath == null) throw StateError('No recording');
      setState(() => _phase = _RecordingPhase.sending);
      final duration = ((_elapsed.elapsedMilliseconds + 999) ~/ 1000).clamp(
        1,
        300,
      );
      await widget.onRecordingComplete(recordedPath, duration);
    } catch (_) {
      if (!mounted) return;
      OpaqueToast.error(
        context,
        'Could not finish the voice message. Please try again.',
      );
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFE3E5E9) : const Color(0xFF303238);
    final muted = dark ? const Color(0xFF97A3B6) : const Color(0xFF73747C);
    final green = dark ? const Color(0xFF8BEA91) : const Color(0xFF26833C);
    final recording = _phase == _RecordingPhase.recording;
    final label = switch (_phase) {
      _RecordingPhase.preparing => 'Preparing microphone…',
      _RecordingPhase.recording => 'Recording voice',
      _RecordingPhase.saving => 'Saving recording…',
      _RecordingPhase.sending => 'Sending voice message…',
      _RecordingPhase.discarding => 'Discarding recording…',
    };
    final duration =
        '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202936) : const Color(0xFFF2F3F6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark ? const Color(0xFF354256) : const Color(0xFFE4E6EB),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (recording)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: green,
                    shape: BoxShape.circle,
                  ),
                )
              else
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: green,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              painter: _VoiceLevels(
                List.of(_levels),
                green,
                muted.withValues(alpha: .18),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                tooltip: 'Discard recording',
                onPressed: recording ? () => _finish(send: false) : null,
                style: IconButton.styleFrom(
                  foregroundColor: dark
                      ? const Color(0xFFE4A0A6)
                      : const Color(0xFFB94C5B),
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 21),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      duration,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5,
                        color: ink,
                      ),
                    ),
                    Text(
                      '5 min limit',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                tooltip: 'Send voice message',
                onPressed: recording ? () => _finish(send: true) : null,
                style: IconButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: dark
                      ? const Color(0xFF202936)
                      : Colors.white,
                  disabledBackgroundColor: ink.withValues(alpha: .10),
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceLevels extends CustomPainter {
  const _VoiceLevels(this.levels, this.active, this.quiet);
  final List<double> levels;
  final Color active, quiet;
  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / levels.length;
    final paint = Paint()
      ..strokeWidth = (step * .42).clamp(1.0, 4.0)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < levels.length; i++) {
      paint.color = levels[i] <= .08
          ? quiet
          : active.withValues(alpha: .35 + .65 * i / levels.length);
      final height = (size.height - 4) * levels[i];
      final x = step * (i + .5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceLevels oldDelegate) => true;
}
