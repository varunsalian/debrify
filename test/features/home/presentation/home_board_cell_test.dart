import 'package:debrify/features/home/application/home_card_metadata_dependencies.dart';
import 'package:debrify/features/home/presentation/home_board_cell.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  testWidgets('horizontal repeats follow row order and stop at the edges', (
    tester,
  ) async {
    final row = _Row();
    addTearDown(row.dispose);
    await tester.pumpWidget(row.build());
    row.nodes.first.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(row.nodes[1].hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(row.nodes.last.hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(row.nodes.last.hasFocus, isTrue);
    expect(row.actions, ['prefetch', 'prefetch', 'prefetch']);
    expect(row.bubbled, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(row.bubbled.single, isA<KeyUpEvent>());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(row.nodes.first.hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    expect(row.actions.last, 'edge');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final held in [false, true]) {
    testWidgets('vertical repeats preserve held overrides: $held', (
      tester,
    ) async {
      final row = _Row();
      addTearDown(row.dispose);
      await tester.pumpWidget(row.build(held: held));
      row.nodes[1].requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      expect(row.actions, [
        'up',
        held ? 'upHold' : 'up',
        'down',
        held ? 'downHold' : 'down',
      ]);
      expect(row.bubbled, hasLength(2));
      expect(row.bubbled, everyElement(isA<KeyUpEvent>()));
      expect(row.nodes[1].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'prefetch starts six cells from the end and precedes horizontal overrides',
    (tester) async {
      final row = _Row(count: 8);
      addTearDown(row.dispose);
      await tester.pumpWidget(row.build(horizontal: true));
      row.nodes[1].requestFocus();
      await tester.pump();
      expect(row.focused, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(row.actions, ['right']);
      row.actions.clear();
      row.nodes[2].requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(row.actions, ['prefetch', 'right', 'prefetch', 'right']);
      expect(row.nodes[2].hasFocus, isTrue);
      expect(row.focused, 2);
      row.nodes.first.requestFocus();
      await tester.pump();
      row.actions.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(row.actions, ['left']);
      expect(row.nodes.first.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('off-TV arrows bubble without dispatch or prefetch', (
    tester,
  ) async {
    final row = _Row();
    addTearDown(row.dispose);
    await tester.pumpWidget(row.build(tv: false, held: true, horizontal: true));
    row.nodes[1].requestFocus();
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
    }
    expect(row.bubbled, hasLength(12));
    expect(row.actions, isEmpty);
    expect(row.nodes[1].hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('card handles activation while back passes to the parent', (
    tester,
  ) async {
    final row = _Row();
    addTearDown(row.dispose);
    await tester.pumpWidget(row.build());
    row.nodes.first.requestFocus();
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.escape,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(row.actions, ['open', 'open']);
    expect(row.bubbled, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    // The wrapper and its card borrow the row's node; removing them cannot dispose it.
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: row.nodes.first, child: const Text('Reused')),
      ),
    );
    row.nodes.first.requestFocus();
    await tester.pump();
    expect(row.nodes.first.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

class _Row {
  _Row({int count = 3}) : nodes = List.generate(count, (_) => FocusNode());
  final List<FocusNode> nodes;
  final actions = <String>[];
  final bubbled = <KeyEvent>[];
  int focused = 0;

  Widget build({bool tv = true, bool held = false, bool horizontal = false}) {
    final data = CardMetadataFake()
      ..respond = (item) async => MetadataPresentation(item);
    return ProviderScope(
      overrides: [
        homeCardMetadataRepositoryProvider.overrideWith(
          (ref, epoch) => data.repository(epoch),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              bubbled.add(event);
              return KeyEventResult.handled;
            },
            child: Row(
              children: [
                for (var i = 0; i < nodes.length; i++)
                  SizedBox(
                    width: 80,
                    height: 120,
                    child: HomeBoardCell(
                      item: StremioMeta(
                        id: '$i',
                        type: 'movie',
                        name: 'Card $i',
                      ),
                      isTelevision: tv,
                      focusNode: nodes[i],
                      column: i,
                      rowNodes: nodes,
                      hasBoundSource: false,
                      showWatchedBadge: false,
                      onFocused: () => focused++,
                      onOpen: () => actions.add('open'),
                      onUp: () => actions.add('up'),
                      onDown: () => actions.add('down'),
                      onLeftEdge: () => actions.add('edge'),
                      onNearEnd: () => actions.add('prefetch'),
                      onLeft: horizontal ? () => actions.add('left') : null,
                      onRight: horizontal ? () => actions.add('right') : null,
                      onUpHold: held ? () => actions.add('upHold') : null,
                      onDownHold: held ? () => actions.add('downHold') : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
  }
}
