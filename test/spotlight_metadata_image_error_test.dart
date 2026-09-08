import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fallback in [false, true]) {
    test('wide card resolves absent primary with fallback=$fallback', () {
      final card = SpotlightCard(
        title: 'A',
        onOpen: () {},
        shape: SpotlightCardShape.wide,
        image: 'old-image',
        fallbackImage: 'old-poster',
      );
      final presented = StremioMeta(
        id: 'a',
        type: 'movie',
        name: 'A',
        poster: 'presented-poster',
      );
      expect(
        card.imageForPresentation(
          presented,
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: 'tmdb'},
            fallback: fallback,
          ),
        ),
        fallback ? 'presented-poster' : null,
      );
    });
  }

  const original = StremioMeta(
    id: 'tmdb:1',
    type: 'movie',
    name: 'Title',
    poster: 'old-poster',
  );
  const presented = StremioMeta(
    id: 'tmdb:1',
    type: 'movie',
    name: 'Title',
    poster: 'selected-poster',
    background: 'broken-backdrop',
  );
  SpotlightCard card({bool episode = false}) => SpotlightCard(
    metadata: original,
    title: 'Title',
    onOpen: () {},
    image: 'old-backdrop',
    fallbackImage: 'old-poster',
    shape: SpotlightCardShape.wide,
    episodeArtwork: episode,
  );
  for (final fallback in [false, true]) {
    test('backdrop image error respects fallback=$fallback', () {
      final prefs = MetadataPreferences(
        providers: {
          MetadataCategory.backgrounds: 'tmdb',
          MetadataCategory.posters: 'tmdb',
        },
        fallback: fallback,
      );
      expect(
        card().imageErrorFallback(presented, prefs),
        fallback ? 'selected-poster' : null,
      );
    });
  }
  test(
    'missing selected poster never restores catalog poster on image error',
    () {
      const missing = StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Title');
      expect(
        card().imageErrorFallback(
          missing,
          MetadataPreferences(providers: {MetadataCategory.posters: 'tmdb'}),
        ),
        isNull,
      );
    },
  );
  test('default image error preserves configured fallback', () {
    expect(
      card().imageErrorFallback(presented, MetadataPreferences()),
      'old-poster',
    );
  });
  test(
    'independent poster selection supplies the fallback for a default backdrop',
    () {
      expect(
        card().imageErrorFallback(
          presented,
          MetadataPreferences(providers: {MetadataCategory.posters: 'tmdb'}),
        ),
        'selected-poster',
      );
    },
  );
  test('selected episode artwork suppresses cross-provider error fallback', () {
    expect(
      card(episode: true).imageErrorFallback(
        presented,
        MetadataPreferences(
          providers: {MetadataCategory.episodeArtwork: 'tmdb'},
        ),
      ),
      isNull,
    );
  });

  test('episode artwork retains its independently managed fallback', () {
    expect(
      card(episode: true).imageErrorFallback(
        presented,
        MetadataPreferences(
          providers: {
            MetadataCategory.backgrounds: 'tmdb',
            MetadataCategory.posters: 'tmdb',
          },
        ),
      ),
      'old-poster',
    );
  });
}
