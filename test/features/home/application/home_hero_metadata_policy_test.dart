import 'package:debrify/features/home/application/home_hero_metadata_policy.dart';
import 'package:debrify/models/hero_metadata_presentation.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

StremioMeta _item({
  String id = 'tt1',
  String? imdbId,
  String? background = 'background',
  String? description = 'plot',
  String? runtime = '90 min',
  String? logo = 'logo',
  double? rating = 8,
  String? poster = 'poster',
}) => StremioMeta(
  id: id,
  imdbId: imdbId,
  type: 'movie',
  name: 'Title',
  background: background,
  description: description,
  runtime: runtime,
  logo: logo,
  imdbRating: rating,
  poster: poster,
);

HomeHeroAmbientArtUpdate? _art(
  StremioMeta? item,
  StremioMeta? enriched, {
  String? publishedItemId,
  String? publishedArt,
}) => homeHeroAmbientArtUpdate(
  item: item,
  enriched: enriched,
  publishedItemId: publishedItemId,
  publishedArt: publishedArt,
);

void main() {
  test(
    'enrichment covers every missing field and selected-provider refresh',
    () {
      expect(needsHomeHeroMetadata(_item(), currentProvider: true), isFalse);
      expect(needsHomeHeroMetadata(_item(), currentProvider: false), isTrue);
      for (final item in [
        _item(background: null),
        _item(background: ''),
        _item(description: null),
        _item(description: ''),
        _item(runtime: null),
        _item(logo: null),
        _item(logo: ''),
        _item(rating: null),
      ]) {
        expect(needsHomeHeroMetadata(item, currentProvider: true), isTrue);
      }
      // Preserve the original exact emptiness/null rules, without trimming or
      // interpreting empty runtime/zero rating as absent.
      expect(
        needsHomeHeroMetadata(
          _item(
            background: ' ',
            description: ' ',
            logo: ' ',
            runtime: '',
            rating: 0,
          ),
          currentProvider: true,
        ),
        isFalse,
      );
    },
  );

  test('legacy catalog backdrop precedes enrichment then poster fallback', () {
    expect(_art(_item(), _item(background: 'enriched'))!.art, 'background');
    expect(
      _art(_item(background: ''), _item(background: 'enriched'))!.art,
      'enriched',
    );
    expect(_art(_item(background: null), null)!.art, 'poster');
    expect(_art(_item(background: ' '), null)!.art, ' ');
  });

  test(
    'sparse same-title arrival retains publication until backdrop arrives',
    () {
      final sparse = _item(background: null);
      expect(
        _art(sparse, null, publishedItemId: 'tt1', publishedArt: 'existing'),
        isNull,
      );
      expect(
        _art(sparse, null, publishedItemId: 'tt1', publishedArt: ''),
        isNull,
      );
      expect(
        _art(
          sparse,
          _item(background: 'resolved'),
          publishedItemId: 'tt1',
          publishedArt: 'existing',
        )!.art,
        'resolved',
      );
      expect(
        _art(
          sparse,
          null,
          publishedItemId: 'other',
          publishedArt: 'existing',
        )!.art,
        'poster',
      );
      expect(_art(sparse, null, publishedItemId: 'tt1')!.art, 'poster');
    },
  );

  test(
    'selected artwork policy clears intentional absence despite old art',
    () {
      for (final category in [
        MetadataCategory.backgrounds,
        MetadataCategory.posters,
      ]) {
        final enriched = HeroMetadataPresentation(
          _item(background: null, poster: null),
          MetadataPreferences(providers: {category: 'tmdb'}, fallback: false),
        );
        final update = _art(
          _item(background: null),
          enriched,
          publishedItemId: 'tt1',
          publishedArt: 'old',
        )!;
        expect(update.itemId, 'tt1');
        expect(update.art, isNull);
      }
    },
  );

  test(
    'canonical identity accepts selected artwork with permitted poster fallback',
    () {
      final original = _item(id: 'tmdb:1', imdbId: 'tt1');
      final enriched = HeroMetadataPresentation(
        _item(background: null, poster: 'provider-poster'),
        MetadataPreferences(
          providers: {
            MetadataCategory.backgrounds: 'tmdb',
            MetadataCategory.posters: 'tmdb',
          },
          fallback: true,
        ),
      );
      final update = _art(original, enriched)!;
      expect(update.itemId, 'tmdb:1');
      expect(update.art, 'provider-poster');
    },
  );

  test(
    'unrelated enrichment and information-only policy keep legacy precedence',
    () {
      for (final enriched in [
        HeroMetadataPresentation(
          _item(id: 'other', background: 'other-art'),
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: 'tmdb'},
          ),
        ),
        HeroMetadataPresentation(
          _item(background: 'translated-art'),
          MetadataPreferences(
            providers: {MetadataCategory.information: 'tmdb'},
          ),
        ),
      ]) {
        expect(_art(_item(), enriched)!.art, 'background');
      }
    },
  );

  test('empty and absent items distinguish clear from retain', () {
    final clear = _art(
      null,
      null,
      publishedItemId: 'old',
      publishedArt: 'old',
    )!;
    expect(clear.itemId, isNull);
    expect(clear.art, isNull);
    expect(_art(_item(background: '', poster: ''), null)!.art, isNull);
    // Legacy enrichment can still supply a backdrop when the catalog is null.
    expect(_art(null, _item(background: 'enriched'))!.art, 'enriched');
  });
}
