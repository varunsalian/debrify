import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const original = StremioMeta(
    id: 'tmdb:550',
    imdbId: 'tt0137523',
    type: 'movie',
    name: 'Existing title',
    poster: 'https://addon/poster',
    description: 'Existing plot',
    imdbRating: 8.8,
    addedAtMs: 123,
    year: '1999',
  );

  test(
    'default presentation is the original object and makes no requests',
    () async {
      final service = MetadataProviderService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => throw StateError('must not fetch'),
        ),
      );
      final result = await service.present(
        original,
        preferences: MetadataPreferences(),
      );
      expect(identical(result.item, original), isTrue);
    },
  );

  test(
    'poster selection preserves description, identity, rating and user state',
    () async {
      final service = MetadataProviderService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient(
            (_) async => http.Response(
              '{"id":550,"title":"Different title","overview":"Different plot",'
              '"poster_path":"/poster.jpg","vote_average":1}',
              200,
            ),
          ),
        ),
      );
      final result = await service.present(
        original,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.posters: MetadataPreferences.tmdb},
        ),
      );
      expect(result.item.poster, 'https://image.tmdb.org/t/p/w500/poster.jpg');
      expect(result.item.name, original.name);
      expect(result.item.description, original.description);
      expect(result.item.id, original.id);
      expect(result.item.imdbId, original.imdbId);
      expect(result.item.imdbRating, original.imdbRating);
      expect(result.item.addedAtMs, original.addedAtMs);
      expect(result.item.year, original.year);
    },
  );

  test(
    'unavailable selected provider does not silently use another source',
    () async {
      final service = MetadataProviderService(
        tmdb: TmdbMetadataRepository(token: ''),
      );
      final result = await service.present(
        original,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.posters: MetadataPreferences.tmdb},
        ),
      );
      expect(result.item.poster, isNull);
      expect(result.unavailable, {MetadataCategory.posters});
    },
  );
  test(
    'recommendation presentation publishes bounded batches and cancels queued titles',
    () async {
      var reads = 0;
      var relevant = true;
      final service = MetadataProviderService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            reads++;
            return http.Response(
              '{"title":"Selected title","overview":"Selected plot"}',
              200,
            );
          }),
        ),
      );
      final items = List.generate(
        9,
        (i) => StremioMeta(
          id: 'tmdb:${i + 1}',
          type: 'movie',
          name: 'Original $i',
          imdbRating: 8,
          addedAtMs: i,
        ),
      );
      final batches = <List<StremioMeta>>[];
      await for (final batch in service.presentBatches(
        items,
        isRelevant: () => relevant,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.information: 'tmdb'},
        ),
      )) {
        batches.add(batch);
        relevant = false;
      }
      expect(reads, 4);
      expect(batches, hasLength(1));
      expect(batches.single.map((i) => i.id), items.map((i) => i.id));
      expect(
        batches.single.take(4).every((i) => i.name == 'Selected title'),
        isTrue,
      );
      expect(batches.single[4], same(items[4]));
      expect(batches.single.first.imdbRating, 8);
      expect(batches.single[3].addedAtMs, 3);
    },
  );

  test('default recommendation presentation does no extra work', () async {
    var reads = 0;
    final service = MetadataProviderService(
      tmdb: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((_) async {
          reads++;
          return http.Response('{}', 200);
        }),
      ),
    );
    expect(
      await service
          .presentBatches(
            [original],
            isRelevant: () => true,
            preferences: MetadataPreferences(),
          )
          .toList(),
      isEmpty,
    );
    expect(reads, 0);
  });
  test('TMDB television runtime uses a valid episode runtime', () {
    final meta = MetadataProviderService.fromTmdb(
      const StremioMeta(id: 'tmdb:1', type: 'series', name: 'Show'),
      {
        'name': 'Show',
        'episode_run_time': [null, 'bad', 0, 47],
      },
      MetadataPreferences(),
    );
    expect(meta.runtime, '47 min');
  });

  test(
    'leaving a card prevents secondary language and original-artwork requests',
    () async {
      var relevant = true;
      var reads = 0;
      final service = MetadataProviderService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            reads++;
            relevant = false;
            return http.Response(
              '{"title":"Title","original_language":"fr","overview":""}',
              200,
            );
          }),
        ),
      );
      await service.present(
        const StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Title'),
        isRelevant: () => relevant,
        preferences: MetadataPreferences(
          language: 'hi-IN',
          artworkLanguage: 'original',
          fallback: true,
          providers: {
            MetadataCategory.information: 'tmdb',
            MetadataCategory.posters: 'tmdb',
          },
        ),
      );
      expect(reads, 1);
    },
  );
}
