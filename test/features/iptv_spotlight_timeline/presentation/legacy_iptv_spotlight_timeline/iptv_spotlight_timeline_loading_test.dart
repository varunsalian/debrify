import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

void main() {
  testWidgets(
    'ready snapshots skip repeated settled requests in the same context',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 110;
        await f.mount(tester);
        await f.settle(tester);
        f.script.calls.single.resolve([]);
        await tester.pump();
        f.scroll(tester).jumpTo(1);
        await f.settle(tester);
        expect(
          f.script.calls,
          hasLength(2),
          reason: 'one newly exposed row loads',
        );
        f.script.calls.last.resolve([]);
        await tester.pump();
        f.scroll(tester).jumpTo(0);
        await f.settle(tester);
        expect(
          f.script.calls,
          hasLength(2),
          reason: 'ready row retains its context snapshot',
        );
      });
    },
  );
  testWidgets(
    'eviction keeps the eight-row buffer and cursor row then reloads beyond buffer',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 110;
        final loaded = <int>[];
        f.loader = (channel) async {
          loaded.add(f.channels.indexOf(channel));
          return [];
        };
        await f.mount(tester);
        await f.settle(tester);
        Future<void> visit(int row) async {
          f.scroll(tester).jumpTo(row * 68.0);
          await f.settle(tester);
        }

        await visit(1);
        await visit(9);
        await visit(1);
        expect(
          loaded.where((i) => i == 1),
          hasLength(1),
          reason: 'eight-row buffer retains row 1 at viewport 9',
        );
        await visit(10);
        await visit(0);
        expect(
          loaded.where((i) => i == 0),
          hasLength(1),
          reason: 'cursor row survives outside the buffer',
        );
        await visit(1);
        expect(
          loaded.where((i) => i == 1),
          hasLength(2),
          reason: 'non-cursor row beyond eight is evicted',
        );
      }, count: 40);
    },
  );
  testWidgets(
    'schedule drops zero and negative durations and sorts start then stop',
    (tester) async {
      await timelineCase(tester, (f) async {
        final start = DateTime(2030, 1, 1, 10);
        final earlyLong = timelineProgramme('Early long', start, minutes: 60);
        final earlyShort = timelineProgramme('Early short', start, minutes: 30);
        final late = timelineProgramme(
          'Late short',
          start.add(const Duration(minutes: 15)),
          minutes: 10,
        );
        f.loader = (_) async => [
          late,
          earlyLong,
          timelineProgramme('Zero', start, minutes: 0),
          timelineProgramme('Reversed', start, minutes: -1),
          earlyShort,
        ];
        await f.mount(tester);
        await f.settle(tester);
        expect(find.text('Zero'), findsNothing);
        expect(find.text('Reversed'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          f.selections.last.programme,
          same(earlyShort),
          reason: 'equal starts sort by earlier stop before nearest lookup',
        );
        // Each same-start entry is painted, in stable start/stop order.
        final labels = tester
            .widgetList<Text>(
              find.byWidgetPredicate(
                (w) =>
                    w is Text &&
                    [
                      'Early short',
                      'Early long',
                      'Late short',
                    ].contains(w.data),
              ),
            )
            .map((w) => w.data)
            .toList();
        expect(labels.take(3), [
          'Early short',
          'Early long',
          'Late short',
        ], reason: 'programme order sorts start before stop');
      }, count: 1);
    },
  );
  testWidgets(
    'unmounted schedule completion cannot publish or call selection',
    (tester) async {
      await timelineCase(tester, (f) async {
        await f.mount(tester);
        await f.settle(tester);
        final calls = f.script.calls.toList();
        await f.close(tester);
        f.selections.clear();
        for (final c in calls) {
          c.resolve([timelineProgramme('Disposed', f.clock)]);
        }
        await tester.pump();
        expect(f.selections, isEmpty);
        expect(
          tester.takeException(),
          isNull,
          reason: 'unmounted result rejected before setState',
        );
      });
    },
  );
  testWidgets(
    'new viewport generation rejects old completion while preserving newer pending token',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 110;
        await f.mount(tester);
        await f.settle(tester);
        final old = f.script.calls.single;
        f.scroll(tester).jumpTo(1);
        await f.settle(tester);
        final current = f.script.forChannel(f.channels[0]).last;
        expect(current, isNot(same(old)));
        old.resolve([timelineProgramme('Stale generation', f.clock)]);
        await tester.pump();
        expect(
          find.text('Stale generation'),
          findsNothing,
          reason: 'older generation never publishes',
        );
        current.resolve([timelineProgramme('Current token', f.clock)]);
        await tester.pump();
        expect(
          find.text('Current token'),
          findsOneWidget,
          reason: 'old rejection must not remove newer pending token',
        );
      });
    },
  );
  for (final recycle in [false, true]) {
    testWidgets(
      'completion rejects ${recycle ? 'in-place recycled channel' : 'out-of-range ordinal'} without widget update',
      (tester) async {
        await timelineCase(tester, (f) async {
          f.height = 110;
          await f.mount(tester);
          await f.settle(tester);
          final pending = f.script.calls.single;
          if (recycle) {
            f.channels[0] = timelineChannel(90);
          } else {
            f.channels.clear();
          }
          pending.resolve([timelineProgramme('Rejected row', f.clock)]);
          await tester.pump();
          expect(
            find.text('Rejected row'),
            findsNothing,
            reason: 'live channel identity/extent checked after await',
          );
          expect(tester.takeException(), isNull);
        }, count: 1);
      },
    );
  }
  testWidgets(
    'retry preserves generation so another visible row completion remains accepted',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 178;
        await f.mount(tester);
        await f.settle(tester);
        f.script.calls.first.fail();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        f.selections.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          f.selections,
          hasLength(1),
          reason: 'retry announces identity lane once',
        );
        f.script.calls[1].resolve([
          timelineProgramme('Other row accepted', f.clock),
        ]);
        await tester.pump();
        expect(
          find.text('Other row accepted'),
          findsOneWidget,
          reason: 'retry does not bump an already armed generation',
        );
      }, count: 2);
    },
  );
  testWidgets(
    'superseded pending token in the same generation rejects independently of channel identity',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 110;
        await f.mount(tester);
        await f.settle(tester);
        f.script.calls.single.fail();
        await tester.pump();
        VoidCallback errorTap() => tester
            .widget<GestureDetector>(
              find
                  .ancestor(
                    of: find.text('Guide unavailable  ·  Retry'),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap!;
        final oldChannel = f.channels[0], oldTap = errorTap();
        final replacement = timelineChannel(90);
        f.channels[0] = replacement;
        await f.refresh(tester);
        final currentTap = errorTap();
        // Dispatch callbacks from the old and replacement row before painting loading.
        oldTap();
        currentTap();
        await tester.pump();
        expect(f.script.calls, hasLength(3));
        f.channels[0] = oldChannel;
        f.script.calls[1].resolve([
          timelineProgramme('Superseded retry', f.clock),
        ]);
        await tester.pump();
        expect(
          find.text('Superseded retry'),
          findsNothing,
          reason:
              'non-current pending token rejected while its channel still matches the ordinal',
        );
        f.channels[0] = replacement;
        f.script.calls[2].resolve([timelineProgramme('Latest retry', f.clock)]);
        await tester.pump();
        expect(
          find.text('Latest retry'),
          findsOneWidget,
          reason: 'rejected token cannot clear newer pending request',
        );
      }, count: 1);
    },
  );
  testWidgets(
    'equal same-generation retry tokens preserve the first completion behavior',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.height = 110;
        await f.mount(tester);
        await f.settle(tester);
        f.script.calls.single.fail();
        await tester.pump();
        await tester.tap(find.text('Guide unavailable  ·  Retry'));
        await tester.tap(find.text('Guide unavailable  ·  Retry'));
        await tester.pump();
        expect(f.script.calls, hasLength(3));
        f.script.calls[1].resolve([
          timelineProgramme('First equal retry', f.clock),
        ]);
        await tester.pump();
        expect(
          find.text('First equal retry'),
          findsOneWidget,
          reason: 'ORIGINAL pending token comparison uses value equality',
        );
        f.script.calls[2].resolve([
          timelineProgramme('Second equal retry', f.clock),
        ]);
        await tester.pump();
        expect(
          find.text('Second equal retry'),
          findsNothing,
          reason: 'first accepted completion removed the equal pending token',
        );
      }, count: 1);
    },
  );
  testWidgets(
    'large lazy list focusChannel examines cursor then only the visible range',
    (tester) async {
      final lazy = TimelineLazyChannels(50000);
      await timelineCase(tester, (f) async {
        f.height = 110;
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        final outside = lazy[40000];
        lazy.reads.clear();
        lazy.allowed = {0};
        expect(
          f.controller!.focusChannel(outside),
          isFalse,
          reason: 'channel beyond visible range is not scanned',
        );
        expect(lazy.reads, everyElement(0));
        lazy.allowed = null;
      }, channels: lazy);
    },
  );
}
