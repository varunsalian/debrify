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
