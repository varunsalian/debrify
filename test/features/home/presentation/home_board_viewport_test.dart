import 'package:debrify/features/home/presentation/home_board_viewport.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogSection section(String id, List<String> items) => CatalogSection(
  title: id,
  addon: StremioAddon(id: 'addon', name: 'Addon', manifestUrl: '', baseUrl: ''),
  catalog: StremioAddonCatalog(id: id, name: id, type: 'movie'),
  items: [
    for (final item in items) StremioMeta(id: item, name: item, type: 'movie'),
  ],
);

void main() {
  test(
    'row reordering retains node identity and incremental column memory',
    () {
      final viewport = HomeBoardViewport();
      final previous = [
        section('a', ['same', 'second']),
        section('b', ['same']),
      ];
      viewport.appendRows(previous);
      final first = viewport.nodes[0][0];
      final otherRow = viewport.nodes[1][0];
      viewport.columns[0] = 1;
      final next = [previous[1], previous[0]];
      viewport.replaceRows(
        previous: previous,
        next: next,
        rowId: (row) => row.catalog.id,
        preserveFocus: true,
        incremental: true,
      );
      expect(viewport.nodes[0][0], same(otherRow));
      expect(viewport.nodes[1][0], same(first));
      expect(viewport.columns, {1: 1});
      viewport.appendItems(1, 1);
      expect(viewport.nodes[1].last.debugLabel, 'search_r1_c2');
      next[1].items.add(
        const StremioMeta(id: 'new', name: 'New', type: 'movie'),
      );
      viewport.replaceRows(
        previous: next,
        next: next,
        rowId: (row) => row.catalog.id,
        preserveFocus: true,
        incremental: false,
      );
      expect(viewport.nodes[1][0], same(first));
      expect(viewport.columns, isEmpty);
      viewport.replaceRows(
        previous: next,
        next: previous,
        rowId: (row) => row.catalog.id,
        preserveFocus: false,
        incremental: false,
      );
      expect(viewport.nodes[0][0], isNot(same(first)));
      viewport.disposeNodes();
      expect(viewport.nodes, isEmpty);
      expect(viewport.columns, isEmpty);
    },
  );

  testWidgets('focus prefers the nearest mounted cell, with left tie-break', (
    tester,
  ) async {
    final viewport = HomeBoardViewport();
    viewport.appendRows([
      section('a', ['left', 'hidden', 'right']),
    ]);
    final nodes = viewport.nodes.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Focus(focusNode: nodes[0], child: const Text('left')),
            Focus(focusNode: nodes[2], child: const Text('right')),
          ],
        ),
      ),
    );
    viewport.requestFocus(nodes, 1, isCurrent: () => true);
    await tester.pump();
    expect(nodes[0].hasFocus, isTrue);
    expect(nodes[2].hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    viewport.disposeNodes();
  });

  for (final retire in [false, true]) {
    testWidgets('unmounted row glides into view; retire=$retire', (
      tester,
    ) async {
      final viewport = HomeBoardViewport();
      viewport.initializeScroll(0);
      viewport.appendRows([
        for (var i = 0; i < 10; i++) section('$i', ['$i']),
      ]);
      var current = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              height: 200,
              child: ListView.builder(
                controller: viewport.scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemExtent: 100,
                itemCount: 10,
                itemBuilder: (_, index) => Focus(
                  focusNode: viewport.nodes[index].single,
                  child: Text('row $index'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(viewport.nodes[3].single.context, isNull);
      viewport.requestFocus(viewport.nodes[3], 0, isCurrent: () => current);
      if (retire) current = false;
      // Retry follows animation completion and a frame, not each animation tick.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pump();
      }
      expect(viewport.nodes[3].single.hasFocus, !retire);
      if (retire) {
        expect(viewport.scroll.offset, closeTo(90, .1));
      } else {
        expect(viewport.scroll.offset, greaterThan(0));
        expect(viewport.scroll.offset, lessThanOrEqualTo(270));
      }
      await tester.pumpWidget(const SizedBox());
      viewport.disposeScroll();
      viewport.disposeNodes();
    });
  }
}
