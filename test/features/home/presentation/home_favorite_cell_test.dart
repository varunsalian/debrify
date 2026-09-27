import 'package:debrify/features/home/presentation/home_favorite_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('horizontal repeats follow row order and stop at its edges', (
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
    expect(row.bubbled, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(row.bubbled.single, isA<KeyUpEvent>());
    row.bubbled.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(row.nodes[1].hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(row.nodes.first.hasFocus, isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    expect(row.leftEdge, 1);
    expect(row.bubbled, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(row.bubbled.single, isA<KeyUpEvent>());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final heldOverrides in [false, true]) {
    testWidgets(
      'vertical repeats use ${heldOverrides ? 'held overrides' : 'ordinary actions'}',
      (tester) async {
        final row = _Row();
        addTearDown(row.dispose);
        await tester.pumpWidget(row.build(heldOverrides: heldOverrides));
        row.nodes[1].requestFocus();
        await tester.pump();
        for (final key in [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ]) {
          await tester.sendKeyDownEvent(key);
          await tester.sendKeyRepeatEvent(key);
          await tester.sendKeyRepeatEvent(key);
          await tester.sendKeyUpEvent(key);
        }
        expect(row.up, heldOverrides ? 1 : 3);
        expect(row.down, heldOverrides ? 1 : 3);
        expect(row.upHold, heldOverrides ? 2 : 0);
        expect(row.downHold, heldOverrides ? 2 : 0);
        expect(row.bubbled, everyElement(isA<KeyUpEvent>()));
        expect(row.bubbled, hasLength(2));
        expect(row.nodes[1].hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('horizontal overrides win over neighbours and sidebar exit', (
    tester,
  ) async {
    final row = _Row();
    addTearDown(row.dispose);
    await tester.pumpWidget(row.build(horizontalOverrides: true));
    for (final node in [row.nodes[1], row.nodes.first, row.nodes.last]) {
      node.requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
        await tester.pump();
        expect(node.hasFocus, isTrue);
      }
    }
    expect(row.left, 6);
    expect(row.right, 6);
    expect(row.leftEdge, 0);
    expect(row.bubbled, hasLength(6));
    expect(row.bubbled, everyElement(isA<KeyUpEvent>()));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('off-TV arrows bubble without invoking TV actions', (
    tester,
  ) async {
    final row = _Row();
    addTearDown(row.dispose);
    await tester.pumpWidget(
      row.build(tv: false, heldOverrides: true, horizontalOverrides: true),
    );
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
    expect([
      row.left,
      row.right,
      row.leftEdge,
      row.up,
      row.down,
      row.upHold,
      row.downHold,
    ], everyElement(0));
    expect(row.nodes[1].hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activation and back keys pass through to the parent', (
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
    expect(row.bubbled, hasLength(6));
    expect(row.leftEdge, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

class _Row {
  final nodes = List.generate(3, (_) => FocusNode());
  final bubbled = <KeyEvent>[];
  int left = 0,
      right = 0,
      leftEdge = 0,
      up = 0,
      down = 0,
      upHold = 0,
      downHold = 0;

  Widget build({
    bool tv = true,
    bool heldOverrides = false,
    bool horizontalOverrides = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Focus(
        onKeyEvent: (_, event) {
          bubbled.add(event);
          return KeyEventResult.handled;
        },
        child: Row(
          children: [
            for (var i = 0; i < nodes.length; i++)
              HomeFavoriteCell(
                isTelevision: tv,
                column: i,
                rowNodes: nodes,
                onUp: () => up++,
                onDown: () => down++,
                onLeftEdge: () => leftEdge++,
                onLeft: horizontalOverrides ? () => left++ : null,
                onRight: horizontalOverrides ? () => right++ : null,
                onUpHold: heldOverrides ? () => upHold++ : null,
                onDownHold: heldOverrides ? () => downHold++ : null,
                child: Focus(
                  focusNode: nodes[i],
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Text('Card $i'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
  }
}
