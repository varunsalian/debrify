import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_catalog_refresh.dart';
import 'package:debrify/widgets/home/home_row_focus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const catalog = StremioAddonCatalog(
  id: 'popular',
  type: 'movie',
  name: 'Popular',
);
StremioAddon addon(String url) => StremioAddon(
  id: 'test',
  name: 'Test',
  manifestUrl: '$url/manifest.json',
  baseUrl: url,
  addedAt: DateTime.utc(2026),
  catalogs: [catalog],
);
StremioMeta item(int i) =>
    StremioMeta(id: '$i', type: 'movie', name: 'Movie $i');
CatalogSection previous(StremioAddon source) => CatalogSection(
  title: 'Popular',
  addon: source,
  catalog: catalog,
  items: List.generate(60, item),
  nextSkip: 100,
);

void main() {
  test('filtered refresh retains the raw horizontal extent', () async {
    final skips = <int>[];
    final refreshed = await loadHomeCatalogSection(
      addon: addon('https://new.invalid'),
      catalog: catalog,
      previous: previous(addon('https://old.invalid')),
      isCurrent: () => true,
      hides: (meta) => int.parse(meta.id) % 5 != 0,
      fetch: (cursor, raw) async {
        skips.add(cursor);
        raw(25);
        return List.generate(25, (i) => item(cursor + i));
      },
    );
    expect(skips, [0, 25, 50, 75, 100, 125]);
    expect(refreshed!.nextSkip, 150);
    expect(refreshed.items, hasLength(30));
    expect(refreshed.items.every((m) => int.parse(m.id) % 5 == 0), isTrue);
  });

  test('an all-watched first batch preserves a resumable Home row', () async {
    final row = await loadHomeCatalogSection(
      addon: addon('https://filtered.invalid'),
      catalog: catalog,
      isCurrent: () => true,
      hides: (_) => true,
      fetch: (skip, raw) async {
        raw(10);
        return List.generate(10, (i) => item(skip + i));
      },
    );
    expect(row, isNotNull);
    expect(row!.items, isEmpty);
    expect(row.nextSkip, 40);
    expect(row.exhausted, isFalse);
    expect(row.pagingPaused, isTrue);
  });

  testWidgets('addon refresh preserves focus beyond the first page', (
    tester,
  ) async {
    final source = addon('https://example.invalid');
    final old = previous(source)..exhausted = true;
    final nodes = List.generate(60, (_) => FocusNode());
    Widget board(List<FocusNode> nodes) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (final n in nodes)
            Focus(key: ObjectKey(n), focusNode: n, child: const SizedBox()),
        ],
      ),
    );
    await tester.pumpWidget(board(nodes));
    nodes[50].requestFocus();
    await tester.pump();
    var fetches = 0;
    final refreshed = await loadHomeCatalogSection(
      addon: addon('https://example.invalid'),
      catalog: catalog,
      previous: old,
      isCurrent: () => true,
      fetch: (skip, raw) async {
        fetches++;
        return [];
      },
    );
    expect(refreshed, same(old));
    expect(fetches, 0);
    expect(refreshed!.nextSkip, 100);
    expect(refreshed.exhausted, isTrue);
    final next = reconcileHomeRowFocus(
      previousIds: [old.items.map((m) => m.id).toList()],
      previousNodes: [nodes],
      nextIds: [refreshed.items.map((m) => m.id).toList()],
    ).single;
    await tester.pumpWidget(board(next));
    await tester.pump();
    expect(next[50], same(nodes[50]));
    expect(next[50].hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    for (final node in next) {
      node.dispose();
    }
  });

  test('changed configuration reloads the raw horizontal extent', () async {
    final skips = <int>[];
    final refreshed = await loadHomeCatalogSection(
      addon: addon('https://new.invalid'),
      catalog: catalog,
      previous: previous(addon('https://old.invalid')),
      isCurrent: () => true,
      fetch: (skip, raw) async {
        skips.add(skip);
        raw(50);
        return List.generate(30, (i) => item(skip ~/ 50 * 30 + i));
      },
    );
    expect(skips, [0, 50]);
    expect(refreshed!.items, hasLength(60));
    expect(refreshed.items[50].id, '50');
    expect(refreshed.nextSkip, 100);
    expect(refreshed.addon.baseUrl, 'https://new.invalid');
  });

  test('superseded refresh stops before requesting more pages', () async {
    var current = true;
    var calls = 0;
    final result = await loadHomeCatalogSection(
      addon: addon('https://new.invalid'),
      catalog: catalog,
      previous: previous(addon('https://old.invalid')),
      isCurrent: () => current,
      fetch: (skip, raw) async {
        calls++;
        current = false;
        raw(50);
        return [item(1)];
      },
    );
    expect(result, isNull);
    expect(calls, 1);
  });

  test(
    'switch-off duplicate pages terminate a catalog which ignores skip',
    () async {
      var calls = 0;
      final result = await loadHomeCatalogSection(
        addon: addon('https://new.invalid'),
        catalog: catalog,
        previous: previous(addon('https://old.invalid')),
        isCurrent: () => true,
        fetch: (skip, raw) async {
          calls++;
          raw(1);
          return [item(1)];
        },
      );
      expect(calls, 2);
      expect(result!.exhausted, isTrue);
      expect(result.pagingPaused, isFalse);
      expect(result.items, hasLength(1));
    },
  );
}
