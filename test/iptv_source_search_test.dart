import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late IptvPlaylist playlist;
  const movie = AdvancedSearchSelection(
    imdbId: 'tt1',
    isSeries: false,
    title: 'Dune',
    year: '2021',
  );
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'iptv-source-test');
    playlist = IptvPlaylist(
      id: 'playlist-a',
      name: 'My TV',
      url: '',
      serverUrl: 'https://panel.test',
      username: 'user',
      password: 'secret',
      addedAt: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({
      'iptv_playlists': [jsonEncode(playlist.toJson())],
    });
    dir = await Directory.systemTemp.createTemp('iptv-source-search');
    IptvCatalogDb.debugDirectoryOverride = dir.path;
    await IptvCatalogDb.open();
  });
  tearDown(() async {
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    ProfileRuntime.debugReset();
    await dir.delete(recursive: true);
  });

  void ingest(String type, List<IptvChannel> channels) => IptvCatalogDb.ingest(
    dbPath: IptvCatalogDb.path,
    catalogKey: IptvCatalogKey.forPlaylist(playlist, type)!,
    channels: channels,
  );

  test('automatic IPTV deadline stops subsequent episode lookups', () async {
    expect(
      TorrentPlaybackService.iptvQuickPlaySearchTimeout,
      const Duration(minutes: 1),
    );
    ingest('series', [
      for (final id in ['deadline1', 'deadline2'])
        IptvChannel(
          name: 'Show',
          url: 'series:$id',
          contentType: 'series',
          attributes: {'series_id': id},
        ),
    ]);
    final pending = Completer<http.Response>();
    var requests = 0;
    await http.runWithClient(
      () async {
        final watch = Stopwatch()..start();
        final result = await TorrentPlaybackService.searchIptvForQuickPlay(
          'tt2',
          'Show',
          '2011',
          false,
          1,
          1,
          QuickPlayRules.debrifyDefault(
            isMovie: false,
          ).copyWith(addonTimeoutSeconds: 5),
          null,
          discoveryTimeout: const Duration(seconds: 1),
        );
        expect(result, isEmpty);
        expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
        expect(requests, 1);
        pending.complete(http.Response('{}', 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(requests, 1);
      },
      () => MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
  });

  test(
    'matches title and year conservatively without erasing numeric titles',
    () {
      expect(
        IptvSourceSearch.matches('EN: Dune (2021) 4K', 'Dune', '2021'),
        isTrue,
      );
      expect(IptvSourceSearch.matches('Dune (1984)', 'Dune', '2021'), isFalse);
      expect(IptvSourceSearch.matches('Dune Part Two', 'Dune', null), isFalse);
      expect(
        IptvSourceSearch.matches('1917 (2019) HD', '1917', '2019'),
        isTrue,
      );
      expect(IptvSourceSearch.matches('Amélie', 'Amélie', '2001'), isTrue);
    },
  );

  test('unloaded movies stay visible and no catalog is downloaded', () async {
    expect(
      await StorageService.getIptvPlaylists(forSettings: false),
      hasLength(1),
    );
    final result = await IptvSourceSearch.search(movie);
    expect(result.single.name, 'My TV');
    expect(result.single.message, contains('Movies'));
    expect(result.single.message, contains('Catalog not loaded'));
    expect(result.single.torrents, isEmpty);
    expect(
      IptvCatalogDb.snapshot(IptvCatalogKey.forPlaylist(playlist, 'vod')!),
      isNull,
    );
  });

  test('movie cache does not imply series readiness', () async {
    ingest('vod', []);
    final result = await IptvSourceSearch.search(
      const AdvancedSearchSelection(
        imdbId: 'tt2',
        isSeries: true,
        title: 'Show',
        season: 1,
        episode: 2,
      ),
    );
    expect(result.single.message, contains('Series'));
    expect(result.single.message, contains('Catalog not loaded'));
  });

  test('empty loaded catalog is no match, not missing', () async {
    ingest('vod', []);
    final result = await IptvSourceSearch.search(movie);
    expect(result.single.message, 'No matching sources.');
  });

  test(
    'Quick Play respects direct-link mode and rejects ambiguous movies',
    () async {
      ingest('vod', [
        for (final title in ['Dune (2021)', 'Dune', 'Dune (1984)'])
          IptvChannel(
            name: title,
            url: 'https://panel.test/movie/${Uri.encodeComponent(title)}.mp4',
            contentType: 'vod',
          ),
      ]);
      final rules = QuickPlayRules.debrifyDefault(isMovie: true);
      Future<List<Torrent>> search(QuickPlayRules r) =>
          TorrentPlaybackService.searchIptvForQuickPlay(
            'tt1',
            'Dune',
            '2021',
            true,
            null,
            null,
            r,
            null,
          );
      expect((await search(rules)).single.name, 'Dune (2021)');
      expect(await search(rules.copyWith(allowDirectLinks: false)), isEmpty);
      expect(
        await search(
          rules.copyWith(sourceMode: QuickPlaySourceMode.torrentsOnly),
        ),
        isEmpty,
      );
      final sources = await search(rules);
      final addon = Torrent.fromJson({
        ...sources.single.toJson(),
        'source': 'stremio:Test',
        'infohash': 'addon-test',
      });
      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          [addon, ...sources],
          rules: rules.copyWith(
            sourcePriority: ['iptv:playlist-a', 'stremio:test'],
          ),
        ).first.source,
        'iptv:playlist-a',
      );
      expect(
        TorrentPlaybackService.orderCandidatesForRules(
          [addon, ...sources],
          rules: rules.copyWith(
            sourcePriority: ['stremio:test', 'iptv:playlist-a'],
          ),
        ).first.source,
        'stremio:test',
      );
      expect(
        TorrentPlaybackService.orderCandidatesForRules([
          ...sources.reversed,
          ...sources,
        ], rules: rules.copyWith(sourcePriority: ['iptv:playlist-a'])),
        hasLength(1),
      );
    },
  );

  test('Quick Play playlist discovery includes missing catalogs', () async {
    final providers = await SourcePriority.providers();
    final iptv = providers.where((p) => p.isIptv).single;
    expect(iptv.name, 'My TV');
    expect(iptv.key, 'iptv:playlist-a');
    expect(
      await TorrentPlaybackService.searchIptvForQuickPlay(
        'tt1',
        'Dune',
        '2021',
        true,
        null,
        null,
        QuickPlayRules.debrifyDefault(isMovie: true),
        null,
      ),
      isEmpty,
    );
  });

  test('Quick Play resolves each next episode from the IPTV series', () async {
    ingest('series', [
      IptvChannel(
        name: 'EN - Show (2011) (US)',
        url: 'series:901',
        contentType: 'series',
        attributes: {'series_id': '901'},
      ),
    ]);
    await http.runWithClient(
      () async {
        final rules = QuickPlayRules.debrifyDefault(isMovie: false);
        for (final episode in [1, 2]) {
          final sources = await TorrentPlaybackService.searchIptvForQuickPlay(
            'tt2',
            'Show',
            '2011',
            false,
            1,
            episode,
            rules,
            null,
          );
          expect(sources.single.directUrl, endsWith('/episode$episode.mp4'));
          await IptvSourceSearch.authorize(sources.single);
        }
      },
      () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'episodes': {
              '1': [
                {'id': 'episode1', 'episode_num': 1},
                {'id': 'episode2', 'episode_num': 2},
              ],
            },
          }),
          200,
        ),
      ),
    );
  });

  test('Xtream whole-series search returns a durable pin descriptor', () async {
    ingest('series', [
      IptvChannel(
        name: 'EN - Show (2011)',
        url: 'xtream-series://901',
        contentType: 'series',
        attributes: {'series_id': '901'},
      ),
    ]);
    final result = await IptvSourceSearch.search(
      const AdvancedSearchSelection(
        imdbId: 'tt2',
        isSeries: true,
        title: 'Show',
        year: '2011',
      ),
    );
    final source = result.single.torrents.single;
    expect(source.directUrl, isEmpty);
    expect(source.iptvPlaylistId, 'playlist-a');
    expect(source.iptvCatalogType, 'series');
    expect(source.iptvEntryKey, 'series:901');
    expect(source.toJson().toString(), isNot(contains('secret')));
    final nativeRoundTrip = Torrent.fromJson(source.toJson());
    expect(nativeRoundTrip.iptvPlaylistId, source.iptvPlaylistId);
    expect(nativeRoundTrip.iptvEntryKey, source.iptvEntryKey);
  });

  test('pinned Xtream series resolves only its saved provider row', () async {
    ingest('series', [
      for (final id in ['901', '902'])
        IptvChannel(
          name: 'Show',
          url: 'xtream-series://$id',
          contentType: 'series',
          attributes: {'series_id': id},
        ),
    ]);
    const pin = SeriesSource(
      torrentHash: '',
      torrentName: 'Show',
      debridService: SeriesSource.iptvDirectService,
      debridTorrentId: '',
      boundAt: 1,
      iptvPlaylistId: 'playlist-a',
      iptvCatalogType: 'series',
      iptvEntryKey: 'series:902',
    );
    final requested = <String>[];
    final resolved = await http.runWithClient(
      () => IptvSourceSearch.resolvePinned(
        pin,
        title: 'Show',
        season: 1,
        episode: 1,
      ),
      () => MockClient((request) async {
        requested.add(request.url.queryParameters['series_id']!);
        return http.Response(
          jsonEncode({
            'episodes': {
              '1': [
                {'id': 'episode1', 'episode_num': 1},
              ],
            },
          }),
          200,
        );
      }),
    );
    expect(requested, ['902']);
    expect(resolved?.iptvEntryKey, 'series:902');
  });

  testWidgets('source picker can pin an Xtream whole-series descriptor', (
    tester,
  ) async {
    ingest('series', [
      IptvChannel(
        name: 'Show',
        url: 'xtream-series://901',
        contentType: 'series',
        attributes: {'series_id': '901'},
      ),
    ]);
    final descriptor = (await IptvSourceSearch.search(
      const AdvancedSearchSelection(
        imdbId: 'tt2',
        isSeries: true,
        title: 'Show',
      ),
    )).single.torrents.single;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );

    expect(
      await TorrentPlaybackService.bindIptvSource(
        context,
        descriptor,
        imdbId: 'tt2',
        isMovie: false,
      ),
      isTrue,
    );
    final stored = await SeriesSourceService.getSources('tt2');
    expect(stored.single.isIptvDirect, isTrue);
    expect(stored.single.iptvEntryKey, 'series:901');
    expect(stored.single.toJson().toString(), isNot(contains('secret')));
  });

  test(
    'generic M3U movies and whole-series pins resolve from catalog',
    () async {
      playlist = IptvPlaylist(
        id: 'generic-a',
        name: 'Generic VOD',
        url: 'https://m3u.test/list.m3u?token=secret',
        addedAt: DateTime(2026),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('iptv_playlists', [
        jsonEncode(playlist.toJson()),
      ]);
      ingest('vod', [
        IptvChannel(
          name: 'Dune (2021)',
          url: 'https://cdn.test/dune.mp4?token=secret',
          group: 'Movies',
          // Common generic M3U VOD shape: providers still emit EXTINF:-1.
          duration: -1,
        ),
        for (final episode in [1, 2])
          IptvChannel(
            name: 'EN - Show (2011) S01E0$episode',
            url: 'https://cdn.test/show-s01e0$episode.mp4?token=secret',
            group: 'Shows',
            duration: -1,
          ),
      ]);

      final movieResult = await IptvSourceSearch.search(movie);
      final movieSource = movieResult.single.torrents.single;
      expect(movieSource.name, 'Dune (2021)');
      final moviePin = SeriesSource(
        torrentHash: '',
        torrentName: movieSource.name,
        debridService: SeriesSource.iptvDirectService,
        debridTorrentId: '',
        boundAt: 1,
        iptvPlaylistId: movieSource.iptvPlaylistId,
        iptvCatalogType: movieSource.iptvCatalogType,
        iptvEntryKey: movieSource.iptvEntryKey,
      );
      ingest('vod', [
        IptvChannel(
          name: 'Dune (2021)',
          url: 'https://cdn.test/dune.mp4?token=fresh',
          group: 'Movies',
          duration: -1,
        ),
        for (final episode in [1, 2])
          IptvChannel(
            name: 'EN - Show (2011) S01E0$episode',
            url: 'https://cdn.test/show-s01e0$episode.mp4?token=fresh',
            group: 'Shows',
            duration: -1,
          ),
      ]);
      final refreshedMovie = await IptvSourceSearch.resolvePinned(
        moviePin,
        title: 'Dune',
        year: '2021',
      );
      expect(refreshedMovie?.directUrl, endsWith('token=fresh'));

      const wholeSeries = AdvancedSearchSelection(
        imdbId: 'tt2',
        isSeries: true,
        title: 'Show',
        year: '2011',
      );
      final whole = await IptvSourceSearch.search(wholeSeries);
      expect(whole.single.torrents, hasLength(1));
      final descriptor = whole.single.torrents.single;
      expect(descriptor.iptvEntryKey, startsWith('m3u-series:'));

      final pin = SeriesSource(
        torrentHash: '',
        torrentName: descriptor.name,
        debridService: SeriesSource.iptvDirectService,
        debridTorrentId: '',
        boundAt: 1,
        iptvPlaylistId: descriptor.iptvPlaylistId,
        iptvCatalogType: descriptor.iptvCatalogType,
        iptvEntryKey: descriptor.iptvEntryKey,
      );
      final stored = pin.toJson();
      expect(stored.toString(), isNot(contains('token=secret')));
      expect(SeriesSource.fromJson(stored).bindingKey, pin.bindingKey);

      final episode = await IptvSourceSearch.resolvePinned(
        pin,
        title: 'Show',
        year: '2011',
        season: 1,
        episode: 2,
      );
      expect(episode?.directUrl, contains('show-s01e02.mp4'));
      await IptvSourceSearch.authorize(episode!);
      final providers = await SourcePriority.providers();
      expect(
        providers.any((provider) => provider.key == 'iptv:generic-a'),
        isTrue,
      );
    },
  );

  test('generic M3U series variants retain the selected rendition', () async {
    playlist = IptvPlaylist(
      id: 'generic-variants',
      name: 'Generic variants',
      url: 'https://m3u.test/list.m3u',
      addedAt: DateTime(2026),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('iptv_playlists', [
      jsonEncode(playlist.toJson()),
    ]);
    ingest('vod', [
      for (final host in ['hd.cdn.test', 'sd.cdn.test'])
        for (final episode in [1, 2])
          IptvChannel(
            name: 'Show S01E0$episode',
            url: 'https://$host/series/show-s01e0$episode.mp4',
            group: 'Shows',
            duration: -1,
          ),
    ]);

    final whole = await IptvSourceSearch.search(
      const AdvancedSearchSelection(
        imdbId: 'tt2',
        isSeries: true,
        title: 'Show',
      ),
    );
    expect(whole.single.torrents, hasLength(2));
    final selected = whole.single.torrents.last;
    final pin = SeriesSource(
      torrentHash: '',
      torrentName: selected.name,
      debridService: SeriesSource.iptvDirectService,
      debridTorrentId: '',
      boundAt: 1,
      iptvPlaylistId: selected.iptvPlaylistId,
      iptvCatalogType: selected.iptvCatalogType,
      iptvEntryKey: selected.iptvEntryKey,
    );

    final episode = await IptvSourceSearch.resolvePinned(
      pin,
      title: 'Show',
      season: 1,
      episode: 2,
    );
    expect(episode?.directUrl, contains('sd.cdn.test'));
  });

  test('pinned Xtream ID survives a provider title rename', () async {
    ingest('vod', [
      IptvChannel(
        name: 'Dune (2021)',
        url: 'https://panel.test/movie/user/secret/42.mp4',
        contentType: 'vod',
        attributes: const {'stream_id': '42'},
      ),
    ]);
    final selected = (await IptvSourceSearch.search(
      movie,
    )).single.torrents.single;
    final pin = SeriesSource(
      torrentHash: '',
      torrentName: selected.name,
      debridService: SeriesSource.iptvDirectService,
      debridTorrentId: '',
      boundAt: 1,
      iptvPlaylistId: selected.iptvPlaylistId,
      iptvCatalogType: selected.iptvCatalogType,
      iptvEntryKey: selected.iptvEntryKey,
    );
    ingest('vod', [
      IptvChannel(
        name: 'Provider renamed this row completely',
        url: 'https://panel.test/movie/user/secret/42.mp4',
        contentType: 'vod',
        attributes: const {'stream_id': '42'},
      ),
    ]);

    final refreshed = await IptvSourceSearch.resolvePinned(
      pin,
      title: 'Dune',
      year: '2021',
    );
    expect(refreshed?.iptvEntryKey, 'vod:42');
    expect(refreshed?.directUrl, endsWith('/42.mp4'));
  });

  test(
    'validated IPTV source auto-pins and a switch replaces movie pin',
    () async {
      ingest('vod', [
        for (final id in ['1', '2'])
          IptvChannel(
            name: 'Dune (2021)',
            url: 'https://panel.test/movie/user/secret/$id.mp4',
            contentType: 'vod',
            attributes: {'stream_id': id},
          ),
      ]);
      final sources = (await IptvSourceSearch.search(movie)).single.torrents;
      final commit = TorrentPlaybackService.validatedSourceCommitterForTesting(
        SeriesSource.iptvDirectService,
        const PlaybackMeta(imdbId: 'tt1', contentType: 'movie', title: 'Dune'),
      );
      await commit(sources.first);
      await commit(sources.last);
      final stored = await SeriesSourceService.getSources('tt1');
      expect(stored, hasLength(1));
      expect(stored.single.isIptvDirect, isTrue);
      expect(stored.single.iptvEntryKey, 'vod:2');
      expect(stored.single.toJson().toString(), isNot(contains('/movie/')));
    },
  );

  test(
    'torrent committed after IPTV uses the configured debrid provider',
    () async {
      ingest('vod', [
        IptvChannel(
          name: 'Dune (2021)',
          url: 'https://panel.test/movie/user/secret/1.mp4',
          contentType: 'vod',
          attributes: const {'stream_id': '1'},
        ),
      ]);
      final iptv = (await IptvSourceSearch.search(
        movie,
      )).single.torrents.single;
      await StorageService.saveApiKey('rd-key');
      await StorageService.setDefaultTorrentProvider('debrid');
      final commit = TorrentPlaybackService.validatedSourceCommitterForTesting(
        SeriesSource.iptvDirectService,
        const PlaybackMeta(imdbId: 'tt1', contentType: 'movie', title: 'Dune'),
      );
      await commit(iptv);
      await commit(
        Torrent(
          rowid: 0,
          infohash: '0123456789abcdef0123456789abcdef01234567',
          name: 'Dune.2021.1080p',
          sizeBytes: 1,
          createdUnix: 0,
          seeders: 1,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'engine:test',
        ),
      );

      final stored = (await SeriesSourceService.getSources('tt1')).single;
      expect(stored.torrentHash, '0123456789abcdef0123456789abcdef01234567');
      expect(stored.debridService, 'rd');
    },
  );

  test(
    'series resolves only the requested episode without fetching catalogs',
    () async {
      ingest('series', [
        IptvChannel(
          name: 'Show',
          url: '',
          contentType: 'series',
          attributes: {'series_id': '42'},
        ),
      ]);
      final requests = <Uri>[];
      final result = await http.runWithClient(
        () => IptvSourceSearch.search(
          const AdvancedSearchSelection(
            imdbId: 'tt2',
            isSeries: true,
            title: 'Show',
            season: 2,
            episode: 3,
          ),
        ),
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'episodes': {
                '2': [
                  {
                    'id': 'wrong',
                    'episode_num': 2,
                    'container_extension': 'mp4',
                  },
                  {
                    'id': 'right',
                    'episode_num': 3,
                    'container_extension': 'mkv',
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      expect(requests.single.queryParameters['action'], 'get_series_info');
      expect(
        result.single.torrents.single.directUrl,
        endsWith('/series/user/secret/right.mkv'),
      );
      expect(result.single.torrents.single.episodeIdentifier, 'S2E3');
    },
  );

  test('canceled searches emit no playlist results', () async {
    final emitted = <IptvSourceResult>[];
    expect(
      await IptvSourceSearch.search(
        movie,
        shouldContinue: () => false,
        onResult: emitted.add,
      ),
      isEmpty,
    );
    expect(emitted, isEmpty);
  });

  test('multiple movie streams survive source deduplication', () async {
    ingest('vod', [
      for (final id in ['1', '2'])
        IptvChannel(
          name: 'Dune (2021)',
          url: 'https://panel.test/movie/$id.mp4',
          contentType: 'vod',
        ),
    ]);
    final sources = (await IptvSourceSearch.search(movie)).single.torrents;
    expect(SourcePriority.orderAndDedupe(sources, []), hasLength(2));
    expect(sources.every((s) => !s.hasRealInfoHash), isTrue);
    final repeated = (await IptvSourceSearch.search(movie)).single.torrents;
    expect(repeated.map((s) => s.infohash), sources.map((s) => s.infohash));
  });

  test(
    'failed series entry retains earlier matches and checks later entries',
    () async {
      ingest('series', [
        for (final id in ['101', '102', '103', '104', '105'])
          IptvChannel(
            name: 'Show',
            url: 'series:$id',
            contentType: 'series',
            attributes: {'series_id': id},
          ),
      ]);
      final requests = <String>[];
      final results = await http.runWithClient(
        () => IptvSourceSearch.search(
          const AdvancedSearchSelection(
            imdbId: 'tt2',
            isSeries: true,
            title: 'Show',
            season: 1,
            episode: 1,
          ),
        ),
        () => MockClient((request) async {
          final id = request.url.queryParameters['series_id']!;
          requests.add(id);
          if (id == '102') return http.Response('{}', 403);
          return http.Response(
            jsonEncode({
              'episodes': {
                '1': [
                  {'id': id, 'episode_num': 1},
                ],
              },
            }),
            200,
          );
        }),
      );
      expect(requests, containsAll(['101', '102', '103', '104', '105']));
      expect(results.single.torrents, hasLength(4));
      expect(
        SourcePriority.orderAndDedupe(results.single.torrents, []),
        hasLength(4),
      );
      expect(results.single.message, contains('Some episode lookups failed'));
    },
  );

  test(
    'cached movies produce direct playable URLs with headers and safe source identity',
    () async {
      ingest('vod', [
        IptvChannel(
          name: '4K-MRVL - Dune (2021) 1080p',
          url: 'https://panel.test/movie/user/secret/1.mp4',
          contentType: 'vod',
          httpHeaders: {'Referer': 'https://panel.test/'},
        ),
        IptvChannel(
          name: 'Dune (1984)',
          url: 'https://panel.test/wrong.mp4',
          contentType: 'vod',
        ),
      ]);
      final result = await IptvSourceSearch.search(movie);
      final source = result.single.torrents.single;
      expect(source.streamType, StreamType.directUrl);
      expect(source.httpHeaders!['Referer'], 'https://panel.test/');
      expect(source.source, 'iptv:playlist-a');
      expect(SourcePriority.keyForSource(source.source), source.source);
      await IptvSourceSearch.authorize(source);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('iptv_playlists', []);
      await expectLater(IptvSourceSearch.authorize(source), throwsStateError);
      expect(
        await TorrentPlaybackService.resolveRecoverySource(
          source,
          provider: null,
        ),
        isNull,
      );
      await expectLater(
        IptvSourceSearch.authorize(Torrent.fromJson(source.toJson())),
        throwsStateError,
      );
    },
  );
}
