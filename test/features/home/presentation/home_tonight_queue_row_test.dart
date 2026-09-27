import 'package:debrify/features/home/presentation/home_tonight_queue_row.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('queue opens once on release of ${key.keyLabel}', (
      tester,
    ) async {
      final row = _Queue();
      addTearDown(row.dispose);
      await tester.pumpWidget(_host(row.widget()));
      row.node.requestFocus();
      await tester.pump();
      expect(row.focused, 1);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      expect(row.opens, 0);
      await tester.sendKeyUpEvent(key);
      expect(row.opens, 1);
      expect(row.holds, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(Focus(focusNode: row.node, child: const Text('Reuse'))),
      );
      row.node.requestFocus();
      await tester.pump();
      expect(row.node.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('queue hold fills for 500ms and release cannot also open', (
    tester,
  ) async {
    final row = _Queue();
    addTearDown(row.dispose);
    await tester.pumpWidget(_host(row.widget()));
    row.node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(row.holds, 0);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      1,
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(row.holds, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(row.opens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(row.opens, 1);
    expect(row.holds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus loss and disposal cancel queued hold actions', (
    tester,
  ) async {
    final row = _Queue();
    final other = FocusNode();
    addTearDown(row.dispose);
    addTearDown(other.dispose);
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            row.widget(),
            Focus(focusNode: other, child: const Text('Other')),
          ],
        ),
      ),
    );
    row.node.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    other.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    row.node.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(row.opens, 0);
    expect(row.holds, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(row.opens, 0);
    expect(row.holds, 0);
    expect(tester.takeException(), isNull);
  });

  for (final held in [false, true]) {
    testWidgets('queue arrows preserve repeats and held-down override=$held', (
      tester,
    ) async {
      final row = _Queue();
      addTearDown(row.dispose);
      final bubbled = <KeyEvent>[];
      await tester.pumpWidget(
        _host(
          Focus(
            onKeyEvent: (_, event) {
              bubbled.add(event);
              return KeyEventResult.handled;
            },
            child: row.widget(held: held),
          ),
        ),
      );
      row.node.requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      expect(row.directions, [
        'up',
        'up',
        'down',
        held ? 'downHold' : 'down',
        'left',
        'left',
      ]);
      expect(bubbled, hasLength(4));
      expect(bubbled, everyElement(isA<KeyUpEvent>()));
      expect(row.node.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(bubbled, hasLength(6));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('touch actions retain thumbnail geometry, badges and progress', (
    tester,
  ) async {
    final row = _Queue();
    addTearDown(row.dispose);
    await tester.pumpWidget(_host(row.widget(progress: 1.5)));
    expect(tester.getSize(find.byType(HomeTonightQueueRow)).height, 100);
    expect(find.text('S2 · E5'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      1,
    );
    await tester.tap(find.text('Queue title'));
    await tester.longPress(find.text('Queue title'));
    expect(row.opens, 1);
    expect(row.holds, 1);
    await tester.pumpWidget(_host(row.widget(progress: null)));
    expect(find.byType(FractionallySizedBox), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus reveals the row through the original 140ms scroll', (
    tester,
  ) async {
    final row = _Queue();
    final scroll = ScrollController();
    addTearDown(row.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 200,
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 400),
                row.widget(),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
    row.node.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final midway = scroll.offset;
    expect(midway, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 70));
    expect(scroll.offset, greaterThan(midway));
    expect(
      tester.getCenter(find.byType(HomeTonightQueueRow)).dy,
      closeTo(
        tester.getRect(find.byType(SingleChildScrollView)).center.dy,
        .01,
      ),
    );
    final settled = scroll.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, settled);
    await tester.pumpWidget(const SizedBox());
    expect(scroll.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 500, child: child)),
  ),
);

class _Queue {
  final node = FocusNode();
  final directions = <String>[];
  int opens = 0, holds = 0, focused = 0;
  Widget widget({bool held = true, double? progress = .4}) =>
      HomeTonightQueueRow(
        item: const StremioMeta(id: 'a', type: 'series', name: 'Queue title'),
        height: 100,
        thumbWidth: 160,
        focusNode: node,
        episode: 'S2 · E5',
        progress: progress,
        hasBoundSource: true,
        onFocused: () => focused++,
        onOpen: () => opens++,
        onLongPress: () => holds++,
        onUp: () => directions.add('up'),
        onDown: () => directions.add('down'),
        onDownHold: held ? () => directions.add('downHold') : null,
        onLeft: () => directions.add('left'),
      );
  void dispose() => node.dispose();
}
