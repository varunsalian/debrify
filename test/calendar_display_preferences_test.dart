import 'package:debrify/widgets/calendar_display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current month begins today, including earlier air times today', () {
    final now = DateTime(2026, 9, 12, 22);
    expect(
      calendarIncludesDay(DateTime(2026, 9, 11), now, showEarlier: false),
      isFalse,
    );
    expect(
      calendarIncludesDay(DateTime(2026, 9, 12), now, showEarlier: false),
      isTrue,
    );
    expect(
      calendarIncludesDay(DateTime(2026, 9, 30), now, showEarlier: false),
      isTrue,
    );
    expect(
      calendarIncludesDay(DateTime(2026, 9, 1), now, showEarlier: true),
      isTrue,
    );
  });

  test('other months and years remain fully browsable', () {
    final now = DateTime(2026, 1, 31);
    for (final day in [
      DateTime(2025, 12, 1),
      DateTime(2026, 2, 1),
      DateTime(2025, 1, 1),
    ]) {
      expect(calendarIncludesDay(day, now, showEarlier: false), isTrue);
    }
    expect(
      calendarIncludesDay(DateTime(2026, 1, 30), now, showEarlier: false),
      isFalse,
    );
  });

  testWidgets('explicit formats handle midnight, noon, and afternoon', (
    tester,
  ) async {
    for (final format in [
      CalendarTimeFormat.twelveHour,
      CalendarTimeFormat.twentyFourHour,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarTimeFormatScope(
            format: format,
            child: Builder(
              builder: (context) => Column(
                children: [
                  for (final hour in [0, 12, 17])
                    Text(
                      CalendarTimeFormatScope.formatTime(
                        context,
                        DateTime(2026, 9, 12, hour, 5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final time
          in format == CalendarTimeFormat.twelveHour
              ? ['12:05 AM', '12:05 PM', '5:05 PM']
              : ['00:05', '12:05', '17:05']) {
        expect(find.text(time), findsOneWidget);
      }
    }
  });

  testWidgets('device format respects the device 24-hour preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(alwaysUse24HourFormat: true),
          child: Builder(
            builder: (context) => Text(
              CalendarTimeFormatScope.formatTime(
                context,
                DateTime(2026, 9, 12, 17, 5),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('17:05'), findsOneWidget);
  });
}
