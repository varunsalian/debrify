import 'package:debrify/features/home/presentation/home_mosaic_cell_navigation.dart';
import 'package:debrify/features/home/presentation/home_stage_hold_latch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('grid edges, paging and held arrows preserve focus paths', (
    tester,
  ) async {
    final nodes = List.generate(6, (_) => FocusNode());
    final hold = HomeStageHoldLatch();
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final node in nodes)
              Focus(focusNode: node, child: const SizedBox()),
          ],
        ),
      ),
    );
    HomeMosaicCellNavigation at(int column, {bool catalog = true}) =>
        HomeMosaicCellNavigation(
          column: column,
          count: 6,
          perRow: 2,
          nodes: nodes,
          hold: hold,
          focusSidebar: () => calls.add('sidebar'),
          switchRail: (direction) => calls.add('rail:$direction'),
          loadMore: catalog ? () => calls.add('page') : null,
          deferRight: () => calls.add('defer'),
        );
    at(0).down();
    await tester.pump();
    expect(nodes[2].hasFocus, isTrue);
    expect(calls, isEmpty);
    at(1).right(); // Wrap at a visual row edge.
    await tester.pump();
    expect(nodes[2].hasFocus, isTrue);
    at(2).left();
    expect(calls, ['sidebar']);
    calls.clear();
    at(3).left();
    await tester.pump();
    expect(nodes[2].hasFocus, isTrue);
    at(4).up();
    await tester.pump();
    expect(nodes[2].hasFocus, isTrue);
    at(5).right();
    expect(calls, ['page', 'defer']);
    calls.clear();
    at(5, catalog: false).right();
    expect(calls, isEmpty);
    at(4).down();
    expect(calls, ['page', 'rail:1']);
    calls.clear();
    at(0).downHold();
    at(4).down();
    at(4).downHold();
    expect(calls, ['rail:1']);
    // An opposite arrow still works; a fresh Down releases the latch.
    at(0).up();
    expect(calls.last, 'rail:-1');
    hold.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
    );
    at(4).down();
    expect(calls.sublist(calls.length - 2), ['page', 'rail:1']);
    await tester.pumpWidget(const SizedBox());
    for (final node in nodes) {
      node.dispose();
    }
  });
}
