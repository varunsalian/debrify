import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

void main() {
  testWidgets('default viewport delay waits exactly 375ms before loading', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SpotlightLiveTimeline(
          channels: [timelineChannel(0)],
          sourceId: 'source',
          loadGeneration: 1,
          epgContextVersion: 0,
          scheduleLoader: (channel) async {
            calls.add(channel.name);
            return [];
          },
          onChannelActivate: (_) {},
          onProgrammeActivate: (_, _) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 374));
    expect(calls, isEmpty, reason: 'default delay has not elapsed');
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['Channel 0'], reason: 'default delay elapses at 375ms');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'controller rebind detaches old owner and disposal releases resources',
    (tester) async {
      await timelineCase(tester, (f) async {
        await f.mount(tester);
        final old = f.controller!;
        final scroll = f.scroll(tester), node = f.node(tester);
        expect(old.hasFocus, isTrue);
        f.controller = IptvSpotlightTimelineController();
        await f.refresh(tester);
        expect(
          old.restoreFocus(),
          isFalse,
          reason: 'old controller detached on replacement',
        );
        expect(
          f.controller!.restoreFocus(),
          isTrue,
          reason: 'new controller attached on replacement',
        );
        await f.close(tester);
        expect(f.controller!.restoreFocus(), isFalse);
        expect(
          () => node.addListener(() {}),
          throwsFlutterError,
          reason: 'owned focus node disposed',
        );
        expect(
          () => scroll.addListener(() {}),
          throwsFlutterError,
          reason: 'owned scroll controller disposed',
        );
        final reads = f.clockReads;
        await tester.pump(const Duration(minutes: 31));
        expect(
          f.clockReads,
          reads,
          reason: 'periodic clock canceled on disposal',
        );
        expect(
          f.script.calls,
          isEmpty,
          reason: 'pending viewport timer canceled on disposal',
        );
      });
    },
  );
  testWidgets(
    'initial window switches explicit to follow-now and back without schedule reload',
    (tester) async {
      await timelineCase(tester, (f) async {
        await f.mount(tester);
        await f.settle(tester);
        for (final c in f.script.calls) {
          c.resolve([]);
        }
        await tester.pump();
        final count = f.script.calls.length;
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsNothing,
        );
        f.initialWindowStart = DateTime(2030, 1, 2, 14);
        await f.refresh(tester);
        expect(find.text('Wed · Jan 2'), findsOneWidget);
        expect(find.text('14:00'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsOneWidget,
        );
        f.initialWindowStart = null;
        await f.refresh(tester);
        expect(
          find.byKey(const ValueKey('spotlight-jump-to-now')),
          findsNothing,
        );
        expect(find.text('09:30'), findsOneWidget);
        await f.settle(tester);
        expect(
          f.script.calls.length,
          count,
          reason: 'window-only updates retain ready schedules',
        );
      });
    },
  );
  for (final property in [
    'height',
    'rowHeight',
    'rulerHeight',
    'viewportSettleDelay',
  ]) {
    testWidgets(
      '$property change re-arms pending viewport at the new settle boundary',
      (tester) async {
        await timelineCase(tester, (f) async {
          await f.mount(tester);
          await tester.pump(const Duration(milliseconds: 200));
          switch (property) {
            case 'height':
              f.height = 310;
            case 'rowHeight':
              f.rowHeight = 80;
            case 'rulerHeight':
              f.rulerHeight = 50;
            case 'viewportSettleDelay':
              f.settleDelay = const Duration(milliseconds: 500);
          }
          await f.refresh(tester);
          await tester.pump(const Duration(milliseconds: 175));
          expect(
            f.script.calls,
            isEmpty,
            reason: 'update cancels the old settled load',
          );
          await tester.pump(
            Duration(
              milliseconds: property == 'viewportSettleDelay' ? 325 : 200,
            ),
          );
          expect(
            f.script.calls,
            isNotEmpty,
            reason: 'new settle timer loads the viewport',
          );
        });
      },
    );
  }
  testWidgets(
    'unrelated callback update does not delay the armed load and reads replacement loader live',
    (tester) async {
      await timelineCase(tester, (f) async {
        final loaded = <String>[];
        await f.mount(tester);
        await tester.pump(const Duration(milliseconds: 200));
        f.loader = (c) async {
          loaded.add(c.name);
          return [];
        };
        f.channelCallback = (_) => f.exits.add('replacement');
        await f.refresh(tester);
        await tester.pump(const Duration(milliseconds: 175));
        expect(
          loaded,
          isNotEmpty,
          reason: 'pending timer reads the new loader at original boundary',
        );
        expect(f.script.calls, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(f.exits, [
          'replacement',
        ], reason: 'replacement activation callback is live');
      });
    },
  );
  testWidgets(
    '30 second clock ticks once and follows the half-hour anchor using replacement clock',
    (tester) async {
      await timelineCase(tester, (f) async {
        f.loader = (_) async => [];
        await f.mount(tester);
        await f.settle(tester);
        final reads = f.clockReads;
        f.clock = DateTime(2030, 1, 1, 10, 50);
        await tester.pump(const Duration(seconds: 29));
        expect(f.clockReads, reads, reason: 'no periodic tick before 30s');
        await tester.pump(const Duration(milliseconds: 625));
        expect(
          f.clockReads,
          reads + 3,
          reason: 'tick, day heading and playhead read the clock once each',
        );
        expect(find.text('10:00'), findsOneWidget);
        var replacementReads = 0;
        f.nowCallback = () {
          replacementReads++;
          return DateTime(2030, 1, 1, 11, 20);
        };
        await f.refresh(tester);
        replacementReads = 0;
        await tester.pump(const Duration(seconds: 30));
        expect(
          replacementReads,
          3,
          reason: 'periodic callback reads the replacement function',
        );
        expect(find.text('10:30'), findsOneWidget);
      });
    },
  );
  testWidgets(
    '30 minute refresh waits for tick then clears retry lane and reloads after settling',
    (tester) async {
      await timelineCase(tester, (f) async {
        await f.mount(tester);
        await f.settle(tester);
        for (final c in f.script.calls) {
          c.fail();
        }
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        final oldCalls = f.script.calls.length;
        f.clock = f.clock.add(const Duration(minutes: 29, seconds: 59));
        await tester.pump(const Duration(seconds: 29, milliseconds: 625));
        expect(
          f.script.calls.length,
          oldCalls,
          reason: 'guide TTL not expired at 29:59',
        );
        f.clock = f.clock.add(const Duration(seconds: 1));
        f.selections.clear();
        await tester.pump(const Duration(seconds: 30));
        expect(
          f.selections,
          hasLength(1),
          reason: 'retry-lane expiration announces identity once',
        );
        expect(f.selections.single.programme, isNull);
        expect(
          f.script.calls.length,
          oldCalls,
          reason: 'refresh preserves viewport settling',
        );
        await f.settle(tester);
        expect(
          f.script.calls.length,
          oldCalls * 2,
          reason: 'expired visible guides reload',
        );
      });
    },
  );
  testWidgets(
    'follow-now retains selected programme time across a clock tick and vertical move',
    (tester) async {
      await timelineCase(tester, (f) async {
        final early = timelineProgramme(
          'Early',
          DateTime(2030, 1, 1, 10),
          minutes: 30,
        );
        final late = timelineProgramme(
          'Late',
          DateTime(2030, 1, 1, 10, 30),
          minutes: 30,
        );
        f.loader = (_) async => [early, late];
        await f.mount(tester);
        await f.settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(f.selections.last.programme, same(early));
        f.clock = DateTime(2030, 1, 1, 10, 45);
        await tester.pump(const Duration(seconds: 30));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          f.selections.last.programme,
          same(early),
          reason: 'selected time survives follow-now clock movement',
        );
      });
    },
  );
}
