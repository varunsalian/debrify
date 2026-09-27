import 'package:debrify/features/home/presentation/home_tonight_queue_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, thumb) in [(260.0, 104.0), (700.0, 100 * 16 / 9)]) {
    testWidgets(
      'Tonight queue at width $width preserves lazy fixed rows and thumbnail space',
      (tester) async {
        final built = <int>[];
        final widths = <double>[];
        var taps = 0;
        await tester.pumpWidget(
          _host(
            width: width,
            itemBuilder: (_, index, thumbnailWidth) {
              built.add(index);
              widths.add(thumbnailWidth);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: SizedBox(key: ValueKey('row-$index'), height: 100),
              );
            },
          ),
        );
        expect(built, contains(0));
        expect(built.length, lessThan(12));
        expect(widths, everyElement(closeTo(thumb, .0001)));
        expect(
          tester.getSize(find.byKey(const ValueKey('row-0'))),
          Size(width, 100),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('row-1'))).dy -
              tester.getTopLeft(find.byKey(const ValueKey('row-0'))).dy,
          112,
        );
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.itemExtent, 112);
        expect(list.padding, EdgeInsets.zero);
        expect(list.clipBehavior, Clip.hardEdge);
        await tester.tap(
          find
              .ancestor(
                of: find.byKey(const ValueKey('row-0')),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(taps, 1);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('queue append and resize retain scroll and borrowed focus', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var latestThumb = 0.0;
    Widget page({int count = 100, double width = 260}) => _host(
      width: width,
      count: count,
      itemBuilder: (_, index, thumb) {
        if (index == 0) {
          latestThumb = thumb;
        }
        return SizedBox(
          height: 100,
          child: index == 0
              ? Focus(focusNode: node, child: const SizedBox.expand())
              : const SizedBox.expand(),
        );
      },
    );
    await tester.pumpWidget(page());
    node.requestFocus();
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(30);
    await tester.pump();
    await tester.pumpWidget(page(count: 101, width: 700));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)),
      same(scroll),
    );
    expect(scroll.position.pixels, 30);
    expect(node.hasFocus, isTrue);
    expect(latestThumb, closeTo(100 * 16 / 9, .0001));
    await tester.pumpWidget(const SizedBox());
    // The list never owns the caller's node; it remains usable after removal.
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: node, child: const SizedBox()),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required double width,
  int count = 100,
  required Widget Function(BuildContext, int, double) itemBuilder,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 300,
      child: buildHomeTonightQueueList(
        itemCount: count,
        rowHeight: 100,
        queueWidth: width,
        itemBuilder: itemBuilder,
      ),
    ),
  ),
);
