import 'package:debrify/widgets/home/home_row_focus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('background row reorder preserves focused content', (
    tester,
  ) async {
    final a = FocusNode();
    final b = FocusNode();
    Widget board(List<FocusNode> nodes) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final node in nodes)
            Focus(
              key: ObjectKey(node),
              focusNode: node,
              child: const SizedBox(),
            ),
        ],
      ),
    );
    await tester.pumpWidget(board([a, b]));
    b.requestFocus();
    await tester.pump();
    expect(b.hasFocus, isTrue);
    final next = reconcileHomeRowFocus(
      previousIds: [
        ['row:a', 'row:b'],
      ],
      previousNodes: [
        [a, b],
      ],
      nextIds: [
        ['row:b', 'row:a', 'row:new'],
      ],
    );
    expect(next.single[0], same(b));
    expect(next.single[1], same(a));
    await tester.pumpWidget(board(next.single));
    await tester.pump();
    expect(b.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    for (final node in next.single) {
      node.dispose();
    }
  });

  test('removed rows release nodes and duplicate identities stay distinct', () {
    final a = FocusNode();
    final b = FocusNode();
    final removed = FocusNode();
    final next = reconcileHomeRowFocus(
      previousIds: [
        ['same', 'same'],
        ['removed'],
      ],
      previousNodes: [
        [a, b],
        [removed],
      ],
      nextIds: [
        ['same', 'same', 'same'],
      ],
    );
    expect(next.single.toSet(), hasLength(3));
    expect(next.single.take(2), [a, b]);
    expect(() => removed.addListener(() {}), throwsFlutterError);
    for (final node in next.single) {
      node.dispose();
    }
  });
}
