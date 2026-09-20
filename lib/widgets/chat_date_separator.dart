import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime chatCalendarDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool startsChatDay(DateTime timestamp, DateTime? previous) =>
    previous == null || chatCalendarDay(timestamp) != chatCalendarDay(previous);

String chatDayLabel(DateTime timestamp, DateTime now) {
  final day = chatCalendarDay(timestamp);
  final today = chatCalendarDay(now);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return DateFormat(
    day.year == today.year ? 'd MMMM' : 'd MMMM yyyy',
  ).format(day);
}

Duration untilNextChatDay(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, local.day + 1).difference(local);
}

class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({
    super.key,
    required this.timestamp,
    required this.now,
  });
  final DateTime timestamp;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Center(
        child: Semantics(
          header: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF252E3B) : const Color(0xFFF0F2F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              chatDayLabel(timestamp, now),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: dark ? const Color(0xFFB6C0D0) : const Color(0xFF616A79),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
