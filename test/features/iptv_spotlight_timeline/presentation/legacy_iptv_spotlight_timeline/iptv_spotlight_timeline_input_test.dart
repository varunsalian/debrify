import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

void main() {
  testWidgets(
    'arrows repeat and Home jumps to now without activating playback',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.initialWindowStart = f.clock.add(const Duration(hours: 3));
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          f.selections.last.entry.sourceOrdinal,
          2,
          reason: 'arrow repeat moves one additional row',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsNothing,
        );
        expect(
          f.selections.last.entry.sourceOrdinal,
          2,
          reason: 'Home keeps the channel cursor',
        );
        expect(f.selections.last.programme, isNull);
        expect(f.activated, isEmpty);
      });
    },
  );
  for (final loss in ['focus', 'source']) {
    testWidgets(
      '$loss change cancels a pending hold without tap or channel actions',
      (tester) async {
        await timelineCase(tester, (f) async {
          f.enableActions = true;
          await f.mount(tester);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
          await tester.pump(const Duration(milliseconds: 300));
          if (loss == 'focus') {
            f.node(tester).unfocus();
            await tester.pump();
          } else {
            f.sourceId = 'replacement';
            await f.refresh(tester);
          }
          await tester.pump(const Duration(milliseconds: 300));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(f.actions, isEmpty, reason: 'hold is reset by $loss handoff');
          expect(
            f.activated,
            isEmpty,
            reason: 'canceled hold does not become a tap',
          );
        });
      },
    );
  }
  testWidgets(
    'hold uses the live cursor entry and replacement host actions on firing',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.enableActions = true;
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        final calls = <SpotlightTimelineEntry>[];
        f.actionsCallback = calls.add;
        await f.refresh(tester);
        f.controller!.focusChannelAt(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          calls.single.channel,
          same(f.channels[1]),
          reason: 'held action reads current row and replacement callback',
        );
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, hasLength(1));
        expect(f.actions, isEmpty);
        expect(f.activated, isEmpty);
      });
    },
  );
  testWidgets('retry lane bypasses hold and activates retry on key down', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.enableActions = true;
      f.height = 110;
      await f.mount(tester);
      await f.settle(tester);
      f.script.calls.single.fail();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        f.script.calls,
        hasLength(2),
        reason: 'retry accepts down without waiting for hold release',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(f.actions, isEmpty);
      expect(f.activated, isEmpty);
    });
  });
  testWidgets(
    'without actions OK activates immediately and repeat cannot open another route',
    (tester) async {
      await timelineCase(tester, (f) async {
        await f.mount(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        expect(
          f.activated,
          hasLength(1),
          reason: 'no hold delay without actions callback',
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        expect(f.activated, hasLength(1));
        expect(f.actions, isEmpty);
      });
    },
  );
  testWidgets(
    'hover dwell is 375ms and pointer announcements preserve programme and origin',
    (tester) async {
      await timelineCase(tester, (f) async {
        final programme = timelineProgramme(
          'Hovered show',
          f.clock.subtract(const Duration(minutes: 10)),
          minutes: 60,
        );
        f.loader = (_) async => [programme];
        f.height = 178;
        await f.mount(tester);
        await f.settle(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        try {
          f.selections.clear();
          await mouse.moveTo(tester.getCenter(find.text('Hovered show').last));
          await tester.pump(const Duration(milliseconds: 374));
          expect(
            f.selections,
            isEmpty,
            reason: 'hover remains unsettled at 374ms',
          );
          await tester.pump(const Duration(milliseconds: 1));
          expect(f.selections.single.programme, same(programme));
          expect(f.selections.single.fromPointer, isTrue);
          f.controller!.focusFirstChannel();
          await tester.pump();
          expect(
            f.selections.last.programme,
            isNull,
            reason: 'identity announcement omits cached programme',
          );
          expect(f.selections.last.fromPointer, isFalse);
        } finally {
          await mouse.removePointer();
        }
      }, count: 2);
    },
  );
  for (final cancel in ['exit', 'drag', 'dispose', 'shrink']) {
    testWidgets('pointer $cancel prevents a pending hover selection', (
      tester,
    ) async {
      await timelineCase(tester, (f) async {
        f.height = 178;
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(0, 0));
        try {
          f.selections.clear();
          await mouse.moveTo(tester.getCenter(find.text('Channel 1').last));
          await tester.pump(const Duration(milliseconds: 200));
          switch (cancel) {
            case 'exit':
              await mouse.moveTo(const Offset(1279, 1));
            case 'drag':
              final gesture = tester.widget<GestureDetector>(
                find.byWidgetPredicate(
                  (w) =>
                      w is GestureDetector && w.onHorizontalDragStart != null,
                ),
              );
              gesture.onHorizontalDragStart!(DragStartDetails());
            case 'dispose':
              await f.close(tester);
            case 'shrink':
              f.channels.removeLast();
          }
          await tester.pump(const Duration(milliseconds: 175));
          expect(
            f.selections.where((s) => s.fromPointer),
            isEmpty,
            reason: '$cancel rejects the dwell',
          );
        } finally {
          await mouse.removePointer();
        }
      }, count: 2);
    });
  }
  testWidgets(
    'replacement programme and selection callbacks use same live channel list',
    (tester) async {
      await timelineCase(tester, (f) async {
        final p = timelineProgramme('Live callback show', f.clock, minutes: 60);
        f.loader = (_) async => [p];
        await f.mount(tester);
        await f.settle(tester);
        final selections = <SpotlightTimelineSelection>[], played = <String>[];
        f.selectionCallback = selections.add;
        f.programmeCallback = (_, programme) => played.add(programme.title);
        f.upCallback = () => played.add('up');
        f.leftCallback = () => played.add('left');
        await f.refresh(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(played, ['up', 'left', 'Live callback show']);
        expect(selections.last.programme, same(p));
        expect(
          f.programmes,
          isEmpty,
          reason: 'old callback not retained by live view',
        );
      });
    },
  );
  testWidgets(
    'programme reveal keeps a twelve percent lead for a cell before the window',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.clock = DateTime(2030, 1, 1, 10);
        f.initialWindowStart = DateTime(2030, 1, 1, 11);
        final programme = timelineProgramme(
          'Before window',
          DateTime(2030, 1, 1, 10),
          minutes: 30,
        );
        f.loader = (_) async => [programme];
        await f.mount(tester);
        await f.settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        final position = find.byWidgetPredicate(
          (w) =>
              w is Positioned &&
              w.key?.toString().contains('programme-position') == true,
        );
        expect(position, findsOneWidget);
        final cell = tester.widget<Positioned>(position);
        expect(
          cell.left,
          closeTo((f.width - f.identityWidth) * 0.12, 0.01),
          reason: 'earlier programme revealed with twelve percent lead',
        );
      }, count: 1);
    },
  );
}
