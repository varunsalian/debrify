import 'package:debrify/features/discover/presentation/discover_source_panel.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const searchOnly = StremioAddonCatalog(
  id: 'search',
  type: 'movie',
  name: 'Search',
  extras: [StremioExtraParam(name: 'search', isRequired: true)],
);
const browse = StremioAddonCatalog(id: 'first', type: 'movie', name: 'First');
const second = StremioAddonCatalog(
  id: 'second',
  type: 'series',
  name: 'Second',
);

class Panels {
  final built = <String>[];
  final lookups = <String>[];
  final inventory = <String, StremioAddon>{};
  final result = const SizedBox(key: ValueKey('original panel'));
  StremioAddon? acceptedAddon;
  StremioAddonCatalog? acceptedCatalog;

  Widget panel(String name) {
    built.add(name);
    return result;
  }

  Widget select(String source, {bool tmdbReady = true}) =>
      buildDiscoverSourcePanel(
        selected: source,
        mediaServer: panel,
        tmdb: tmdbReady ? () => panel('tmdb') : null,
        trakt: () => panel('trakt'),
        simkl: () => panel('simkl'),
        mdblist: () => panel('mdblist'),
        findAddon: (id) {
          lookups.add(id);
          return inventory[id];
        },
        catalog: (addon, catalog) {
          acceptedAddon = addon;
          acceptedCatalog = catalog;
          return panel('catalog');
        },
        continueWatching: () => panel('cw'),
      );

  StremioAddon install(List<StremioAddonCatalog> catalogs) {
    final addon = StremioAddon(
      id: 'configured:one',
      name: 'Original name',
      userAlias: 'User alias',
      baseUrl: 'https://example.invalid',
      manifestUrl: 'https://example.invalid/manifest.json',
      catalogs: catalogs,
    );
    inventory[addon.id] = addon;
    return addon;
  }
}

void main() {
  test(
    'fixed sources invoke only their selected builder without inventory access or wrapping',
    () {
      for (final source in [
        'cw',
        'trakt',
        'simkl',
        'tmdb',
        'jellyfin',
        'emby',
        'mdblist',
        'unknown',
      ]) {
        final panels = Panels();
        expect(panels.select(source), same(panels.result));
        expect(panels.built, [source == 'unknown' ? 'cw' : source]);
        expect(panels.lookups, isEmpty);
      }
    },
  );

  test('TMDB keeps CW fallback until its preferences are ready', () {
    final panels = Panels();
    panels.select('tmdb', tmdbReady: false);
    panels.select('tmdb');
    expect(panels.built, ['cw', 'tmdb']);
    expect(panels.lookups, isEmpty);
  });

  test(
    'catalog uses stable configured id and first browsable catalog in inventory order',
    () {
      final panels = Panels();
      final addon = panels.install([searchOnly, browse, second]);
      expect(panels.select('a:configured:one'), same(panels.result));
      expect(panels.built, ['catalog']);
      expect(panels.lookups, ['configured:one']);
      expect(panels.acceptedAddon, same(addon));
      expect(panels.acceptedCatalog, same(browse));
    },
  );

  test(
    'inventory is read afresh so a removed addon falls back on the next build',
    () {
      final panels = Panels();
      panels.install([browse]);
      panels.select('a:configured:one');
      panels.inventory.clear();
      panels.select('a:configured:one');
      expect(panels.built, ['catalog', 'cw']);
      expect(panels.lookups, ['configured:one', 'configured:one']);
    },
  );

  for (final catalogs in [
    <StremioAddonCatalog>[],
    [searchOnly],
  ]) {
    test(
      'addon with ${catalogs.length} non-browsable catalogs falls back without building catalog',
      () {
        final panels = Panels();
        panels.install(catalogs);
        panels.select('a:configured:one');
        expect(panels.built, ['cw']);
        expect(panels.acceptedCatalog, isNull);
      },
    );
  }
}
