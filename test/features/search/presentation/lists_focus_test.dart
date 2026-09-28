import 'package:debrify/features/search/presentation/lists_focus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'return focus resolves current index and reset releases old nodes',
    (tester) async {
      final focus = ListsFocus()..resize(2);
      final first = focus.nodes.first;
      focus.resize(3);
      expect(focus.nodes.first, same(first));
      var index = 0;
      var current = true;
      focus.restore(isCurrent: () => current, indexOfResult: () => index);
      index = 1;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final node in focus.nodes)
                Focus(focusNode: node, child: const SizedBox()),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(focus.nodes[1].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      focus.resize(1);
      expect(focus.nodes.single, same(first));
      focus.restore(
        isCurrent: () => current,
        indexOfResult: () => fail('retired route'),
      );
      current = false;
      focus.clear();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(focus.nodes, isEmpty);
      expect(tester.takeException(), isNull);
      focus.resize(1);
      expect(focus.nodes.single, isNot(same(first)));
      focus.clear();
    },
  );
}
