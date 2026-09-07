// Origin pin for TorrentPlaybackService's playback-provider resolution and the
// two "Load more sources" fetcher factories (lane T4). Written against the
// ORIGIN statics in lib/services/torrent_playback_service.dart before
// seriesFetcherFor / movieFetcherFor / _effectiveFetchProvider and the
// _configuredProviders / _defaultConfiguredProvider / _isConfigured trio move
// to lib/services/torrent_playback/. It must keep passing, unedited, after the
// move.
//
// Seam. The resolution helpers are private, so everything here is observed
// through the two PUBLIC factories. Two observables carry the whole pin:
//
//   * movieFetcherFor(...).fetch(modeMovie) returns null WITHOUT issuing a
//     single addon request when no provider resolves, and a list when one
//     does — a crisp "was a provider resolved?" probe over _isConfigured /
//     _configuredProviders / _defaultConfiguredProvider.
//   * seriesFetcherFor(...).fetch(modeEpisodes) takes the provider-free branch
//     (addon search, direct-URL rows ONLY) when no provider resolves and the
//     PlaybackSourceSearch.searchCuratedSources branch (direct AND torrent
//     rows) when one does — which is how _effectiveFetchProvider's override
//     rules become visible.
//
// Known limit, recorded deliberately: which of several configured providers
// wins is NOT observable through this seam (nothing downstream of the fetchers
// varies by provider id unless a torrent-search engine is configured, and the
// pack path can never see addon rows because addon streams carry no
// coverageType). Every SINGLE-provider combination below therefore pins the
// exact provider that _configuredProviders must find; the multi-provider
// precedence order is pinned only as "a provider is still resolved".
//
// Quirks pinned here (keep, do not "fix"):
//  * Playback configuration is key-only for RD/TB/PM/AD — the per-provider
//    integration toggle does NOT gate playback — and toggle-only for PikPak:
//    a saved pikpak_email with the toggle off is NOT configured, and the
//    toggle on with no email IS.
//  * An empty-string API key is not configured.
//  * A saved default provider that is no longer configured is ignored and the
//    first configured provider is used instead; with nothing configured the
//    resolution is null even though a default is saved.
//  * _effectiveFetchProvider passes ANY non-placeholder provider straight
//    through without checking that it is configured; only null, 'local',
//    'stremio_direct' and 'stream' fall back to the resolved default.
//  * The provider-free episode fetch keeps direct-URL rows only; the
//    provider-backed one keeps the addon's torrent rows too, in the addon
//    layer's historic torrent-before-direct order.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';

const _seriesMeta = PlaybackMeta(
  imdbId: 'tt1234567',
  contentType: 'series',
  season: 1,
  episode: 1,
  title: 'Show',
);

