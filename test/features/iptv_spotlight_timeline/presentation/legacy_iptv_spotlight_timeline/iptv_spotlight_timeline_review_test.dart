import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

Future<void> mountWithAncestor(
  WidgetTester tester,
  IptvSpotlightTimelineFixture f, {
  FocusNode? node,
  FocusOnKeyEventCallback? onKeyEvent,
}) async {
  await f.mount(tester);
  final app = (f.host() as RepaintBoundary).child! as MaterialApp;
  // Dispose the first route before attaching its controller to the new host.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: app.theme,
      home: app.home,
      builder: (_, child) =>
          Focus(focusNode: node, onKeyEvent: onKeyEvent, child: child!),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('focusChannel does not read outside its lazy visible range', (
    tester,
  ) async {
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
        () => f.controller!.focusChannel(outside),
        returnsNormally,
        reason: 'focusChannel must not read an offscreen lazy row',
      );
      expect(f.controller!.focusChannel(outside), isFalse);
      expect(lazy.reads, everyElement(0));
      lazy.allowed = null;
    }, channels: lazy);
  });

  testWidgets('failed pending programme row announces identity exactly once', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      await f.mount(tester);
      await f.settle(tester);
      final p = timelineProgramme('Ready row', f.clock);
      f.script.forChannel(f.channels[0]).single.resolve([p]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(f.selections.last.programme, same(p));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(f.selections.last.entry.sourceOrdinal, 1);
      f.selections.clear();
      f.script.forChannel(f.channels[1]).single.fail();
      await tester.pump();
      expect(
        f.selections,
        hasLength(1),
        reason:
            'failed programme lane announces its identity fallback exactly once',
      );
      expect(f.selections.single.programme, isNull);
      expect(f.selections.single.entry.channel, same(f.channels[1]));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(
        f.activated.single.channel,
        same(f.channels[1]),
        reason: 'failed programme row stays playable',
      );
    }, count: 2);
  });

  testWidgets('Down at last row is handled before ancestor focus', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.loader = (_) async => [];
      final bubbled = <LogicalKeyboardKey>[];
      await mountWithAncestor(
        tester,
        f,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) bubbled.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        bubbled,
        isNot(contains(LogicalKeyboardKey.arrowDown)),
        reason: 'ancestor must not receive Down at the last guide row',
      );
      expect(f.node(tester).hasPrimaryFocus, isTrue);
    }, count: 1);
  });

  testWidgets('focus loss clears tap preview before focus is regained', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.loader = (_) async => [];
      final outside = FocusNode(debugLabel: 'outside-guide');
      addTearDown(outside.dispose);
      await mountWithAncestor(tester, f, node: outside);
      await f.settle(tester);
      await tester.tap(find.text('Channel 0'));
      await tester.pump();
      expect(f.activated, isEmpty);
      expect(find.text('Tap again to watch'), findsOneWidget);
      outside.requestFocus();
      await tester.pump();
      expect(outside.hasPrimaryFocus, isTrue);
      await tester.pump();
      expect(find.text('Tap again to watch'), findsNothing);
      f.node(tester).requestFocus();
      await tester.pump();
      await tester.tap(find.text('Channel 0'));
      await tester.pump();
      expect(
        f.activated,
        isEmpty,
        reason: 'first tap after focus regain previews again',
      );
      expect(find.text('Tap again to watch'), findsOneWidget);
      await tester.tap(find.text('Channel 0'));
      expect(f.activated, hasLength(1));
    }, count: 1);
  });

  testWidgets(
    'disposed failed schedule completion produces no asynchronous error',
    (tester) async {
      final errors = <Object>[];
      final finished = Completer<void>();
      runZonedGuarded(() async {
        try {
          await timelineCase(tester, (f) async {
            await f.mount(tester);
            await f.settle(tester);
            final pending = f.script.calls.single;
            await f.close(tester);
            f.selections.clear();
            pending.fail();
            await tester.pump();
            expect(f.selections, isEmpty);
          }, count: 1);
        } finally {
          finished.complete();
        }
      }, (error, _) => errors.add(error));
      await finished.future;
      expect(
        errors,
        isEmpty,
        reason: 'disposed failed completion must be rejected before setState',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ignored Home on Now cannot reach the guide cursor handler', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.initialWindowStart = f.clock.add(const Duration(hours: 3));
      f.loader = (_) async => [];
      await f.mount(tester);
      await f.settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'spotlight-now');
      f.selections.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'spotlight-now',
        reason: 'ignored Home leaves primary focus on Now',
      );
      expect(
        find.byKey(const ValueKey('spotlight-jump-to-now')),
        findsOneWidget,
      );
      expect(
        f.selections,
        isEmpty,
        reason: 'ignored Now key cannot announce or move a guide cursor',
      );
    }, count: 1);
  });

  testWidgets('Down from Now restores the selected programme cell', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.initialWindowStart = f.clock.subtract(const Duration(minutes: 20));
      final p = timelineProgramme('Guide cell', f.clock);
      f.loader = (_) async => [p];
      await f.mount(tester);
      await f.settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(f.selections.last.programme, same(p));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'spotlight-now');
      f.selections.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        f.node(tester).hasPrimaryFocus,
        isTrue,
        reason: 'Down from Now restores primary guide focus',
      );
      expect(
        f.selections,
        hasLength(1),
        reason: 'Down from Now announces guide restoration exactly once',
      );
      expect(f.selections.single.programme, same(p));
      expect(f.selections.single.entry.sourceOrdinal, 0);
    }, count: 1);
  });

  testWidgets('future archived programme has no replay icon', (tester) async {
    await timelineCase(tester, (f) async {
      final p = timelineProgramme(
        'Future archive',
        f.clock.add(const Duration(minutes: 20)),
        archive: true,
      );
      f.loader = (_) async => [p];
      await f.mount(tester);
      await f.settle(tester);
      expect(find.text('Future archive'), findsOneWidget);
      expect(
        find.byIcon(Icons.replay_rounded),
        findsNothing,
        reason: 'future archive programme cannot show a replay icon',
      );
    }, count: 1);
  });
  testWidgets('old generation for retained offscreen row cannot become ready', (
    tester,
  ) async {
    await timelineCase(tester, (f) async {
      f.height = 110;
      await f.mount(tester);
      await f.settle(tester);
      final old = f.script.forChannel(f.channels[0]).single;
      f.scroll(tester).jumpTo(68);
      await f.settle(tester);
      old.resolve([timelineProgramme('Old offscreen result', f.clock)]);
      await tester.pump();
      f.scroll(tester).jumpTo(0);
      await f.settle(tester);
      expect(
        f.script.forChannel(f.channels[0]),
        hasLength(2),
        reason:
            'old generation cannot leave a retained row ready and skip its fresh load',
      );
      expect(find.text('Old offscreen result'), findsNothing);
    }, count: 20);
  });
  testWidgets(
    'in-place shrink rejects pending ordinal without asynchronous error',
    (tester) async {
      final errors = <Object>[];
      final finished = Completer<void>();
      runZonedGuarded(() async {
        try {
          await timelineCase(tester, (f) async {
            await f.mount(tester);
            await f.settle(tester);
            final pending = f.script.calls.single;
            f.channels.clear();
            pending.resolve([timelineProgramme('Removed ordinal', f.clock)]);
            await tester.pump();
            expect(find.text('Removed ordinal'), findsNothing);
          }, count: 1);
        } finally {
          finished.complete();
        }
      }, (error, _) => errors.add(error));
      await finished.future;
      expect(
        errors,
        isEmpty,
        reason:
            'pending out-of-range ordinal must be rejected before indexing the live list',
      );
    },
  );
  testWidgets('pointer shrink checks upper bound before indexing live list', (
    tester,
  ) async {
    final errors = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(() async {
      try {
        await timelineCase(tester, (f) async {
          f.loader = (_) async => [];
          f.height = 178;
          await f.mount(tester);
          await f.settle(tester);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 0));
          try {
            await mouse.moveTo(tester.getCenter(find.text('Channel 1').last));
            await tester.pump(const Duration(milliseconds: 200));
            f.channels.removeLast();
            await tester.pump(const Duration(milliseconds: 175));
          } finally {
            await mouse.removePointer();
          }
        }, count: 2);
      } finally {
        finished.complete();
      }
    }, (error, _) => errors.add(error));
    await finished.future;
    expect(
      errors,
      isEmpty,
      reason:
          'pointer dwell must reject an out-of-range row before indexing the live list',
    );
  });
}
