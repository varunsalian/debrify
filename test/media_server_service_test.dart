import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/utils/filter_ladder.dart';
import 'package:debrify/utils/torrent_filter_matcher.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ProfileRegistry registry;
  late ConnectionResourceService resources;
  late String admin;
  late String member;
  var unavailable = false;
  var failureStatus = 503;
  Map<String, dynamic> videoMetadata = {};
  List<Map<String, dynamic>> audioStreams = [];
  var episodeNumber = 1;
  var requestCount = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    temp = await Directory.systemTemp.createTemp('media-server-test-');
    registry = await ProfileRegistry.open(path: '${temp.path}/profiles.db');
    admin = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    member = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: admin,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(List.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    resources = ConnectionResourceService(registry: registry, cipher: cipher);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: admin, dataGeneration: 1, sessionEpoch: 1),
    );
    unavailable = false;
    failureStatus = 503;
    videoMetadata = {};
    audioStreams = [];
    requestCount = 0;
    episodeNumber = 1;
    MediaServerService.clientFactory = () => MediaServerClient(
      client: MockClient((request) async {
        requestCount++;
        if (unavailable) {
          return http.Response('private server error', failureStatus);
        }
        Object data;
        if (request.url.path.endsWith('AuthenticateByName')) {
          data = {
            'User': {'Id': 'user1'},
            'AccessToken': 'token-secret',
            'ServerId': 'server1',
          };
        } else if (request.url.path.endsWith('System/Info')) {
          return http.Response('Administrator access required', 403);
        } else if (request.url.path.endsWith('System/Info/Public')) {
          data = {'Id': 'server1'};
        } else if (request.url.path.endsWith('Users/user1')) {
          expect(request.headers['X-Emby-Token'], 'token-secret');
          data = {
            'Id': 'user1',
            'Policy': {'IsAdministrator': false},
          };
        } else if (request.url.path.endsWith('/Items')) {
          final movie =
              request.url.queryParameters['IncludeItemTypes'] == 'Movie';
          data = {
            'Items': [
              {
                'Id': movie ? 'movie1' : 'series1',
                'Name': 'Example',
                'Type': movie ? 'Movie' : 'Series',
                'ProviderIds': {'Imdb': 'tt123'},
              },
            ],
          };
        } else if (request.url.path.endsWith('/Episodes')) {
          data = {
            'Items': [
              {
                'Id': 'episode$episodeNumber',
                'Name': 'Episode $episodeNumber',
                'Type': 'Episode',
                'ParentIndexNumber': 1,
                'IndexNumber': episodeNumber,
              },
            ],
          };
        } else if (request.url.path.endsWith('/PlaybackInfo')) {
          data = {
            'MediaSources': [
              for (final height in [1080, 2160])
                {
                  'Id': 'version${episodeNumber}_$height',
                  'SupportsDirectPlay': true,
                  'Protocol': 'File',
                  'Container': 'mkv',
                  'Size': 12345678,
                  'MediaStreams': [
                    ...audioStreams,
                    {
                      'Type': 'Video',
                      'Height': height,
                      'Codec': 'hevc',
                      ...videoMetadata,
                    },
                  ],
                },
            ],
          };
        } else {
          throw StateError('Unexpected endpoint: ${request.url.path}');
        }
        return http.Response(jsonEncode(data), 200);
      }),
    );
  });

  tearDown(() async {
    MediaServerService.clientFactory = MediaServerClient.new;
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    await registry.close();
    await temp.delete(recursive: true);
  });

  Future<ConnectionResource> connect([
    MediaServerKind kind = MediaServerKind.jellyfin,
  ]) async {
    await MediaServerService.connect(
      kind: kind,
      label: 'My ${kind.label}',
      baseUrl: 'https://server.example/base/',
      username: 'user',
      password: 'password-secret',
    );
    final resource = (await MediaServerService.connections()).last;
    // New resources follow the app's default family sharing. Most tests
    // exercise an explicitly unshared connection; the borrower test grants use.
    await resources.revokeGrant(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: member,
      resourceId: resource.id,
    );
    return (await registry.getResource(resource.id))!;
  }

  Future<List<Torrent>> search({bool movie = true, int episode = 1}) async =>
      (await MediaServerService.search(
            id: 'tt123',
            isMovie: movie,
            season: movie ? null : 1,
            episode: movie ? null : episode,
          ))['torrents']
          as List<Torrent>;

  test(
    'both servers store encrypted tokens and expose multiple direct versions',
    () async {
      for (final kind in MediaServerKind.values) {
        await connect(kind);
      }
      final connections = await MediaServerService.connections();
      expect(connections, hasLength(2));
      expect(
        jsonEncode(connections.map((r) => r.publicConfig).toList()),
        isNot(contains('token-secret')),
      );
      final records = await ProfileCollectionResourceFacade.read(
        types: MediaServerService.types,
        feature: ProfileFeature.cloud,
      );
      expect(records.map((r) => r['kind']).toSet(), {'jellyfin', 'emby'});
      expect(jsonEncode(records), isNot(contains('password-secret')));
      final sources = await search();
      expect(sources, hasLength(4));
      for (final source in sources) {
        expect(
          source.directUrl,
          startsWith('https://server.example/base/Videos/'),
        );
        expect(source.directUrl, isNot(contains('token-secret')));
        expect(source.httpHeaders!['X-Emby-Token'], 'token-secret');
        final args = TorrentPlaybackService.playerArgsForTesting(
          null,
          httpHeaders: source.httpHeaders,
        );
        expect(args.disableExternalPlayer, isTrue);
        expect(args.httpHeaders, source.httpHeaders);
        await DirectSourceAuthorization.authorize(source);
      }
    },
  );

  test(
    'movie pin persists no secret and re-resolves the selected version',
    () async {
      await connect();
      final source = (await search()).last;
      final pin = MediaServerService.bindingFor(source)!;
      final persisted = jsonEncode(pin.toJson());
      expect(persisted, isNot(contains('token-secret')));
      expect(persisted, isNot(contains('https://')));
      final restored = SeriesSource.fromJson(jsonDecode(persisted));
      final resolved = await MediaServerService.resolvePinned(restored);
      expect(resolved?.directUrl, source.directUrl);
      await DirectSourceAuthorization.authorize(resolved!);
    },
  );

  test(
    'series pin follows the next episode at the selected resolution',
    () async {
      await connect();
      final pin = MediaServerService.bindingFor(
        (await search(movie: false)).last,
      )!;
      episodeNumber = 2;
      final next = await MediaServerService.resolvePinned(
        pin,
        season: 1,
        episode: 2,
      );
      expect(next?.directUrl, contains('/Videos/episode2/stream'));
      expect(next?.name, contains('2160p'));
      expect(next?.episodeIdentifier, 'S01E02');
      expect(MediaServerService.bindingFor(next!)?.bindingKey, pin.bindingKey);
    },
  );

  for (final movie in [false, true]) {
    for (final combined in [false, true]) {
      test(
        'canonical ${movie ? 'movie' : 'episode'} reaches native sources in ${combined ? 'combined' : 'addon-only'} search',
        () async {
          await connect();
          for (final originVideoId in [null, '  ']) {
            final batches = <Torrent>[];
            final result = combined
                ? await TorrentService.searchByImdbWithStremio(
                    'tt123',
                    engineStates: const {},
                    isMovie: movie,
                    season: movie ? null : 1,
                    episode: movie ? null : 1,
                    originVideoId: originVideoId,
                    onBatch: (_, sources) => batches.addAll(sources),
                  )
                : await TorrentService.searchStremioAddonsOnly(
                    imdbId: 'tt123',
                    isMovie: movie,
                    season: movie ? null : 1,
                    episode: movie ? null : 1,
                    originVideoId: originVideoId,
                    onBatch: (_, sources) => batches.addAll(sources),
                  );
            expect(result['torrents'], hasLength(2));
            expect(batches, hasLength(2));
            expect(result['addonStatuses'], hasLength(1));
          }
        },
      );
    }
  }

  test(
    'player source menus list and fetch native movie and episode sources',
    () async {
      final resource = await connect();
      final key = 'mediaserver:${resource.id}';
      final movie = TorrentPlaybackService.movieFetcherFor(
        meta: const PlaybackMeta(imdbId: 'tt123', contentType: 'movie'),
      )!;
      expect((await movie.listAddons!()).map((ref) => ref.id), contains(key));
      expect(await movie.fetchAddonEpisodes!(key, 0, 0), hasLength(2));
      final series = TorrentPlaybackService.seriesFetcherFor(
        meta: const PlaybackMeta(
          imdbId: 'tt123',
          contentType: 'series',
          season: 1,
          episode: 1,
        ),
      )!;
      expect((await series.listAddons!()).map((ref) => ref.id), contains(key));
      expect(await series.fetchAddonEpisodes!(key, 1, 1), hasLength(2));
      expect(await series.fetchAddonPacks!(key, 1), isEmpty);
      unavailable = true;
      expect(await movie.fetchAddonEpisodes!(key, 0, 0), isNull);
    },
  );

  for (final combined in [false, true]) {
    test(
      'custom episode identity excludes native sources in ${combined ? 'combined' : 'addon-only'} search',
      () async {
        await connect();
        final before = requestCount;
        final batches = <Torrent>[];
        final result = combined
            ? await TorrentService.searchByImdbWithStremio(
                'tt123',
                isMovie: false,
                season: 1,
                episode: 1,
                originAddonKey: 'onepace',
                originVideoId: 'RO_1',
                onBatch: (_, sources) => batches.addAll(sources),
              )
            : await TorrentService.searchStremioAddonsOnly(
                imdbId: 'tt123',
                isMovie: false,
                season: 1,
                episode: 1,
                originAddonKey: 'onepace',
                originVideoId: 'RO_1',
                onBatch: (_, sources) => batches.addAll(sources),
              );
        expect(result['torrents'], isEmpty);
        expect(result['addonStatuses'], isEmpty);
        expect(batches, isEmpty);
        expect(requestCount, before);
      },
    );
  }

  test(
    'custom episode source menus neither list nor fetch native providers',
    () async {
      final resource = await connect();
      final key = 'mediaserver:${resource.id}';
      final before = requestCount;
      // Missing custom metadata must not fall back to the canonical episode.
      for (final videoId in ['RO_1', null]) {
        final series = TorrentPlaybackService.seriesFetcherFor(
          meta: PlaybackMeta(
            imdbId: 'tt123',
            contentType: 'series',
            season: 1,
            episode: 1,
            stremioAddonKey: 'onepace',
            stremioCatalogId: 'tt123',
            stremioVideoId: videoId,
          ),
        )!;
        expect(
          (await series.listAddons!()).map((ref) => ref.id),
          isNot(contains(key)),
        );
        expect(await series.fetchAddonEpisodes!(key, 1, 1), isEmpty);
        expect(await series.fetchAddonPacks!(key, 1), isEmpty);
      }
      expect(requestCount, before);
    },
  );

  testWidgets(
    'native downloads are rejected before URL resolution or queueing',
    (tester) async {
      final source = (await tester.runAsync(() async {
        await connect();
        return (await search()).first;
      }))!;
      expect(
        TorrentPlaybackService.supportsDirectStreamDownload(source),
        isFalse,
      );
      final ordinary = Torrent.fromJson({
        ...source.toJson(),
        'source': 'stremio:example',
      });
      expect(
        TorrentPlaybackService.supportsDirectStreamDownload(ordinary),
        isTrue,
      );
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final requestsBefore = requestCount;
      await TorrentPlaybackService.downloadDirectStream(pageContext, source);
      await tester.pump();
      expect(
        find.text('Jellyfin and Emby downloads are not supported yet.'),
        findsOneWidget,
      );
      expect(requestCount, requestsBefore);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'cropped originals retain canonical quality in filters and strict Quick Play',
    () async {
      await connect();
      for (final sample in [
        (1920, 800, QualityTier.fullHd, '1080p'),
        (3840, 1600, QualityTier.ultraHd, '2160p'),
        (1280, 536, QualityTier.hd, '720p'),
      ]) {
        videoMetadata = {'Width': sample.$1, 'Height': sample.$2};
        final sources = await search();
        final filter = TorrentFilterState(qualities: {sample.$3});
        expect(sources.every((s) => s.name.contains(sample.$4)), isTrue);
        expect(TorrentFilterMatcher.apply(sources, filter), sources);
        expect(
          TorrentPlaybackService.orderCandidatesForRules(
            sources,
            rules: QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(relaxFilters: false),
            ladder: FilterLadder(filter),
          ),
          sources,
        );
      }
    },
  );

  test(
    'server HDR metadata reaches shared filters and strict Quick Play',
    () async {
      await connect();
      final sdr = TorrentFilterState(dynamicRanges: {DynamicRange.sdr});
      for (final metadata in <Map<String, dynamic>>[
        {'VideoRange': 'HDR'},
        {'VideoRangeType': 'HDR10'},
        {'VideoRangeType': 'DOVIWithHDR10'},
        {'VideoRangeType': 'HLG'},
        {'ExtendedVideoType': 'Hdr10Plus'},
        {'DvProfile': 5},
        {'Hdr10PlusPresentFlag': true},
        {'ColorTransfer': 'smpte2084'},
        {'ColorTransfer': 'arib-std-b67'},
      ]) {
        videoMetadata = metadata;
        final sources = await search();
        expect(sources, isNotEmpty);
        expect(
          TorrentFilterMatcher.apply(sources, sdr),
          isEmpty,
          reason: '$metadata',
        );
        expect(
          TorrentPlaybackService.orderCandidatesForRules(
            sources,
            rules: QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(relaxFilters: false),
            ladder: FilterLadder(sdr),
          ),
          isEmpty,
          reason: '$metadata',
        );
      }
      videoMetadata = {
        'VideoRange': 'SDR',
        'BitDepth': 10,
        'ColorTransfer': 'bt709',
      };
      final sources = await search();
      expect(TorrentFilterMatcher.apply(sources, sdr), sources);
    },
  );

  for (final (status, mode) in [
    (401, QuickPlaySourceMode.addonsOnly),
    (503, QuickPlaySourceMode.addonsOnly),
    (401, QuickPlaySourceMode.together),
    (503, QuickPlaySourceMode.together),
  ]) {
    testWidgets(
      'Quick Play $mode retries native HTTP $status and reports the server error',
      (tester) async {
        await tester.runAsync(() async {
          await connect();
          await StorageService.setQuickPlayRules(
            QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(sourceMode: mode),
            isMovie: true,
          );
        });
        late BuildContext pageContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  pageContext = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        unavailable = true;
        failureStatus = status;
        final before = requestCount;
        await tester.runAsync(
          () => TorrentPlaybackService.playFromSelection(
            pageContext,
            imdbId: 'tt123',
            isMovie: true,
            skipBoundSources: true,
            meta: const PlaybackMeta(
              imdbId: 'tt123',
              contentType: 'movie',
              title: 'Example',
            ),
          ),
        );
        await tester.pump();
        expect(requestCount - before, 2);
        expect(
          find.textContaining(
            status == 401 ? 'Reconnect this server' : 'HTTP 503',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Add a debrid provider'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'URL-only searches exclude native sources and do not contact the server',
    () async {
      await connect();
      final before = requestCount;
      final result = await TorrentService.searchByImdbWithStremio(
        'tt123',
        isMovie: true,
        engineStates: const {},
        includeMediaServers: false,
      );
      expect(result['torrents'], isEmpty);
      expect(requestCount, before);
      final enabled = await TorrentService.searchByImdbWithStremio(
        'tt123',
        isMovie: true,
        engineStates: const {},
      );
      expect(enabled['torrents'], hasLength(2));
      final tvCode = File(
        'lib/screens/stremio_tv/stremio_tv_screen.dart',
      ).readAsStringSync();
      final calls = RegExp(
        r'searchByImdbWithStremio\([\s\S]*?\);',
      ).allMatches(tvCode).toList();
      expect(calls, hasLength(2));
      expect(
        calls.every(
          (call) => call.group(0)!.contains('includeMediaServers: false'),
        ),
        isTrue,
      );
    },
  );

  test(
    'server audio tracks govern both filters without title or English guesses',
    () async {
      await connect();
      List<Torrent> strict(List<Torrent> sources, AudioLanguage language) =>
          TorrentPlaybackService.orderCandidatesForRules(
            sources,
            rules: QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(relaxFilters: false),
            ladder: FilterLadder(TorrentFilterState(languages: {language})),
          );
      for (final language in ['spa', 'es', 'es-MX']) {
        audioStreams = [
          {'Type': 'Audio', 'Language': language},
          {'Type': 'Subtitle', 'Language': 'eng'},
          {'Type': 'Audio', 'Language': 'eng', 'IsExternal': true},
        ];
        final sources = await search();
        expect(
          TorrentFilterMatcher.apply(
            sources,
            TorrentFilterState(languages: {AudioLanguage.spanish}),
          ),
          sources,
        );
        expect(strict(sources, AudioLanguage.spanish), sources);
        expect(strict(sources, AudioLanguage.english), isEmpty);
        expect(sources.first.name, contains('spanish'));
        expect(Torrent.fromJson(sources.first.toJson()).audioLanguages, [
          language.toLowerCase(),
        ]);
      }
      audioStreams = [
        {'Type': 'Audio', 'Language': 'spa'},
        {'Type': 'Audio', 'Language': 'eng'},
      ];
      final bilingual = await search();
      for (final language in [
        AudioLanguage.spanish,
        AudioLanguage.english,
        AudioLanguage.multiAudio,
      ]) {
        expect(
          TorrentFilterMatcher.apply(
            bilingual,
            TorrentFilterState(languages: {language}),
          ),
          bilingual,
        );
        expect(strict(bilingual, language), bilingual);
      }
      expect(strict(bilingual, AudioLanguage.french), isEmpty);
      for (final unknown in [
        <String, dynamic>{},
        {'Language': 'und'},
        {'Language': 'swe'},
      ]) {
        audioStreams = [
          {'Type': 'Audio', ...unknown},
        ];
        expect(strict(await search(), AudioLanguage.english), isEmpty);
      }
    },
  );

  for (final movie in [true, false]) {
    test(
      'synced ${movie ? 'movie' : 'series'} pin resolves after JSON reordering',
      () async {
        final resource = await connect();
        final source = (await search(movie: movie)).last;
        final pin = MediaServerService.bindingFor(source)!;
        final decoded = jsonDecode(pin.debridTorrentId) as Map<String, dynamic>;
        final reordered = SeriesSource.fromJson({
          ...pin.toJson(),
          'debridTorrentId': jsonEncode({
            for (final key in decoded.keys.toList().reversed) key: decoded[key],
          }),
        });
        expect(reordered.bindingKey, pin.bindingKey);
        final maps = WebDavSyncIdentityMaps(
          circleToLocalProfiles: {'circle-profile': admin},
          circleToLocalResources: {'circle-server': resource.id},
        );
        final synced = SeriesSource.fromJson(
          Map<String, dynamic>.from(
            maps.toLocal(maps.toWire(reordered.toJson())) as Map,
          ),
        );
        if (!movie) episodeNumber = 2;
        final resolved = await MediaServerService.resolvePinned(
          synced,
          season: movie ? null : 1,
          episode: movie ? null : 2,
        );
        expect(resolved, isNotNull);
        expect(
          MediaServerService.bindingFor(resolved!)!.bindingKey,
          pin.bindingKey,
        );
        await DirectSourceAuthorization.authorize(resolved);
      },
    );
  }

  for (final change in ['disabled', 'reconnected', 'revoked']) {
    test(
      'startup fallback never opens a $change server with stale credentials',
      () async {
        final resource = await connect();
        final owner = await ProfileAuthorizationContext.capture(registry);
        if (change == 'revoked') {
          await resources.grant(
            actor: owner,
            targetProfileId: member,
            resourceId: resource.id,
            permissions: {ResourcePermission.use},
          );
          await registry.setActiveProfile(member);
          ProfileRuntime.publish(
            ProfileScope(profileId: member, dataGeneration: 1, sessionEpoch: 2),
          );
        }
        final candidates = await search();
        var opened = 0;
        // The first open failed; change authority before the next fallback.
        expect(
          await DirectSourceAuthorization.runIfAuthorized(
            candidates.first,
            () async {
              opened++;
              return false;
            },
          ),
          isFalse,
        );
        switch (change) {
          case 'disabled':
            await registry.setProfileResourceSettings(
              profileId: admin,
              resourceId: resource.id,
              enabled: false,
              settings: {},
              actingAuthorizationRevision: owner.authorizationRevision,
              expectedResourceAuthorizationRevision:
                  resource.authorizationRevision,
              feature: ProfileFeature.cloud,
            );
          case 'reconnected':
            await MediaServerService.connect(
              kind: MediaServerKind.jellyfin,
              label: resource.label,
              baseUrl: 'https://server.example/base/',
              username: 'user',
              password: 'new-password',
              replaceId: resource.id,
            );
          case 'revoked':
            // Simulate an authoritative registry revocation while playback's
            // profile and its previously fetched rows remain in memory.
            await registry.revokeGrant(member, resource.id);
        }
        await expectLater(
          DirectSourceAuthorization.runIfAuthorized(candidates.last, () async {
            opened++;
            return true;
          }),
          throwsA(anything),
        );
        expect(opened, 1);
      },
    );
  }

  test(
    'Flutter startup passes source identity through the final player-open barrier',
    () {
      final code = File(
        'lib/screens/video_player_screen.dart',
      ).readAsStringSync();
      final open = code.substring(
        code.indexOf('Future<void> _openMedia('),
        code.indexOf('void _releasePlayerDiagnostic('),
      );
      expect(
        open,
        contains(
          'DirectSourceAuthorization.runIfAuthorized(source, commitOpen)',
        ),
      );
      expect(
        open.indexOf('runIfAuthorized'),
        greaterThan(open.indexOf('await remedy.onNewMedia')),
      );
      final probe = code.substring(
        code.indexOf('Future<bool> _tryOpenStartupVod('),
        code.indexOf('Future<bool> _openInitialVodWithFailover('),
      );
      expect(probe, contains('source: source,'));
      expect(probe, contains('beforeOpen: () {\n          armed = true;'));
      final failover = code.substring(
        code.indexOf('Future<bool> _openInitialVodWithFailover('),
        code.indexOf('Future<void> _commitValidatedStremioSource('),
      );
      expect(
        failover.substring(failover.indexOf(': await _tryOpenStartupVod(')),
        contains('source: source,'),
      );
    },
  );

  test(
    'multi-audio counts recognized languages without filter chips',
    () async {
      await connect();
      final filter = TorrentFilterState(languages: {AudioLanguage.multiAudio});
      for (final sample in [
        (['eng', 'swe'], true),
        (['sv-SE', 'en_US'], true),
        (['swe', 'fin'], true),
        (['sv', 'swe', 'Swedish', 'sv-SE'], false),
        (['en', 'eng', 'en-US'], false),
        (['eng', 'und', 'zxx', 'unknown', ''], false),
      ]) {
        audioStreams = [
          for (final language in sample.$1)
            {'Type': 'Audio', 'Language': language},
        ];
        final sources = await search();
        expect(
          TorrentFilterMatcher.apply(sources, filter).isNotEmpty,
          sample.$2,
          reason: '${sample.$1}',
        );
        expect(
          TorrentPlaybackService.orderCandidatesForRules(
            sources,
            rules: QuickPlayRules.debrifyDefault(
              isMovie: true,
            ).copyWith(relaxFilters: false),
            ladder: FilterLadder(filter),
          ).isNotEmpty,
          sample.$2,
          reason: '${sample.$1}',
        );
      }
    },
  );

  test('disconnect invalidates old results and their pins', () async {
    final resource = await connect();
    final source = (await search()).first;
    final pin = MediaServerService.bindingFor(source)!;
    await MediaServerService.remove(resource);
    await expectLater(
      DirectSourceAuthorization.authorize(source),
      throwsStateError,
    );
    expect(await MediaServerService.resolvePinned(pin), isNull);
    expect(await search(), isEmpty);
  });

  test(
    'a profile switch rejects cached source credentials and hides unshared servers',
    () async {
      await connect();
      final source = (await search()).first;
      await registry.setActiveProfile(member);
      ProfileRuntime.publish(
        ProfileScope(profileId: member, dataGeneration: 1, sessionEpoch: 2),
      );
      await expectLater(
        DirectSourceAuthorization.authorize(source),
        throwsA(anything),
      );
      expect(await MediaServerService.connections(), isEmpty);
      expect(await search(), isEmpty);
    },
  );

  test(
    'use-only borrower can play but cannot reconnect another owner account',
    () async {
      final resource = await connect();
      final owner = await ProfileAuthorizationContext.capture(registry);
      await resources.grant(
        actor: owner,
        resourceId: resource.id,
        targetProfileId: member,
        permissions: {ResourcePermission.use},
      );
      await registry.setActiveProfile(member);
      ProfileRuntime.publish(
        ProfileScope(profileId: member, dataGeneration: 1, sessionEpoch: 2),
      );
      expect(await search(), hasLength(2));
      await expectLater(
        MediaServerService.connect(
          kind: MediaServerKind.jellyfin,
          label: 'Hijack',
          baseUrl: 'https://server.example',
          username: 'user',
          password: 'pw',
          replaceId: resource.id,
        ),
        throwsA(isA<ResourceAuthorizationException>()),
      );
      expect(requestCount, greaterThan(0));
    },
  );

  test(
    'server failures remain visible without blocking other source searches',
    () async {
      await connect();
      unavailable = true;
      final result = await MediaServerService.search(
        id: 'tt123',
        isMovie: true,
      );
      expect(result['torrents'], isEmpty);
      expect(result['addonErrors'], isNotEmpty);
      expect(
        jsonEncode(result['addonErrors']),
        isNot(contains('private server error')),
      );
    },
  );

  test(
    'deserialized credential-bearing rows cannot bypass authorization',
    () async {
      await connect();
      final source = (await search()).first;
      final copy = Torrent.fromJson(source.toJson());
      await expectLater(
        DirectSourceAuthorization.authorize(copy),
        throwsA(isA<MediaServerException>()),
      );
    },
  );
}
