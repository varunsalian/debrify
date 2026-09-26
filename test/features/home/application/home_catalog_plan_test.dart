import 'package:debrify/features/home/application/home_catalog_plan.dart';
import 'package:debrify/features/home/models/home_catalog_plan.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon addon(
  String id,
  List<StremioAddonCatalog> catalogs, {
  String? config,
}) => StremioAddon(
  id: id,
  name: id,
  manifestUrl: 'https://example.invalid/${config ?? id}/manifest.json',
  baseUrl: 'https://example.invalid/${config ?? id}',
  addedAt: DateTime.utc(2026),
  catalogs: catalogs,
);

StremioAddonCatalog catalog(String id, {String type = 'movie'}) =>
    StremioAddonCatalog(id: id, type: type, name: id);

void main() {
  test(
    'filters only non-browsable, hidden and collection-owned row identities',
    () {
      final source = addon('one', [
        catalog('same'),
        catalog('same', type: 'series'),
        catalog('claimed'),
        const StremioAddonCatalog(
          id: 'search',
          type: 'movie',
          name: 'Search',
          extras: [StremioExtraParam(name: 'search', isRequired: true)],
        ),
        const StremioAddonCatalog(
          id: 'optional',
          type: 'movie',
          name: 'Optional search',
          extras: [StremioExtraParam(name: 'search')],
        ),
      ]);
      final other = addon('two', [catalog('same')]);
      final plan = planHomeCatalogs(
        [source, other],
        disabled: {'one:movie:same'},
        claimed: {'one:movie:claimed'},
      );
      expect(plan.references.map(homeCatalogRowId), [
        'one:series:same',
        'one:movie:optional',
        'two:movie:same',
      ]);
      expect(plan.references.first.$1, same(source));
      expect(plan.references.first.$2, same(source.catalogs[1]));
    },
  );

  test('saved order ranks known rows and appends unranked source order', () {
    final sources = [
      addon('a', [catalog('first'), catalog('second')]),
      addon('b', [catalog('third'), catalog('fourth')]),
    ];
    final saved = [
      'missing:movie:row',
      'b:movie:third',
      'a:movie:second',
      'b:movie:third',
    ];
    final plan = planHomeCatalogs(
      sources,
      disabled: {},
      claimed: {},
      rowOrder: saved,
    );
    expect(plan.references.map(homeCatalogRowId), [
      'b:movie:third',
      'a:movie:second',
      'a:movie:first',
      'b:movie:fourth',
    ]);
    expect(saved, [
      'missing:movie:row',
      'b:movie:third',
      'a:movie:second',
      'b:movie:third',
    ]);
    expect(sources.first.catalogs.map((c) => c.id), ['first', 'second']);
  });

  test('source order is preserved when Home ordering is not active', () {
    final sources = [
      addon('b', [catalog('z'), catalog('a')]),
      addon('a', [catalog('b')]),
    ];
    for (final order in [null, <String>[]]) {
      final plan = planHomeCatalogs(
        sources,
        disabled: {},
        claimed: {},
        rowOrder: order,
      );
      expect(plan.references.map(homeCatalogRowId), [
        'b:movie:z',
        'b:movie:a',
        'a:movie:b',
      ]);
    }
  });

  test(
    'metadata lookup retains first configuration including filtered addons',
    () {
      final first = addon('same', [catalog('hidden')], config: 'first');
      final second = addon('same', [catalog('visible')], config: 'second');
      final empty = addon('empty', []);
      final plan = planHomeCatalogs(
        [first, second, empty],
        disabled: {'same:movie:hidden'},
        claimed: {},
      );
      expect(plan.references.single.$1, same(second));
      expect(plan.addonsById['same'], same(first));
      expect(plan.addonsById['empty'], same(empty));
      expect(plan.addonsById.keys, ['same', 'empty']);
    },
  );

  test(
    'large inventories are uncapped and repeated references are retained',
    () {
      final source = addon('one', List.generate(130, (i) => catalog('$i')));
      final plan = planHomeCatalogs(
        [source, source],
        disabled: {},
        claimed: {},
      );
      expect(plan.references, hasLength(260));
      expect(plan.references[0].$2, same(plan.references[130].$2));
      expect(plan.addonsById, hasLength(1));
    },
  );

  test(
    'containers are independent read-only results and empty input is valid',
    () {
      final sources = [
        addon('one', [catalog('row')]),
      ];
      final plan = planHomeCatalogs(sources, disabled: {}, claimed: {});
      sources.clear();
      expect(plan.references, hasLength(1));
      expect(plan.addonsById, hasLength(1));
      expect(() => plan.references.clear(), throwsUnsupportedError);
      expect(() => plan.addonsById.clear(), throwsUnsupportedError);
      final empty = planHomeCatalogs(
        [],
        disabled: {},
        claimed: {},
        rowOrder: ['old'],
      );
      expect(empty.references, isEmpty);
      expect(empty.addonsById, isEmpty);
    },
  );
}
