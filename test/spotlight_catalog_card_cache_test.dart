import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:debrify/widgets/home/spotlight_catalog_card_cache.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon addon(String id) => StremioAddon(
  id: id,
  name: id,
  manifestUrl: 'https://example.invalid/$id/manifest.json',
  baseUrl: 'https://example.invalid/$id',
);

class _ResolvedMeta extends StremioMeta {
  _ResolvedMeta() : super(id: 'tmdb:42', type: 'movie', name: 'Title');
  String? resolvedId;
  @override
  String? get effectiveImdbId => resolvedId;
}

void main() {
  test('late identity resolution refreshes artwork and watched identity', () {
    final item = _ResolvedMeta();
    final source = addon('source');
    final cache = SpotlightCatalogCardCache(
      wideArtwork: (m) => m.effectiveImdbId,
      onOpen: (_, __) {},
    );
    final unresolved = cache.resolve(item, source, landscape: true);
    expect(unresolved.watchedImdbId, 'tmdb:42');
    item.resolvedId = 'tt42';
    final resolved = cache.resolve(item, source, landscape: true);
    expect(resolved, isNot(same(unresolved)));
    expect(resolved.image, 'tt42');
    expect(resolved.watchedImdbId, 'tt42');
    expect(cache.resolve(item, source, landscape: true), same(resolved));
  });
  const item = StremioMeta(
    id: 'tmdb:1',
    imdbId: 'tt1',
    type: 'movie',
    name: 'First',
    poster: 'poster',
    background: 'wide',
    imdbRating: 8.5,
  );
  test(
    'reuses immutable presentation and refreshes orientation and provenance',
    () {
      var reads = 0;
      StremioAddon? opened;
      final cache = SpotlightCatalogCardCache(
        wideArtwork: (m) {
          reads++;
          return m.background;
        },
        onOpen: (_, a) => opened = a,
      );
      final firstAddon = addon('first');
      final nextAddon = addon('next');
      final first = cache.resolve(item, firstAddon, landscape: true);
      expect(cache.resolve(item, firstAddon, landscape: true), same(first));
      expect(reads, 1);
      expect(first.image, 'wide');
      expect(first.fallbackImage, 'poster');
      expect(first.rating, 8.5);
      expect(first.watchedImdbId, 'tt1');
      final portrait = cache.resolve(item, firstAddon, landscape: false);
      expect(portrait.image, 'poster');
      expect(portrait.fallbackImage, isNull);
      expect(portrait.shape, SpotlightCardShape.poster);
      final replacement = cache.resolve(item, nextAddon, landscape: false);
      replacement.onOpen();
      expect(opened, same(nextAddon));
      first.onOpen();
      expect(
        opened,
        same(firstAddon),
        reason: 'previous callbacks do not follow shifted row indices',
      );
      const updated = StremioMeta(
        id: 'tmdb:1',
        type: 'movie',
        name: 'Changed',
        poster: 'new',
      );
      expect(
        cache.resolve(updated, firstAddon, landscape: false).title,
        'Changed',
      );
    },
  );
  test(
    'large loaded catalogs do not repeat artwork work on unrelated rebuilds',
    () {
      var reads = 0;
      final cache = SpotlightCatalogCardCache(
        wideArtwork: (m) {
          reads++;
          return m.background;
        },
        onOpen: (_, __) {},
      );
      final source = addon('source');
      final items = [
        for (var i = 0; i < 3000; i++)
          StremioMeta(id: 'tt$i', type: 'movie', name: '$i'),
      ];
      for (var rebuild = 0; rebuild < 10; rebuild++) {
        for (final m in items) {
          cache.resolve(m, source, landscape: true);
        }
      }
      expect(reads, items.length);
    },
  );
}
