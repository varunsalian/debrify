import 'package:debrify/features/home/presentation/home_classic_rows.dart';
import 'package:debrify/features/home/presentation/home_row_entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home insertion and reorder retain mounted row state and focus', (
    tester,
  ) async {
    final scroll = ScrollController();
    final node = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(node.dispose);
    Widget rows(List<String> ids, {int generation = 1}) => _host(
      HomeClassicRows(
        scrollController: scroll,
        generation: generation,
        catalogRowCount: 0,
        orderedRowIds: ids,
        rowBuilder: (_, i) => _Probe(ids[i], ids[i] == 'b' ? node : null),
        footerBuilder: (_) => const Text('Footer'),
        showFooter: false,
        tailPadding: 0,
        isFresh: () => false,
      ),
    );
    await tester.pumpWidget(rows(['a', 'b']));
    final before = tester.state(
      find.byWidgetPredicate((w) => w is _Probe && w.label == 'b'),
    );
    node.requestFocus();
    await tester.pump();
    await tester.pumpWidget(rows(['new', 'b', 'a']));
    expect(
      tester.state(
        find.byWidgetPredicate((w) => w is _Probe && w.label == 'b'),
      ),
      same(before),
    );
    expect(node.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('board-reveal-1-b')), findsOneWidget);
    await tester.pumpWidget(rows(['b', 'a', 'new'], generation: 2));
    expect(
      tester.state(
        find.byWidgetPredicate((w) => w is _Probe && w.label == 'b'),
      ),
      isNot(same(before)),
    );
    await tester.pumpWidget(const SizedBox());
    expect(scroll.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'catalog indices, footer, padding and cache extent keep their contracts',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Widget rows(bool footer) => _host(
        HomeClassicRows(
          scrollController: scroll,
          generation: 7,
          catalogRowCount: 2,
          orderedRowIds: null,
          rowBuilder: (_, i) => SizedBox(height: 50, child: Text('Catalog $i')),
          footerBuilder: (_) => const Text('Footer'),
          showFooter: footer,
          tailPadding: 45,
          isFresh: () => false,
        ),
      );
      await tester.pumpWidget(rows(true));
      expect(
        find.byKey(const ValueKey('board-reveal-7-index:0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('board-reveal-7-index:1')),
        findsOneWidget,
      );
      expect(find.text('Footer'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Footer'),
          matching: find.byType(HomeRowEntrance, skipOffstage: false),
        ),
        findsNothing,
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding, const EdgeInsets.only(top: 6, bottom: 77));
      expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(300));
      expect(
        (list.childrenDelegate as SliverChildBuilderDelegate)
            .findChildIndexCallback,
        isNull,
      );
      await tester.pumpWidget(rows(false));
      expect(find.text('Footer'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'lazy rows evaluate freshness after construction and stagger only first six',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final order = <String>[];
      var fresh = true;
      await tester.pumpWidget(
        _host(
          HomeClassicRows(
            scrollController: scroll,
            generation: 1,
            catalogRowCount: 100,
            orderedRowIds: null,
            rowBuilder: (_, i) {
              order.add('row:$i');
              return SizedBox(height: 80, child: Text('Row $i'));
            },
            footerBuilder: (_) => const Text('Footer'),
            showFooter: false,
            tailPadding: 0,
            isFresh: () {
              order.add('fresh');
              return fresh;
            },
          ),
        ),
      );
      expect(order.length, lessThan(200));
      for (var i = 0; i < order.length; i += 2) {
        expect(order[i], startsWith('row:'));
        expect(order[i + 1], 'fresh');
      }
      final initial = tester
          .widgetList<HomeRowEntrance>(
            find.byType(HomeRowEntrance, skipOffstage: false),
          )
          .toList();
      expect(initial.where((w) => w.play), hasLength(6));
      expect(initial.where((w) => !w.play), isNotEmpty);
      expect(initial.take(6).map((w) => w.delayMs), [
        0,
        60,
        120,
        180,
        240,
        300,
      ]);
      await tester.pump(const Duration(seconds: 1));
      fresh = false;
      scroll.jumpTo(4000);
      await tester.pump();
      expect(
        tester
            .widgetList<HomeRowEntrance>(
              find.byType(HomeRowEntrance, skipOffstage: false),
            )
            .every((w) => !w.play),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

class _Probe extends StatefulWidget {
  const _Probe(this.label, this.node);
  final String label;
  final FocusNode? node;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 70,
    child: Focus(focusNode: widget.node, child: Text(widget.label)),
  );
}
