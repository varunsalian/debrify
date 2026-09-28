import 'package:debrify/features/home/presentation/home_continuation_nodes.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shrinking a focused tail hands off after disposal and retains prefix',
    (tester) async {
      final pools = HomeContinuationNodes();
      const kind = HomeContinuationKind.local;
      final calls = <int>[];
      void focus(List<FocusNode> nodes, int column) {
        calls.add(column);
        nodes[column].requestFocus();
      }

      Widget view() => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            for (final node in [...pools.movies(kind), ...pools.series(kind)])
              Focus(
                key: ObjectKey(node),
                focusNode: node,
                child: const SizedBox(),
              ),
          ],
        ),
      );
      pools.resize(kind, movies: 3, series: 1, requestFocus: focus);
      final first = pools.movies(kind).first;
      final rowList = pools.movies(kind);
      await tester.pumpWidget(view());
      pools.movies(kind).last.requestFocus();
      await tester.pump();
      expect(pools.movies(kind).last.hasFocus, isTrue);
      pools.resize(kind, movies: 1, series: 0, requestFocus: focus);
      await tester.pumpWidget(view());
      expect(calls, [0]);
      expect(first.hasFocus, isTrue);
      expect(pools.movies(kind), same(rowList));
      expect(pools.movies(kind).first, same(first));
      // Merged mode grows the same movie pool and leaves the series slot empty.
      pools.resize(kind, movies: 4, series: 0, requestFocus: focus);
      await tester.pumpWidget(view());
      expect(pools.movies(kind).first, same(first));
      expect(pools.series(kind), isEmpty);
      pools.resize(kind, movies: 0, series: 0, requestFocus: focus);
      await tester.pumpWidget(view());
      expect(calls, [
        0,
      ]); // Empty-row recovery remains the host's responsibility.
      await tester.pumpWidget(const SizedBox());
      pools.disposeNodes();
      pools.clearNodes();
    },
  );
}
