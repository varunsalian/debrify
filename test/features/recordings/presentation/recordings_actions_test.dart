import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_visual_assertions.dart';

Future<void> waitForEmptyDvr(
  WidgetTester tester,
  RecordingsFixture fixture,
) async {
  for (
    var i = 0;
    i < 200 && find.text('Your DVR is empty').evaluate().isEmpty;
    i++
  ) {
    await fixture.settle(tester, frames: 1);
  }
}

void main() {
  testWidgets(
    'cancel dialog focuses Cancel and Keep leaves schedule untouched',
    (t) async {
      await recordingsCase(t, (f) async {
        await f.seedSchedules([f.schedule('cancel', title: 'Programme')]);
        await f.mount(t);
        await f.tap(t, find.text('Programme'));
        expect(find.text('Cancel recording?'), findsOneWidget);
        final cancel = t.widget<TextButton>(
          find.widgetWithText(TextButton, 'Cancel recording'),
        );
        expect(
          cancel.autofocus,
          isTrue,
          reason: 'cancel dialog autofocus belongs to Cancel',
        );
        await f.tap(t, find.text('Keep'));
        expect((await DesktopScheduleService.instance.list()).length, 1);
        await f.tap(t, find.text('Programme'));
        await f.tap(t, find.widgetWithText(TextButton, 'Cancel recording'));
        expect(
          await DesktopScheduleService.instance.list(),
          isEmpty,
          reason: 'accepted cancel persists deletion',
        );
        await waitForEmptyDvr(t, f);
        expect(
          find.text('Your DVR is empty'),
          findsOneWidget,
          reason: 'revision listener reloads cancelled schedule',
        );
      });
    },
  );

  testWidgets('delete safe autofocus confirmation and library reload', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final file = await t.runAsync(() => f.file('Delete_me.ts'));
      await f.mount(t);
      await f.tap(t, find.byTooltip('Delete recording'));
      expect(find.text('Delete recording?'), findsOneWidget);
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, 'Keep')).autofocus,
        isTrue,
        reason: 'delete dialog autofocus belongs to Keep',
      );
      await f.tap(t, find.text('Keep'));
      expect(await t.runAsync(file!.exists), isTrue);
      await f.tap(t, find.byTooltip('Delete recording'));
      await f.tap(t, find.widgetWithText(TextButton, 'Delete'));
      expect(
        await t.runAsync(file.exists),
        isFalse,
        reason: 'accepted delete removes real file',
      );
      await waitForEmptyDvr(t, f);
      expect(
        find.text('Your DVR is empty'),
        findsOneWidget,
        reason: 'successful delete reloads library',
      );
    });
  });

  for (final bytes in [188, 0]) {
    testWidgets('desktop Stop outcome $bytes bytes', (t) async {
      await recordingsCase(t, (f) async {
        await t.runAsync(() => f.capture(bytes: bytes));
        await f.mount(t);
        expect(find.text('RECORDING NOW'), findsOneWidget);
        await f.tap(t, find.text('Stop'));
        await f.until(t, () => recordingsType('_LiveCard').evaluate().isEmpty);
        expect(
          find.text(
            bytes > 0
                ? 'Recording saved (188 B)'
                : 'Recording stopped — nothing was captured',
          ),
          findsOneWidget,
          reason: 'Stop snackbar matches captured byte outcome $bytes',
        );
        recordingTextProperties(
          t,
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              )
              .first,
          reason: 'desktop Stop snackbar Text properties',
        );
        expect(
          recordingsType('_LibraryRow'),
          bytes > 0 ? findsOneWidget : findsNothing,
        );
      });
    });
  }

  testWidgets('active capture refuses delete and failure still reloads', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final file = await t.runAsync(() => f.file('Busy.ts'));
      await f.mount(t);
      final dynamic row = t.widget(recordingsType('_LibraryRow'));
      final VoidCallback delete = row.onDelete as VoidCallback;
      await t.runAsync(() => f.capture(path: file!.path));
      await f.settle(t);
      delete();
      await f.settle(t);
      final reads = f.paths.reads;
      await f.tap(t, find.widgetWithText(TextButton, 'Delete'));
      expect(
        find.text("Couldn't delete the recording"),
        findsOneWidget,
        reason: 'active-capture deletion reports refusal',
      );
      recordingTextProperties(
        t,
        find.text("Couldn't delete the recording"),
        reason: 'delete failure snackbar Text properties',
      );
      expect(
        f.paths.reads - reads,
        1,
        reason: 'failed delete still reloads library',
      );
      expect(
        await t.runAsync(file!.exists),
        true,
        reason: 'active capture file is preserved',
      );
    });
  });
}
