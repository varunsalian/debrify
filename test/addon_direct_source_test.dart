import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent direct({
  required String url,
  required String key,
  required int index,
}) => Torrent(
  rowid: 0,
  infohash: 'url:$index',
  name: 'Direct $index',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio:test',
  streamType: StreamType.directUrl,
  directUrl: url,
  hasRealInfoHash: false,
  stremioAddonId: 'test.addon',
  stremioAddonKey: 'addon-key',
  stremioStreamKey: key,
  stremioStreamIndex: index,
);

Torrent torrentSource({required String name, required String hash}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 1,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio:test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('addon binding identity is opaque and configuration-specific', () {
    final addon = StremioAddon(
      id: 'test.addon',
      name: 'Test',
      manifestUrl: 'https://addon.test/secret-token/manifest.json',
      baseUrl: 'https://addon.test/secret-token',
    );
    final other = StremioAddon(
      id: 'test.addon',
      name: 'Test',
      manifestUrl: 'https://addon.test/other-token/manifest.json',
      baseUrl: 'https://addon.test/other-token',
    );

    expect(addon.sourceBindingKey, hasLength(64));
    expect(addon.sourceBindingKey, isNot(contains('secret-token')));
    expect(addon.sourceBindingKey, isNot(other.sourceBindingKey));
  });

  test('binding identity survives a response-position change', () {
    // The addon reorders results between searches (cache state, seeders), so
    // the same file comes back at a new index. Including that index in the
    // identity made every replay append a duplicate pin instead of promoting
    // the existing one.
    SeriesSource at(int index) => SeriesSource(
      torrentHash: '',
      torrentName: 'Show S01E02 1080p',
      debridService: SeriesSource.addonDirectService,
      debridTorrentId: '',
      boundAt: 1,
      addonId: 'test.addon',
      addonKey: 'opaque-addon-key',
      streamKey: 'quality-profile',
      streamIndex: index,
    );

    expect(at(2).bindingKey, at(9).bindingKey);
    expect(
      at(2).matchesAddonDirect(
        candidateAddonKey: 'opaque-addon-key',
        candidateStreamKey: 'quality-profile',
      ),
      isTrue,
    );
    // A different profile is still a different source.
    expect(
      at(2).matchesAddonDirect(
        candidateAddonKey: 'opaque-addon-key',
        candidateStreamKey: 'other-profile',
      ),
      isFalse,
    );
    // The index is still STORED — resolution needs it to pick between streams
    // sharing a profile (see selectPinnedDirectStream).
    expect(at(9).streamIndex, 9);
  });

  test('stream profile survives URL, episode, hash, and size changes', () {
    final first = StremioStream.fromJson({
      'name': 'Provider 1080p',
      'description': 'Show.S01E01.1080p.WEB-DL 1.4 GB',
      'url': 'https://signed.test/old-token',
      'behaviorHints': {
        'filename': 'Show.S01E01.1080p.WEB-DL.mkv',
        'bingeGroup': 'provider|${'a' * 40}',
      },
    }, 'Test');
    final next = StremioStream.fromJson({
      'name': 'Provider 1080p',
      'description': 'Show.S01E02.1080p.WEB-DL 1.6 GB',
      'url': 'https://signed.test/fresh-token',
      'behaviorHints': {
        'filename': 'Show.S01E02.1080p.WEB-DL.mkv',
        'bingeGroup': 'provider|${'b' * 40}',
      },
    }, 'Test');

    expect(next.streamKey, first.streamKey);
  });

  test('conversion carries refresh provenance without changing direct URL', () {
    final stream = StremioStream.fromJson(
      {'name': 'Provider 4K', 'url': 'https://signed.test/current'},
      'Test',
      addonId: 'test.addon',
      addonKey: 'opaque',
      streamIndex: 3,
    );

    final converted = StremioService.instance.convertStreamsForTesting([
      stream,
    ], preserveOrder: true).single;

    expect(converted.directUrl, 'https://signed.test/current');
    expect(converted.stremioAddonId, 'test.addon');
    expect(converted.stremioAddonKey, 'opaque');
    expect(converted.stremioStreamKey, stream.streamKey);
    expect(converted.stremioStreamIndex, 3);
  });

  test('addon-direct source persists provenance but no playback URL', () async {
    const source = SeriesSource(
      torrentHash: '',
      torrentName: 'Show S01E01 1080p',
      debridService: SeriesSource.addonDirectService,
      debridTorrentId: '',
      boundAt: 1,
      addonId: 'test.addon',
      addonKey: 'opaque-addon-key',
      streamKey: 'quality-profile',
      streamIndex: 2,
    );
    final json = source.toJson();
    final restored = SeriesSource.fromJson(json);

    expect(restored.isAddonDirect, isTrue);
    expect(restored.bindingKey, source.bindingKey);
    expect(json.toString(), isNot(contains('https://')));

    await SeriesSourceService.addSource('tt1234567', source);
    await SeriesSourceService.addSource(
      'tt1234567',
      SeriesSource.fromJson({...json, 'torrentName': 'Updated label'}),
    );
    final stored = await SeriesSourceService.getSources('tt1234567');
    expect(stored, hasLength(1));
    expect(stored.single.torrentName, 'Updated label');
  });

  testWidgets('direct binding stores the refresh descriptor for a movie', (
    tester,
  ) async {
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
    final torrent = direct(
      url: 'https://signed.test/must-not-be-stored',
      key: 'profile',
      index: 5,
    );

    final pinned = await TorrentPlaybackService.bindDirectSource(
      context,
      torrent,
      imdbId: 'tt7654321',
      isMovie: true,
    );
    final stored = await SeriesSourceService.getSources('tt7654321');

    expect(pinned, isTrue);
    expect(stored.single.isAddonDirect, isTrue);
    expect(stored.single.streamIndex, 5);
    expect(
      stored.single.toJson().toString(),
      isNot(contains(torrent.directUrl!)),
    );
  });

  test(
    'validated movie direct source auto-pins and successful switch replaces it',
    () async {
      const imdbId = 'tt1000001';
      await SeriesSourceService.setSources(imdbId, [
        const SeriesSource(
          torrentHash: 'ffffffffffffffffffffffffffffffffffffffff',
          torrentName: 'Previous movie pin',
          debridService: 'rd',
          debridTorrentId: '',
          boundAt: 1,
        ),
      ]);
      final first = direct(
        url: 'https://signed.test/movie-first',
        key: 'movie-first',
        index: 1,
      );
      final switched = direct(
        url: 'https://signed.test/movie-switched',
        key: 'movie-switched',
        index: 2,
      );
      final commit = TorrentPlaybackService.validatedSourceCommitterForTesting(
        'rd',
        const PlaybackMeta(imdbId: imdbId, contentType: 'movie'),
      );

      // Deliberately overlap callbacks: player commit notifications are
      // fire-and-forget, but the latest successful movie switch must win.
      final firstWrite = commit(first);
      final switchedWrite = commit(switched);
      await Future.wait([firstWrite, switchedWrite]);

      final stored = await SeriesSourceService.getSources(imdbId);
      expect(stored, hasLength(1));
      expect(stored.single.isAddonDirect, isTrue);
      expect(stored.single.streamKey, 'movie-switched');
      expect(stored.single.streamIndex, 2);
      expect(stored.single.toJson().toString(), isNot(contains('signed.test')));

      final torrent = torrentSource(
        name: 'Movie.2026.2160p',
        hash: 'cccccccccccccccccccccccccccccccccccccccc',
      );
      await commit(torrent);
      final torrentStored = await SeriesSourceService.getSources(imdbId);
      expect(torrentStored, hasLength(1));
      expect(torrentStored.single.torrentHash, torrent.infohash);
      expect(torrentStored.single.isAddonDirect, isFalse);
    },
  );

  test(
    'validated series switches promote new source without replacing old pins',
    () async {
      const imdbId = 'tt1000002';
      const previous = SeriesSource(
        torrentHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        torrentName: 'Previous series pin',
        debridService: 'rd',
        debridTorrentId: '',
        boundAt: 1,
      );
      await SeriesSourceService.setSources(imdbId, [previous]);
      final first = direct(
        url: 'https://signed.test/series-first',
        key: 'series-first',
        index: 1,
      );
      final torrent = torrentSource(
        name: 'Show.S01E01.1080p',
        hash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      final switched = direct(
        url: 'https://signed.test/series-switched',
        key: 'series-switched',
        index: 3,
      );
      final commit = TorrentPlaybackService.validatedSourceCommitterForTesting(
        'rd',
        const PlaybackMeta(
          imdbId: imdbId,
          contentType: 'series',
          season: 1,
          episode: 1,
        ),
      );

      await commit(first);
      await commit(torrent);
      await commit(switched);
      await commit(switched);

      final stored = await SeriesSourceService.getSources(imdbId);
      expect(stored, hasLength(4));
      expect(stored[0].streamKey, 'series-switched');
      expect(stored[1].torrentHash, torrent.infohash);
      expect(stored[2].streamKey, 'series-first');
      expect(stored[3].bindingKey, previous.bindingKey);
    },
  );

  test('unrefreshable direct source is never auto-pinned', () async {
    const imdbId = 'tt1000003';
    final unrefreshable = direct(
      url: 'https://signed.test/no-stable-profile',
      key: '',
      index: 0,
    );
    final commit = TorrentPlaybackService.validatedSourceCommitterForTesting(
      'rd',
      const PlaybackMeta(imdbId: imdbId, contentType: 'movie'),
    );

    await commit(unrefreshable);

    expect(await SeriesSourceService.getSources(imdbId), isEmpty);

    final refreshable = direct(
      url: 'https://signed.test/valid-later-switch',
      key: 'valid-later-switch',
      index: 1,
    );
    await commit(refreshable);
    final stored = await SeriesSourceService.getSources(imdbId);
    expect(stored, hasLength(1));
    expect(stored.single.streamKey, 'valid-later-switch');
  });

  test('fresh direct matcher prefers profile then original response index', () {
    final sources = [
      direct(url: 'https://fresh.test/a', key: 'other', index: 0),
      direct(url: 'https://fresh.test/b', key: 'wanted', index: 4),
      direct(url: 'https://fresh.test/c', key: 'wanted', index: 7),
    ];

    expect(
      StremioService.selectPinnedDirectStream(
        sources,
        streamKey: 'wanted',
        streamIndex: 7,
      )?.directUrl,
      'https://fresh.test/c',
    );
    expect(
      StremioService.selectPinnedDirectStream(
        sources,
        streamKey: 'changed-for-next-episode',
        streamIndex: 4,
      )?.directUrl,
      'https://fresh.test/b',
    );
  });

  test(
    'pinned resolver requests the current episode and returns a fresh URL',
    () async {
      late Uri requested;
      final service = StremioService.instance;
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'streams': [
              {
                'name': 'Provider 720p',
                'description': 'Show.S02E03.720p.WEB-DL',
                'url': 'http://cdn.test/720p-fresh',
              },
              {
                'name': 'Provider 1080p',
                'description': 'Show.S02E03.1080p.WEB-DL 1.8 GB',
                'url': 'http://cdn.test/1080p-fresh',
                'behaviorHints': {
                  'filename': 'Show.S02E03.1080p.WEB-DL.mkv',
                  'bingeGroup': 'provider|${'c' * 40}',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(() => service.debugStreamHttpClientFactory = null);

      const baseUrl = 'https://addon.test/configured';
      final addon = StremioAddon(
        id: 'test.addon',
        name: 'Test',
        manifestUrl: '$baseUrl/manifest.json',
        baseUrl: baseUrl,
        types: const ['movie', 'series'],
        resources: const ['stream'],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      final pinned = StremioStream.fromJson({
        'name': 'Provider 1080p',
        'description': 'Show.S01E01.1080p.WEB-DL 1.4 GB',
        'url': 'http://cdn.test/expired',
        'behaviorHints': {
          'filename': 'Show.S01E01.1080p.WEB-DL.mkv',
          'bingeGroup': 'provider|${'a' * 40}',
        },
      }, 'Test');

      final fresh = await service.resolvePinnedDirectStream(
        addonId: addon.id,
        addonKey: addon.sourceBindingKey,
        streamKey: pinned.streamKey!,
        streamIndex: 1,
        type: 'series',
        contentId: 'tt1234567',
        season: 2,
        episode: 3,
      );

      expect(fresh?.directUrl, 'http://cdn.test/1080p-fresh');
      expect(
        Uri.decodeComponent(requested.path),
        '/configured/stream/series/tt1234567:2:3.json',
      );
    },
  );
}
