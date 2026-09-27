import 'package:debrify/features/home/presentation/home_catalog_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'catalog row reads live count lazily and retains cards, focus and scroll through page changes',
    (tester) async {
      var count = 0;
      var loading = true;
      var showHeader = true;
      final built = <int>{};
      var reads = 0;
      final nodes = List.generate(100, (_) => FocusNode());
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      Widget row() => buildHomeCatalogRow(
        header: showHeader ? const Text('Catalog') : const SizedBox(height: 8),
        cellHeight: 240,
        readChildCount: () {
          reads++;
          return count + (loading ? 1 : 0);
        },
        onLoadMore: () {},
        itemBuilder: (_, index) {
          if (index >= count) {
            return const SizedBox(
              key: ValueKey('spinner'),
              width: 52,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          built.add(index);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Center(
              child: SizedBox(
                width: index == 1 ? 220 : 160,
                height: 240,
                child: InkWell(
                  key: ValueKey('card-$index'),
                  focusNode: nodes[index],
                  onTap: () {},
                  child: Text('Card $index'),
                ),
              ),
            ),
          );
        },
      );
      Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));
      final initial = row();
      expect(reads, 0);
      count = 3;
      await tester.pumpWidget(page(initial));
      expect(reads, 1);
      expect(find.byKey(const ValueKey('card-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('spinner')), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)).height, 254);
      expect(
        tester.getSize(find.byKey(const ValueKey('card-1'))),
        const Size(220, 240),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.clipBehavior, Clip.hardEdge);
      expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(400));
      expect(list.padding, const EdgeInsets.symmetric(horizontal: 13));
      nodes[1].requestFocus();
      await tester.pump();
      final card = tester.element(find.byKey(const ValueKey('card-1')));
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      count = 100;
      loading = false;
      await tester.pumpWidget(page(row()));
      expect(find.byKey(const ValueKey('spinner')), findsNothing);
      expect(built, isNot(contains(99)));
      expect(nodes[1].hasFocus, isTrue);
      expect(tester.element(find.byKey(const ValueKey('card-1'))), same(card));
      scrollable.position.jumpTo(100);
      await tester.pump();
      showHeader = false;
      await tester.pumpWidget(page(row()));
      expect(find.text('Catalog'), findsNothing);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)),
        same(scrollable),
      );
      expect(scrollable.position.pixels, 100);
      expect(nodes[1].hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      nodes[1].requestFocus(); // Focus nodes remain owned by the host.
    },
  );

  testWidgets(
    'paging uses the inclusive horizontal threshold and lets notifications bubble',
    (tester) async {
      var requests = 0;
      var bubbled = 0;
      const childKey = ValueKey('cell');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                bubbled++;
                return false;
              },
              child: buildHomeCatalogRow(
                header: const Text('Catalog'),
                cellHeight: 240,
                readChildCount: () => 1,
                onLoadMore: () => requests++,
                itemBuilder: (_, _) =>
                    const SizedBox(key: childKey, width: 160),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byKey(childKey));
      FixedScrollMetrics metrics(double pixels, {bool vertical = false}) =>
          FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 1000,
            pixels: pixels,
            viewportDimension: 800,
            axisDirection: vertical ? AxisDirection.down : AxisDirection.right,
            devicePixelRatio: 1,
          );
      requests = 0;
      bubbled = 0;
      ScrollUpdateNotification(
        metrics: metrics(99),
        context: context,
        scrollDelta: 1,
      ).dispatch(context);
      expect(requests, 0);
      ScrollUpdateNotification(
        metrics: metrics(100),
        context: context,
        scrollDelta: 1,
      ).dispatch(context);
      expect(requests, 1);
      ScrollUpdateNotification(
        metrics: metrics(1000, vertical: true),
        context: context,
        scrollDelta: 1,
      ).dispatch(context);
      expect(requests, 1);
      ScrollStartNotification(
        metrics: metrics(100),
        context: context,
      ).dispatch(context);
      ScrollEndNotification(
        metrics: metrics(100),
        context: context,
      ).dispatch(context);
      expect(
        requests,
        3,
      ); // Existing loader owns deduplication, not the layout.
      expect(bubbled, 5);
      expect(tester.takeException(), isNull);
    },
  );
}
