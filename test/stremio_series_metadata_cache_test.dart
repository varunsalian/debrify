import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only real IMDb episode IDs are canonical', () {
    expect(
      StremioService.isCanonicalEpisodeId('tt123', 'tt123:1:2', 1, 2),
      isTrue,
    );
    expect(
      StremioService.isCanonicalEpisodeId('custom', 'custom:1:2', 1, 2),
      isFalse,
    );
    expect(
      StremioService.isCanonicalEpisodeId('tt123', 'edit_2', 1, 2),
      isFalse,
    );
    expect(
      StremioService.isCanonicalEpisodeId('tt123', 'tt123:1:3', 1, 2),
      isFalse,
    );
  });

  test('missing origin never falls back to a same-ID configuration', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'meta': {
            'videos': [
              {'id': 'custom:1:1', 'season': 1, 'episode': 1},
              {'id': 'custom:1:2', 'season': 1, 'episode': 2},
            ],
          },
        }),
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final addon = StremioAddon(
      id: 'same.manifest',
      name: 'Remaining configuration',
      baseUrl: base,
      manifestUrl: '$base/manifest.json',
      resources: const ['meta', 'stream'],
      types: const ['series'],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
    });
    final service = StremioService.instance;
    service.invalidateCache();
    addTearDown(() async {
      await server.close(force: true);
      service.invalidateCache();
    });
    expect(
      await service.resolveSeriesEpisodeVideoId(
        addonKey: 'removed-key',
        addonId: addon.id,
        catalogId: 'custom',
        season: 1,
        episode: 1,
      ),
      isNull,
    );
    expect(
      await service.resolveAdjacentSeriesEpisode(
        addonKey: 'removed-key',
        addonId: addon.id,
        catalogId: 'custom',
        season: 1,
        episode: 1,
        direction: 1,
      ),
      isNull,
    );
    expect(
      await service.customSeriesEpisodeInventory(
        addonKey: 'removed-key',
        addonId: addon.id,
        catalogId: 'custom',
      ),
      isEmpty,
    );
    expect(requests, 0);
    final exact = await service.episodeVideoIdForLaunch(
      addon: addon,
      catalogId: 'custom',
      imdbId: 'custom',
      season: 1,
      episode: 1,
    );
    expect(exact, 'custom:1:1');
    expect(
      StremioService.isCanonicalEpisodeId('custom', exact!, 1, 1),
      isFalse,
    );
    final fetcher = TorrentPlaybackService.seriesFetcherFor(
      meta: PlaybackMeta(
        imdbId: 'custom',
        contentType: 'series',
        season: 1,
        episode: 1,
        stremioAddonId: addon.id,
        stremioAddonKey: addon.sourceBindingKey,
        stremioCatalogId: 'custom',
        stremioVideoId: exact,
      ),
    );
    expect(await fetcher!.resolveAdjacentEpisode!(1, 1, 1), (
      season: 1,
      episode: 2,
    ));
  });
  test(
    'unmapped custom launch resolves exact IDs and navigation skips duplicates',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'meta': {
              'videos': [
                {'id': 'first', 'season': 1, 'episode': 1},
                {'id': 'first-alt', 'season': 1, 'episode': 1},
                {'id': 'second', 'season': 1, 'episode': 2},
                {'id': 'second-alt', 'season': 1, 'episode': 2},
                {'id': 'third', 'season': 2, 'episode': 1},
                {'id': 'third-alt', 'season': 2, 'episode': 1},
              ],
            },
          }),
        );
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final addon = StremioAddon(
        id: 'unmapped.custom',
        name: 'Custom',
        baseUrl: base,
        manifestUrl: '$base/manifest.json',
        resources: const ['meta', 'stream'],
        types: const ['series'],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      final service = StremioService.instance;
      service.invalidateCache();
      addTearDown(() async {
        await server.close(force: true);
        service.invalidateCache();
      });
      expect(
        StremioService.isCanonicalCatalogAlias('custom-show', 'custom-show'),
        isFalse,
      );
      expect(
        await service.episodeVideoIdForLaunch(
          addon: addon,
          catalogId: 'custom-show',
          imdbId: 'custom-show',
          season: 1,
          episode: 1,
        ),
        'first',
      );
      expect(requests, 1);
      Future<({int season, int episode, String videoId})?> adjacent(
        int s,
        int e,
        int d,
      ) => service.resolveAdjacentSeriesEpisode(
        addonKey: addon.sourceBindingKey,
        addonId: addon.id,
        catalogId: 'custom-show',
        season: s,
        episode: e,
        direction: d,
      );
      final next = await adjacent(1, 1, 1);
      expect((next?.season, next?.episode), (1, 2));
      final after = await adjacent(next!.season, next.episode, 1);
      expect((after?.season, after?.episode), (2, 1));
      final previous = await adjacent(2, 1, -1);
      expect((previous?.season, previous?.episode), (1, 2));
      final before = await adjacent(1, 2, -1);
      expect((before?.season, before?.episode), (1, 1));
      expect(await adjacent(1, 1, -1), isNull);
      expect(await adjacent(2, 1, 1), isNull);
      expect(await adjacent(9, 9, 1), isNull);
    },
  );
  test('ordinary catalog launches do not request optional metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = 503;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final addon = StremioAddon(
      id: 'ordinary',
      name: 'Ordinary',
      baseUrl: 'http://127.0.0.1:${server.port}',
      manifestUrl: 'http://127.0.0.1:${server.port}/manifest.json',
      resources: const ['meta', 'stream'],
      types: const ['series'],
    );
    for (final id in ['tt123', 'tmdb:123', 'trakt:123']) {
      expect(
        await StremioService().episodeVideoIdForLaunch(
          addon: addon,
          catalogId: id,
          imdbId: 'tt123',
          season: 1,
          episode: 1,
        ),
        isNull,
      );
    }
    expect(requests, 0);
    expect(StremioService.isCanonicalCatalogAlias('onepace', 'tt123'), isFalse);
  });
  test('custom startup recovery never searches canonical packs', () async {
    SharedPreferences.setMockInitialValues({});
    final fetcher = TorrentPlaybackService.seriesFetcherFor(
      provider: 'debrid',
      meta: const PlaybackMeta(
        imdbId: 'tt0388629',
        contentType: 'series',
        season: 1,
        episode: 1,
        stremioAddonKey: 'custom-key',
        stremioCatalogId: 'onepace',
        stremioVideoId: 'RO_1',
      ),
    )!;
    expect(
      await fetcher.fetch(
        SeriesSourceFetcher.modePacks,
        automaticRecovery: true,
      ),
      isEmpty,
    );
  });
  test(
    'missing custom episode metadata never queries canonical streams',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final streamPaths = <String>[];
      server.listen((request) async {
        if (request.uri.path.contains('/stream/')) {
          streamPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'streams': [
                {
                  'url': 'https://cdn.test/wrong-original-episode',
                  'name': '1080p',
                },
              ],
            }),
          );
        } else {
          request.response.statusCode = 503;
        }
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}/missing';
      final addon = StremioAddon(
        id: 'missing.catalog',
        name: 'Missing catalog',
        baseUrl: base,
        manifestUrl: '$base/manifest.json',
        resources: const ['meta', 'stream'],
        types: const ['series'],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      StremioService.instance.invalidateCache();
      try {
        final fetcher = TorrentPlaybackService.seriesFetcherFor(
          meta: PlaybackMeta(
            imdbId: 'tt0388629',
            contentType: 'series',
            season: 1,
            episode: 1,
            stremioAddonKey: addon.sourceBindingKey,
            stremioCatalogId: 'missing-edit',
            stremioVideoId: 'RO_1',
          ),
        )!;
        expect(
          await fetcher.fetch(
            SeriesSourceFetcher.modeEpisodes,
            season: 1,
            episode: 2,
          ),
          isNull,
        );
        expect(fetcher.episodesFetched, isFalse);
        expect(await fetcher.loadCustomEpisodeInventory!(), isEmpty);
        expect(streamPaths, isEmpty);
      } finally {
        await server.close(force: true);
        StremioService.instance.invalidateCache();
      }
    },
  );
  test(
    'episode cache separates configurations with the same addon ID',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var reads = 0;
      server.listen((request) async {
        reads++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'meta': {
              'videos': [
                {
                  'season': 1,
                  'episode': 1,
                  'title': request.uri.pathSegments.first,
                  'id': '${request.uri.pathSegments.first}-custom-video',
                },
              ],
            },
          }),
        );
        await request.response.close();
      });
      StremioAddon addon(String config) {
        final base = 'http://127.0.0.1:${server.port}/$config';
        return StremioAddon(
          id: 'same.manifest.id',
          name: 'Configured addon',
          baseUrl: base,
          manifestUrl: '$base/manifest.json',
          resources: const ['meta'],
          types: const ['series'],
        );
      }

      try {
        final first = await StremioService.instance.fetchSeriesMeta(
          addon('first'),
          'tt1234567',
        );
        final second = await StremioService.instance.fetchSeriesMeta(
          addon('second'),
          'tt1234567',
        );
        final cached = await StremioService.instance.fetchSeriesMeta(
          addon('first'),
          'tt1234567',
        );
        expect(first!.single['title'], 'first');
        expect(second!.single['title'], 'second');
        expect(cached!.single['title'], 'first');
        expect(
          await StremioService.instance.episodeVideoIdForLaunch(
            addon: addon('first'),
            catalogId: 'tt1234567',
            imdbId: 'tt1234567',
            season: 1,
            episode: 1,
          ),
          'first-custom-video',
        );
        expect(reads, 2);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('custom catalog video ids resolve by episode and adjacency', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final streamPaths = <String>[];
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.contains('/stream/series/')) {
        streamPaths.add(Uri.decodeComponent(request.uri.path));
        request.response.write(
          jsonEncode({
            'streams': [
              {
                'url': 'https://cdn.test/ro2',
                'name': '1080p',
                'behaviorHints': {'bingeGroup': 'group'},
              },
            ],
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'meta': {
              'videos': [
                {'id': 'RO_1', 'season': 1, 'episode': 1},
                {'id': 'RO_2', 'season': 1, 'episode': 2},
                {'id': 'OP_1', 'season': 2, 'episode': 1},
              ],
            },
          }),
        );
      }
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/onepace';
    final addon = StremioAddon(
      id: 'onepace.test',
      name: 'One Pace',
      baseUrl: base,
      manifestUrl: '$base/manifest.json',
      resources: const ['meta', 'stream'],
      types: const ['series'],
    );
    final streamOnlyAddon = StremioAddon(
      id: 'onepace.stream.test',
      name: 'One Pace streams',
      baseUrl: 'http://127.0.0.1:${server.port}/fallback',
      manifestUrl: 'http://127.0.0.1:${server.port}/fallback/manifest.json',
      resources: const ['stream'],
      types: const ['series'],
    );
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([
        addon.toJson(),
        streamOnlyAddon.toJson(),
      ]),
    });
    StremioService.instance.invalidateCache();

    try {
      for (final imdbId in <String?>['tt0388629', null]) {
        final fetcher = TorrentPlaybackService.seriesFetcherFor(
          meta: PlaybackMeta(
            imdbId: imdbId,
            contentType: 'series',
            season: 1,
            episode: 1,
            stremioAddonKey: addon.sourceBindingKey,
            stremioCatalogId: 'onepace',
            stremioVideoId: 'RO_1',
          ),
        )!;
        expect(await fetcher.loadCustomEpisodeInventory!(), [
          {'season': 1, 'number': 1},
          {'season': 1, 'number': 2},
          {'season': 2, 'number': 1},
        ]);
      }
      expect(
        await StremioService.instance.resolveSeriesEpisodeVideoId(
          addonKey: addon.sourceBindingKey,
          addonId: addon.id,
          catalogId: 'onepace',
          season: 1,
          episode: 2,
        ),
        'RO_2',
      );
      final next = await StremioService.instance.resolveAdjacentSeriesEpisode(
        addonKey: addon.sourceBindingKey,
        addonId: addon.id,
        catalogId: 'onepace',
        season: 1,
        episode: 2,
        direction: 1,
      );
      expect(next, (season: 2, episode: 1, videoId: 'OP_1'));
      Future<Torrent?> resolvePinned({bool prepare = false}) =>
          StremioService.instance.resolvePinnedDirectStream(
            addonId: addon.id,
            addonKey: addon.sourceBindingKey,
            originCatalogId: 'onepace',
            streamKey: '1080p',
            bingeGroup: 'group',
            streamIndex: 0,
            type: 'series',
            contentId: 'tt0388629',
            season: 1,
            episode: 2,
            prepare: prepare,
          );
      await resolvePinned(prepare: true);
      final pinned = await resolvePinned();
      expect(pinned?.directUrl, 'https://cdn.test/ro2');
      final crossAddonPin = await StremioService.instance
          .resolvePinnedDirectStream(
            addonId: streamOnlyAddon.id,
            addonKey: streamOnlyAddon.sourceBindingKey,
            originCatalogId: 'onepace',
            originVideoId: 'RO_2',
            streamKey: '1080p',
            bingeGroup: 'group',
            streamIndex: 0,
            type: 'series',
            contentId: 'tt0388629',
            season: 1,
            episode: 2,
          );
      expect(crossAddonPin?.directUrl, 'https://cdn.test/ro2');
      expect(streamPaths, [
        '/onepace/stream/series/RO_2.json',
        '/fallback/stream/series/RO_2.json',
      ]);
    } finally {
      StremioService.instance.invalidateCache();
      await server.close(force: true);
    }
  });
}
