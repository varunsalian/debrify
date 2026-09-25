import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/adjacent_episode_resolver.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const cached = <Map<String, dynamic>>[
    {'season': 1, 'number': 1},
    {'season': 1, 'number': 2},
    {'season': 2, 'number': 1},
  ];

  Future<({int season, int episode})?> resolve(
    List<Map<String, dynamic>>? providerRows, {
    int direction = 1,
    List<Map<String, dynamic>> guide = cached,
  }) {
    final metadata = NativeSeriesMetadataService(
      tmdb: TmdbMetadataRepository(token: ''),
      fallbackSeasons: (_) async => providerRows == null
          ? throw StateError('offline')
          : [
              {'episodes': providerRows},
            ],
    );
    return resolveAdjacentWithGuideFallback(
      resolver: (s, e, d) => NextEpisodeService.findAdjacentEpisode(
        'tt0118360',
        s,
        e,
        direction: d,
        metadata: metadata,
        preferBuiltIn: true,
        reportGuideUnavailable: true,
      ),
      season: 1,
      episode: 2,
      direction: direction,
      cachedGuide: () => cachedGuideAdjacentEpisode(guide, 1, 2, direction),
    );
  }

  test(
    'failed lookup retains cached next and previous across a pack boundary',
    () async {
      expect(await resolve(null), (season: 2, episode: 1));
      expect(await resolve(null, direction: -1), (season: 1, episode: 1));
      expect(await resolve(null, guide: []), isNull);
    },
  );

  test(
    'missing current episode permits the loaded guide to resolve navigation',
    () async {
      expect(
        await resolve([
          {'season': 9, 'number': 1},
        ]),
        (season: 2, episode: 1),
      );
    },
  );

  test(
    'successful origin ordering takes precedence over cached guide',
    () async {
      expect(
        await resolve([
          {'season': 1, 'number': 2},
          {'season': 3, 'number': 1},
        ]),
        (season: 3, episode: 1),
      );
    },
  );

  test('confirmed end and future episode do not use cached fallback', () async {
    expect(
      await resolve([
        {'season': 1, 'number': 2},
      ]),
      isNull,
    );
    expect(
      await resolve([
        {'season': 1, 'number': 2},
        {'season': 2, 'number': 1, 'first_aired': '2999-01-01'},
      ]),
      isNull,
    );
  });

  test(
    'cached fallback also stops at an upcoming episode without skipping',
    () async {
      expect(
        await resolve(
          null,
          guide: [
            {'season': 1, 'number': 2},
            {'season': 2, 'number': 1, 'airdate': '2999-01-01'},
            {'season': 2, 'number': 2},
          ],
        ),
        isNull,
      );
    },
  );

  test(
    'unavailable custom metadata never permits a canonical guide fallback',
    () async {
      expect(
        await NextEpisodeService.findAdjacentEpisode(
          const CustomSeriesIdentity('missing-addon', 'private-show').id,
          1,
          2,
          direction: -1,
          reportGuideUnavailable: true,
        ),
        isNull,
      );
    },
  );

  test('custom resolver null remains authoritative', () async {
    expect(
      await resolveAdjacentWithGuideFallback(
        resolver: (_, _, _) async => null,
        season: 1,
        episode: 2,
        direction: -1,
        cachedGuide: () => throw StateError('Must not use unrelated guide'),
      ),
      isNull,
    );
  });
}
