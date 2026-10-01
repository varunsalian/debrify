import 'package:debrify/features/home/application/home_playback_providers.dart';
import 'package:debrify/features/home/data/home_random_episode_selector.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final addon = StremioAddon(
  id: 'origin',
  name: 'Origin',
  baseUrl: 'https://fixture.invalid/config',
  manifestUrl: 'https://fixture.invalid/config/manifest.json',
  addedAt: DateTime.utc(2026),
);
const title = StremioMeta(
  id: 'tt123',
  type: 'series',
  name: 'Show',
  year: '2020',
  poster: 'poster',
);
HomeRandomEpisodeSelector selector(int Function(int) choose) =>
    HomeRandomEpisodeSelector(
      videoIdFor: StremioService.randomEpisodeVideoId,
      isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
      chooseIndex: choose,
    );

void main() {
  test(
    'filters malformed, special, nonpositive and future episodes before choosing',
    () {
      final videos = <Map<String, dynamic>>[
        {}, {'season': '1', 'number': 1}, {'season': 0, 'number': 1},
        {'season': 1, 'number': 0}, {'season': 1, 'number': '1', 'episode': 2},
        {'season': 1, 'number': 2, 'airdate': '2026-10-01'},
        {'season': 1, 'number': 1, 'released': '2026-09-01'},
        {'season': 2.9, 'episode': 3.8},
        {
          'season': 1,
          'number': 1,
        }, // Duplicates retain their original weighting.
        {'season': 3, 'number': 4, 'released': 'unknown'},
      ];
      final picks = <(int?, int?)>[];
      for (var i = 0; i < 4; i++) {
        final result =
            selector((length) {
              expect(length, 4);
              return i;
            }).select(
              item: title,
              metadataAddon: addon,
              contentId: title.id,
              progressId: title.id,
              videos: videos,
              continuous: false,
              now: DateTime.utc(2026, 9, 28),
            )!;
        picks.add((result.season, result.episode));
        expect(result.stremioVideoId, isNull);
      }
      expect(picks, [(1, 1), (2, 3), (1, 1), (3, 4)]);
      expect(
        videos[7]['season'],
        2.9,
      ); // Normalization never mutates raw metadata.
    },
  );

  test('empty or unplayable inventories do not call randomness', () {
    final policy = selector((_) => throw StateError('must not choose'));
    for (final videos in <List<Map<String, dynamic>>?>[
      null,
      [],
      [
        {'season': 0, 'number': 1},
      ],
      [
        {'season': 1, 'number': 1},
      ],
    ]) {
      expect(
        policy.select(
          item: title,
          metadataAddon: addon,
          contentId: 'custom',
          progressId: 'tt123',
          videos: videos,
          continuous: true,
        ),
        isNull,
      );
    }
  });

  test(
    'custom episode selection preserves configuration, parent and exact video ID',
    () {
      final result = selector((_) => 0).select(
        item: title,
        metadataAddon: addon,
        contentId: 'custom-cut',
        progressId: 'tt123',
        videos: [
          {'season': 2, 'number': 3, 'id': '  cut:episode:v2  '},
        ],
        continuous: true,
      )!;
      expect(result.stremioAddonId, addon.id);
      expect(result.stremioAddonKey, addon.sourceBindingKey);
      expect(result.stremioCatalogId, 'custom-cut');
      expect(result.stremioVideoId, 'cut:episode:v2');
      expect(result.initialContinuousShuffle, isTrue);
      expect(result.title, title.name);
      expect(result.year, title.year);
      expect(result.posterUrl, title.poster);
      expect(result.contentType, title.type);
      expect(result.isSeries, isTrue);
    },
  );

  test('canonical aliases synthesize IDs without adding an addon override', () {
    for (final catalog in ['tt123', 'tmdb:123', 'trakt:123']) {
      final result = selector((_) => 0).select(
        item: title,
        metadataAddon: addon,
        contentId: catalog,
        progressId: 'tt123',
        videos: [
          {'season': 2, 'number': 4},
        ],
        continuous: false,
      )!;
      expect((result.season, result.episode), (2, 4));
      expect(result.imdbId, 'tt123');
      expect(result.stremioAddonId, isNull);
      expect(result.stremioVideoId, isNull);
      expect(result.initialContinuousShuffle, isFalse);
    }
  });

  test(
    'unknown progress falls back to catalog identity and keeps exact addon identity',
    () {
      const item = StremioMeta(
        id: 'custom-title',
        type: 'series',
        name: 'Custom',
      );
      final result = selector((_) => 0).select(
        item: item,
        metadataAddon: addon,
        contentId: item.id,
        progressId: null,
        videos: [
          {'season': 1, 'number': 1, 'id': 42},
        ],
        continuous: false,
      )!;
      final identity = CustomSeriesIdentity.parse(result.imdbId)!;
      expect(identity.catalogId, item.id);
      expect(identity.addonKey, addon.sourceBindingKey);
      expect(result.stremioVideoId, '42');
      expect(result.stremioCatalogId, item.id);
    },
  );

  test(
    'no metadata addon leaves the selection unscoped even for a custom video',
    () {
      final result = selector((_) => 0).select(
        item: title,
        metadataAddon: null,
        contentId: title.id,
        progressId: title.id,
        videos: [
          {'season': 1, 'number': 1, 'id': 'custom-video'},
        ],
        continuous: false,
      )!;
      expect(result.stremioAddonId, isNull);
      expect(result.stremioVideoId, isNull);
    },
  );

  test(
    'production DI uses existing identity rules with continuous intent intact',
    () {
      final container = ProviderContainer.test();
      final result = container
          .read(homeRandomEpisodeSelectorProvider)
          .select(
            item: title,
            metadataAddon: addon,
            contentId: 'custom',
            progressId: title.id,
            videos: [
              {'season': 3, 'number': 2, 'id': 'custom:3:2'},
            ],
            continuous: true,
          )!;
      expect(result.stremioVideoId, 'custom:3:2');
      expect(result.initialContinuousShuffle, isTrue);
      expect((result.season, result.episode), (3, 2));
    },
  );
}
