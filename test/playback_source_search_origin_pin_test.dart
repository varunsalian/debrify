// Origin pin for the source-search / engine cluster of
// lib/services/torrent_playback_service.dart (lane T3, PR #238).
//
// Written AFTER a first extraction attempt was already made, and placed BEFORE
// the move by history rewrite so the two-commit rule (pin, then move) reads
// correctly. Recording that here because the reviewer asked for it.
//
// The six functions this file must EXECUTE on the origin:
//
//   searchSeriesPackSources   (origin 1959-2089)  public static
//   searchCuratedSources      (origin 2107-2208)  public static
//   _sourceEngineListing      (origin 2473-2486)  private
//   _fetchOneEngine           (origin 2488-2512)  private
//   _curateCandidates         (origin 2514-2557)  private
//   _curatePackCandidates     (origin 2559-2635)  private
//
// Seams used — all pre-existing, no production change was needed:
//
//  * Real engines. An engine YAML is imported through LocalEngineStorage the
//    same way a user imports one, and EngineRegistry reloads it, so
//    TorrentService.getImdbSearchEngines / isEngineEnabled / searchByImdb run
//    for real. Only the HTTP transport is faked (http.runWithClient +
//    MockClient), exactly like test/keyword_search_origin_widget_test.dart.
//  * Indexer managers. A Jackett config seeded into 'indexer_manager_configs_v1'
//    (plaintext is accepted; SecretVault re-seals on first read) becomes a
//    synthesized imdb-capable engine, which is how the indexer-manager branch
//    of _sourceEngineListing and the engineErrors branch of _fetchOneEngine
//    become reachable — Jackett's own search THROWS on a non-2xx, which is the
//    only in-band engine error a fetch without a timeout can produce.
//  * Addons. StremioService.debugStreamHttpClientFactory + MockClient, and a
//    'stremio_addons_v1' entry, as in test/quick_play_rules_test.dart and the
//    T4 pin.
//  * Cache-first. CloudProviderRegistry.instance + test/support's
//    FakeCloudProvider, as in test/cloud_playback_cache_first_test.dart.
//
// _sourceEngineListing / _fetchOneEngine are private and are NOT reachable
// from the two search statics; their only public door is the pair of fetcher
// factories (seriesFetcherFor / movieFetcherFor), whose listEngines /
// fetchEngine fields ARE those two functions. That is the door used here.
//
// Quirks pinned deliberately (keep them, do not "fix" them in the move):
//  * _curateCandidates never empties a non-empty list: each of its three steps
//    falls back to its own input when it would remove everything.
//  * _curatePackCandidates is STRICT — the same RD-blocked-keyword step there
//    CAN empty the list, and that empty is a cacheable "no pack", not null.
//  * A pack stage that reported an in-band engine error yields null (unknown),
//    even though the search itself did not throw.
//  * In searchCuratedSources the engine stage is NOT wrapped in a try/catch
//    (failures propagate to the caller) while the addon stage is (failures
//    fail silently to an empty list). The onResults narration callback sits
//    inside both, so a throwing callback shows exactly where the boundary is.
//  * _fetchOneEngine's own timeout branch is unreachable: it calls
//    TorrentService.searchByImdb without a timeout, so engineErrors can only
//    be populated by a throwing engine (see the indexer-manager seam above).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/filter_ladder.dart';

import 'support/fake_cloud_provider.dart';

// ── fixtures ────────────────────────────────────────────────────────────────

/// An ordinary imported engine with IMDB capability. Only the transport is
/// faked; lib owns request construction, parsing, coverage detection, merge.
String _engineYaml(String id, String displayName, String host) =>
    '''
id: $id
display_name: $displayName
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: false
  imdb_search: true
  series_support: false
api:
  base_url: https://$host/search
  method: GET
query_params:
  type: query_params
  param_name: imdb
response_format:
  type: direct_json
  results_path: results
field_mappings:
  infohash: infohash
  name: name
  seeders: seeders
  size_bytes: size_bytes
''';

var _hashSeed = 0;

/// Distinct valid infohashes; the executor drops rows whose hash isn't one.
String _hash(String tag) {
  final base = tag.codeUnits.fold<int>(17, (a, c) => (a * 31 + c) & 0xffffff);
  _hashSeed++;
  return (base.toRadixString(16) + _hashSeed.toRadixString(16))
      .padLeft(40, 'c')
      .substring(0, 40);
}

