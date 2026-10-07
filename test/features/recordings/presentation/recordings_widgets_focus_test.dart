import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.arrowDown,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  testWidgets('TV first schedule owns autofocus and activation ignores KeyUp', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      await f.seedSchedules([f.schedule('first'), f.schedule('second')]);
      await f.mount(t);
      final rows = recordingsType('_ScheduleRow');
      final first = f.focus(t, rows.at(0));
      expect(
        first.autofocus,
        isTrue,
        reason: 'first TV schedule has autofocus',
      );
      expect(
        first.focusNode!.hasFocus,
        isTrue,
        reason: 'first schedule receives TV focus',
      );
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      expect(
        first.onKeyEvent!(first.focusNode!, up),
        KeyEventResult.ignored,
        reason: 'schedule ignores activation KeyUp',
      );
      await t.pump();
      expect(
        find.text('Cancel recording?'),
        findsNothing,
        reason: 'KeyUp does not activate',
      );
      expect(
        first.onKeyEvent!(first.focusNode!, down(LogicalKeyboardKey.enter)),
        KeyEventResult.handled,
      );
      await f.settle(t);
      expect(find.text('Cancel recording?'), findsOneWidget);
      await f.tap(t, find.text('Keep'));
    });
  });

  testWidgets(
    'folder DOWN swallows repeats and library borrows first focus node',
    (t) async {
      await recordingsCase(t, (f) async {
        f.television = true;
        final file = await t.runAsync(() => f.file('Borrowed.ts'));
        await f.mount(t);
        final row = f.focus(t, recordingsType('_LibraryRow'));
        final borrowed = row.focusNode!;
        final folder = f.focus(t, recordingsType('_HubIconButton').last);
        expect(
          folder.onKeyEvent!(
            folder.focusNode!,
            down(LogicalKeyboardKey.arrowDown),
          ),
          KeyEventResult.handled,
        );
        final repeat = KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.arrowDown,
          logicalKey: LogicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        );
        expect(
          folder.onKeyEvent!(folder.focusNode!, repeat),
          KeyEventResult.handled,
          reason: 'DOWN repeat is swallowed',
        );
        await t.pump();
        expect(
          borrowed.hasFocus,
          isTrue,
          reason: 'folder DOWN redirects to library play focus',
        );
        final container = t.widget<Container>(
          find
              .descendant(
                of: recordingsType('_LibraryRow'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          ((container.decoration! as BoxDecoration).border! as Border)
              .top
              .color,
          const Color(0xFFF5C042),
          reason: 'focused library row paints live gold border',
        );
        await t.runAsync(file!.delete);
        await f.revision(t);
        void listen() {}
        expect(
          () => borrowed.addListener(listen),
          returnsNormally,
          reason: 'row disposal keeps borrowed first-library focus usable',
        );
        borrowed.removeListener(listen);
        await t.runAsync(() => f.file('Borrowed.ts'));
        await f.revision(t);
        expect(
          () => borrowed.requestFocus(),
          returnsNormally,
          reason: 'row never disposes borrowed first-library focus',
        );
        await t.pump();
        expect(borrowed.hasFocus, isTrue);
      });
    },
  );

  testWidgets('live TV card is static focused and renders elapsed hour', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      final capture = await t.runAsync(f.capture);
      await f.mount(t);
      final stop = f.focus(t, recordingsType('_LiveCard'));
      expect(
        stop.focusNode!.hasFocus,
        isTrue,
        reason: 'first live Stop owns TV focus',
      );
      expect(
        find.byType(FadeTransition),
        findsNothing,
        reason: 'TV recording dot is static',
      );
      f.clock(t).value = capture!.startedAt.add(
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      await t.pump();
      expect(
        find.textContaining('1:02:03'),
        findsOneWidget,
        reason: 'elapsed hour keeps h:mm:ss',
      );
      expect(find.textContaining('188 B'), findsWidgets);
    });
  });
}
