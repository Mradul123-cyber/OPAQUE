import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/widgets/chat_date_separator.dart';

void main() {
  test('Local calendar labels cross month and year boundaries', () {
    final now = DateTime(2026, 1, 1, 0, 1);
    expect(chatDayLabel(DateTime(2026, 1, 1, 23), now), 'Today');
    expect(chatDayLabel(DateTime(2025, 12, 31, 0), now), 'Yesterday');
    expect(chatDayLabel(DateTime(2025, 12, 30), now), '30 December 2025');
    expect(
      chatDayLabel(DateTime(2026, 2, 28), DateTime(2026, 3, 1)),
      'Yesterday',
    );
    expect(
      chatDayLabel(DateTime(2026, 1, 5), DateTime(2026, 3, 1)),
      '5 January',
    );
    final utc = DateTime.utc(2026, 9, 20, 23, 45);
    expect(chatCalendarDay(utc), chatCalendarDay(utc.toLocal()));
  });
  test('Appending older pages recalculates boundaries without duplicates', () {
    final firstPage = [DateTime(2026, 9, 20, 12), DateTime(2026, 9, 20, 14)];
    final merged = [
      DateTime(2026, 9, 19, 23),
      DateTime(2026, 9, 20, 8),
      ...firstPage,
    ];
    List<bool> boundaries(List<DateTime> dates) => [
      for (var i = 0; i < dates.length; i++)
        startsChatDay(dates[i], i == 0 ? null : dates[i - 1]),
    ];
    expect(boundaries(firstPage), [true, false]);
    expect(boundaries(merged), [true, true, false, false]);
    expect(boundaries([merged[0], merged[3]]), [true, true]);
    expect(
      untilNextChatDay(DateTime(2026, 12, 31, 23, 59)),
      const Duration(minutes: 1),
    );
  });
  for (final brightness in Brightness.values) {
    testWidgets('Separator fits large text over wallpaper in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: ColoredBox(
                    color: Colors.purple,
                    child: ChatDateSeparator(
                      timestamp: DateTime(2025, 9, 20),
                      now: DateTime(2026, 9, 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('20 September 2025'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatDateSeparator(
            timestamp: DateTime(2026, 9, 20),
            now: DateTime(2026, 9, 21),
          ),
        ),
      );
      expect(find.text('Yesterday'), findsOneWidget);
    });
  }
}
