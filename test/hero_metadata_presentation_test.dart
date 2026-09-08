import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/models/hero_metadata_presentation.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const original = StremioMeta(
    id: 'tt1234567',
    type: 'movie',
    name: 'Original',
    description: 'Original plot',
    runtime: '90 min',
    genres: ['Drama'],
    logo: 'original-logo',
    background: 'original-background',
    poster: 'original-poster',
    imdbRating: 8,
    addedAtMs: 123,
  );
  const sparse = StremioMeta(
    id: 'tt1234567',
    type: 'movie',
    name: 'Translated',
  );

  test('sparse details retain the complete catalog fallback baseline', () {
    final merged = mergeHeroMetadata(original, sparse);
    expect(merged.name, 'Translated');
    expect(merged.description, original.description);
    expect(merged.background, original.background);
    expect(merged.runtime, original.runtime);
    expect(merged.genres, original.genres);
    expect(merged.imdbRating, original.imdbRating);
    expect(merged.id, original.id);
    expect(merged.addedAtMs, original.addedAtMs);
  });

  for (final fallback in [true, false]) {
    test(
      'sparse host baseline survives missing TMDB with fallback=$fallback',
      () async {
        const catalog = StremioMeta(
          id: 'unmapped-custom',
          type: 'movie',
          name: 'Catalog',
          description: 'Catalog plot',
          background: 'catalog-art',
          poster: 'poster',
        );
        const host = StremioMeta(
          id: 'unmapped-custom',
          type: 'movie',
          name: 'Catalog',
          runtime: '95 min',
        );
        final prefs = MetadataPreferences(
          providers: {
            MetadataCategory.information: 'tmdb',
            MetadataCategory.backgrounds: 'tmdb',
          },
          fallback: fallback,
        );
        final result = await MetadataProviderService.instance.present(
          mergeHeroMetadata(catalog, host),
          preferences: prefs,
        );
        final fields = HeroMetadataFields(
          catalog,
          HeroMetadataPresentation(result.item, prefs),
        );
        expect(fields.description, fallback ? 'Catalog plot' : null);
        expect(fields.background, fallback ? 'catalog-art' : null);
        expect(fields.runtime, fallback ? '95 min' : null);
      },
    );
  }

  test('legacy sparse enrichment keeps current stage fallback behaviour', () {
    final fields = HeroMetadataFields(original, sparse);
    expect(fields.name, 'Original');
    expect(fields.description, 'Original plot');
    expect(fields.runtime, '90 min');
    expect(fields.genres, ['Drama']);
    expect(fields.logo, 'original-logo');
    expect(fields.background, 'original-background');
    expect(fields.posterFallback, 'original-poster');
    expect(fields.allowArtworkFallback, true);
  });

  test(
    'selected information renders localized title and preserves missing fields',
    () {
      final fields = HeroMetadataFields(
        original,
        HeroMetadataPresentation(
          sparse,
          MetadataPreferences(
            providers: {MetadataCategory.information: 'tmdb'},
          ),
        ),
      );
      expect(fields.name, 'Translated');
      expect(fields.description, isNull);
      expect(fields.runtime, isNull);
      expect(fields.genres, isNull);
      expect(fields.logo, 'original-logo');
      expect(fields.allowArtworkFallback, true);
    },
  );

  test(
    'selected backgrounds disable original, derived and poster fallback',
    () {
      final fields = HeroMetadataFields(
        original,
        HeroMetadataPresentation(
          sparse,
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: 'tmdb'},
          ),
        ),
      );
      expect(fields.logo, isNull);
      expect(fields.background, isNull);
      expect(fields.posterFallback, isNull);
      expect(fields.allowArtworkFallback, false);
      expect(fields.name, 'Original');
      expect(fields.description, 'Original plot');
    },
  );

  test('explicit fallback permits derived art and poster recovery', () {
    final fields = HeroMetadataFields(
      original,
      HeroMetadataPresentation(
        sparse,
        MetadataPreferences(
          providers: {MetadataCategory.backgrounds: 'tmdb'},
          fallback: true,
        ),
      ),
    );
    expect(fields.allowArtworkFallback, true);
    expect(fields.posterFallback, 'original-poster');
  });

  test(
    'successful selected fields survive while identity and ratings stay intact',
    () {
      const presented = StremioMeta(
        id: 'tt1234567',
        type: 'movie',
        name: 'Translated',
        description: 'Translated plot',
        runtime: '95 min',
        genres: ['Comedy'],
        logo: 'selected-logo',
        background: 'selected-background',
        imdbRating: 8,
        addedAtMs: 123,
      );
      final snapshot = HeroMetadataPresentation(
        presented,
        MetadataPreferences(
          providers: {
            MetadataCategory.information: 'tmdb',
            MetadataCategory.backgrounds: 'tmdb',
          },
        ),
      );
      final fields = HeroMetadataFields(original, snapshot);
      expect(fields.name, 'Translated');
      expect(fields.description, 'Translated plot');
      expect(fields.runtime, '95 min');
      expect(fields.genres, ['Comedy']);
      expect(fields.logo, 'selected-logo');
      expect(fields.background, 'selected-background');
      expect(snapshot.id, original.id);
      expect(snapshot.imdbRating, original.imdbRating);
      expect(snapshot.addedAtMs, original.addedAtMs);
    },
  );

  test('a default-policy snapshot retains legacy sparse behaviour', () {
    final fields = HeroMetadataFields(
      original,
      HeroMetadataPresentation(sparse, MetadataPreferences()),
    );
    expect(fields.name, 'Original');
    expect(fields.description, 'Original plot');
    expect(fields.background, 'original-background');
    expect(fields.allowArtworkFallback, true);
  });
}
