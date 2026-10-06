import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_manual_driver.dart';

void main() {
  testWidgets('revision listeners exist only for the mounted page', (t) async {
    await recordingsCase(t, (f) async {
      final schedules = LiveRecordingService.schedulesRevision;
      final desktop = DesktopRecordingService.instance.revision;
      // Protected API intentionally observes registration, including inert leaks.
      // ignore: invalid_use_of_protected_member
      final schedulesBefore = schedules.hasListeners;
      // ignore: invalid_use_of_protected_member
      final desktopBefore = desktop.hasListeners;
      await f.mount(t);
      expect(
        // ignore: invalid_use_of_protected_member
        schedules.hasListeners,
        isTrue,
        reason: 'mounted schedules listener exists',
      );
      expect(
        // ignore: invalid_use_of_protected_member
        desktop.hasListeners,
        isTrue,
        reason: 'mounted desktop listener exists',
      );
      await t.pumpWidget(const SizedBox());
      expect(
        // ignore: invalid_use_of_protected_member
        schedules.hasListeners,
        schedulesBefore,
        reason: 'disposed schedules listener returns to baseline',
      );
      expect(
        // ignore: invalid_use_of_protected_member
        desktop.hasListeners,
        desktopBefore,
        reason: 'disposed desktop listener returns to baseline',
      );
    });
  });

  testWidgets('inactive lifecycle leaves the visible ticker running', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await f.seedSchedules([f.schedule('inactive')]);
      await f.mount(t);
      final clock = f.clock(t);
      var ticks = 0;
      void changed() => ticks++;
      clock.addListener(changed);
      try {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await t.pump(const Duration(seconds: 2));
        expect(
          ticks,
          greaterThan(0),
          reason: 'inactive is ignored and ticker keeps running',
        );
      } finally {
        clock.removeListener(changed);
      }
    });
  });

  testWidgets('live capture without schedules arms ticker and clamps elapsed', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      final capture = await t.runAsync(f.capture);
      await f.mount(t);
      final clock = f.clock(t);
      var ticks = 0;
      void changed() => ticks++;
      clock.addListener(changed);
      try {
        await t.pump(const Duration(seconds: 2));
        expect(
          ticks,
          greaterThan(0),
          reason: 'live capture alone arms one-second ticker',
        );
        clock.value = capture!.startedAt.subtract(const Duration(seconds: 2));
        await t.pump();
        expect(
          find.text('00:00 · 188 B'),
          findsOneWidget,
          reason: 'negative live elapsed is clamped to zero',
        );
      } finally {
        clock.removeListener(changed);
      }
    });
  });

  testWidgets(
    'live Stop fill follows focus and live card keeps its decoration',
    (t) async {
      await recordingsCase(t, (f) async {
        f.television = true;
        await t.runAsync(f.capture);
        await f.mount(t);
        final card = recordingsType('_LiveCard');
        final stop = find.descendant(
          of: card,
          matching: recordingsType('_HubButton'),
        );
        final focus = f.focus(t, stop);
        BoxDecoration decoration(Finder widget) =>
            t
                    .widget<Container>(
                      find
                          .descendant(
                            of: widget,
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        const rec = Color(0xFFF43F5E);
        expect(
          decoration(card).color,
          const Color(0xFF10142A),
          reason: 'live card background stays pinned',
        );
        expect(
          decoration(card).border,
          Border.all(color: rec.withValues(alpha: 0.35), width: 1.2),
          reason: 'live card border stays pinned',
        );
        expect(focus.focusNode!.hasFocus, isTrue);
        expect(
          decoration(stop).color,
          rec.withValues(alpha: 0.32),
          reason: 'focused live Stop fill is 0.32',
        );
        final scheduleButton = find.ancestor(
          of: find.text('Schedule').first,
          matching: recordingsType('_HubButton'),
        );
        f.focus(t, scheduleButton).focusNode!.requestFocus();
        await f.settle(t);
        expect(focus.focusNode!.hasFocus, isFalse);
        expect(
          decoration(stop).color,
          rec.withValues(alpha: 0.16),
          reason: 'unfocused live Stop fill is 0.16',
        );
      });
    },
  );

  testWidgets('scheduled empty hint retains exact text', (t) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(() => f.file('Library.ts'));
      await f.mount(t);
      expect(
        find.text(
          "Nothing scheduled — pick an upcoming programme in a channel's TV guide, or press Schedule above.",
        ),
        findsOneWidget,
        reason: 'scheduled empty hint keeps original punctuation and wording',
      );
    });
  });

  testWidgets(
    'cancel dialog content uses title dash channel or channel alone',
    (t) async {
      await recordingsCase(t, (f) async {
        await f.seedSchedules([
          f.schedule('title', title: 'Programme'),
          f.schedule('plain'),
        ]);
        await f.mount(t);
        await f.tap(t, find.text('Programme'));
        expect(
          t.widget<AlertDialog>(find.byType(AlertDialog)).content,
          isA<Text>(),
        );
        expect(
          (t.widget<AlertDialog>(find.byType(AlertDialog)).content! as Text)
              .data,
          'Programme — Channel title',
          reason: 'cancel content uses title em dash channel',
        );
        await f.tap(t, find.text('Keep'));
        await f.tap(t, find.text('Channel plain'));
        expect(
          (t.widget<AlertDialog>(find.byType(AlertDialog)).content! as Text)
              .data,
          'Channel plain',
          reason: 'empty programme cancel content is channel alone',
        );
        await f.tap(t, find.text('Keep'));
      });
    },
  );

  testWidgets('delete dialog content names title size and this device', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(() => f.file('Delete_me.ts'));
      await f.mount(t);
      await f.tap(t, find.byTooltip('Delete recording'));
      expect(
        (t.widget<AlertDialog>(find.byType(AlertDialog)).content! as Text).data,
        'Delete me (1 KB) will be removed from this device.',
        reason: 'delete content names title size and this device',
      );
      await f.tap(t, find.text('Keep'));
    });
  });

  testWidgets(
    'desktop manual pickers pin dates times and no preset autofocus',
    (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(f.profiles);
        await f.mount(t);
        final driver = RecordingsManualDriver(t, f);
        final originatingLowerBound = DateTime.now();
        final before = DateUtils.dateOnly(originatingLowerBound);
        final earliest = TimeOfDay.fromDateTime(
          originatingLowerBound.add(const Duration(minutes: 2)),
        );
        await driver.open();
        final after = DateUtils.dateOnly(DateTime.now());
        final picker = t.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(
          picker.helpText,
          'Recording date',
          reason: 'date picker help text is Recording date',
        );
        expect(
          [before, after],
          contains(picker.initialDate),
          reason: 'date picker initial date is today',
        );
        expect(
          picker.firstDate,
          picker.initialDate,
          reason: 'date picker first date is originating today',
        );
        expect(
          picker.lastDate,
          picker.firstDate.add(const Duration(days: 7)),
          reason: 'date picker last date is originating today plus seven days',
        );
        await driver.date(picker.initialDate!.add(const Duration(days: 2)));
        final latest = TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(minutes: 2)),
        );
        final startPicker = t.widget<TimePickerDialog>(
          find.byType(TimePickerDialog),
        );
        expect(
          startPicker.helpText,
          'Start time',
          reason: 'desktop start uses Material picker with Start time',
        );
        expect(
          [earliest, latest],
          contains(startPicker.initialTime),
          reason:
              'start picker initial time is originating now plus two minutes',
        );
        await driver.time(const TimeOfDay(hour: 12, minute: 15));
        await driver.length();
        expect(
          t
              .widget<ListTile>(
                find.widgetWithText(ListTile, '5 minutes (test)'),
              )
              .autofocus,
          isFalse,
          reason: 'first length preset has no non-TV autofocus',
        );
        await f.tap(t, find.text('Pick end time…'));
        final endPicker = t.widget<TimePickerDialog>(
          find.byType(TimePickerDialog),
        );
        expect(
          endPicker.helpText,
          'End time',
          reason: 'end picker help text stays End time',
        );
        expect(
          endPicker.initialTime,
          const TimeOfDay(hour: 13, minute: 15),
          reason: 'end picker starts one hour after chosen start',
        );
        f.navigator.currentState!.pop();
        await f.settle(t);
      });
    },
  );

  testWidgets('Android TV cached flag selects remote spinner for both times', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      await t.runAsync(f.profiles);
      await f.mount(t);
      final driver = RecordingsManualDriver(t, f);
      await driver.open();
      await driver.date(DateTime.now().add(const Duration(days: 2)));
      expect(
        find.text('Up/Down changes · Left/Right moves'),
        findsOneWidget,
        reason: 'Android TV start uses remote time spinner',
      );
      expect(
        find.byType(TimePickerDialog),
        findsNothing,
        reason: 'TV start does not present Material dial',
      );
      expect(find.text('Start time'), findsOneWidget);
      await driver.time(const TimeOfDay(hour: 12, minute: 15));
      await driver.length();
      expect(
        t
            .widget<ListTile>(find.widgetWithText(ListTile, '5 minutes (test)'))
            .autofocus,
        isTrue,
        reason: 'first length preset autofocus is enabled on TV',
      );
      await f.tap(t, find.text('Pick end time…'));
      expect(
        find.text('Up/Down changes · Left/Right moves'),
        findsOneWidget,
        reason: 'Android TV end uses remote time spinner',
      );
      expect(find.text('End time'), findsOneWidget);
      final spinner = recordingsType('_TvTimePickerDialog');
      expect(
        (t.widget(spinner) as dynamic).initialTime,
        const TimeOfDay(hour: 13, minute: 15),
        reason: 'TV end spinner starts one hour after chosen start',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await f.settle(t);
      expect(
        find.text("That's a long recording"),
        findsNothing,
        reason: 'remote OK accepts one-hour end',
      );
    });
  });

  for (final (live, scheduled) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    testWidgets('TV autofocus precedence live=$live scheduled=$scheduled', (
      t,
    ) async {
      await recordingsCase(t, (f) async {
        f.television = true;
        await t.runAsync(() => f.file('Library.ts'));
        if (scheduled) {
          await f.seedSchedules([f.schedule('first'), f.schedule('second')]);
        }
        if (live) {
          await t.runAsync(f.capture);
          await t.runAsync(f.capture);
        }
        await f.mount(t);
        if (live) {
          final cards = recordingsType('_LiveCard');
          expect(
            f.focus(t, cards.at(0)).autofocus,
            isTrue,
            reason: 'first desktop Stop has TV autofocus',
          );
          expect(
            f.focus(t, cards.at(1)).autofocus,
            isFalse,
            reason: 'second desktop Stop has no autofocus',
          );
          expect(
            f.focus(t, cards.at(0)).focusNode!.hasFocus,
            isTrue,
            reason:
                'first desktop Stop receives TV focus ahead of schedules and library',
          );
        }
        if (scheduled) {
          expect(
            f.focus(t, recordingsType('_ScheduleRow').first).autofocus,
            !live,
            reason: 'first schedule autofocus requires no live capture',
          );
          expect(
            f.focus(t, recordingsType('_ScheduleRow').last).autofocus,
            isFalse,
            reason: 'later schedules have no autofocus',
          );
        }
        await t.ensureVisible(find.text('Library'));
        expect(
          f.focus(t, recordingsType('_LibraryRow')).autofocus,
          !live && !scheduled,
          reason:
              'first library autofocus requires no live captures and no schedules',
        );
      });
    });
  }
}
