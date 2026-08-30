import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/utils/filter_ladder.dart';

Torrent _torrent(
  String name, {
  StreamType type = StreamType.torrent,
  int size = 0,
  int seeders = 0,
  String source = 'test',
  String? infohash,
  String? directUrl,
  String? stremioAddonId,
}) => Torrent(
  rowid: 0,
  infohash: infohash ?? name.hashCode.abs().toRadixString(16).padLeft(40, '0'),
  name: name,
  sizeBytes: size,
  createdUnix: 0,
  seeders: seeders,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
  streamType: type,
  directUrl: type == StreamType.directUrl
      ? (directUrl ?? 'https://example.test/$name')
      : null,
  stremioAddonId: stremioAddonId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adjacent episode direct-link validation', () {
    test(
      'provider-free adjacent fetch queries addons for direct links',
      () async {
        late Uri requested;
        final service = StremioService.instance;
        service.debugStreamHttpClientFactory = () =>
            MockClient((request) async {
              requested = request.url;
              return http.Response(
                jsonEncode({
                  'streams': [
                    {
                      'name': 'Direct 1080p',
                      'description': 'Show.S01E02.1080p.WEB-DL',
                      'url': 'https://cdn.test/show-s01e02.mkv',
                    },
                    {
                      'name': 'Torrent twin',
                      'description': 'Show.S01E02.1080p.WEB-DL',
                      'infoHash': 'a' * 40,
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            });
        addTearDown(() {
          service.debugStreamHttpClientFactory = null;
          service.invalidateCache();
        });

        const baseUrl = 'https://addon.test/configured';
        final addon = StremioAddon(
          id: 'test.direct',
          name: 'Direct Test',
          manifestUrl: '$baseUrl/manifest.json',
          baseUrl: baseUrl,
          types: const ['series'],
          resources: const ['stream'],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode([addon.toJson()]),
        });
        service.invalidateCache();
        await StorageService.setQuickPlayRules(
          QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
            preset: QuickPlayPreset.custom,
            sourceMode: QuickPlaySourceMode.addonsThenTorrents,
            preferSeriesPacks: false,
          ),
          isMovie: false,
        );

        final fetcher = TorrentPlaybackService.seriesFetcherFor(
          meta: const PlaybackMeta(
            imdbId: 'tt1234567',
            contentType: 'series',
            season: 1,
            episode: 1,
            title: 'Show',
          ),
          episodesFetched: true,
        );
        final fetched = await fetcher!.fetch(
          SeriesSourceFetcher.modeEpisodes,
          season: 1,
          episode: 2,
        );

        expect(Uri.decodeComponent(requested.path), contains('tt1234567:1:2'));
        expect(fetched, hasLength(1));
        expect(fetched!.single.streamType, StreamType.directUrl);
        expect(fetched.single.directUrl, 'https://cdn.test/show-s01e02.mkv');
      },
    );

    test(
      'provider-free addon failure keeps adjacent fetch retryable',
      () async {
        final service = StremioService.instance;
        service.debugStreamHttpClientFactory = () =>
            MockClient((_) async => http.Response('unavailable', 503));
        addTearDown(() {
          service.debugStreamHttpClientFactory = null;
          service.invalidateCache();
        });

        const baseUrl = 'https://addon.test/configured';
        final addon = StremioAddon(
          id: 'test.failing',
          name: 'Failing Test',
          manifestUrl: '$baseUrl/manifest.json',
          baseUrl: baseUrl,
          types: const ['series'],
          resources: const ['stream'],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode([addon.toJson()]),
        });
        service.invalidateCache();
        await StorageService.setQuickPlayRules(
          QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
            preset: QuickPlayPreset.custom,
            sourceMode: QuickPlaySourceMode.addonsThenTorrents,
            preferSeriesPacks: false,
          ),
          isMovie: false,
        );

        final fetcher = TorrentPlaybackService.seriesFetcherFor(
          meta: const PlaybackMeta(
            imdbId: 'tt1234567',
            contentType: 'series',
            season: 1,
            episode: 1,
            title: 'Show',
          ),
        );
        final fetched = await fetcher!.fetch(
          SeriesSourceFetcher.modeEpisodes,
          season: 1,
          episode: 2,
        );

        expect(fetched, isNull);
        expect(fetcher.episodesFetched, isFalse);
      },
    );

    test('series fetcher rejects a positively dead direct stream', () async {
      SharedPreferences.setMockInitialValues({});
      final realFactory = StreamUrlValidator.clientFactory;
      addTearDown(() => StreamUrlValidator.clientFactory = realFactory);
      StreamUrlValidator.clientFactory = () =>
          MockClient((_) async => http.Response('gone', 404));
      final fetcher = TorrentPlaybackService.seriesFetcherFor(
        meta: const PlaybackMeta(
          imdbId: 'tt1234567',
          contentType: 'series',
          season: 1,
          episode: 1,
          title: 'Show',
        ),
      );

      expect(fetcher, isNotNull);
      expect(
        await fetcher!.allowsCandidate(
          _torrent('dead', type: StreamType.directUrl),
        ),
        isFalse,
      );
    });

    test(
      'series fetcher leaves torrent candidates to normal resolution',
      () async {
        SharedPreferences.setMockInitialValues({});
        final realFactory = StreamUrlValidator.clientFactory;
        addTearDown(() => StreamUrlValidator.clientFactory = realFactory);
        StreamUrlValidator.clientFactory = () => MockClient(
          (_) async => throw StateError('torrent candidate must not make HTTP'),
        );
        final fetcher = TorrentPlaybackService.seriesFetcherFor(
          meta: const PlaybackMeta(
            imdbId: 'tt1234567',
            contentType: 'series',
            season: 1,
            episode: 1,
            title: 'Show',
          ),
        );

        expect(await fetcher!.allowsCandidate(_torrent('pack')), isTrue);
      },
    );
  });

  group('Debrify default compatibility contract', () {
    test('movie defaults preserve the pre-profile behavior', () {
      final rules = QuickPlayRules.debrifyDefault(isMovie: true);
      expect(rules.preset, QuickPlayPreset.debrifyDefault);
      expect(rules.sourceMode, QuickPlaySourceMode.torrentsThenAddons);
      expect(rules.ranking, QuickPlayRanking.exactOrder);
      expect(rules.useFilters, isTrue);
      expect(rules.relaxFilters, isTrue);
      expect(rules.tryNextOnFailure, isTrue);
      expect(rules.maxAttempts, 5);
      expect(rules.allowDirectLinks, isTrue);
      expect(rules.validateDirectLinks, isTrue);
      expect(rules.preferSeriesPacks, isFalse);
      expect(
        rules.searchTimeoutSeconds,
        0,
        reason: 'legacy active path waited for engine completion',
      );
      expect(rules.addonTimeoutSeconds, 15);
    });

    test('series adds the existing pack-first and six-hour behavior', () {
      final rules = QuickPlayRules.debrifyDefault(isMovie: false);
      expect(rules.preferSeriesPacks, isTrue);
      expect(rules.packPreference, QuickPlayPackPreference.widestFirst);
      expect(rules.preserveLegacyCombinedPackSearch, isTrue);
      expect(rules.failedPackCacheHours, 6);
    });

    test(
      'default ordering is stable when no saved filter ladder is active',
      () {
        final input = [
          _torrent('first 720p', seeders: 1),
          _torrent('second 2160p', seeders: 100),
          _torrent('third direct', type: StreamType.directUrl),
        ];
        final ordered = TorrentPlaybackService.orderCandidatesForRules(
          input,
          rules: QuickPlayRules.debrifyDefault(isMovie: true),
        );
        expect(ordered, orderedEquals(input));
      },
    );
  });

  group('profile persistence and legacy migration', () {
    test(
      'untouched installs resolve to Debrify default for both types',
      () async {
        SharedPreferences.setMockInitialValues({});
        expect(
          await StorageService.getQuickPlayRules(isMovie: true),
          QuickPlayRules.debrifyDefault(isMovie: true),
        );
        expect(
          await StorageService.getQuickPlayRules(isMovie: false),
          QuickPlayRules.debrifyDefault(isMovie: false),
        );
      },
    );

    test(
      'legacy overrides migrate as Custom without changing values',
      () async {
        SharedPreferences.setMockInitialValues({
          'quick_play_honors_filters_v1': false,
          'quick_play_try_multiple_torrents': false,
          'quick_play_max_retries': 3,
          'auto_bind_series_packs_on_play': false,
        });
        final movie = await StorageService.getQuickPlayRules(isMovie: true);
        final series = await StorageService.getQuickPlayRules(isMovie: false);
        expect(movie.preset, QuickPlayPreset.custom);
        expect(movie.useFilters, isFalse);
        expect(movie.tryNextOnFailure, isFalse);
        expect(movie.maxAttempts, 3);
        expect(series.preset, QuickPlayPreset.custom);
        expect(series.preferSeriesPacks, isFalse);
      },
    );

    test('restore writes the exact compatibility profiles', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setQuickPlayRules(
        QuickPlayRules.forPreset(QuickPlayPreset.fastest, isMovie: true),
        isMovie: true,
      );
      await StorageService.restoreQuickPlayDefaults();
      expect(
        await StorageService.getQuickPlayRules(isMovie: true),
        QuickPlayRules.debrifyDefault(isMovie: true),
      );
      expect(
        await StorageService.getQuickPlayRules(isMovie: false),
        QuickPlayRules.debrifyDefault(isMovie: false),
      );
    });

    test('turning off season packs leaves series auto-pin alone', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getSeriesAutoPinOnPlay(), isTrue);
      // These two shared one preference key, so this toggle silently disabled
      // ALL series pinning — Smart mode then never found a pin and Quick Play
      // lost its fast path. They must stay independent.
      await StorageService.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(
          isMovie: false,
        ).copyWith(preset: QuickPlayPreset.custom, preferSeriesPacks: false),
        isMovie: false,
      );
      expect(await StorageService.getSeriesAutoPinOnPlay(), isTrue);
      // …and the reverse: auto-pin off must not rewrite the packs rule.
      await StorageService.setSeriesAutoPinOnPlay(false);
      expect(await StorageService.getSeriesAutoPinOnPlay(), isFalse);
      final rules = await StorageService.getQuickPlayRules(isMovie: false);
      expect(rules.preferSeriesPacks, isFalse);
    });

    test('play button mode defaults to quick and rejects junk', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getPlayButtonMode(), 'quick');
      // A value from a newer build (or a corrupted profile) must not leave the
      // Play button in a mode this build cannot honor.
      SharedPreferences.setMockInitialValues({'play_button_mode': 'nonsense'});
      expect(await StorageService.getPlayButtonMode(), 'quick');
    });

    test('play button mode round-trips and restore clears it', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setPlayButtonMode('always');
      expect(await StorageService.getPlayButtonMode(), 'always');
      await StorageService.setPlayButtonMode('smart');
      expect(await StorageService.getPlayButtonMode(), 'smart');
      // "Restore defaults" claims it restored default Quick Play behavior, so
      // the Play button must actually go back to quick-playing.
      await StorageService.restoreQuickPlayDefaults();
      expect(await StorageService.getPlayButtonMode(), 'quick');
    });

    test('saving movies cannot leak retry settings into series', () async {
      SharedPreferences.setMockInitialValues({});
      final movies = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        tryNextOnFailure: true,
        maxAttempts: 10,
      );
      await StorageService.setQuickPlayRules(movies, isMovie: true);

      expect(
        await StorageService.getQuickPlayRules(isMovie: false),
        QuickPlayRules.debrifyDefault(isMovie: false),
      );
    });

    test('saving series cannot leak retry settings into movies', () async {
      SharedPreferences.setMockInitialValues({});
      final series = QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
        preset: QuickPlayPreset.custom,
        tryNextOnFailure: false,
        maxAttempts: 1,
      );
      await StorageService.setQuickPlayRules(series, isMovie: false);

      expect(
        await StorageService.getQuickPlayRules(isMovie: true),
        QuickPlayRules.debrifyDefault(isMovie: true),
      );
    });

    test('legacy global filter writes do not rewrite v2 profiles', () async {
      SharedPreferences.setMockInitialValues({});
      final movies = QuickPlayRules.forPreset(
        QuickPlayPreset.bestQuality,
        isMovie: true,
      );
      final series = QuickPlayRules.forPreset(
        QuickPlayPreset.fastest,
        isMovie: false,
      );
      await StorageService.setQuickPlayRules(movies, isMovie: true);
      await StorageService.setQuickPlayRules(series, isMovie: false);

      await StorageService.setQuickPlayHonorsFilters(true);

      expect(await StorageService.getQuickPlayRules(isMovie: true), movies);
      expect(await StorageService.getQuickPlayRules(isMovie: false), series);
    });

    test('JSON round-trip preserves every option', () {
      final rules =
          QuickPlayRules.forPreset(
            QuickPlayPreset.bestQuality,
            isMovie: false,
          ).copyWith(
            preset: QuickPlayPreset.custom,
            packPreference: QuickPlayPackPreference.seasonFirst,
            searchTimeoutSeconds: 20,
            addonTimeoutSeconds: 45,
            failedPackCacheHours: 24,
          );
      expect(QuickPlayRules.fromJson(rules.toJson(), isMovie: false), rules);
    });

    test('older v2 named presets infer their intended pack search', () {
      final json = QuickPlayRules.forPreset(
        QuickPlayPreset.bestQuality,
        isMovie: false,
      ).toJson()..remove('preserveLegacyCombinedPackSearch');
      expect(
        QuickPlayRules.fromJson(
          json,
          isMovie: false,
        ).preserveLegacyCombinedPackSearch,
        isFalse,
      );
    });

    test('old implicit ranking migrates to provider-returned order', () {
      final json = QuickPlayRules.debrifyDefault(isMovie: true).toJson()
        ..['ranking'] = QuickPlayRanking.debrify.name;

      expect(
        QuickPlayRules.fromJson(json, isMovie: true).ranking,
        QuickPlayRanking.exactOrder,
      );
    });
  });

  group('provider-returned ranking', () {
    test(
      'Stremio conversion preserves an interleaved addon response exactly',
      () {
        final streams = [
          StremioStream(
            url: 'https://example.test/first',
            title: 'direct first',
            source: 'AIOStreams',
          ),
          StremioStream(
            infoHash: 'a' * 40,
            title: 'torrent second 👤 900',
            source: 'AIOStreams',
          ),
          StremioStream(
            url: 'https://example.test/third',
            title: 'direct third',
            source: 'AIOStreams',
          ),
        ];
        final converted = StremioService.instance.convertStreamsForTesting(
          streams,
          preserveOrder: true,
        );
        expect(converted.map((t) => t.displayTitle), [
          'direct first',
          'torrent second 👤 900',
          'direct third',
        ]);
      },
    );

    test('Comet URL and binge-group hash become separate source rows', () {
      final hash = 'c' * 40;
      final stream = StremioStream.fromJson({
        'name': '[TB] Comet 1080p',
        'description': 'Movie.1080p.WEB-DL 👤 42',
        'url': 'https://comet.example/stream',
        'behaviorHints': {
          'bingeGroup': 'comet|torbox|$hash',
          'filename': 'Movie.1080p.WEB-DL.mkv',
          'videoSize': 1234,
        },
      }, 'Comet | TB');

      final converted = StremioService.instance.convertStreamsForTesting([
        stream,
      ], preserveOrder: true);

      expect(converted, hasLength(2));
      final direct = converted[0];
      expect(direct.streamType, StreamType.directUrl);
      expect(direct.directUrl, 'https://comet.example/stream');
      expect(direct.infohash, startsWith('url:'));
      expect(direct.hasRealInfoHash, isFalse);

      final torrent = converted[1];
      expect(torrent.streamType, StreamType.torrent);
      expect(torrent.directUrl, isNull);
      expect(torrent.infohash, hash);
      expect(torrent.hasRealInfoHash, isTrue);

      final normalSearch = StremioService.instance.convertStreamsForTesting([
        stream,
      ]);
      expect(normalSearch, hasLength(2));
      expect(normalSearch.map((row) => row.infohash).toSet(), hasLength(2));
    });

    test('exact addon conversion preserves repeated returned entries', () {
      final streams = [
        StremioStream(
          infoHash: 'b' * 40,
          title: 'first label 👤 1',
          source: 'AIOStreams',
        ),
        StremioStream(
          infoHash: 'b' * 40,
          title: 'second label 👤 999',
          source: 'AIOStreams',
        ),
      ];
      final converted = StremioService.instance.convertStreamsForTesting(
        streams,
        preserveOrder: true,
      );
      expect(converted.map((t) => t.displayTitle), [
        'first label 👤 1',
        'second label 👤 999',
      ]);
      final defaultConversion = StremioService.instance
          .convertStreamsForTesting(streams);
      expect(defaultConversion, hasLength(1));
      expect(defaultConversion.single.displayTitle, 'second label 👤 999');
    });

    test('exact order does not promote direct links or high seeders', () {
      final input = [
        _torrent('torrent first', seeders: 1),
        _torrent('direct second', type: StreamType.directUrl),
        _torrent('torrent third', seeders: 999),
      ];
      final rules = QuickPlayRules.forPreset(
        QuickPlayPreset.addonOrder,
        isMovie: true,
      );
      expect(
        TorrentPlaybackService.orderCandidatesForRules(input, rules: rules),
        orderedEquals(input),
      );
    });

    test('prefer torrents follows provider priority, not source family', () {
      final aioDirect = _torrent(
        'aio direct',
        type: StreamType.directUrl,
        source: 'stremio:AIOStreams',
      );
      final aioTorrent = _torrent('aio torrent', source: 'stremio:AIOStreams');
      final engineTorrent = _torrent('engine torrent', source: 'comet');
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(sourcePriority: const ['stremio:aiostreams', 'engine:comet']);

      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          engineTorrent,
          aioDirect,
          aioTorrent,
        ], rules: rules),
        [aioTorrent, engineTorrent, aioDirect],
      );
    });

    test('prefer torrents advances when a provider has only direct links', () {
      final aioDirect = _torrent(
        'aio direct',
        type: StreamType.directUrl,
        source: 'stremio:AIOStreams',
      );
      final engineTorrent = _torrent('engine torrent', source: 'comet');
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(sourcePriority: const ['stremio:aiostreams', 'engine:comet']);

      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          engineTorrent,
          aioDirect,
        ], rules: rules),
        [engineTorrent, aioDirect],
      );
    });

    test('prefer torrents off keeps each prioritized provider response', () {
      final aioDirect = _torrent(
        'aio direct',
        type: StreamType.directUrl,
        source: 'stremio:AIOStreams',
      );
      final aioTorrent = _torrent('aio torrent', source: 'stremio:AIOStreams');
      final engineTorrent = _torrent('engine torrent', source: 'comet');
      final rules = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        sourceMode: QuickPlaySourceMode.addonsThenTorrents,
        sourcePriority: const ['stremio:aiostreams', 'engine:comet'],
      );

      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          engineTorrent,
          aioDirect,
          aioTorrent,
        ], rules: rules),
        [aioDirect, aioTorrent, engineTorrent],
      );
    });

    test('earlier provider owns a shared torrent hash', () {
      final hash = 'f' * 40;
      final engine = _torrent('engine copy', source: 'comet', infohash: hash);
      final aio = _torrent(
        'aio copy',
        source: 'stremio:AIOStreams',
        infohash: hash,
      );
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(sourcePriority: const ['stremio:aiostreams', 'engine:comet']);

      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          engine,
          aio,
        ], rules: rules),
        [aio],
      );
    });

    test('strict filters choose a matching duplicate representation', () {
      final hash = 'e' * 40;
      final aio1080 = _torrent(
        'Movie 1080p WEB-DL',
        source: 'stremio:AIOStreams',
        infohash: hash,
      );
      final comet4k = _torrent(
        'Movie 2160p WEB-DL',
        source: 'comet',
        infohash: hash,
      );
      final ladder = FilterLadder(
        TorrentFilterState(qualities: {QualityTier.ultraHd}),
      );
      final rules = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        sourcePriority: const ['stremio:aiostreams', 'engine:comet'],
        relaxFilters: false,
      );

      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          [comet4k, aio1080],
          rules: rules,
          ladder: ladder,
        ),
        [comet4k],
      );
    });

    test('exact order honors an active relaxed filter ladder', () {
      final first = _torrent('Movie 720p WEB-DL', seeders: 1);
      final second = _torrent('Movie 1080p WEB-DL', seeders: 900);
      final ladder = FilterLadder(
        TorrentFilterState(qualities: {QualityTier.fullHd}),
      );
      final rules =
          QuickPlayRules.forPreset(
            QuickPlayPreset.addonOrder,
            isMovie: true,
          ).copyWith(
            preset: QuickPlayPreset.custom,
            useFilters: true,
            relaxFilters: true,
          );

      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          [first, second],
          rules: rules,
          ladder: ladder,
        ),
        [second, first],
      );
    });

    test('relaxed filters reorder only within Addon Priority groups', () {
      final aio1080 = _torrent(
        'Movie 1080p WEB-DL',
        source: 'stremio:AIOStreams',
      );
      final aio4k = _torrent(
        'Movie 2160p WEB-DL',
        source: 'stremio:AIOStreams',
      );
      final comet4k = _torrent('Movie 2160p WEB-DL Comet', source: 'comet');
      final ladder = FilterLadder(
        TorrentFilterState(qualities: {QualityTier.ultraHd}),
      );
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(sourcePriority: const ['stremio:aiostreams', 'engine:comet']);

      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          [comet4k, aio1080, aio4k],
          rules: rules,
          ladder: ladder,
        ),
        [aio4k, aio1080, comet4k],
      );
    });

    test('quality and smallest are deterministic and opt-in', () {
      final small = _torrent('Movie 720p', size: 2, seeders: 50);
      final large = _torrent('Movie 2160p', size: 20, seeders: 1);
      final input = [small, large];
      final quality = QuickPlayRules.forPreset(
        QuickPlayPreset.bestQuality,
        isMovie: true,
      );
      expect(
        TorrentPlaybackService.orderCandidatesForRules(input, rules: quality),
        [large, small],
      );
      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          input,
          rules: quality.copyWith(
            preset: QuickPlayPreset.custom,
            ranking: QuickPlayRanking.smallest,
          ),
        ),
        [small, large],
      );
    });

    test('ready-first keeps cache hits ahead of stronger uncached torrents', () {
      final cached = _torrent('cached 1080p', seeders: 2);
      final uncached = _torrent('uncached 1080p', seeders: 900);
      final rules = QuickPlayRules.forPreset(
        QuickPlayPreset.fastest,
        isMovie: true,
      );

      // `_cacheFirst` has already stably partitioned this list. The post-cache
      // rule pass must not sort it back into seeder order.
      expect(
        TorrentPlaybackService.orderCacheCheckedCandidatesForRules([
          cached,
          uncached,
        ], rules: rules),
        [cached, uncached],
      );
    });

    test('exact order keeps cached packs ahead of provider priority', () {
      final cachedLowerProvider = _torrent('cached pack', source: 'comet');
      final uncachedHigherProvider = _torrent(
        'uncached pack',
        source: 'stremio:AIOStreams',
      );
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: false,
      ).copyWith(sourcePriority: const ['stremio:aiostreams', 'engine:comet']);

      // `_cacheFirst` has already produced this cached/miss partition. The
      // post-cache pass must not restore provider priority over cachedness.
      expect(
        TorrentPlaybackService.orderCacheCheckedCandidatesForRules([
          cachedLowerProvider,
          uncachedHigherProvider,
        ], rules: rules),
        [cachedLowerProvider, uncachedHigherProvider],
      );
    });

    test('cache preparation reorders torrents without moving direct rows', () {
      final uncached = _torrent('uncached torrent');
      final direct = _torrent('direct', type: StreamType.directUrl);
      final cached = _torrent('cached torrent');

      expect(
        TorrentPlaybackService.mergePreparedTorrentOrder(
          [uncached, direct, cached],
          [cached, uncached],
        ),
        [cached, direct, uncached],
      );
    });

    test('ready-first keeps cache hits within each relaxed filter tier', () {
      final cached720 = _torrent('cached 720p', seeders: 2);
      final uncached720 = _torrent('uncached 720p', seeders: 900);
      final cached1080 = _torrent('cached 1080p', seeders: 1);
      final ladder = FilterLadder(
        TorrentFilterState(qualities: {QualityTier.fullHd}),
      );
      final rules = QuickPlayRules.forPreset(
        QuickPlayPreset.fastest,
        isMovie: true,
      ).copyWith(useFilters: true, relaxFilters: true);

      expect(
        TorrentPlaybackService.orderCacheCheckedCandidatesForRules(
          [cached720, uncached720, cached1080],
          rules: rules,
          ladder: ladder,
        ),
        [cached1080, cached720, uncached720],
      );
    });

    test('disabling direct links removes them before selection', () {
      final torrent = _torrent('torrent');
      final direct = _torrent('direct', type: StreamType.directUrl);
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(preset: QuickPlayPreset.custom, allowDirectLinks: false);
      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          direct,
          torrent,
        ], rules: rules),
        [torrent],
      );
    });

    test('torrent retry count does not change direct validation budget', () {
      final oneAttempt = QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        tryNextOnFailure: false,
        maxAttempts: 1,
      );
      final tenAttempts = oneAttempt.copyWith(
        tryNextOnFailure: true,
        maxAttempts: 10,
      );
      expect(
        TorrentPlaybackService.directValidationBudgetForRules(oneAttempt),
        5,
      );
      expect(
        TorrentPlaybackService.directValidationBudgetForRules(tenAttempts),
        5,
      );
    });

    test('AIOStreams direct links bypass the destructive HEAD preflight', () {
      expect(
        TorrentPlaybackService.shouldPreflightDirectStream(
          _torrent(
            'AIOStreams result',
            type: StreamType.directUrl,
            source: 'stremio:AIOStreams | ElfHosted',
          ),
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldPreflightDirectStream(
          _torrent(
            'renamed addon',
            type: StreamType.directUrl,
            stremioAddonId: 'com.aiostreams.viren070.user',
          ),
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldPreflightDirectStream(
          _torrent(
            'provider proxy',
            type: StreamType.directUrl,
            directUrl: 'https://aiostreams.elfhosted.com/api/v1/debrid/link',
          ),
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldPreflightDirectStream(
          _torrent('ordinary CDN', type: StreamType.directUrl),
        ),
        isTrue,
      );
    });

    test('AIOStreams playable error slates are rejected by duration', () {
      expect(
        StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
          addonId: 'com.aiostreams.renamed.user',
          url: 'https://opaque-provider.example/video',
          duration: const Duration(minutes: 2),
        ),
        isTrue,
      );
      expect(
        StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
          sourceName: 'AIOStreams | ElfHosted',
          duration: const Duration(minutes: 45),
        ),
        isFalse,
      );
      expect(
        StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
          sourceName: 'ordinary provider',
          duration: const Duration(minutes: 2),
        ),
        isFalse,
      );
    });

    test('only multi-file series packs must prove the episode', () {
      expect(
        StartupStreamPolicy.requiresExactEpisodeMatch(
          isSeries: true,
          playlistLength: 12,
        ),
        isTrue,
      );
      // A single-episode torrent has nothing else to play — trust the
      // episode-scoped search even when its filename parses to no SxxEyy.
      expect(
        StartupStreamPolicy.requiresExactEpisodeMatch(
          isSeries: true,
          playlistLength: 1,
        ),
        isFalse,
      );
      expect(
        StartupStreamPolicy.requiresExactEpisodeMatch(
          isSeries: false,
          playlistLength: 12,
        ),
        isFalse,
      );
    });

    test('series fallback requires the requested episode', () {
      expect(
        StartupStreamPolicy.resolvedPlaylistIndex(
          requiresEpisodeMatch: true,
          matchedEpisodeIndex: -1,
        ),
        isNull,
      );
      expect(
        StartupStreamPolicy.resolvedPlaylistIndex(
          requiresEpisodeMatch: true,
          matchedEpisodeIndex: 7,
        ),
        7,
      );
      expect(
        StartupStreamPolicy.resolvedPlaylistIndex(requiresEpisodeMatch: false),
        0,
      );
    });

    test('failed initial resolution advances to the next ranked source', () {
      expect(
        StartupStreamPolicy.rankedFailoverStart(
          selectedSourceIndex: 2,
          initialAttemptAlreadyFailed: true,
        ),
        (sourceIndex: 3, attempts: 1),
      );
      expect(
        StartupStreamPolicy.rankedFailoverStart(
          selectedSourceIndex: 2,
          initialAttemptAlreadyFailed: false,
        ),
        (sourceIndex: 2, attempts: 0),
      );
    });

    test('failed initial PikPak resolution consumes its acquisition', () {
      expect(
        StartupStreamPolicy.initialPikPakAcquisitionAttempted(
          isPikPakResolver: true,
          initialSourceIsTorrent: true,
          hasResolvedInitialUrl: false,
          initialAttemptAlreadyFailed: true,
        ),
        isTrue,
      );
      expect(
        StartupStreamPolicy.initialPikPakAcquisitionAttempted(
          isPikPakResolver: true,
          initialSourceIsTorrent: true,
          hasResolvedInitialUrl: false,
          initialAttemptAlreadyFailed: false,
        ),
        isFalse,
      );
      expect(
        StartupStreamPolicy.initialPikPakAcquisitionAttempted(
          isPikPakResolver: true,
          initialSourceIsTorrent: false,
          hasResolvedInitialUrl: false,
          initialAttemptAlreadyFailed: true,
        ),
        isFalse,
      );
    });

    test('source preference selects the dual-source transport order', () {
      final torrentFirst = QuickPlayRules.debrifyDefault(isMovie: true);
      final addonFirst = torrentFirst.copyWith(
        sourceMode: QuickPlaySourceMode.addonsThenTorrents,
      );

      expect(
        TorrentPlaybackService.shouldTryDirectBeforeTorrent(torrentFirst),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldTryDirectBeforeTorrent(addonFirst),
        isTrue,
      );
      expect(TorrentPlaybackService.shouldTryDirectBeforeTorrent(null), isTrue);
    });

    test('external links do not count as addon-first autoplay results', () {
      final external = _torrent('open browser', type: StreamType.externalUrl);
      final direct = _torrent('play direct', type: StreamType.directUrl);
      final torrent = _torrent('play torrent');
      expect(TorrentPlaybackService.isAutoPlayableCandidate(external), isFalse);
      expect(TorrentPlaybackService.isAutoPlayableCandidate(direct), isTrue);
      expect(TorrentPlaybackService.isAutoPlayableCandidate(torrent), isTrue);
    });

    test('only addon-only mode defers the provider prompt', () {
      final movieDefault = QuickPlayRules.debrifyDefault(isMovie: true);
      final seriesDefault = QuickPlayRules.debrifyDefault(isMovie: false);
      final mixed = movieDefault.copyWith(
        sourceMode: QuickPlaySourceMode.addonsThenTorrents,
      );
      final addonOnly = movieDefault.copyWith(
        sourceMode: QuickPlaySourceMode.addonsOnly,
      );

      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          movieDefault,
          isMovie: true,
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          seriesDefault,
          isMovie: false,
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          mixed,
          isMovie: true,
        ),
        isFalse,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonOnly,
          isMovie: true,
        ),
        isTrue,
      );
      expect(
        TorrentPlaybackService.shouldSearchAddonsBeforeProvider(
          addonOnly,
          isMovie: true,
          hasPreferredProvider: true,
        ),
        isFalse,
      );
    });

    test('torrents-only disables addon fast paths', () {
      final torrentsOnly = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(sourceMode: QuickPlaySourceMode.torrentsOnly);
      final defaultRules = QuickPlayRules.debrifyDefault(isMovie: true);

      expect(TorrentPlaybackService.allowsAddonSearch(torrentsOnly), isFalse);
      expect(TorrentPlaybackService.allowsAddonSearch(defaultRules), isTrue);
    });

    test('direct-stream paths combine mixed providers', () {
      final defaultSeries = QuickPlayRules.debrifyDefault(isMovie: false);
      final explicit = defaultSeries.copyWith(
        preset: QuickPlayPreset.custom,
        preserveLegacyCombinedPackSearch: false,
      );

      expect(TorrentPlaybackService.addonStreamSearchPlan(defaultSeries), [
        QuickPlaySourceMode.together,
      ]);
      expect(
        TorrentPlaybackService.addonStreamSearchPlan(
          explicit.copyWith(sourceMode: QuickPlaySourceMode.addonsThenTorrents),
        ),
        [QuickPlaySourceMode.together],
      );
      expect(
        TorrentPlaybackService.addonStreamSearchPlan(
          explicit.copyWith(sourceMode: QuickPlaySourceMode.torrentsOnly),
        ),
        [QuickPlaySourceMode.torrentsOnly],
      );
      expect(
        TorrentPlaybackService.addonStreamSearchPlan(
          explicit.copyWith(sourceMode: QuickPlaySourceMode.torrentsOnly),
          noProvider: true,
        ),
        [QuickPlaySourceMode.addonsOnly],
      );
    });
  });

  group('series smart fallback ordering', () {
    test('exact order keeps repeated hashes across both batches', () {
      final repeated = _torrent('same release');
      final later = _torrent('later release');

      final exact = StremioService.instance.mergeSmartFallbackTorrents(
        [repeated],
        [repeated, later],
        preserveOrder: true,
      );
      expect(exact, [repeated, repeated, later]);

      final normal = StremioService.instance.mergeSmartFallbackTorrents(
        [repeated],
        [repeated, later],
      );
      expect(normal, [repeated, later]);
    });
  });

  group('series pack source priority', () {
    test('in-band engine timeouts make an empty pack search inconclusive', () {
      expect(
        TorrentPlaybackService.packSearchReportedErrors({
          'engineErrors': {'engine': 'Timeout after 10s'},
        }, QuickPlaySourceMode.torrentsOnly),
        isTrue,
      );
      expect(
        TorrentPlaybackService.packSearchReportedErrors({
          'engineErrors': <String, String>{},
        }, QuickPlaySourceMode.torrentsOnly),
        isFalse,
      );
      expect(
        TorrentPlaybackService.packSearchReportedErrors({
          'addonErrors': {'stremio:aio': 'Timeout'},
        }, QuickPlaySourceMode.addonsOnly),
        isTrue,
      );
    });

    test('default keeps the shipped combined pack search', () {
      final rules = QuickPlayRules.debrifyDefault(isMovie: false);
      expect(TorrentPlaybackService.seriesPackSearchPlan(rules), [
        QuickPlaySourceMode.together,
      ]);
    });

    test('explicit source priority keeps pack searches combined', () {
      final base = QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
        preset: QuickPlayPreset.custom,
        preserveLegacyCombinedPackSearch: false,
      );
      expect(
        TorrentPlaybackService.seriesPackSearchPlan(
          base.copyWith(sourceMode: QuickPlaySourceMode.torrentsThenAddons),
        ),
        [QuickPlaySourceMode.together],
      );
      expect(
        TorrentPlaybackService.seriesPackSearchPlan(
          base.copyWith(sourceMode: QuickPlaySourceMode.addonsThenTorrents),
        ),
        [QuickPlaySourceMode.together],
      );
    });
  });
}
