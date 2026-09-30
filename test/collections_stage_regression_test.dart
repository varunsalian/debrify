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
  // Every stage layout builds its cells through the shared HomeStageCards
  // builder, which owns collection shape, artwork and focus preview.
  final stageCards = File(
    'lib/features/home/presentation/home_stage_cards.dart',
  ).readAsStringSync();
  test(
    'shared stage cards use collection artwork, shape and focus preview',
    () {
      expect(stageCards, contains('aspectOf(rail'));
      expect(stageCards, contains('artOf(rail'));
      expect(stageCards, contains('focusArtOf('));
      expect(stageCards, contains('focusVideoOf('));
      expect(stageCards, contains('focusGlowEnabled:'));
      expect(stageCards, contains('hideTitle'));
      // The screen wires the collection-aware geometry, not global title
      // geometry, into the shared builder.
      expect(source, contains('aspectOf: _stageCardAspect,'));
      expect(source, contains('artOf: _stageCardArt,'));
    },
  );
  for (final (start, end) in [
    ('Widget _canvasCell', 'void _maybeCompleteStageAdvance'),
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
      expect(body, contains('_stageCards.build('));
    });
  }
  test('Canvas board sizes its rail with collection geometry', () {
    final from = source.indexOf('Widget _buildCanvasBoard');
    final to = source.indexOf('double get _titleCardAspect', from);
    expect(from, isNonNegative);
    expect(to, greaterThan(from));
    final body = source.substring(from, to);
    expect(body, contains('_stageCardAspect(view.rail)'));
    expect(body, contains('_canvasCell(view, col)'));
  });
  test('folder focus retires title work and owns the hero', () {
    final source = File(
      'lib/features/home/presentation/home_hero_section.dart',
    ).readAsStringSync();
    final start = source.indexOf('  void setHero(');
    final body = source.substring(
      start,
      source.indexOf('// A catalog/CW card owns', start),
    );
    const cancel = '_deps.media().metadata.cancel()';
    expect(body, contains(cancel));
    // The loader's executable cancellation tests cover request retirement;
    // this guard checks the folder caller invokes it before replacing the hero.
    expect(
      body.indexOf(cancel),
      lessThan(body.indexOf('heroItem.value = item')),
    );
    expect(body, contains('_deps.preview().clearHeroTrailer()'));
    expect(body, contains('_deps.clearLive()'));
    expect(body, contains('heroItem.value = item'));
    expect(body, contains('heroEnriched.value = null'));
  });
}
