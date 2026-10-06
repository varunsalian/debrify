import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

void main() {
  testWidgets('schedules ascend and library descends by embedded stamp', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final now = DateTime.now();
      await f.seedSchedules([
        f.schedule('late', start: now.add(const Duration(hours: 5))),
        f.schedule('early', start: now.add(const Duration(hours: 2))),
      ]);
      await t.runAsync(() async {
        await f.file(
          'Older_20240301_120000.ts',
          modified: DateTime(2024, 3, 5),
        );
        await f.file(
          'Newer_20240302_120000_2.ts',
          modified: DateTime(2024, 3, 2, 13),
        );
      });
      await f.mount(t);
      final schedules = t.widgetList(recordingsType('_ScheduleRow')).toList();
      expect(
        (schedules[0] as dynamic).schedule.channelName,
        'Channel early',
        reason: 'schedule order is ascending',
      );
      final rows = t.widgetList(recordingsType('_LibraryRow')).toList();
      expect(
        (rows[0] as dynamic).title,
        'Newer',
        reason: 'library order uses embedded stamp descending',
      );
      expect(
        find.text('Newer'),
        findsOneWidget,
        reason: 'optional collision stamp suffix is stripped',
      );
    });
  });

  testWidgets('countdown renders second minute hour and day boundaries', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final raw = DateTime.now().add(const Duration(days: 5));
      final start = DateTime.fromMillisecondsSinceEpoch(
        raw.millisecondsSinceEpoch,
      );
      await f.seedSchedules([f.schedule('clock', start: start)]);
      await f.mount(t);
      for (final (duration, label) in [
        (const Duration(seconds: 60), 'starting…'),
        (const Duration(seconds: 61), 'in 1m'),
        (const Duration(hours: 1), 'in 1h'),
        (const Duration(hours: 1, minutes: 2), 'in 1h 2m'),
        (const Duration(days: 2, hours: 3), 'in 2d 3h'),
      ]) {
        f.clock(t).value = start.subtract(duration);
        await t.pump();
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'countdown boundary $duration renders $label',
        );
      }
      f.clock(t).value = start.add(const Duration(seconds: 1));
      await t.pump();
      expect(find.text('due'), findsOneWidget, reason: 'past schedule is due');
    });
  });

  testWidgets('last schedule cancels ticker and idle reload does not arm it', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.seedSchedules([f.schedule('timer')]);
      await f.mount(t);
      final clock = f.clock(t);
      var ticks = 0;
      void changed() => ticks++;
      clock.addListener(changed);
      await t.pump(const Duration(seconds: 2));
      expect(ticks, greaterThan(0), reason: 'schedule arms one-second ticker');
      await f.seedSchedules([]);
      await f.revision(t);
      ticks = 0;
      await t.pump(const Duration(seconds: 2));
      expect(ticks, 0, reason: 'last schedule cancels ticker');
      await f.revision(t);
      await t.pump(const Duration(seconds: 2));
      expect(ticks, 0, reason: 'empty reload leaves ticker unarmed');
      clock.removeListener(changed);
    });
  });

  testWidgets('ticker rebuilds clock scope while page and row stay mounted', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.seedSchedules([f.schedule('scope')]);
      await f.mount(t);
      final page = t.element(find.byKey(f.pageKey));
      final row = t.element(recordingsType('_ScheduleRow'));
      final clock = t.element(find.byType(ValueListenableBuilder<DateTime>));
      final rebuilt = <Element>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilt.add(element);
        previous?.call(element, builtOnce);
      };
      try {
        await t.pump(const Duration(seconds: 1));
        expect(rebuilt, contains(clock), reason: 'ticker rebuilds clock scope');
        expect(
          rebuilt,
          isNot(contains(page)),
          reason: 'ticker keeps page clean',
        );
        expect(rebuilt, isNot(contains(row)), reason: 'ticker keeps row clean');
        expect(t.element(recordingsType('_ScheduleRow')), same(row));
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
    });
  });

  testWidgets('library formats byte thresholds titles and duration window', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final stamp = DateTime(2024, 3, 1, 12);
      await t.runAsync(() async {
        await f.file('Gigabyte.ts', bytes: 1024 * 1024 * 1024);
        await f.file('Megabyte.ts', bytes: 1024 * 1024);
        await f.file('.mp4', bytes: 1024);
        await f.file('___ .ts', bytes: 1);
        await f.file(
          'Minute_20240301_120000.ts',
          modified: stamp.add(const Duration(minutes: 1)),
        );
        await f.file(
          'Hour_20240301_120000.ts',
          modified: stamp.add(const Duration(hours: 1, minutes: 2)),
        );
        await f.file(
          'Second_20240301_120000.ts',
          modified: stamp.add(const Duration(seconds: 2)),
        );
        await f.file(
          'OneSecond_20240301_120000.ts',
          modified: stamp.add(const Duration(seconds: 1)),
        );
        await f.file(
          'TwelveHours_20240301_120000.ts',
          modified: stamp.add(const Duration(hours: 12)),
        );
      });
      await f.mount(t);
      final rows = <String, String>{};
      void collectVisible() {
        for (final row in t.widgetList(recordingsType('_LibraryRow'))) {
          rows[(row as dynamic).title as String] =
              (row as dynamic).subtitle as String;
        }
      }

      collectVisible();
      await t.drag(find.byType(ListView), const Offset(0, -1200));
      await f.settle(t);
      collectVisible();
      expect(
        rows.keys,
        containsAll(['OneSecond', 'TwelveHours']),
        reason: 'duration boundary rows are rendered before absence assertions',
      );
      expect(
        rows['Gigabyte'],
        contains('1.00 GB'),
        reason: 'exact GB threshold uses GB',
      );
      expect(
        rows['Megabyte'],
        contains('1 MB'),
        reason: 'MB has zero decimal places',
      );
      expect(
        rows,
        contains('.mp4'),
        reason: 'dot-zero extension remains the title',
      );
      expect(
        rows,
        contains('Recording'),
        reason: 'empty title falls back to Recording',
      );
      expect(
        rows['Minute'],
        endsWith(' · 1 min'),
        reason: 'exact minute uses minute form',
      );
      expect(
        rows['Hour'],
        endsWith(' · 1h 2m'),
        reason: 'duration retains remaining minutes',
      );
      expect(
        rows['Second'],
        endsWith(' · 2s'),
        reason: 'sub-minute duration uses seconds',
      );
      expect(
        rows['OneSecond'],
        isNot(contains(' · 1s')),
        reason: 'one second is outside plausible duration window',
      );
      expect(
        rows['TwelveHours'],
        isNot(contains(' · 12h')),
        reason: 'twelve hours is outside plausible duration window',
      );
    });
  });

  testWidgets('relative day labels keep tomorrow and yesterday distinct', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      await f.seedSchedules([
        f.schedule('tomorrow', start: today.add(const Duration(days: 1))),
      ]);
      await t.runAsync(
        () => f.file(
          'Yesterday.ts',
          modified: today.subtract(const Duration(days: 1)),
        ),
      );
      await f.mount(t);
      expect(
        find.textContaining('Tomorrow ·'),
        findsOneWidget,
        reason: 'tomorrow schedule label',
      );
      expect(
        find.textContaining('Yesterday '),
        findsOneWidget,
        reason: 'yesterday library label',
      );
    });
  });
}
