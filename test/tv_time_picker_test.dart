import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/tv_time_picker.dart';

/// The TV spinner exists because Material's picker can't be driven by a remote,
/// so what matters here is purely the key grammar: UP/DOWN changes the selected
/// field, LEFT/RIGHT walks the fields, OK commits, and every field wraps.
void main() {
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Opens the picker and hands back its pending result.
  ///
  /// The 24-hour override sits ABOVE the MaterialApp on purpose: the picker is
  /// a route under the app's Navigator, so a MediaQuery inside `home` would
  /// never reach it — same reason it reads the platform setting on device.
  Future<Future<TimeOfDay?> Function()> show(
    WidgetTester tester, {
    TimeOfDay initial = const TimeOfDay(hour: 10, minute: 30),
    required bool use24Hour,
  }) async {
    Future<TimeOfDay?>? pending;
    await tester.pumpWidget(
      Builder(
        builder: (outer) => MediaQuery(
          data: MediaQuery.of(outer).copyWith(alwaysUse24HourFormat: use24Hour),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => pending = showTvTimePicker(
                  context: context,
                  initialTime: initial,
                  helpText: 'End time',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => pending!;
  }

  testWidgets('UP/DOWN changes the selected field, LEFT/RIGHT walks them',
      (tester) async {
    await show(tester, use24Hour: true);

    // Hour starts selected.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('29'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('OK on a value field commits the time', (tester) async {
    final result = await show(tester, use24Hour: true);

    await press(tester, LogicalKeyboardKey.arrowUp); // 11:30
    await press(tester, LogicalKeyboardKey.enter);

    expect(await result(), const TimeOfDay(hour: 11, minute: 30));
  });

  testWidgets('every field wraps', (tester) async {
    await show(tester,
        initial: const TimeOfDay(hour: 0, minute: 0), use24Hour: true);

    await press(tester, LogicalKeyboardKey.arrowDown); // hour 0 -> 23
    expect(find.text('23'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown); // minute 0 -> 59
    expect(find.text('59'), findsOneWidget);
  });

  testWidgets('12-hour locales get an AM/PM field that leaves the hour alone',
      (tester) async {
    final result = await show(tester, use24Hour: false);

    expect(find.text('AM'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // 12-hour label, no leading zero

    await press(tester, LogicalKeyboardKey.arrowRight); // minute
    await press(tester, LogicalKeyboardKey.arrowRight); // period
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text('PM'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // hour label unchanged

    await press(tester, LogicalKeyboardKey.enter);
    expect(await result(), const TimeOfDay(hour: 22, minute: 30));
  });

  testWidgets('12-hour mode wraps 12 -> 1 without flipping the period',
      (tester) async {
    final result = await show(tester,
        initial: const TimeOfDay(hour: 23, minute: 0), use24Hour: false);

    expect(find.text('11'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowUp); // 11 PM -> 12 PM
    expect(find.text('12'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowUp); // 12 PM -> 1 PM
    expect(find.text('1'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    expect(await result(), const TimeOfDay(hour: 13, minute: 0));
  });

  testWidgets('Cancel is reachable by walking right and returns nothing',
      (tester) async {
    final result = await show(tester, use24Hour: true);

    // hour -> minute -> Cancel (no period field in 24-hour mode).
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('Cancel'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);

    expect(await result(), isNull);
  });

  testWidgets('walking right past Set wraps back to the hour', (tester) async {
    final result = await show(tester, use24Hour: true);

    for (var i = 0; i < 4; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    // Back on the hour field: UP must change the value, not activate a button.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.text('11'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    expect(await result(), const TimeOfDay(hour: 11, minute: 30));
  });
}