const _movieMeta = PlaybackMeta(
  imdbId: 'tt7654321',
  contentType: 'movie',
  title: 'Film',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://addon.test/configured';
  final addon = StremioAddon(
    id: 'test.both',
    name: 'Both Test',
    manifestUrl: '$baseUrl/manifest.json',
    baseUrl: baseUrl,
    types: const ['series', 'movie'],
    resources: const ['stream'],
  );

  late List<Uri> requested;

  /// One direct-URL stream and one infoHash (torrent) stream. The provider-free
  /// episode branch keeps only the direct one; the provider-backed curated
  /// search keeps both.
  final streamsJson = jsonEncode({
    'streams': [
      {
        'name': 'Direct 1080p',
        'description': 'Show.S01E02.1080p.WEB-DL',
        'url': 'https://cdn.test/show-s01e02.mkv',
      },
      {
        'name': 'Torrent 1080p',
        'description': 'Show.S01E02.1080p.WEB-DL',
        'infoHash': 'a' * 40,
      },
    ],
  });

  setUp(() {
    requested = <Uri>[];
    StremioService.instance.debugStreamHttpClientFactory = () =>
        MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            streamsJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        });
  });

  tearDown(() {
    StremioService.instance.debugStreamHttpClientFactory = null;
    StremioService.instance.invalidateCache();
  });

  /// Seeds the configured addon plus [credentials] (plaintext credential keys
  /// are accepted; the vault re-seals them on first read).
  void seed(Map<String, Object> credentials) {
    requested = <Uri>[];
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
      ...credentials,
    });
    StremioService.instance.invalidateCache();
  }

  /// True when the launch resolved a debrid provider: the movie fetcher's
  /// search returns null and never touches the network without one.
  Future<bool> resolvesProvider(Map<String, Object> credentials) async {
    seed(credentials);
    final fetcher = TorrentPlaybackService.movieFetcherFor(meta: _movieMeta);
    final fetched = await fetcher!.fetch(SeriesSourceFetcher.modeMovie);
    if (fetched == null) {
      expect(
        requested,
        isEmpty,
        reason: 'an unresolved provider must not issue a search',
      );
      return false;
    }
    expect(requested, isNotEmpty);
    return true;
  }

  Future<List<Torrent>?> episodeFetch({
    String? provider,
    Map<String, Object> credentials = const {},
  }) async {
    seed(credentials);
    final fetcher = TorrentPlaybackService.seriesFetcherFor(
      meta: _seriesMeta,
      provider: provider,
    );
    return fetcher!.fetch(
      SeriesSourceFetcher.modeEpisodes,
      season: 1,
      episode: 2,
    );
  }

  // ── _isConfigured / _configuredProviders: the credential matrix ──────────
  group('provider resolution — configured-provider combinations', () {
    test('nothing configured resolves no provider', () async {
      expect(await resolvesProvider(const {}), isFalse);
    });

    test('each API-key provider alone resolves', () async {
      for (final key in const [
        'real_debrid_api_key',
        'torbox_api_key',
        'premiumize_api_key',
        'alldebrid_api_key',
      ]) {
        expect(
          await resolvesProvider({key: 'seeded-key'}),
          isTrue,
          reason: '$key alone must resolve a provider',
        );
      }
    });

    test('an empty API key is not configured', () async {
      expect(await resolvesProvider(const {'real_debrid_api_key': ''}), isFalse);
    });

    test('playback ignores the per-provider integration toggle', () async {
      expect(
        await resolvesProvider(const {
          'torbox_api_key': 'seeded-key',
          'torbox_integration_enabled': false,
        }),
        isTrue,
      );
    });

    test('PikPak is toggle-configured, not email-configured', () async {
      expect(
        await resolvesProvider(const {'pikpak_email': 'user@pikpak.test'}),
        isFalse,
      );
      expect(await resolvesProvider(const {'pikpak_enabled': true}), isTrue);
    });

    test('a saved default that is no longer configured is ignored', () async {
      expect(
        await resolvesProvider(const {
          'torbox_api_key': 'seeded-key',
          'default_torrent_provider_v1': 'premiumize',
        }),
        isTrue,
      );
    });

    test('a saved default cannot resolve with nothing configured', () async {
      expect(
        await resolvesProvider(const {
          'default_torrent_provider_v1': 'debrid',
        }),
        isFalse,
      );
    });

    test("the 'none' default falls through to the configured list", () async {
      expect(
        await resolvesProvider(const {
          'alldebrid_api_key': 'seeded-key',
          'default_torrent_provider_v1': 'none',
        }),
        isTrue,
      );
      expect(
        await resolvesProvider(const {'default_torrent_provider_v1': 'none'}),
        isFalse,
      );
    });

    test('every configured provider still resolves one', () async {
      expect(
        await resolvesProvider(const {
          'real_debrid_api_key': 'seeded-key',
          'torbox_api_key': 'seeded-key',
          'premiumize_api_key': 'seeded-key',
          'alldebrid_api_key': 'seeded-key',
          'pikpak_enabled': true,
        }),
        isTrue,
      );
    });
  });

  // ── _effectiveFetchProvider: which launches fall back to the default ─────
  group('effective fetch provider — override rules', () {
    List<StreamType> types(List<Torrent>? fetched) =>
        [for (final t in fetched ?? const <Torrent>[]) t.streamType];

    test('a real launch provider is used as-is, even unconfigured', () async {
      // Passthrough does NOT check that the provider is configured.
      final fetched = await episodeFetch(provider: 'torbox');
      expect(types(fetched), [StreamType.torrent, StreamType.directUrl]);
    });

    test('a bound local source falls back to the resolved default', () async {
      final withProvider = await episodeFetch(
        provider: SeriesSource.localService,
        credentials: const {'real_debrid_api_key': 'seeded-key'},
      );
      expect(types(withProvider), [StreamType.torrent, StreamType.directUrl]);

      final without = await episodeFetch(provider: SeriesSource.localService);
      expect(types(without), [StreamType.directUrl]);
    });

    test('an addon-direct source falls back to the default', () async {
      final withProvider = await episodeFetch(
        provider: SeriesSource.addonDirectService,
        credentials: const {'premiumize_api_key': 'seeded-key'},
      );
      expect(types(withProvider), [StreamType.torrent, StreamType.directUrl]);

      final without = await episodeFetch(
        provider: SeriesSource.addonDirectService,
      );
      expect(types(without), [StreamType.directUrl]);
    });

    test("the 'stream' pseudo-provider falls back to the default", () async {
      final withProvider = await episodeFetch(
        provider: 'stream',
        credentials: const {'alldebrid_api_key': 'seeded-key'},
      );
      expect(types(withProvider), [StreamType.torrent, StreamType.directUrl]);

      final without = await episodeFetch(provider: 'stream');
      expect(types(without), [StreamType.directUrl]);
    });

    test('no launch provider resolves the default', () async {
      final withProvider = await episodeFetch(
        credentials: const {'torbox_api_key': 'seeded-key'},
      );
      expect(types(withProvider), [StreamType.torrent, StreamType.directUrl]);

      final without = await episodeFetch();
      expect(types(without), [StreamType.directUrl]);
    });

    test('the pack fetch fails soft without a provider', () async {
      seed(const {});
      final fetcher = TorrentPlaybackService.seriesFetcherFor(
        meta: _seriesMeta,
      );
      expect(
        await fetcher!.fetch(SeriesSourceFetcher.modePacks, season: 1),
        isNull,
      );
      expect(fetcher.packsFetched, isFalse);
      expect(requested, isEmpty);
    });
  });

  // ── the searches the returned fetchers actually issue ────────────────────
  group('fetchers issue the expected search', () {
    test('the provider-free episode fetch is episode-scoped', () async {
      final fetched = await episodeFetch();
      expect(requested, hasLength(1));
      expect(
        Uri.decodeComponent(requested.single.path),
        contains('/stream/series/tt1234567:1:2'),
      );
      expect(fetched, hasLength(1));
      expect(fetched!.single.directUrl, 'https://cdn.test/show-s01e02.mkv');
      expect(fetched.single.source, startsWith('stremio:'));
    });

    test('the provider-backed movie fetch is title-scoped', () async {
      seed(const {'real_debrid_api_key': 'seeded-key'});
      final fetcher = TorrentPlaybackService.movieFetcherFor(meta: _movieMeta);
      final fetched = await fetcher!.fetch(SeriesSourceFetcher.modeMovie);
      expect(requested, hasLength(1));
      expect(
        Uri.decodeComponent(requested.single.path),
        contains('/stream/movie/tt7654321'),
      );
      expect(fetched, hasLength(2));
      expect(
        [for (final t in fetched!) t.streamType],
        containsAll(const [StreamType.torrent, StreamType.directUrl]),
      );
      expect(fetcher.movieFetched, isTrue);
    });

    test('a failed fetch leaves "Load more" retryable', () async {
      seed(const {});
      final fetcher = TorrentPlaybackService.movieFetcherFor(meta: _movieMeta);
      expect(await fetcher!.fetch(SeriesSourceFetcher.modeMovie), isNull);
      expect(fetcher.movieFetched, isFalse);
    });
  });

  // ── the factories' shape gates ───────────────────────────────────────────
  group('factory shape gates', () {
    test('seriesFetcherFor rejects non-series-shaped launches', () {
      expect(TorrentPlaybackService.seriesFetcherFor(meta: null), isNull);
      expect(
        TorrentPlaybackService.seriesFetcherFor(meta: _movieMeta),
        isNull,
        reason: 'movies use movieFetcherFor',
      );
      expect(
        TorrentPlaybackService.seriesFetcherFor(
          meta: const PlaybackMeta(
            imdbId: 'kitsu:123',
            contentType: 'series',
            season: 1,
            episode: 1,
          ),
        ),
        isNull,
        reason: 'non-tt ids are not searchable',
      );
      expect(
        TorrentPlaybackService.seriesFetcherFor(
          meta: const PlaybackMeta(
            imdbId: 'tt1234567',
            contentType: 'series',
            season: 1,
          ),
        ),
        isNull,
        reason: 'a concrete season AND episode are required',
      );
    });

    test('movieFetcherFor rejects non-movie-shaped launches', () {
      expect(TorrentPlaybackService.movieFetcherFor(meta: null), isNull);
      expect(TorrentPlaybackService.movieFetcherFor(meta: _seriesMeta), isNull);
      expect(
        TorrentPlaybackService.movieFetcherFor(
          meta: const PlaybackMeta(imdbId: 'kitsu:9', contentType: 'movie'),
        ),
        isNull,
      );
    });

    test('the fetched flags carry the launch state through', () {
      final fresh = TorrentPlaybackService.seriesFetcherFor(meta: _seriesMeta)!;
      expect(fresh.packsFetched, isFalse);
      expect(fresh.episodesFetched, isFalse);
      final carried = TorrentPlaybackService.seriesFetcherFor(
        meta: _seriesMeta,
        packsFetched: true,
        episodesFetched: true,
      )!;
      expect(carried.packsFetched, isTrue);
      expect(carried.episodesFetched, isTrue);
      expect(carried.season, 1);
      expect(carried.episode, 1);
    });

    test('each flavor answers only its own modes', () async {
      seed(const {});
      final movie = TorrentPlaybackService.movieFetcherFor(meta: _movieMeta)!;
      expect(await movie.fetch(SeriesSourceFetcher.modePacks, season: 1), isNull);
      expect(
        await movie.fetch(SeriesSourceFetcher.modeEpisodes, season: 1, episode: 1),
        isNull,
      );
      final series = TorrentPlaybackService.seriesFetcherFor(meta: _seriesMeta)!;
      expect(await series.fetch(SeriesSourceFetcher.modeMovie), isNull);
      expect(requested, isEmpty);
    });
  });
}
