import 'dart:convert';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_manual_driver.dart';
import '../../../support/recordings_visual_assertions.dart';

class RecordingWrites extends InMemorySharedPreferencesStore {
  RecordingWrites(super.values) : super.withData();
  final schedules = <List<dynamic>>[];
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('desktop_recording_schedules_v1')) {
      schedules.add(jsonDecode(value as String) as List);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  testWidgets('past start clamps to captured now and writes immediate schedule', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      f.drainScheduleDeadline = true;
      final previous = SharedPreferencesStorePlatform.instance;
      final writes = RecordingWrites(await previous.getAll());
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = writes;
      try {
        await f.mount(t);
        final driver = RecordingsManualDriver(t, f);
        final before = DateTime.now();
        await driver.untilLength(
          day: before,
          time: const TimeOfDay(hour: 0, minute: 0),
        );
        await f.tap(t, find.text('30 minutes'));
        await f.until(
          t,
          () =>
              writes.schedules.any((rows) => rows.isNotEmpty) ||
              find.text('That time has already passed').evaluate().isNotEmpty,
        );
        expect(
          writes.schedules.any((rows) => rows.isNotEmpty),
          isTrue,
          reason: 'past start is clamped to originating now',
        );
        final stored =
            writes.schedules.firstWhere((rows) => rows.isNotEmpty).single
                as Map;
        expect(
          stored['startMs'],
          greaterThanOrEqualTo(before.millisecondsSinceEpoch),
          reason: 'past start is clamped to originating now',
        );
        expect(
          stored['startMs'],
          lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
        );
        expect(
          find.text('Recording starts in a few seconds'),
          findsOneWidget,
          reason: 'immediate schedule reports immediate result',
        );
        f.captures.addAll(
          DesktopRecordingService.instance.captures.where(
            (c) => !f.captures.contains(c),
          ),
        );
      } finally {
        // Future due work is cancelled before the preference transport changes.
        DesktopScheduleService.instance.shutdown();
        SharedPreferencesStorePlatform.instance = previous;
      }
    });
  });

  testWidgets('hidden owner capacity backstop reports overlap result', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      final day = DateTime.now().add(const Duration(days: 2));
      final start = DateTime(day.year, day.month, day.day, 12);
      await f.seedSchedules([
        f.schedule('other1', start: start, owner: 'other-profile'),
        f.schedule('other2', start: start, owner: 'other-profile'),
      ]);
      await f.mount(t);
      final driver = RecordingsManualDriver(t, f);
      await driver.untilLength(day: day);
      await f.tap(t, find.text('30 minutes'));
      await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(
        find.text(
          'Would exceed the simultaneous-recordings limit — raise it in IPTV settings or pick another slot',
        ),
        findsOneWidget,
        reason: 'backend overlap retains original result message',
      );
      expect(await DesktopScheduleService.instance.list(), isEmpty);
    });
  });
  testWidgets(
    'manual preset persists empty programme headers and exact duration',
    (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        await f.mount(t);
        final driver = RecordingsManualDriver(t, f);
        await driver.untilLength();
        await f.tap(t, find.text('30 minutes'));
        await f.until(
          t,
          () => find.text('Recording scheduled').evaluate().isNotEmpty,
        );
        expect(
          find.text('Recording scheduled'),
          findsOneWidget,
          reason: 'scheduled result snackbar verbatim',
        );
        recordingTextProperties(
          t,
          find.text('Recording scheduled'),
          reason: 'scheduled result snackbar Text properties',
        );
        final rows = await DesktopScheduleService.instance.list();
        expect(rows, hasLength(1));
        expect(
          rows.single.programmeTitle,
          '',
          reason: 'manual programme title stays empty',
        );
        expect(rows.single.channelName, 'Manual channel');
        expect(rows.single.url, driver.url);
        expect(rows.single.headers, {'X-Fixture': 'manual'});
        expect(rows.single.endMs - rows.single.startMs, 30 * 60 * 1000);
      });
    },
  );

  testWidgets(
    'manual capacity conflict omits Manage and cancellation writes nothing',
    (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        final day = DateTime.now().add(const Duration(days: 2));
        final start = DateTime(day.year, day.month, day.day, 12);
        await f.seedSchedules([
          f.schedule('busy1', start: start),
          f.schedule('busy2', start: start),
        ]);
        await f.mount(t);
        final driver = RecordingsManualDriver(t, f);
        await driver.untilLength(day: day);
        await f.tap(t, find.text('30 minutes'));
        await f.until(
          t,
          () => find.text('Recording conflict').evaluate().isNotEmpty,
        );
        expect(
          find.text('Manage recordings'),
          findsNothing,
          reason: 'manual conflict has no Manage action',
        );
        await f.tap(t, find.widgetWithText(TextButton, 'Cancel'));
        expect(
          (await DesktopScheduleService.instance.list()).length,
          2,
          reason: 'conflict cancellation creates no schedule',
        );
      });
    },
  );

  testWidgets('exact six hours proceeds without long-recording confirmation', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      await f.mount(t);
      final driver = RecordingsManualDriver(t, f);
      await driver.untilLength();
      await f.tap(t, find.text('Pick end time…'));
      await driver.time(const TimeOfDay(hour: 18, minute: 0));
      await f.settle(t);
      expect(
        find.text("That's a long recording"),
        findsNothing,
        reason: 'exact six-hour duration needs no confirmation',
      );
      await f.until(
        t,
        () => find.text('Recording scheduled').evaluate().isNotEmpty,
      );
      final rows = await DesktopScheduleService.instance.list();
      expect(
        rows.single.endMs - rows.single.startMs,
        const Duration(hours: 6).inMilliseconds,
      );
    });
  });

  testWidgets('earlier end rolls tomorrow and long-recording Cancel is safe', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      f.television = true;
      await f.mount(t);
      final driver = RecordingsManualDriver(t, f);
      await driver.untilLength(time: const TimeOfDay(hour: 23, minute: 0));
      expect(
        t
            .widget<ListTile>(find.widgetWithText(ListTile, '5 minutes (test)'))
            .autofocus,
        isTrue,
      );
      await f.tap(t, find.text('Pick end time…'));
      await driver.time(const TimeOfDay(hour: 22, minute: 30));
      expect(find.text("That's a long recording"), findsOneWidget);
      expect(
        find.textContaining('23h 30m'),
        findsOneWidget,
        reason: 'earlier end rolls to next calendar day',
      );
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .autofocus,
        isTrue,
      );
      await f.tap(t, find.widgetWithText(TextButton, 'Cancel'));
      expect(
        await DesktopScheduleService.instance.list(),
        isEmpty,
        reason: 'long-recording cancellation writes nothing',
      );
    });
  });

  testWidgets('confirmed long recording persists its full window and result', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      await f.mount(t);
      final day = DateTime.now().add(const Duration(days: 2));
      final start = DateTime(day.year, day.month, day.day, 23);
      final end = DateTime(day.year, day.month, day.day + 1, 22, 30);
      final driver = RecordingsManualDriver(t, f);
      await driver.untilLength(
        day: day,
        time: const TimeOfDay(hour: 23, minute: 0),
      );
      await f.tap(t, find.text('Pick end time…'));
      await driver.time(const TimeOfDay(hour: 22, minute: 30));
      expect(find.text("That's a long recording"), findsOneWidget);
      await f.tap(t, find.widgetWithText(TextButton, 'Record'));
      final rows = await DesktopScheduleService.instance.list();
      expect(
        rows.length,
        1,
        reason: 'confirmed long recording persists a desktop schedule',
      );
      expect(
        [rows.single.startMs, rows.single.endMs],
        [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        reason: 'confirmed long recording preserves the picked start and end',
      );
      expect(
        find.text('Recording scheduled'),
        findsOneWidget,
        reason: 'confirmed long recording reports the scheduling result',
      );
    });
  });
}
