import 'package:debrify/models/metadata_card_artwork.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fallback in [false, true]) {
    for (final override in [null, 'host-art']) {
      test(
        'missing primary respects fallback=$fallback override=$override',
        () {
          final art = metadataCardArtwork(
            presented: const StremioMeta(
              id: 'a',
              type: 'movie',
              name: 'A',
              poster: 'poster',
            ),
            preferences: MetadataPreferences(
              providers: {MetadataCategory.backgrounds: 'tmdb'},
              fallback: fallback,
            ),
            wide: true,
            overrideUrl: override,
          );
          expect(art.primary, fallback ? override ?? 'poster' : null);
        },
      );
    }
  }

  const title = StremioMeta(
    id: 'show',
    type: 'series',
    name: 'Show',
    background: 'selected-backdrop',
    poster: 'catalog-poster',
  );
  final backdrop = MetadataPreferences(
    providers: {MetadataCategory.backgrounds: 'tmdb'},
  );
  test('a CW title with no actual still uses selected show artwork', () {
    final art = metadataCardArtwork(
      presented: title,
      preferences: backdrop,
      wide: true,
      overrideUrl: 'old-show-art',
    );
    expect(art.primary, 'selected-backdrop');
    expect(art.fallback, isNull);
  });
  test(
    'actual episode still remains independent of the backdrop selection',
    () {
      final art = metadataCardArtwork(
        presented: title,
        preferences: backdrop,
        wide: true,
        overrideUrl: 'episode-still',
        episodeArtwork: true,
      );
      expect(art.primary, 'episode-still');
      expect(art.fallback, 'catalog-poster');
    },
  );
  test(
    'an explicitly selected episode still cannot fall back on image failure',
    () {
      final art = metadataCardArtwork(
        presented: title,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.episodeArtwork: 'tmdb'},
        ),
        wide: true,
        overrideUrl: 'episode-still',
        episodeArtwork: true,
      );
      expect(art.primary, 'episode-still');
      expect(art.fallback, isNull);
    },
  );
  test('missing selected backdrop does not restore catalog artwork', () {
    final art = metadataCardArtwork(
      presented: const StremioMeta(
        id: 'show',
        type: 'series',
        name: 'Show',
        poster: 'poster',
      ),
      preferences: backdrop,
      wide: true,
      overrideUrl: 'old-show-art',
    );
    expect(art.primary, isNull);
    expect(art.fallback, isNull);
  });
  test('default and collection artwork preserve their existing override', () {
    for (final collection in [false, true]) {
      final art = metadataCardArtwork(
        presented: title,
        preferences: collection ? backdrop : MetadataPreferences(),
        wide: true,
        overrideUrl: 'override',
        collection: collection,
      );
      expect(art.primary, 'override');
      expect(art.fallback, 'catalog-poster');
    }
  });
}
