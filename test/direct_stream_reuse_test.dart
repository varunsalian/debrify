import 'dart:convert';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/resolved_playback_link_cache.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent stream({
  String group = 'group-A',
  String profile = '1080p',
  int index = 0,
  String url = 'https://cdn.test/episode.mp4',
  String addon = 'addon-config',
}) => Torrent(
  rowid: 0,
  infohash: '',
  name: 'Show S01E01',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: StreamType.directUrl,
  directUrl: url,
  stremioAddonId: 'test',
  stremioAddonKey: addon,
  stremioStreamKey: profile,
  stremioBingeGroup: group,
  stremioStreamIndex: index,
  stremioVideoId: 'tt123:1:1',
  httpHeaders: const {
    'Authorization': 'Bearer secret',
    'Referer': 'https://addon.test/',
  },
);

SeriesSource pin({
  String group = 'group-A',
  String profile = '1080p',
  int index = 0,
  String addon = 'addon-config',
}) => SeriesSource(
  torrentHash: '',
  torrentName: 'Show',
  debridService: SeriesSource.addonDirectService,
  debridTorrentId: '',
  boundAt: 1,
  addonId: 'test',
  addonKey: addon,
  streamKey: profile,
  bingeGroup: group,
  streamIndex: index,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'direct-reuse-test');
  });
  tearDown(() {
    StreamUrlValidator.clientFactory = http.Client.new;
  });

  test(
    'next episode queries the pinned addon and caches the actual episode identity',
    () async {
      final addon = StremioAddon(
        id: 'test',
        name: 'Test',
        manifestUrl: 'https://addon.test/manifest.json',
        baseUrl: 'https://addon.test',
        types: const ['series'],
        resources: const ['stream'],
      );
      SharedPreferences.setMockInitialValues({
        'stremio_addons_v1': jsonEncode([addon.toJson()]),
      });
      final service = StremioService.instance;
      service.invalidateCache();
      final requested = <String>[];
      service.debugStreamHttpClientFactory = () => MockClient((request) async {
        requested.add(Uri.decodeComponent(request.url.path));
        return http.Response(
          jsonEncode({
            'streams': [
              {
                'url': 'https://cdn.test/wrong',
                'name': '1080p',
                'behaviorHints': {'bingeGroup': 'other'},
              },
              {
                'url': 'https://cdn.test/episode2',
                'name': 'new label',
                'behaviorHints': {
                  'bingeGroup': 'group-A',
                  'proxyHeaders': {
                    'request': {'Authorization': 'episode-2'},
                  },
                },
              },
            ],
          }),
          200,
        );
      });
      addTearDown(() {
        service.debugStreamHttpClientFactory = null;
        service.invalidateCache();
      });
      await SeriesSourceService.setSources('tt123', [
        pin(addon: addon.sourceBindingKey),
      ]);
      const launch = PlaybackMeta(
        imdbId: 'tt123',
        contentType: 'series',
        season: 1,
        episode: 1,
      );
      final fetcher = TorrentPlaybackService.seriesFetcherFor(meta: launch)!;
      final candidate = await fetcher.pinnedDirectCandidates!(1, 2).first;
      expect(requested, ['/stream/series/tt123:1:2.json']);
      expect(candidate.directUrl, 'https://cdn.test/episode2');
      expect(candidate.httpHeaders?['Authorization'], 'episode-2');
      await TorrentPlaybackService.validatedSourceCommitterForTesting(
        SeriesSource.addonDirectService,
        launch,
      )(candidate);
      final saved = (await SeriesSourceService.getSources('tt123')).first;
      expect(
        await ResolvedPlaybackLinkCache.get(
          id: 'tt123',
          type: 'series',
          season: 1,
          episode: 1,
          pin: saved,
        ),
        isNull,
      );
      expect(
        (await ResolvedPlaybackLinkCache.get(
          id: 'tt123',
          type: 'series',
          season: 1,
          episode: 2,
          pin: saved,
        ))?.directUrl,
        'https://cdn.test/episode2',
      );
    },
  );

  test(
    'group wins despite changing labels and position; missing group is a miss',
    () {
      final other = stream(group: 'group-B');
      final wanted = stream(profile: 'new-title', index: 7);
      expect(
        StremioService.selectPinnedDirectStream(
          [other, wanted],
          streamKey: '1080p',
          streamIndex: 0,
          bingeGroup: 'group-A',
        ),
        same(wanted),
      );
      expect(
        StremioService.selectPinnedDirectStream(
          [other],
          streamKey: '1080p',
          streamIndex: 0,
          bingeGroup: 'group-A',
        ),
        isNull,
      );
    },
  );

  test(
    'cache isolates episode, addon, profile, group and index and encrypts headers',
    () async {
      await ResolvedPlaybackLinkCache.save(
        id: 'tt123',
        type: 'series',
        season: 1,
        episode: 1,
        source: stream(),
      );
      Future<Torrent?> read(SeriesSource source, {int episode = 1}) =>
          ResolvedPlaybackLinkCache.get(
            id: 'tt123',
            type: 'series',
            season: 1,
            episode: episode,
            pin: source,
          );
      expect(
        (await read(pin()))?.httpHeaders?['Authorization'],
        'Bearer secret',
      );
      expect(await read(pin(), episode: 2), isNull);
      expect(await read(pin(addon: 'other-config')), isNull);
      expect(await read(pin(profile: '4k')), isNull);
      expect(await read(pin(group: 'group-B')), isNull);
      expect(await read(pin(index: 7)), isNull);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(ResolvedPlaybackLinkCache.preferenceKey)!;
      expect(raw, startsWith(SecretVault.prefix));
      expect(raw, isNot(contains('Bearer secret')));
      expect(
        ProfilePreferencePortability.allowsKey(
          ResolvedPlaybackLinkCache.preferenceKey,
        ),
        isFalse,
      );
      await ResolvedPlaybackLinkCache.remove(
        id: 'tt123',
        type: 'series',
        season: 1,
        episode: 1,
        pin: pin(),
      );
      expect(await read(pin()), isNull);
    },
  );

  test(
    'known expiry is case insensitive and expired URLs are never saved',
    () async {
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: 5));
      final url =
          'https://cdn.test/a?Expires=${expires.millisecondsSinceEpoch ~/ 1000}';
      expect(
        ResolvedPlaybackLinkCache.expiresAt(url, now).difference(now),
        lessThan(const Duration(minutes: 6)),
      );
      await ResolvedPlaybackLinkCache.save(
        id: 'tt123',
        type: 'series',
        season: 1,
        episode: 1,
        source: stream(url: 'https://cdn.test/a?Expires=1000'),
      );
      expect(
        await ResolvedPlaybackLinkCache.get(
          id: 'tt123',
          type: 'series',
          season: 1,
          episode: 1,
          pin: pin(),
        ),
        isNull,
      );
    },
  );

  test(
    'resuming an unchanged URL does not extend its cached lifetime',
    () async {
      await ResolvedPlaybackLinkCache.save(
        id: 'tt123',
        type: 'series',
        season: 1,
        episode: 1,
        source: stream(),
      );
      final prefs = await SharedPreferences.getInstance();
      Future<Object?> expiry() async {
        final value =
            jsonDecode(
                  (await SecretVault.open(
                    prefs.getString(ResolvedPlaybackLinkCache.preferenceKey),
                  ))!,
                )
                as Map;
        return (value.values.single as Map)['expires'];
      }

      final before = await expiry();
      await ResolvedPlaybackLinkCache.save(
        id: 'tt123',
        type: 'series',
        season: 1,
        episode: 1,
        source: stream(),
      );
      expect(await expiry(), before);
    },
  );

  test('series preflight sends the selected stream credentials', () async {
    var requests = 0;
    StreamUrlValidator.clientFactory = () => MockClient((request) async {
      requests++;
      expect(request.headers['authorization'], 'Bearer secret');
      expect(request.headers['referer'], 'https://addon.test/');
      return http.Response('', 200, headers: {'content-length': '100000000'});
    });
    final fetcher = TorrentPlaybackService.seriesFetcherFor(
      meta: const PlaybackMeta(
        imdbId: 'tt123',
        contentType: 'series',
        season: 1,
        episode: 1,
      ),
    );
    expect(await fetcher!.allowsCandidate(stream()), isTrue);
    expect(requests, 1);
  });

  for (final target in [
    'https://other.test/a',
    'http://cdn.test/a',
    'https://cdn.test:8443/a',
  ]) {
    test(
      'preflight strips addon credentials when redirected to $target',
      () async {
        var requests = 0;
        StreamUrlValidator.clientFactory = () => MockClient((request) async {
          requests++;
          if (requests == 1) {
            expect(request.headers['authorization'], 'Bearer secret');
            return http.Response(
              '',
              302,
              headers: {'location': '/same-origin'},
            );
          }
          if (requests == 2) {
            expect(request.headers['authorization'], 'Bearer secret');
            return http.Response('', 302, headers: {'location': target});
          }
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response(
            '',
            200,
            headers: {'content-length': '100000000'},
          );
        });
        expect(
          await StreamUrlValidator.isPlayableVideoUrl(
            'https://cdn.test/start',
            headers: {
              'Authorization': 'Bearer secret',
              'Cookie': 'session=secret',
            },
          ),
          isTrue,
        );
        expect(requests, 3);
      },
    );
  }
}
