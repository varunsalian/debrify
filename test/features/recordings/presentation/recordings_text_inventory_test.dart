import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_manual_driver.dart';
import '../../../support/recordings_visual_assertions.dart';

const scheduleHint =
    'Nothing scheduled — pick an upcoming programme in a channel\'s TV guide, '
    'or press Schedule above.';
const libraryHint =
    'No recordings yet. Focus a live channel and press Record, or schedule one '
    '— finished recordings appear here, ready to play.';
const desktopFooter =
    'Recordings run while Debrify is open and the computer is awake · saved in '
    'Downloads/Debrify/Recordings';

void main() {
  testWidgets('empty DVR verbatim chrome hints buttons and tooltip', (t) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      for (final text in [
        'Recordings',
        'Schedule',
        'Your DVR is empty',
        'Record what\'s on now with the Record button on any live channel, set '
            'a recording from a programme guide, or schedule a channel and '
            'time yourself.',
        'Schedule a recording',
      ]) {
        expect(
          find.text(text),
          findsOneWidget,
          reason: 'empty DVR verbatim text: $text',
        );
      }
      expect(
        find.byTooltip('Back'),
        findsOneWidget,
        reason: 'Back tooltip verbatim',
      );
    });
  });

  testWidgets('populated DVR verbatim headers chips footer and live text', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      final capture = await t.runAsync(f.capture);
      await f.seedSchedules([
        f.schedule('plain'),
        f.schedule('titled', title: 'Programme'),
      ]);
      await t.runAsync(() => f.file('Library_title.ts'));
      await f.mount(t);
      f.clock(t).value = capture!.startedAt.add(const Duration(seconds: 3));
      await t.pump();
      for (final text in [
        'RECORDING NOW',
        '1 LIVE',
        'Live 0',
        '00:03 · 188 B',
        'Stop',
        'SCHEDULED',
        '2 UPCOMING',
        'LIBRARY',
        '1 · 1 KB',
        'Library title',
        'Channel plain',
        'Programme',
        desktopFooter,
      ]) {
        expect(
          find.text(text),
          findsOneWidget,
          reason: 'populated DVR verbatim text: $text',
        );
      }
      expect(
        find.byTooltip('Show in folder'),
        findsOneWidget,
        reason: 'folder tooltip verbatim',
      );
      expect(
        find.byTooltip('Delete recording'),
        findsOneWidget,
        reason: 'delete tooltip verbatim',
      );
      f.clock(t).value = capture.startedAt.add(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      await t.pump();
      expect(
        recordingText(recordingsType('_LiveCard'), '1:02:03 · 188 B'),
        findsOneWidget,
        reason: 'elapsed hour template verbatim',
      );
    });
  });

  testWidgets(
    'relative day and channel prefix templates are verbatim in both row kinds',
    (t) async {
      await recordingsCase(t, (f) async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 12);
        for (final (offset, label) in [
          (0, 'Today'),
          (1, 'Tomorrow'),
          (-1, 'Yesterday'),
        ]) {
          final day = today.add(Duration(days: offset));
          await f.seedSchedules([
            f.schedule('relative', start: day, title: 'Programme'),
          ]);
          await t.runAsync(() async {
            if (await f.library.exists()) {
              for (final file in await f.library.list().toList()) {
                await file.delete();
              }
            }
            await f.file('___ .ts', modified: day);
          });
          if (offset == 0) {
            await f.mount(t);
          } else {
            await f.revision(t);
          }
          expect(
            recordingText(
              recordingsType('_ScheduleRow'),
              'Channel relative · $label · 12:00 PM – 1:00 PM',
            ),
            findsOneWidget,
            reason: 'relative titled schedule subtitle verbatim: $label',
          );
          expect(
            recordingText(
              recordingsType('_LibraryRow'),
              '$label 12:00 PM · 1 KB',
            ),
            findsOneWidget,
            reason: 'relative library subtitle verbatim: $label',
          );
          expect(
            find.text('Recording'),
            findsOneWidget,
            reason: 'fallback library title verbatim',
          );
          expect(
            find.text('Programme'),
            findsOneWidget,
            reason: 'programme row title verbatim',
          );
        }
      });
    },
  );

  testWidgets(
    'each nonrelative weekday and day month appears in both row kinds',
    (t) async {
      await recordingsCase(t, (f) async {
        f.television = true;
        for (final (day, label) in [
          (2, 'Sat 2/3'),
          (3, 'Sun 3/3'),
          (4, 'Mon 4/3'),
          (5, 'Tue 5/3'),
          (6, 'Wed 6/3'),
          (7, 'Thu 7/3'),
          (8, 'Fri 8/3'),
        ]) {
          await f.seedSchedules([
            f.schedule('weekday', start: DateTime(2024, 3, day, 12)),
          ]);
          await t.runAsync(() async {
            if (await f.library.exists()) {
              for (final file in await f.library.list().toList()) {
                await file.delete();
              }
            }
            await f.file('Weekday.ts', modified: DateTime(2024, 3, day, 12));
          });
          if (day == 2) {
            await f.mount(t);
          } else {
            await f.revision(t);
          }
          expect(
            recordingText(
              recordingsType('_ScheduleRow'),
              '$label · 12:00 PM – 1:00 PM',
            ),
            findsOneWidget,
            reason: 'nonrelative schedule weekday d/m verbatim: $label',
          );
          expect(
            recordingText(
              recordingsType('_LibraryRow'),
              '$label 12:00 PM · 1 KB',
            ),
            findsOneWidget,
            reason: 'nonrelative library weekday d/m verbatim: $label',
          );
        }
      });
    },
  );

  testWidgets('empty zones retain both full hints and desktop footer', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(() => f.file('Only.ts'));
      await f.mount(t);
      expect(
        find.text(scheduleHint),
        findsOneWidget,
        reason: 'scheduled hint verbatim inventory',
      );
      expect(
        find.text(desktopFooter),
        findsOneWidget,
        reason: 'desktop footer verbatim inventory',
      );
      await t.runAsync(() async {
        for (final file in await f.library.list().toList()) {
          await file.delete();
        }
      });
      await f.seedSchedules([f.schedule('only')]);
      await f.revision(t);
      expect(
        find.text(libraryHint),
        findsOneWidget,
        reason: 'library hint verbatim inventory',
      );
    });
  });

  testWidgets('Today label and exact whole-hour library duration', (t) async {
    await recordingsCase(t, (f) async {
      final today = DateTime.now();
      await t.runAsync(() async {
        await f.file(
          'Today.ts',
          modified: DateTime(today.year, today.month, today.day, 12),
        );
        await f.file(
          'Hour_20240301_120000.ts',
          modified: DateTime(2024, 3, 1, 13),
        );
      });
      await f.mount(t);
      expect(
        find.text('Today 12:00 PM · 1 KB'),
        findsOneWidget,
        reason: 'Today library label verbatim',
      );
      expect(
        find.text('Fri 1/3 12:00 PM · 1 KB · 1h'),
        findsOneWidget,
        reason: 'whole hour duration verbatim',
      );
    });
  });

  testWidgets(
    'byte and duration templates are verbatim in rendered subtitles',
    (t) async {
      await recordingsCase(t, (f) async {
        for (final (name, bytes, seconds, text) in [
          ('Byte', 188, 0, 'Fri 1/3 12:00 PM · 188 B'),
          ('Kilo', 1024, 0, 'Fri 1/3 12:00 PM · 1 KB'),
          ('Mega', 1024 * 1024, 0, 'Fri 1/3 12:00 PM · 1 MB'),
          ('Giga', 1024 * 1024 * 1024, 0, 'Fri 1/3 12:00 PM · 1.00 GB'),
          ('Second', 1024, 2, 'Fri 1/3 12:00 PM · 1 KB · 2s'),
          ('Minute', 1024, 60, 'Fri 1/3 12:00 PM · 1 KB · 1 min'),
          ('Hour', 1024, 3600, 'Fri 1/3 12:00 PM · 1 KB · 1h'),
          ('Mixed', 1024, 3720, 'Fri 1/3 12:00 PM · 1 KB · 1h 2m'),
        ]) {
          await t.runAsync(() async {
            if (await f.library.exists()) {
              for (final file in await f.library.list().toList()) {
                await file.delete();
              }
            }
            await f.file(
              '${name}_20240301_120000.ts',
              bytes: bytes,
              modified: DateTime(
                2024,
                3,
                1,
                12,
              ).add(Duration(seconds: seconds)),
            );
          });
          if (name == 'Byte') {
            await f.mount(t);
          } else {
            await f.revision(t);
          }
          expect(
            recordingText(recordingsType('_LibraryRow'), text),
            findsOneWidget,
            reason: 'formatted library subtitle verbatim: $text',
          );
        }
      });
    },
  );

  testWidgets('zero-byte live elapsed has no byte separator', (t) async {
    await recordingsCase(t, (f) async {
      final capture = await t.runAsync(() => f.capture(bytes: 0));
      await f.mount(t);
      f.clock(t).value = capture!.startedAt.add(
        const Duration(minutes: 2, seconds: 3),
      );
      await t.pump();
      expect(
        recordingText(recordingsType('_LiveCard'), '02:03'),
        findsOneWidget,
        reason: 'zero-byte live elapsed verbatim without separator',
      );
    });
  });

  testWidgets(
    'manual picker title invalid channel and duplicate result verbatim',
    (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        await f.mount(t);
        await f.tap(t, find.text('Schedule'));
        await f.until(t, () => find.byType(AlertDialog).evaluate().isNotEmpty);
        expect(
          find.text('Record which channel?'),
          findsOneWidget,
          reason: 'channel picker title verbatim',
        );
        f.navigator.currentState!.pop();
        await f.settle(t);
        final driver = RecordingsManualDriver(t, f);
        await driver.open(channelUrl: 'https://recordings.test/master.m3u8');
        expect(
          find.text(
            "This channel can't be scheduled — recording needs a direct TS or Xtream stream",
          ),
          findsOneWidget,
          reason: 'unschedulable channel snackbar verbatim',
        );
        recordingTextProperties(
          t,
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              )
              .first,
          reason: 'manual result snackbar Text properties',
        );
        ScaffoldMessenger.of(
          t.element(find.byKey(f.pageKey)),
        ).removeCurrentSnackBar();
        await f.settle(t);
        final day = DateTime.now().add(const Duration(days: 2));
        final start = DateTime(day.year, day.month, day.day, 12);
        await f.seedSchedules([
          DesktopSchedule(
            id: 'duplicate',
            channelName: 'Existing',
            url: driver.url,
            headers: const {},
            startMs: start.millisecondsSinceEpoch,
            endMs: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
            programmeTitle: '',
            ownerProfileId: 'other-profile',
          ),
        ]);
        await driver.untilLength(day: day);
        await f.tap(t, find.text('30 minutes'));
        await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
        expect(
          find.text('Already scheduled at that time'),
          findsOneWidget,
          reason: 'duplicate result snackbar verbatim',
        );
      });
    },
  );

  testWidgets(
    'long recording full content all interpolation branches and buttons',
    (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        await f.mount(t);
        final driver = RecordingsManualDriver(t, f);
        for (final (start, end, message) in [
          (
            const TimeOfDay(hour: 12, minute: 0),
            const TimeOfDay(hour: 19, minute: 0),
            'Recording would run 7h, ending 7:00 PM.',
          ),
          (
            const TimeOfDay(hour: 23, minute: 0),
            const TimeOfDay(hour: 22, minute: 30),
            'Recording would run 23h 30m, ending 10:30 PM the next day.',
          ),
          (
            const TimeOfDay(hour: 23, minute: 0),
            const TimeOfDay(hour: 11, minute: 0),
            'Recording would run 12h, ending 11:00 AM the next day.',
          ),
        ]) {
          await driver.untilLength(time: start);
          expect(
            find.text('Record for how long?'),
            findsOneWidget,
            reason: 'length title verbatim',
          );
          for (final text in [
            'Record for how long?',
            '5 minutes (test)',
            '30 minutes',
            '1 hour',
            '2 hours',
            '3 hours',
            'Pick end time…',
          ]) {
            recordingTextProperties(
              t,
              find.text(text),
              reason: 'length dialog Text properties: $text',
            );
          }
          await f.tap(t, find.text('Pick end time…'));
          await driver.time(end);
          expect(
            find.text("That's a long recording"),
            findsOneWidget,
            reason: 'long recording title verbatim',
          );
          expect(
            find.text(message),
            findsOneWidget,
            reason: 'long recording content verbatim: $message',
          );
          for (final text in [
            "That's a long recording",
            message,
            'Cancel',
            'Record',
          ]) {
            expect(
              find.text(text),
              findsOneWidget,
              reason: 'long recording button and title verbatim: $text',
            );
            recordingTextProperties(
              t,
              find.text(text),
              reason: 'long dialog Text properties: $text',
            );
          }
          await f.tap(t, find.widgetWithText(TextButton, 'Cancel'));
        }
      });
    },
  );

  testWidgets('manual next-minute end and removed source result text', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(f.profiles);
      await f.mount(t);
      final driver = RecordingsManualDriver(t, f);
      final now = DateTime.now();
      await driver.untilLength(
        day: now,
        time: const TimeOfDay(hour: 0, minute: 0),
      );
      await f.tap(t, find.text('Pick end time…'));
      await driver.time(
        TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 1))),
      );
      await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(
        find.text('That time has already passed'),
        findsOneWidget,
        reason: 'bad-time result snackbar verbatim',
      );
      ScaffoldMessenger.of(
        t.element(find.byKey(f.pageKey)),
      ).removeCurrentSnackBar();
      await f.settle(t);
      await driver.open(resourceId: 'removed-source', resourceRevision: 1);
      await driver.date(DateTime.now().add(const Duration(days: 2)));
      await driver.time(const TimeOfDay(hour: 12, minute: 0));
      await driver.length();
      await f.tap(t, find.text('30 minutes'));
      await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(
        find.text("Couldn't schedule recording"),
        findsOneWidget,
        reason: 'removed-source result snackbar verbatim',
      );
    });
  });

  testWidgets(
    'cancel and delete dialog complete verbatim text and Text properties',
    (t) async {
      await recordingsCase(t, (f) async {
        await f.seedSchedules([f.schedule('dialog', title: 'Programme')]);
        await t.runAsync(() => f.file('Delete_me.ts'));
        await f.mount(t);
        await f.tap(t, find.text('Programme'));
        for (final text in [
          'Cancel recording?',
          'Programme — Channel dialog',
          'Keep',
          'Cancel recording',
        ]) {
          expect(
            find.text(text),
            findsOneWidget,
            reason: 'cancel dialog verbatim inventory: $text',
          );
          recordingTextProperties(
            t,
            find.text(text),
            reason: 'cancel dialog Text properties: $text',
          );
        }
        await f.tap(t, find.text('Keep'));
        await f.tap(t, find.byTooltip('Delete recording'));
        for (final text in [
          'Delete recording?',
          'Delete me (1 KB) will be removed from this device.',
          'Keep',
          'Delete',
        ]) {
          expect(
            find.text(text),
            findsOneWidget,
            reason: 'delete dialog verbatim inventory: $text',
          );
          recordingTextProperties(
            t,
            find.text(text),
            color: text == 'Delete' ? const Color(0xFFF43F5E) : null,
            reason: 'delete dialog Text properties: $text',
          );
        }
        await f.tap(t, find.text('Keep'));
      });
    },
  );
}
