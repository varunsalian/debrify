import 'dart:async';

import 'package:debrify/features/home/presentation/home_continue_watching_actions.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  final actions = HomeContinueWatchingActions();
  late BuildContext context;
  bool current = true, quickPlay = false, pikpakOnly = false, removable = true;
  int plays = 0, removes = 0, refocuses = 0, reads = 0;
  Future<bool> Function()? readOverride;
  Completer<void>? removalGate;
  Future<void>? pending;
  HomeContinuationKind kind = HomeContinuationKind.local;
  StremioMeta item = const StremioMeta(id: 'tt1', type: 'series', name: 'Show');

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return Scaffold(
              body: TextButton(
                onPressed: () => pending = open(),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> open() => actions.open(
    context: context,
    row: HomeContinuationRow(
      rowId: 'row',
      title: 'History',
      tag: null,
      kind: kind,
      items: [item],
      nodes: [],
      progressOf: (_) => 50,
      episodeOf: (_) => 'S2 · E3',
      remainingMinutesOf: (_) => null,
      episodeArtworkOf: (_) => null,
      onOpen: (_) {},
      onQuickPlay: (_) => plays++,
      onRemove: (_) async {
        removes++;
        await removalGate?.future;
      },
      canRemove: (_) => removable,
    ),
    item: item,
    pikpakOnly: pikpakOnly,
    isTelevision: () => false,
    isCurrent: () => current,
    readHoldToQuickPlay: () {
      reads++;
      return readOverride?.call() ?? Future.value(quickPlay);
    },
    refocusAfterRemoval: () => refocuses++,
  );
}

void main() {
  testWidgets(
    'hold preference dispatches quick play once while read is pending',
    (tester) async {
      final f = Fixture();
      final gate = Completer<bool>();
      f.readOverride = () => gate.future;
      await f.mount(tester);
      final first = f.open();
      await f.open();
      expect(f.reads, 1);
      gate.complete(true);
      await first;
      expect(f.plays, 1);
      expect(find.text('Remove from Continue Watching'), findsNothing);
    },
  );

  for (final kind in HomeContinuationKind.values) {
    testWidgets(
      '$kind removal uses real menu and restores focus after completion',
      (tester) async {
        final f = Fixture()..kind = kind;
        f.removalGate = Completer<void>();
        await f.mount(tester);
        final pending = f.open();
        await tester.pumpAndSettle();
        expect(find.text('History  ·  S2 · E3'), findsOneWidget);
        expect(
          find.text(kind == HomeContinuationKind.iptv ? 'Open series' : 'Play'),
          findsOneWidget,
        );
        await f.open();
        expect(f.reads, 1);
        await tester.tap(find.text('Remove from Continue Watching'));
        await tester.pumpAndSettle();
        expect(f.removes, 1);
        expect(f.refocuses, 0);
        f.removalGate!.complete();
        await pending;
        expect(f.refocuses, 1);
      },
    );
  }

  testWidgets('IPTV series still opens menu when hold-to-play is enabled', (
    tester,
  ) async {
    final f = Fixture()
      ..kind = HomeContinuationKind.iptv
      ..quickPlay = true;
    await f.mount(tester);
    final pending = f.open();
    await tester.pumpAndSettle();
    expect(f.plays, 0);
    await tester.tap(find.text('Open series'));
    await tester.pumpAndSettle();
    await pending;
    expect(f.plays, 1);
  });

  testWidgets(
    'PikPak-only hides play; no eligible action avoids preference I/O',
    (tester) async {
      final f = Fixture()
        ..pikpakOnly = true
        ..quickPlay = true
        ..removable = false;
      await f.mount(tester);
      await f.open();
      expect(f.reads, 0);
      f.removable = true;
      final pending = f.open();
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsNothing);
      expect(f.plays, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pending;
    },
  );

  testWidgets('failed preference read retains the existing menu', (
    tester,
  ) async {
    final f = Fixture()..readOverride = (() async => throw StateError('prefs'));
    await f.mount(tester);
    final pending = f.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await pending;
    expect(f.plays, 1);
  });

  testWidgets('retirement during preference read prevents menu and playback', (
    tester,
  ) async {
    final f = Fixture();
    final gate = Completer<bool>();
    f.readOverride = () => gate.future;
    await f.mount(tester);
    final pending = f.open();
    f.current = false;
    gate.complete(true);
    await pending;
    await tester.pumpAndSettle();
    expect(f.plays, 0);
    expect(find.text('Remove from Continue Watching'), findsNothing);
  });

  testWidgets('retirement while menu is open prevents removal', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    final pending = f.open();
    await tester.pumpAndSettle();
    f.current = false;
    await tester.tap(find.text('Remove from Continue Watching'));
    await tester.pumpAndSettle();
    await pending;
    expect(f.removes, 0);
    expect(f.refocuses, 0);
  });

  testWidgets(
    'retirement during accepted removal suppresses focus restoration',
    (tester) async {
      final f = Fixture()..removalGate = Completer<void>();
      await f.mount(tester);
      final pending = f.open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Continue Watching'));
      await tester.pumpAndSettle();
      f.current = false;
      f.removalGate!.complete();
      await pending;
      expect(f.removes, 1);
      expect(f.refocuses, 0);
    },
  );
}