Map<String, dynamic> _row(
  String name, {
  int seeders = 10,
  int size = 1 << 30,
}) => {
  'infohash': _hash(name),
  'name': name,
  'seeders': seeders,
  'size_bytes': size,
};

String _engineBody(List<Map<String, dynamic>> rows) =>
    jsonEncode({'results': rows});

FilterLadder get _ladder => FilterLadder(TorrentFilterState());

const _seriesMeta = PlaybackMeta(
  imdbId: 'tt3322110',
  contentType: 'series',
  season: 1,
  episode: 2,
  title: 'Pin Show',
);

const _movieMeta = PlaybackMeta(
  imdbId: 'tt3322111',
  contentType: 'movie',
  title: 'Pin Film',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  /// Full profile/storage reset with [prefs] seeded, then the engine registry
  /// re-initialized from an empty on-disk engine directory.
  Future<void> boot([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues({...prefs});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    StremioService.instance.invalidateCache();
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
  }

  /// Imports [ids] as real engine YAML files, `id` → `https://<id>.invalid`.
  Future<void> importEngines(List<String> ids) async {
    for (final id in ids) {
      await LocalEngineStorage.instance.saveEngine(
        engineId: id,
        fileName: '$id.yaml',
        yamlContent: _engineYaml(
          id,
          id
              .split('_')
              .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
              .join(' '),
          '$id.invalid'.replaceAll('_', '-'),
        ),
        displayName: id
            .split('_')
            .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' '),
      );
    }
    await EngineRegistry.instance.reload();
  }

  /// The prefs value that makes a Jackett indexer manager exist.
  Map<String, Object> indexerPrefs({
    required String id,
    required String name,
    bool enabled = true,
  }) => {
    'indexer_manager_configs_v1': <String>[
      jsonEncode({
        'id': id,
        'name': name,
        'type': 'jackett',
        'base_url': 'https://jackett-pin.invalid',
        'api_key': 'pin-key',
        'enabled': enabled,
      }),
    ],
  };

  const addonBase = 'https://addon-pin.invalid/x';
  final addon = StremioAddon(
    id: 'pin.addon',
    name: 'Pin Addon',
    manifestUrl: '$addonBase/manifest.json',
    baseUrl: addonBase,
    types: const ['series', 'movie'],
    resources: const ['stream'],
  );

  Map<String, Object> addonPrefs() => {
    'stremio_addons_v1': jsonEncode([addon.toJson()]),
  };

  /// Installs a MockClient answering engine (and Jackett) requests by host.
  Future<T> withEngineHttp<T>(
    Future<T> Function() body, {
    required Map<String, http.Response Function(http.Request)> byHost,
    List<Uri>? seen,
  }) {
    return http.runWithClient(
      body,
      () => MockClient((request) async {
        seen?.add(request.url);
        final handler = byHost[request.url.host];
        if (handler == null) {
          return http.Response('not found', 404);
        }
        return handler(request);
      }),
    );
  }

  http.Response Function(http.Request) engineAnswer(
    List<Map<String, dynamic>> rows,
  ) =>
      (_) => http.Response(
        _engineBody(rows),
        200,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('playback-search-pin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await boot();
  });

  tearDown(() async {
    StremioService.instance.debugStreamHttpClientFactory = null;
    StremioService.instance.invalidateCache();
    CloudProviderRegistry.debugReset();
    ProfileSessionMemory.clearAll();
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  QuickPlayRules enginesOnly({
    QuickPlayPackPreference pack = QuickPlayPackPreference.widestFirst,
  }) => QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
    sourceMode: QuickPlaySourceMode.torrentsOnly,
    packPreference: pack,
  );

  List<String> names(List<Torrent>? list) => [
    for (final t in list ?? const <Torrent>[]) t.name,
  ];

  // ────────────────────────────────────────────────────────────────────────
  group('searchCuratedSources — engine path and _curateCandidates', () {
    test(
      'title mismatch is dropped, the requested episode leads, RD-blocked names go last-resort',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await withEngineHttp(
          () => TorrentPlaybackService.searchCuratedSources(
            imdbId: 'tt3322110',
            label: 'Pin Show',
            isMovie: false,
            season: 1,
            episode: 2,
            provider: 'debrid',
            rules: enginesOnly(),
          ),
          byHost: {
            'alpha.invalid': engineAnswer([
              _row('Unrelated Other Thing S01E02 1080p x265', seeders: 900),
              _row('Pin Show S01E02 2160p WEB-DL', seeders: 500),
              _row('Pin Show S01E02 1080p x265', seeders: 100),
              _row('Pin Show S02E04 1080p x265', seeders: 400),
            ]),
          },
        );
        // 1. title match dropped the unrelated row.
        expect(
          names(result),
          isNot(contains('Unrelated Other Thing S01E02 1080p x265')),
        );
        // 3. the RD-blocked WEB-DL row is gone (RD provider, setting default on).
        expect(names(result), isNot(contains('Pin Show S01E02 2160p WEB-DL')));
        // 2. the exact requested episode outranks the other season.
        expect(names(result).first, 'Pin Show S01E02 1080p x265');
      },
    );

    test('a non-debrid provider keeps RD-blocked names', () async {
      await boot();
      await importEngines(['alpha']);
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322110',
          label: 'Pin Show',
          isMovie: false,
          season: 1,
          episode: 2,
          provider: 'torbox',
          rules: enginesOnly(),
        ),
        byHost: {
          'alpha.invalid': engineAnswer([
            _row('Pin Show S01E02 2160p WEB-DL', seeders: 500),
            _row('Pin Show S01E02 1080p x265', seeders: 100),
          ]),
        },
      );
      expect(names(result), contains('Pin Show S01E02 2160p WEB-DL'));
    });

    test(
      'the rd_skip_blocked_torrents setting off keeps blocked names on RD',
      () async {
        await boot(const {'rd_skip_blocked_torrents': false});
        await importEngines(['alpha']);
        final result = await withEngineHttp(
          () => TorrentPlaybackService.searchCuratedSources(
            imdbId: 'tt3322110',
            label: 'Pin Show',
            isMovie: false,
            season: 1,
            episode: 2,
            provider: 'debrid',
            rules: enginesOnly(),
          ),
          byHost: {
            'alpha.invalid': engineAnswer([
              _row('Pin Show S01E02 2160p WEB-DL', seeders: 500),
              _row('Pin Show S01E02 1080p x265', seeders: 100),
            ]),
          },
        );
        expect(names(result), contains('Pin Show S01E02 2160p WEB-DL'));
      },
    );

    test(
      'curation never empties: a total title miss keeps the whole list',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await withEngineHttp(
          () => TorrentPlaybackService.searchCuratedSources(
            imdbId: 'tt3322110',
            label: 'Nothing Matches This Label',
            isMovie: true,
            provider: 'torbox',
            rules: enginesOnly(),
          ),
          byHost: {
            'alpha.invalid': engineAnswer([
              _row('Pin Film 2160p x265', seeders: 300),
              _row('Pin Film 1080p x265', seeders: 200),
            ]),
          },
        );
        expect(names(result), hasLength(2));
      },
    );

    test(
      'curation never empties: every candidate RD-blocked keeps the whole list',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await withEngineHttp(
          () => TorrentPlaybackService.searchCuratedSources(
            imdbId: 'tt3322111',
            label: 'Pin Film',
            isMovie: true,
            provider: 'debrid',
            rules: enginesOnly(),
          ),
          byHost: {
            'alpha.invalid': engineAnswer([
              _row('Pin Film 2160p WEB-DL', seeders: 300),
              _row('Pin Film 1080p WEBRip', seeders: 200),
            ]),
          },
        );
        expect(names(result), hasLength(2));
      },
    );

    test('onResults reports the pre-curation engine count', () async {
      await boot();
      await importEngines(['alpha']);
      final counts = <int>[];
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322111',
          label: 'Pin Film',
          isMovie: true,
          provider: 'debrid',
          rules: enginesOnly(),
          onResults: counts.add,
        ),
        byHost: {
          'alpha.invalid': engineAnswer([
            _row('Pin Film 2160p WEB-DL', seeders: 300),
            _row('Pin Film 1080p x265', seeders: 200),
            _row('Unrelated 1080p x265', seeders: 100),
          ]),
        },
      );
      expect(counts, [3], reason: 'the count is taken before curation');
      expect(names(result), ['Pin Film 1080p x265']);
    });

    test('isCancelled short-circuits before curation', () async {
      await boot();
      await importEngines(['alpha']);
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322111',
          label: 'Pin Film',
          isMovie: true,
          provider: 'debrid',
          rules: enginesOnly(),
          isCancelled: () => true,
        ),
        byHost: {
          'alpha.invalid': engineAnswer([
            _row('Pin Film 2160p WEB-DL', seeders: 300),
            _row('Unrelated 1080p x265', seeders: 100),
          ]),
        },
      );
      expect(names(result), hasLength(2), reason: 'uncurated raw list');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('searchCuratedSources — addon stage and the failure contract', () {
    void mockAddon(String body, {int status = 200}) {
      StremioService.instance.debugStreamHttpClientFactory = () =>
          MockClient((_) async {
            if (status != 200) return http.Response('boom', status);
            return http.Response(
              body,
              200,
              headers: {'content-type': 'application/json'},
            );
          });
    }

    final oneDirectOneTorrent = jsonEncode({
      'streams': [
        {
          'name': 'Addon Direct',
          'description': 'Pin.Show.S01E02.1080p',
          'url': 'https://cdn.pin.invalid/s01e02.mkv',
        },
        {
          'name': 'Addon Torrent',
          'description': 'Pin.Show.S01E02.1080p',
          'infoHash': 'b' * 40,
        },
      ],
    });

    test('engines dry: the addon stage supplies the sources', () async {
      await boot(addonPrefs());
      await importEngines(['alpha']);
      mockAddon(oneDirectOneTorrent);
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322110',
          label: 'Pin Show',
          isMovie: false,
          season: 1,
          episode: 2,
          provider: 'debrid',
          rules: QuickPlayRules.debrifyDefault(isMovie: false),
        ),
        byHost: {'alpha.invalid': engineAnswer(const [])},
      );
      expect(result, hasLength(2));
      expect([
        for (final t in result) t.streamType,
      ], containsAll(const [StreamType.directUrl, StreamType.torrent]));
    });

    test('an addon failure fails silently; engine rows survive', () async {
      await boot(addonPrefs());
      await importEngines(['alpha']);
      mockAddon('', status: 500);
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322110',
          label: 'Pin Show',
          isMovie: false,
          season: 1,
          episode: 2,
          provider: 'torbox',
          rules: QuickPlayRules.debrifyDefault(isMovie: false),
        ),
        byHost: {
          'alpha.invalid': engineAnswer([
            _row('Pin Show S01E02 1080p x265', seeders: 30),
          ]),
        },
      );
      expect(names(result), ['Pin Show S01E02 1080p x265']);
    });

    test(
      'the engine stage is unguarded while the addon stage swallows its own failure',
      () async {
        await boot(addonPrefs());
        await importEngines(['alpha']);
        mockAddon(oneDirectOneTorrent);

        // onResults fires inside BOTH stages. Engine rows only → the throw
        // escapes searchCuratedSources. Addon rows only → it is swallowed and
        // the addon contributes nothing.
        Future<List<Torrent>> run(List<Map<String, dynamic>> engineRows) =>
            withEngineHttp(
              () => TorrentPlaybackService.searchCuratedSources(
                imdbId: 'tt3322110',
                label: 'Pin Show',
                isMovie: false,
                season: 1,
                episode: 2,
                provider: 'torbox',
                rules: QuickPlayRules.debrifyDefault(isMovie: false),
                onResults: (_) => throw StateError('narration failed'),
              ),
              byHost: {'alpha.invalid': engineAnswer(engineRows)},
            );

        await expectLater(
          run([_row('Pin Show S01E02 1080p x265', seeders: 30)]),
          throwsA(isA<StateError>()),
        );
        expect(
          await run(const []),
          isEmpty,
          reason: 'the addon stage catches its own throw and returns empty',
        );
      },
    );

    test(
      'addonsOnly drops direct links when allowDirectLinks is off',
      () async {
        await boot(addonPrefs());
        mockAddon(oneDirectOneTorrent);
        final result = await TorrentPlaybackService.searchCuratedSources(
          imdbId: 'tt3322110',
          label: 'Pin Show',
          isMovie: false,
          season: 1,
          episode: 2,
          provider: 'debrid',
          rules: QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
            sourceMode: QuickPlaySourceMode.addonsOnly,
            allowDirectLinks: false,
          ),
        );
        expect([
          for (final t in result) t.streamType,
        ], everyElement(isNot(StreamType.directUrl)));
        expect(result, hasLength(1));
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  group('searchSeriesPackSources — _curatePackCandidates', () {
    Future<List<Torrent>?> packs({
      required List<Map<String, dynamic>> rows,
      String provider = 'debrid',
      String label = 'Pin Show',
      QuickPlayPackPreference preference = QuickPlayPackPreference.widestFirst,
      void Function()? onCacheCheck,
    }) => withEngineHttp(
      () => TorrentPlaybackService.searchSeriesPackSources(
        imdbId: 'tt3322110',
        label: label,
        season: 2,
        provider: provider,
        ladder: _ladder,
        rules: enginesOnly(pack: preference),
        onCacheCheck: onCacheCheck,
      ),
      byHost: {'alpha.invalid': engineAnswer(rows)},
    );

    test(
      'STRICT: singles, wrong seasons and title misses are dropped',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await packs(
          provider: 'torbox',
          rows: [
            _row('Pin Show S02E01 1080p x265', seeders: 900), // single episode
            _row('Other Series S02 Complete 1080p x265', seeders: 800), // title
            _row('Pin Show S03 1080p x265', seeders: 700), // wrong season pack
            _row(
              'Pin Show S04-S05 1080p x265',
              seeders: 600,
            ), // range misses S02
            _row('Pin Show S02 1080p x265', seeders: 10), // keeper
          ],
        );
        expect(names(result), ['Pin Show S02 1080p x265']);
      },
    );

    test(
      'widestFirst: complete series, then multi-season, then season pack',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await packs(
          provider: 'torbox',
          rows: [
            _row('Pin Show S02 1080p x265', seeders: 900),
            _row('Pin Show S02-S03 1080p x265', seeders: 5),
            _row('Pin Show Complete Series 1080p x265', seeders: 1),
          ],
        );
        expect(names(result), [
          'Pin Show Complete Series 1080p x265',
          'Pin Show S02-S03 1080p x265',
          'Pin Show S02 1080p x265',
        ]);
      },
    );

    test('seasonFirst inverts the tier order', () async {
      await boot();
      await importEngines(['alpha']);
      final result = await packs(
        provider: 'torbox',
        preference: QuickPlayPackPreference.seasonFirst,
        rows: [
          _row('Pin Show Complete Series 1080p x265', seeders: 900),
          _row('Pin Show S02-S03 1080p x265', seeders: 800),
          _row('Pin Show S02 1080p x265', seeders: 1),
        ],
      );
      expect(names(result), [
        'Pin Show S02 1080p x265',
        'Pin Show S02-S03 1080p x265',
        'Pin Show Complete Series 1080p x265',
      ]);
    });

    test('inside a tier, more seasons wins, then seeders', () async {
      await boot();
      await importEngines(['alpha']);
      final result = await packs(
        provider: 'torbox',
        rows: [
          _row('Pin Show S02-S03 1080p x265', seeders: 900),
          _row('Pin Show S02-S06 1080p x265', seeders: 3),
          _row('Pin Show S02 x265 low', seeders: 4),
          _row('Pin Show S02 x265 high', seeders: 40),
        ],
      );
      expect(names(result), [
        'Pin Show S02-S06 1080p x265', // 5 seasons beats 2 despite seeders
        'Pin Show S02-S03 1080p x265',
        'Pin Show S02 x265 high', // same tier + count → seeders decide
        'Pin Show S02 x265 low',
      ]);
    });

    test(
      'STRICT: an all-blocked pack list empties, and that empty is cacheable (not null)',
      () async {
        await boot();
        await importEngines(['alpha']);
        final result = await packs(
          rows: [
            _row('Pin Show S02 1080p WEB-DL', seeders: 900),
            _row('Pin Show S02-S03 1080p WEBRip', seeders: 800),
          ],
        );
        expect(
          result,
          isEmpty,
          reason: 'no fallback-to-unfiltered here, unlike _curateCandidates',
        );
        expect(result, isNotNull, reason: 'the search itself succeeded');
      },
    );

    test('a stage that reported an engine error yields null', () async {
      await boot(indexerPrefs(id: '77', name: 'Pin Jackett'));
      final result = await withEngineHttp(
        () => TorrentPlaybackService.searchSeriesPackSources(
          imdbId: 'tt3322110',
          label: 'Pin Show',
          season: 2,
          provider: 'torbox',
          ladder: _ladder,
          rules: enginesOnly(),
        ),
        byHost: {'jackett-pin.invalid': (_) => http.Response('nope', 500)},
      );
      expect(
        result,
        isNull,
        reason: 'an in-band engine error is "unknown", not "no pack exists"',
      );
    });

    test('a clean empty engine answer is a cacheable empty', () async {
      await boot();
      await importEngines(['alpha']);
      final result = await packs(provider: 'torbox', rows: const []);
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test(
      'cache-first hoists a cached pack and fires onCacheCheck for a cache-checking provider',
      () async {
        await boot();
        await importEngines(['alpha']);
        // Capture the hashes the engine will report so the fake can mark one.
        final wide = _row('Pin Show Complete Series 1080p x265', seeders: 900);
        final narrow = _row('Pin Show S02 1080p x265', seeders: 1);
        CloudProviderRegistry.instance = CloudProviderRegistry([
          FakeCloudProvider(
            id: CloudProviderId.torbox,
            cachedHashes: {(narrow['infohash'] as String).toLowerCase()},
          ),
        ]);
        var cacheStages = 0;
        final result = await packs(
          provider: 'torbox',
          rows: [wide, narrow],
          onCacheCheck: () => cacheStages++,
        );
        expect(cacheStages, 1);
        expect(names(result), [
          'Pin Show S02 1080p x265',
          'Pin Show Complete Series 1080p x265',
        ]);
      },
    );

    test(
      'a provider without a cache check never reaches the cache stage',
      () async {
        await boot();
        await importEngines(['alpha']);
        CloudProviderRegistry.instance = CloudProviderRegistry([
          FakeCloudProvider(id: CloudProviderId.torbox),
        ]);
        var cacheStages = 0;
        final result = await packs(
          provider: 'debrid',
          rows: [_row('Pin Show S02 1080p x265', seeders: 5)],
          onCacheCheck: () => cacheStages++,
        );
        expect(cacheStages, 0);
        expect(names(result), ['Pin Show S02 1080p x265']);
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  group('_sourceEngineListing and _fetchOneEngine via the fetcher factories', () {
    test(
      'listEngines skips disabled engines and keeps registry-then-indexer order',
      () async {
        await boot(indexerPrefs(id: '99', name: 'Pin Jackett'));
        await importEngines(['alpha', 'bravo']);
        await TorrentService.setEngineEnabled('bravo', false);

        final fetcher = TorrentPlaybackService.movieFetcherFor(
          meta: _movieMeta,
        );
        final refs = await fetcher!.listEngines!();
        expect(
          [for (final r in refs) r.id],
          ['alpha', 'indexer_manager_pin_jackett_99'],
        );
        expect([for (final r in refs) r.name], ['Alpha', 'Pin Jackett']);
        // An ordinary engine keys on its id; an indexer manager keys on its
        // lowercased DISPLAY NAME, because that is what its rows carry.
        expect([for (final r in refs) r.sourceKey], ['alpha', 'pin jackett']);
      },
    );

    test('a disabled indexer manager is skipped too', () async {
      await boot(indexerPrefs(id: '99', name: 'Pin Jackett', enabled: false));
      await importEngines(['alpha']);
      final refs = await TorrentPlaybackService.movieFetcherFor(
        meta: _movieMeta,
      )!.listEngines!();
      expect([for (final r in refs) r.id], ['alpha']);
    });

    test('fetchEngine returns only the requested engine rows', () async {
      await boot();
      await importEngines(['alpha', 'bravo']);
      final fetcher = TorrentPlaybackService.seriesFetcherFor(
        meta: _seriesMeta,
        provider: 'torbox',
      );
      final fetched = await withEngineHttp(
        () => fetcher!.fetchEngine!('bravo', 1, 2),
        byHost: {
          'alpha.invalid': engineAnswer([
            _row('Pin Show S01E02 from alpha', seeders: 9),
          ]),
          'bravo.invalid': engineAnswer([
            _row('Pin Show S01E02 from bravo', seeders: 8),
          ]),
        },
      );
      expect(names(fetched), ['Pin Show S01E02 from bravo']);
    });

    test('fetchEngine returns an empty list for a silent engine', () async {
      await boot();
      await importEngines(['alpha']);
      final fetched = await withEngineHttp(
        () => TorrentPlaybackService.movieFetcherFor(
          meta: _movieMeta,
        )!.fetchEngine!('alpha', 0, 0),
        byHost: {'alpha.invalid': engineAnswer(const [])},
      );
      expect(fetched, isNotNull, reason: 'empty is not failure');
      expect(fetched, isEmpty);
    });

    test('fetchEngine returns null when the engine reports an error', () async {
      await boot(indexerPrefs(id: '99', name: 'Pin Jackett'));
      final fetched = await withEngineHttp(
        () => TorrentPlaybackService.movieFetcherFor(
          meta: _movieMeta,
        )!.fetchEngine!('indexer_manager_pin_jackett_99', 0, 0),
        byHost: {'jackett-pin.invalid': (_) => http.Response('nope', 500)},
      );
      expect(fetched, isNull);
    });
  });
}
