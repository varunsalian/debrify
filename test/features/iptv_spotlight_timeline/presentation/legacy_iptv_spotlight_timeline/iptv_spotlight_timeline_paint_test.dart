import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

void main() {
  testWidgets(
    'identity width clamps at 45 percent and row extent includes both text-scaler terms',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.width = 600;
        f.identityWidth = 400;
        f.textScale = 1.3;
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        final list = tester.widget<ListView>(
          find.byKey(const ValueKey('spotlight-live-timeline-rows')),
        );
        // 14pt name grows 4.2pt on two 1.1-height lines; 10pt subtitle grows 3pt.
        expect(
          list.itemExtent,
          81,
          reason: 'row height adds ceil(4.2 * 2 * 1.1 + 3)',
        );
        final identity = find.byWidgetPredicate(
          (w) => w.key?.toString().contains('spotlight-identity') == true,
        );
        expect(
          tester.getSize(identity.first).width,
          270,
          reason: 'identity width is capped at 45 percent',
        );
        f.dense = true;
        f.rowHeight = 46;
        await f.refresh(tester);
        expect(
          tester
              .widget<ListView>(
                find.byKey(const ValueKey('spotlight-live-timeline-rows')),
              )
              .itemExtent,
          55,
          reason: 'dense names use 12.5pt without subtitle term',
        );
      });
    },
  );
  for (final minutes in [24, 25]) {
    testWidgets('NOW badge threshold is 25 minutes: duration $minutes', (
      tester,
    ) async {
      await timelineCase(tester, (f) async {
        f.loader = (_) async => [
          timelineProgramme(
            'Current show',
            f.clock.subtract(const Duration(minutes: 5)),
            minutes: minutes,
          ),
        ];
        await f.mount(tester);
        await f.settle(tester);
        expect(
          find.text('NOW'),
          minutes == 25 ? findsOneWidget : findsNothing,
          reason: 'NOW requires at least 25 minutes',
        );
      }, count: 1);
    });
  }
  testWidgets(
    'past archive cell preserves replay icon, semantics, selected flags and animation',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await timelineCase(tester, (f) async {
          f.initialWindowStart = DateTime(2030, 1, 1, 9);
          final p = timelineProgramme(
            'Archived show',
            DateTime(2030, 1, 1, 9),
            minutes: 60,
            archive: true,
          );
          f.loader = (_) async => [p];
          await f.mount(tester);
          await f.settle(tester);
          expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
          final cell = find.bySemanticsLabel(
            'Archived show, 09:00 to 10:00, replay available',
          );
          var data = tester.getSemantics(cell).getSemanticsData();
          expect(data.hint, 'Tap to preview; tap again to open');
          expect(data.flagsCollection.isSelected, Tristate.isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          data = tester.getSemantics(cell).getSemanticsData();
          expect(data.flagsCollection.isFocused, Tristate.isTrue);
          expect(data.flagsCollection.isSelected, Tristate.isTrue);
          final scale = tester.widget<AnimatedScale>(
            find.descendant(of: cell, matching: find.byType(AnimatedScale)),
          );
          expect(
            (scale.scale, scale.duration),
            (1.018, const Duration(milliseconds: 130)),
          );
          expect(f.selections.last.programme, same(p));
        }, count: 1);
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets(
    'playhead appears only inside the epoch window with positive track width',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        final labels = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Current time 10:20',
        );
        expect(
          labels,
          findsOneWidget,
          reason: 'playhead label is present inside the window',
        );
        f.initialWindowStart = f.clock.add(const Duration(hours: 2));
        await f.refresh(tester);
        expect(
          labels,
          findsNothing,
          reason: 'playhead outside window is absent',
        );
        f.initialWindowStart = f.clock;
        f.width = 0;
        await f.refresh(tester);
        expect(
          labels,
          findsNothing,
          reason: 'zero-width track has no playhead',
        );
      });
    },
  );
  testWidgets(
    'empty and VOD rows retain messages, header, semantics and playable identity',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await timelineCase(tester, (f) async {
          await f.mount(tester);
          expect(find.text('No live channels'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.label == 'Live television programme guide',
            ),
            findsOneWidget,
          );
          expect(f.controller!.focusFirstChannel(), isFalse);
          f.channels = [timelineChannel(0, live: false)];
          await f.refresh(tester);
          await f.settle(tester);
          expect(
            f.script.calls,
            isEmpty,
            reason: 'VOD never asks the guide loader',
          );
          expect(find.text('On demand  ·  Press OK to open'), findsOneWidget);
          expect(find.text('Today · Jan 1'), findsOneWidget);
          f.controller!.focusFirstChannel();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(f.activated.single.channel, same(f.channels.single));
        }, count: 0);
      } finally {
        handle.dispose();
      }
    },
  );
}
