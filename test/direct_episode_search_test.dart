import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkTestBinding();
  final service = StremioService.instance;
  StremioAddon addon(String name) => StremioAddon(
    id: name,
    name: name,
    manifestUrl: 'https://$name.test/manifest.json',
    baseUrl: 'https://$name.test',
    types: const ['series'],
    resources: const ['stream'],
  );
  void install(List<StremioAddon> addons) {
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode(addons.map((a) => a.toJson()).toList()),
    });
    service.invalidateCache();
  }

  http.Response response(String url) => http.Response(
    jsonEncode({
      'streams': [
        {
          'url': url,
          'name': '1080p',
          'behaviorHints': {
            'bingeGroup': 'group',
            'proxyHeaders': {
              'request': {'Authorization': 'episode-token'},
            },
          },
        },
      ],
    }),
    200,
  );
  tearDown(() {
    service.debugStreamHttpClientFactory = null;
    service.invalidateCache();
  });

  Torrent candidate({
    bool direct = true,
    String url = 'https://cdn.test/1',
    Map<String, String>? headers,
  }) => Torrent(
    rowid: 0,
    infohash: direct ? '' : 'abc',
    name: 'Show S01E01',
    sizeBytes: 0,
    createdUnix: 0,
    seeders: 0,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    streamType: direct ? StreamType.directUrl : StreamType.torrent,
    directUrl: direct ? url : null,
    httpHeaders: headers,
  );
  test(
    'early recovery preserves later direct links and the acquisition budget',
    () {
      final failed = candidate();
      final torrent = candidate(direct: false);
      final dead = candidate(url: 'https://cdn.test/dead');
      final working = candidate(url: 'https://cdn.test/working');
      for (final attempts in [1, 2, 5]) {
        final rules = QuickPlayRules.forPreset(
          QuickPlayPreset.addonOrder,
          isMovie: false,
        ).copyWith(maxAttempts: attempts);
        final recovery = TorrentPlaybackService.earlyDirectRecovery(
          [failed, torrent, dead, working],
          failed: failed,
          rules: rules,
        );
        expect(recovery.sources, [torrent, dead, working]);
        expect(recovery.rules, same(rules));
        expect(recovery.rules.maxAttempts, attempts);
      }
    },
  );

  test('early recovery excludes only the failed URL and headers', () {
    final failed = candidate(headers: {'Authorization': 'old'});
    final replacement = candidate(headers: {'Authorization': 'new'});
    final duplicate = candidate(headers: {'Authorization': 'old'});
    final recovery = TorrentPlaybackService.earlyDirectRecovery(
      [failed, replacement, duplicate],
      failed: failed,
      rules: QuickPlayRules.debrifyDefault(isMovie: false),
    );
    expect(recovery.sources, [replacement]);
  });
  test(
    'early selection respects exact order and does not bypass torrent rows',
    () {
      final rules = QuickPlayRules.forPreset(
        QuickPlayPreset.addonOrder,
        isMovie: false,
      );
      final direct = candidate();
      final torrent = candidate(direct: false);
      expect(
        TorrentPlaybackService.earlyDirectCandidate([
          direct,
          torrent,
        ], rules: rules),
        same(direct),
      );
      expect(
        TorrentPlaybackService.earlyDirectCandidate([
          torrent,
          direct,
        ], rules: rules),
        isNull,
      );
      for (final other in [
        rules.copyWith(ranking: QuickPlayRanking.quality),
        rules.copyWith(allowDirectLinks: false),
        rules.copyWith(tryNextOnFailure: false),
        rules.copyWith(maxAttempts: 1),
        QuickPlayRules.debrifyDefault(isMovie: false),
      ]) {
        expect(
          TorrentPlaybackService.earlyDirectCandidate([direct], rules: other),
          isNull,
        );
      }
    },
  );

  test('early launch source menu joins the original episode search', () async {
    final gate = Completer<List<Torrent>>();
    final fetcher = TorrentPlaybackService.seriesFetcherFor(
      meta: const PlaybackMeta(
        imdbId: 'tt123',
        contentType: 'series',
        season: 1,
        episode: 1,
      ),
      initialEpisodeSearch: gate.future,
    )!;
    expect(fetcher.episodesFetched, isFalse);
    final fetched = fetcher.fetch(
      SeriesSourceFetcher.modeEpisodes,
      season: 1,
      episode: 1,
    );
    final direct = candidate();
    gate.complete([direct]);
    expect(await fetched, [direct]);
    expect(fetcher.episodesFetched, isTrue);
  });

  test('early direct uses exact addon configuration priority keys', () {
    final primary = StremioAddon(
      id: 'com.test.aio',
      name: 'AIOStreams',
      manifestUrl: 'https://primary.test/secret/manifest.json',
      baseUrl: 'https://primary.test/secret',
      types: const ['series'],
      resources: const ['stream'],
    );
    final backup = StremioAddon(
      id: 'com.test.aio',
      name: 'AIOStreams',
      manifestUrl: 'https://backup.test/secret/manifest.json',
      baseUrl: 'https://backup.test/secret',
      types: const ['series'],
      resources: const ['stream'],
    );

    expect(
      TorrentPlaybackService.leadingDirectAddonKey(
        [primary, backup],
        [backup.sourceKey, primary.sourceKey],
      ),
      backup.sourceKey,
    );
    expect(
      TorrentPlaybackService.leadingDirectAddonKey(
        [primary, backup],
        [primary.legacySourceKey],
      ),
      isNull,
    );
  });

  test(
    'prepared episode is consumed once with its headers and identity',
    () async {
      final a = addon('one');
      install([a]);
      var calls = 0;
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        calls++;
        expect(
          Uri.decodeComponent(request.url.path),
          '/stream/series/tt123:1:2.json',
        );
        return response('https://cdn.test/episode2');
      });
      Future<Torrent?> resolve({bool prepare = false}) =>
          service.resolvePinnedDirectStream(
            addonId: a.id,
            addonKey: a.sourceBindingKey,
            streamKey: '1080p',
            streamIndex: 0,
            bingeGroup: 'group',
            type: 'series',
            contentId: 'tt123',
            season: 1,
            episode: 2,
            prepare: prepare,
          );
      await resolve(prepare: true);
      final selected = await resolve();
      expect(calls, 1);
      expect(selected?.httpHeaders?['Authorization'], 'episode-token');
      expect(selected?.stremioVideoId, 'tt123:1:2');
      await resolve();
      expect(calls, 2);
    },
  );

  test('expired prepared signed URLs are not consumed', () async {
    final a = addon('one');
    install([a]);
    var calls = 0;
    service.debugStreamHttpClientFactory = () => MockClient((_) async {
      calls++;
      return response('https://cdn.test/episode2?Expires=1');
    });
    Future<Torrent?> resolve({bool prepare = false}) =>
        service.resolvePinnedDirectStream(
          addonId: a.id,
          addonKey: a.sourceBindingKey,
          streamKey: '1080p',
          streamIndex: 0,
          bingeGroup: 'group',
          type: 'series',
          contentId: 'tt123',
          season: 1,
          episode: 2,
          prepare: prepare,
        );
    await resolve(prepare: true);
    await resolve();
    expect(calls, 2);
  });

  test('disabled addon cannot serve a prepared link', () async {
    final a = addon('one');
    install([a]);
    service.debugStreamHttpClientFactory = () =>
        MockClient((_) async => response('https://cdn.test/2'));
    Future<Torrent?> resolve({bool prepare = false}) =>
        service.resolvePinnedDirectStream(
          addonId: a.id,
          addonKey: a.sourceBindingKey,
          streamKey: '1080p',
          streamIndex: 0,
          bingeGroup: 'group',
          type: 'series',
          contentId: 'tt123',
          season: 1,
          episode: 2,
          prepare: prepare,
        );
    await resolve(prepare: true);
    install([]);
    expect(await resolve(), isNull);
  });

  test('targeted retry selects the exact same-manifest configuration', () async {
    final main = addon('main').copyWith(
      id: 'org.example.aio',
      name: 'AIOStreams',
    ).withUserAlias('AIOStreams Main');
    final backup = addon('backup').copyWith(
      id: 'org.example.aio',
      name: 'AIOStreams',
    ).withUserAlias('AIOStreams Backup');
    install([main, backup]);
    final hosts = <String>[];
    service.debugStreamHttpClientFactory = () => MockClient((request) async {
      hosts.add(request.url.host);
      return response('https://cdn.test/backup');
    });

    final results = await service.retryAddonStreams(
      addonId: backup.sourceBindingKey,
      type: 'series',
      imdbId: 'tt123',
      season: 1,
      episode: 2,
    );

    expect(hosts, ['backup.test']);
    expect(results.single.source, backup.sourceKey);
    expect(results.single.addonDisplayName, 'AIOStreams Backup');
  });

  test(
    'search UI receives fast addon before slow one; final order is unchanged',
    () async {
      final slowAddon = addon('slow');
      final fastAddon = addon('fast');
      install([slowAddon, fastAddon]);
      final slow = Completer<http.Response>();
      final first = Completer<void>();
      final batches = <String>[];
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        if (request.url.host == 'slow.test') return slow.future;
        return response('https://cdn.test/fast');
      });
      final search = TorrentService.searchByImdbWithStremio(
        'tt123',
        isMovie: false,
        season: 1,
        episode: 2,
        engineStates: const {},
        preserveSourceOrder: true,
        onBatch: (source, torrents) {
          if (!source.startsWith('stremio:')) return;
          batches.add(source);
          if (!first.isCompleted) first.complete();
        },
      );
      await first.future.timeout(const Duration(seconds: 5));
      expect(batches, [fastAddon.sourceKey]);
      slow.complete(response('https://cdn.test/slow'));
      final result = await search;
      expect(batches, [fastAddon.sourceKey, slowAddon.sourceKey]);
      expect((result['torrents'] as List<Torrent>).map((t) => t.directUrl), [
        'https://cdn.test/slow',
        'https://cdn.test/fast',
      ]);
    },
  );

  test(
    'custom episode protocol id is sent to every compatible addon',
    () async {
      final origin = addon('onepace');
      final fallback = addon('fallback');
      install([origin, fallback]);
      final paths = <String, String>{};
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        paths[request.url.host] = Uri.decodeComponent(request.url.path);
        return response('https://cdn.test/${request.url.host}');
      });

      final result = await service.searchStreams(
        type: 'series',
        imdbId: 'tt0388629',
        season: 1,
        episode: 1,
        originAddonKey: origin.sourceBindingKey,
        originVideoId: 'RO_1',
      );

      expect(paths['onepace.test'], '/stream/series/RO_1.json');
      expect(paths['fallback.test'], '/stream/series/RO_1.json');
      expect(result['torrents'], hasLength(2));
    },
  );

  test(
    'concurrent pinned lookup and ordinary search share addon request',
    () async {
      final a = addon('one');
      install([a]);
      var calls = 0;
      final started = Completer<void>();
      final gate = Completer<http.Response>();
      service.debugStreamHttpClientFactory = () => MockClient((_) {
        calls++;
        if (!started.isCompleted) started.complete();
        return gate.future;
      });
      final pin = service.resolvePinnedDirectStream(
        addonId: a.id,
        addonKey: a.sourceBindingKey,
        streamKey: '1080p',
        streamIndex: 0,
        bingeGroup: 'group',
        type: 'series',
        contentId: 'tt123',
        season: 1,
        episode: 2,
        prepare: true,
      );
      await started.future;
      final search = service.searchStreams(
        type: 'series',
        imdbId: 'tt123',
        season: 1,
        episode: 2,
      );
      // Let addon/profile reads settle before releasing the shared network job.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete(response('https://cdn.test/2'));
      await Future.wait([pin, search]);
      expect(calls, 1);
    },
  );

  test(
    'episode HTTP requests reuse a connection but not foreground results',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final ports = <int>[];
      server.listen((request) async {
        ports.add(request.connectionInfo!.remotePort);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'streams': [
              {'url': 'https://cdn.test/2'},
            ],
          }),
        );
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final local = StremioAddon(
        id: 'local',
        name: 'Local',
        manifestUrl: '$base/manifest.json',
        baseUrl: base,
        types: const ['series'],
        resources: const ['stream'],
      );
      service.debugStreamHttpClientFactory = null;
      await service.fetchStreamsForContentId(local, 'series', 'tt123:1:2');
      await service.fetchStreamsForContentId(local, 'series', 'tt123:1:3');
      expect(ports.length, 2);
      expect(ports[0], ports[1]);
    },
  );
}
