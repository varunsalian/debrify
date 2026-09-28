import 'package:debrify/features/search/presentation/lists_search_rail.dart';
import 'package:debrify/models/mdblist_list_choice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single rail handles directions and activation repeats', (
    tester,
  ) async {
    final nodes = [FocusNode(), FocusNode()];
    final opened = <int>[];
    var sidebar = 0;
    var up = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildListsSearchRail(
            posterW: 100,
            header: const SizedBox(),
            results: () => const [
              MdblistListChoice(id: 1, name: 'First'),
              MdblistListChoice(id: 2, name: 'Second'),
            ],
            nodes: nodes,
            isTelevision: true,
            onOpen: (list) => opened.add(list.id),
            onSidebar: () => sidebar++,
            onUp: () => up++,
          ),
        ),
      ),
    );
    nodes.first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(sidebar, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(nodes.last.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nodes.last.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(opened, [2, 2]); // The host retains its existing debounce policy.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(up, 1);
    await tester.pumpWidget(const SizedBox());
    for (final node in nodes) {
      node.dispose();
    }
  });
}
