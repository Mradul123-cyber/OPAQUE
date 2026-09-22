import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'opaque_design.dart';

Future<TimeOfDay?> showOpaqueTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'Backup time',
  String description = 'Choose when automatic backups should run.',
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => OpaqueTimePickerSheet(
      initialTime: initialTime,
      title: title,
      description: description,
    ),
  );
}

class OpaqueTimePickerSheet extends StatefulWidget {
  const OpaqueTimePickerSheet({
    super.key,
    required this.initialTime,
    required this.title,
    required this.description,
  });

  final TimeOfDay initialTime;
  final String title;
  final String description;

  @override
  State<OpaqueTimePickerSheet> createState() => _OpaqueTimePickerSheetState();
}

enum _ClockMode { hour, minute }

class _OpaqueTimePickerSheetState extends State<OpaqueTimePickerSheet> {
  late int _hour24;
  late int _minute;
  _ClockMode _mode = _ClockMode.hour;

  @override
  void initState() {
    super.initState();
    _hour24 = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
  }

  bool get _isAm => _hour24 < 12;

  int get _hour12 {
    final h = _hour24 % 12;
    return h == 0 ? 12 : h;
  }

  void _setPeriod(bool am) {
    if (am == _isAm) return;
    HapticFeedback.selectionClick();
    setState(() {
      _hour24 = am ? _hour24 % 12 : (_hour24 % 12) + 12;
    });
  }

  void _selectHour12(int hour12) {
    HapticFeedback.selectionClick();
    setState(() {
      final base = hour12 % 12;
      _hour24 = _isAm ? base : base + 12;
      _mode = _ClockMode.minute;
    });
  }

  void _selectMinute(int minute) {
    HapticFeedback.selectionClick();
    setState(() => _minute = minute.clamp(0, 59));
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    final hourLabel = _hour12.toString().padLeft(2, '0');
    final minuteLabel = _minute.toString().padLeft(2, '0');

    return OpaqueSheet(
      title: widget.title,
      description: widget.description,
      icon: Icons.schedule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _DigitalBlock(
                      value: hourLabel,
                      selected: _mode == _ClockMode.hour,
                      onTap: () => setState(() => _mode = _ClockMode.hour),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        ':',
                        style: c.text(30, bold: true).copyWith(color: c.muted),
                      ),
                    ),
                    _DigitalBlock(
                      value: minuteLabel,
                      selected: _mode == _ClockMode.minute,
                      onTap: () => setState(() => _mode = _ClockMode.minute),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PeriodToggle(
                isAm: _isAm,
                onChanged: _setPeriod,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: _ClockDial(
              mode: _mode,
              hour12: _hour12,
              minute: _minute,
              onHourSelected: _selectHour12,
              onMinuteSelected: _selectMinute,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OpaqueButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OpaqueButton(
                  label: 'Set time',
                  primary: true,
                  onPressed: () => Navigator.pop(
                    context,
                    TimeOfDay(hour: _hour24, minute: _minute),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DigitalBlock extends StatelessWidget {
  const _DigitalBlock({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF507FC3) : c.soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF507FC3) : c.line,
          ),
        ),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: c.text(28, bold: true).copyWith(
                height: 1,
                letterSpacing: -0.8,
                color: selected ? Colors.white : c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.isAm, required this.onChanged});

  final bool isAm;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _periodChip('AM', isAm, () => onChanged(true)),
          _periodChip('PM', !isAm, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _periodChip(String label, bool selected, VoidCallback onTap) {
    return Builder(
      builder: (context) {
        final c = OpaqueColors(context);
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: c.text(11, bold: selected).copyWith(
                    letterSpacing: 0.5,
                    color: selected ? c.blue : c.muted,
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _ClockDial extends StatelessWidget {
  const _ClockDial({
    required this.mode,
    required this.hour12,
    required this.minute,
    required this.onHourSelected,
    required this.onMinuteSelected,
  });

  final _ClockMode mode;
  final int hour12;
  final int minute;
  final ValueChanged<int> onHourSelected;
  final ValueChanged<int> onMinuteSelected;

  static const double _size = 248;

  double get _angle {
    if (mode == _ClockMode.hour) {
      return (hour12 % 12) * (2 * math.pi / 12) - math.pi / 2;
    }
    return (minute % 60) * (2 * math.pi / 60) - math.pi / 2;
  }

  void _handleOffset(Offset local) {
    final center = const Offset(_size / 2, _size / 2);
    final delta = local - center;
    if (delta.distance < 18) return;

    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    if (mode == _ClockMode.hour) {
      var hour = ((angle / (2 * math.pi)) * 12).round() % 12;
      if (hour == 0) hour = 12;
      onHourSelected(hour);
    } else {
      final minuteValue = ((angle / (2 * math.pi)) * 60).round() % 60;
      onMinuteSelected(minuteValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = OpaqueColors(context);
    return GestureDetector(
      onPanDown: (d) => _handleOffset(d.localPosition),
      onPanUpdate: (d) => _handleOffset(d.localPosition),
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _ClockPainter(
            mode: mode,
            angle: _angle,
            hour12: hour12,
            minute: minute,
            soft: c.soft,
            line: c.line,
            ink: c.ink,
            muted: c.muted,
            accent: const Color(0xFF507FC3),
            surface: c.surface,
          ),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.mode,
    required this.angle,
    required this.hour12,
    required this.minute,
    required this.soft,
    required this.line,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.surface,
  });

  final _ClockMode mode;
  final double angle;
  final int hour12;
  final int minute;
  final Color soft, line, ink, muted, accent, surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = soft);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final labelRadius = radius - 28;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    if (mode == _ClockMode.hour) {
      for (var i = 1; i <= 12; i++) {
        final a = (i % 12) * (2 * math.pi / 12) - math.pi / 2;
        final pos = Offset(
          center.dx + labelRadius * math.cos(a),
          center.dy + labelRadius * math.sin(a),
        );
        final selected = i == hour12;
        textPainter.text = TextSpan(
          text: '$i',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: selected ? 15 : 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : muted,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          pos - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    } else {
      for (var i = 0; i < 60; i += 5) {
        final a = i * (2 * math.pi / 60) - math.pi / 2;
        final pos = Offset(
          center.dx + labelRadius * math.cos(a),
          center.dy + labelRadius * math.sin(a),
        );
        final selected = minute == i || (i == 0 && minute == 0);
        textPainter.text = TextSpan(
          text: i.toString().padLeft(2, '0'),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: selected ? 14 : 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : muted,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          pos - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }

    final handLength = radius - 52;
    final handEnd = Offset(
      center.dx + handLength * math.cos(angle),
      center.dy + handLength * math.sin(angle),
    );

    canvas.drawLine(
      center,
      handEnd,
      Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(center, 5.5, Paint()..color = accent);
    canvas.drawCircle(center, 2.2, Paint()..color = surface);
    canvas.drawCircle(handEnd, 22, Paint()..color = accent.withOpacity(0.16));
    canvas.drawCircle(handEnd, 18, Paint()..color = accent);

    textPainter.text = TextSpan(
      text: mode == _ClockMode.hour
          ? '$hour12'
          : minute.toString().padLeft(2, '0'),
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      handEnd - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.mode != mode ||
      old.angle != angle ||
      old.hour12 != hour12 ||
      old.minute != minute ||
      old.soft != soft ||
      old.line != line ||
      old.ink != ink ||
      old.muted != muted ||
      old.surface != surface;
}
