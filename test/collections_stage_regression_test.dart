import 'dart:io';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/home_row_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all import forms accept a leading Unicode BOM', () {
    const record = '{"id":"services","title":"Services","folders":[]}';
    for (final json in [record, '[$record]', '{"collections":[$record]}']) {
      expect(HomeCollectionParser.parse('\uFEFF$json').single.id, 'services');
      expect(
        HomeCollectionParser.parse(' \n\uFEFF$json').single.id,
        'services',
      );
    }
  });

  test('a missing provider cannot browse or claim another providers top', () {
    final cinemeta = StremioAddon(
      id: 'cinemeta',
      name: 'Cinemeta',
      manifestUrl: 'https://cinemeta.invalid/manifest.json',
      baseUrl: 'https://cinemeta.invalid',
      resources: ['catalog'],
      catalogs: const [
        StremioAddonCatalog(id: 'top', type: 'movie', name: 'Top'),
      ],
    );
    const source = CollectionCatalogSource(
      addonId: 'missing',
      type: 'movie',
      catalogId: 'top',
    );
    const collection = HomeCollection(
      id: 'c',
      title: 'C',
      folders: [
        HomeCollectionFolder(id: 'f', title: 'F', sources: [source]),
      ],
    );
    expect(HomeCollectionsStore.resolveAddon(source, [cinemeta]), isNull);
    expect(HomeCollectionsStore.unresolvedAddonIds([collection], [cinemeta]), {
      'missing',
    });
    expect(
      HomeCollectionsStore.claimedCatalogKeys([collection], [cinemeta]),
      isEmpty,
    );
  });

  test('new collections follow CW and saved manual positions survive', () {
    const saved = ['cw:movies', 'traktlist:watchlist', 'collection:old'];
    final seeded = HomeRowOrder.seedCollections(saved, [
      'collection:new',
      'collection:old',
    ]);
    expect(seeded, [
      'cw:movies',
      'collection:new',
      'traktlist:watchlist',
      'collection:old',
    ]);
    expect(
      HomeRowOrder.seedCollections(seeded, [
        'collection:new',
        'collection:old',
      ]),
      seeded,
    );
    expect(HomeRowOrder.seedCollections([], ['collection:new']), isEmpty);
  });

  // The stage layouts are private parts of SearchScreen. These wiring guards
  // supplement the rendered shared-card tests; they catch a layout reverting
  // to global title geometry while the shared presentation stays correct.
  final source = File('lib/screens/search_screen.dart').readAsStringSync();
  for (final (start, end) in [
    ('Widget _buildCanvasBoard', 'double get _titleCardAspect'),
    ('Widget _promenadeCell', 'Widget _buildAtriumBoard'),
    ('Widget _atriumRow', 'Widget _buildMosaicBoard'),
    ('Widget _mosaicCell', 'Widget _buildDeckBoard'),
    ('Widget _stageShelfCell', 'Widget _buildTonightBoard'),
  ]) {
    test('$start uses collection artwork, shape and focus preview', () {
      final from = source.indexOf(start);
      final to = source.indexOf(end, from);
      expect(from, isNonNegative);
      expect(to, greaterThan(from));
      final body = source.substring(from, to);
      expect(body, contains('_stageCardAspect(rail'));
      expect(body, contains('_stageCardArt(rail'));
      expect(body, contains('focusArtOf('));
      expect(body, contains('focusVideoOf('));
      expect(body, contains('focusGlowEnabled:'));
      expect(body, contains('hideTitle'));
    });
  }
  test('folder focus retires title work and owns the hero', () {
    final start = source.indexOf('  void _setHero(');
    final body = source.substring(
      start,
      source.indexOf('// A catalog/CW card owns', start),
    );
    expect(body, contains('_heroReqId++'));
    expect(body, contains('_heroTimer?.cancel()'));
    expect(body, contains('_clearHeroTrailer()'));
    expect(body, contains('_clearHeroLiveIptv()'));
    expect(body, contains('_heroItem.value = item'));
    expect(body, contains('_heroEnriched.value = null'));
  });
}
