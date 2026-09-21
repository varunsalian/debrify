import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/player_visibility.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // These are real IO tests; use the application binding for lifecycle
  // observers without a widget-test binding's HTTP override/fake clock.
  WidgetsFlutterBinding.ensureInitialized();
  final service = IptvCatalogRefreshService.instance;
  final player = Object();
  late Directory root;
  late Directory downloads;
  late HttpServer server;
  late IptvPlaylist xtream;
  late IptvPlaylist m3u;
  late String base;
  final requests = <String>[];
  final outstanding = <Future<IptvParseResult>>[];
  Completer<void>? held;
  Completer<void>? arrived;
  String? holdAction;
  var vodBody = '';
  var m3uStatus = HttpStatus.ok;
  var active = 0;
  var maxActive = 0;

  Future<IptvParseResult> refresh(
    IptvPlaylist playlist,
    String type, {
    bool force = true,
    bool priority = false,
  }) {
    final future = service.refreshCatalog(
      playlist,
      type,
      force: force,
      priority: priority,
    );
    outstanding.add(future);
    return future;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'iptv-refresh-queue-test');
    root = await Directory.systemTemp.createTemp('iptv-refresh-queue-test-');
    downloads = await Directory('${root.path}/downloads').create();
    XtreamCodesService.debugDownloadDirectory = downloads.path;
    IptvService.debugDownloadDirectoryOverride = downloads.path;
    IptvCatalogDb.debugDirectoryOverride = root.path;
    await IptvCatalogDb.open();
    requests.clear();
    outstanding.clear();
    held = null;
    arrived = null;
    holdAction = null;
    active = 0;
    maxActive = 0;
    vodBody = '[{"name":"Original movie","stream_id":1,"category_id":"7"}]';
    m3uStatus = HttpStatus.ok;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    xtream = IptvPlaylist(
      id: base,
      name: 'Xtream',
      url: '',
      serverUrl: base,
      username: 'user',
      password: 'pass',
      addedAt: DateTime(2026),
    );
    m3u = IptvPlaylist(
      id: '$base/m3u',
      name: 'M3U',
      url: '$base/list.m3u',
      addedAt: DateTime(2026),
    );
    server.listen((request) async {
      final action =
          request.uri.queryParameters['action'] ??
          (request.uri.path == '/list.m3u' ? 'm3u' : 'login');
      requests.add(action);
      active++;
      if (active > maxActive) maxActive = active;
      try {
        if (action == holdAction) {
          if (!(arrived?.isCompleted ?? true)) arrived!.complete();
          await held!.future;
        }
        request.response.headers.contentType = ContentType.json;
        if (action.endsWith('_categories')) {
          request.response.write(
            '[{"category_id":"7","category_name":"Test"}]',
          );
        } else if (action == 'get_vod_streams') {
          request.response.write(vodBody);
        } else if (action == 'get_series') {
          request.response.write(
            '[{"name":"Series","series_id":2,"category_id":"7"}]',
          );
        } else if (action == 'get_live_streams') {
          request.response.write(
            '[{"name":"Live","stream_id":3,"category_id":"7"}]',
          );
        } else if (action == 'm3u') {
          request.response.statusCode = m3uStatus;
          request.response.write(
            '#EXTM3U\n#EXTINF:-1 group-title="Test",Original channel\n$base/live.ts\n',
          );
        } else if (action == 'login') {
          request.response.write('{"user_info":{"auth":1,"status":"Active"}}');
        } else {
          request.response.statusCode = HttpStatus.badRequest;
        }
        await request.response.close();
      } finally {
        active--;
      }
    });
  });

  tearDown(() async {
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    PlayerVisibility.settleDuration = const Duration(seconds: 30);
    PlayerVisibility.closed(player);
    if (held != null && !held!.isCompleted) held!.complete();
    await Future.wait(outstanding).timeout(const Duration(seconds: 10));
    // The singleton yields for 100ms after completing the final job.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    service.dispose();
    await server.close(force: true);
    expect(downloads.listSync(), isEmpty);
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    XtreamCodesService.debugDownloadDirectory = null;
    IptvService.debugDownloadDirectoryOverride = null;
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    await root.delete(recursive: true);
  });

  test(
    'first movie search discovers saved legacy source and downloads missing catalog',
    () async {
      final saved = await StorageService.setIptvPlaylistsAndReload([
        xtream,
      ], forSettings: false);
      expect(saved.single.serverUrl, base);
      expect(saved.single.username, 'user');
      expect(saved.single.password, 'pass');
      expect(
        (await StorageService.getIptvPlaylists(forSettings: false)).single.id,
        xtream.id,
      );
      final key = IptvCatalogKey.forPlaylist(xtream, 'vod')!;
      expect(IptvCatalogDb.snapshot(key), isNull);
      expect(requests, isEmpty);

      final results = await IptvSourceSearch.search(
        const AdvancedSearchSelection(
          imdbId: 'tt1234567',
          isSeries: false,
          title: 'Original movie',
        ),
      );
      expect(results, hasLength(1));
      expect(
        results.single.retryableFailure,
        isFalse,
        reason: results.single.message,
      );
      expect(
        results.single.torrents,
        hasLength(1),
        reason: results.single.message,
      );
      expect(results.single.torrents.single.name, contains('Original movie'));
      expect(IptvCatalogDb.snapshot(key)!.channelCount, 1);
      expect(requests.where((a) => a == 'get_vod_streams'), hasLength(1));
      expect(requests, isNot(contains('get_live_streams')));
    },
  );

  test(
    'playback pauses automatic queue and closing player resumes it',
    () async {
      service.start();
      PlayerVisibility.opened(player);
      var completed = false;
      final pending = refresh(xtream, 'vod', force: false).then((result) {
        completed = true;
        return result;
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests, isEmpty);
      expect(completed, isFalse);
      PlayerVisibility.closed(player);
      final result = await pending.timeout(const Duration(seconds: 5));
      expect(result.hasError, isFalse, reason: result.error);
      expect(result.ingest?.channelCount, 1);
      expect(requests.where((a) => a == 'get_vod_streams'), hasLength(1));
    },
  );

  test(
    'forced priority refresh bypasses paused automatic work during playback',
    () async {
      service.start();
      PlayerVisibility.opened(player);
      var automaticCompleted = false;
      final pending = refresh(xtream, 'vod', force: false).then((result) {
        automaticCompleted = true;
        return result;
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests, isEmpty);
      final forced = await refresh(
        m3u,
        'live',
        priority: true,
      ).timeout(const Duration(seconds: 5));
      expect(forced.hasError, isFalse, reason: forced.error);
      expect(PlayerVisibility.visible.value, isTrue);
      expect(automaticCompleted, isFalse);
      expect(requests, ['m3u']);
      PlayerVisibility.closed(player);
      expect(
        (await pending.timeout(const Duration(seconds: 5))).hasError,
        isFalse,
      );
    },
  );

  test(
    'force upgrades identical queued automatic job while player is visible',
    () async {
      service.start();
      PlayerVisibility.opened(player);
      final automatic = refresh(xtream, 'vod', force: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests, isEmpty);
      final forced = refresh(xtream, 'vod', priority: true);
      final results = await Future.wait([
        automatic,
        forced,
      ]).timeout(const Duration(seconds: 5));
      expect(PlayerVisibility.visible.value, isTrue);
      expect(results.first.hasError, isFalse, reason: results.first.error);
      expect(results.last, same(results.first));
      expect(requests.where((a) => a == 'get_vod_streams'), hasLength(1));
    },
  );

  test(
    'overlapping identical forced requests share one download and publication',
    () async {
      holdAction = 'get_vod_streams';
      held = Completer<void>();
      arrived = Completer<void>();
      final revision = service.revision.value;
      final first = refresh(xtream, 'vod');
      await arrived!.future.timeout(const Duration(seconds: 5));
      final others = List.generate(5, (_) => refresh(xtream, 'vod'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      held!.complete();
      final results = await Future.wait([first, ...others]);
      for (final result in results) {
        expect(result.hasError, isFalse, reason: result.error);
        expect(result.ingest?.channelCount, 1);
        expect(identical(result, results.first), isTrue);
      }
      expect(requests.where((a) => a == 'get_vod_streams'), hasLength(1));
      expect(service.revision.value, revision + 1);
    },
  );

  test('active automatic download finishes when playback starts', () async {
    service.start();
    holdAction = 'get_vod_streams';
    held = Completer<void>();
    arrived = Completer<void>();
    final pending = refresh(xtream, 'vod', force: false);
    await arrived!.future.timeout(const Duration(seconds: 5));
    PlayerVisibility.opened(player);
    held!.complete();
    final result = await pending.timeout(const Duration(seconds: 5));
    expect(result.hasError, isFalse, reason: result.error);
    expect(result.ingest?.channelCount, 1);
    expect(PlayerVisibility.visible.value, isTrue);
  });

  test('stable native playback allows queue while Flutter is paused', () async {
    service.start();
    PlayerVisibility.settleDuration = const Duration(milliseconds: 100);
    PlayerVisibility.opened(player, native: true);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final pending = refresh(xtream, 'vod', force: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, isEmpty);
    PlayerVisibility.playbackState(player, ready: true);
    final result = await pending.timeout(const Duration(seconds: 5));
    expect(result.hasError, isFalse, reason: result.error);
    expect(result.ingest?.channelCount, 1);
  });

  test('stable Flutter playback starts work only while foregrounded', () async {
    service.start();
    PlayerVisibility.settleDuration = const Duration(milliseconds: 100);
    PlayerVisibility.opened(player);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final pending = refresh(xtream, 'vod', force: false);
    PlayerVisibility.playbackState(player, ready: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(requests, isEmpty);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final result = await pending.timeout(const Duration(seconds: 5));
    expect(result.hasError, isFalse, reason: result.error);
    expect(result.ingest?.channelCount, 1);
  });

  test('Xtream and M3U catalogs share a serialized queue', () async {
    holdAction = 'get_vod_streams';
    held = Completer<void>();
    arrived = Completer<void>();
    final first = refresh(xtream, 'vod');
    await arrived!.future.timeout(const Duration(seconds: 5));
    final pending = [
      refresh(m3u, 'live'),
      refresh(xtream, 'series'),
      refresh(xtream, 'live'),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests.where((a) => !a.endsWith('_categories')).toList(), [
      'get_vod_streams',
    ]);
    held!.complete();
    for (final result in await Future.wait([first, ...pending])) {
      expect(result.hasError, isFalse, reason: result.error);
      expect(result.ingest?.channelCount, 1);
    }
    expect(maxActive, 1);
    expect(
      requests
          .where((a) => !a.endsWith('_categories') && a != 'login')
          .toList(),
      ['get_vod_streams', 'm3u', 'get_series', 'get_live_streams'],
    );
  });

  test(
    'malformed Xtream replacement preserves published snapshot; force retries',
    () async {
      expect((await refresh(xtream, 'vod')).hasError, isFalse);
      final key = IptvCatalogKey.forPlaylist(xtream, 'vod')!;
      final original = IptvCatalogDb.snapshot(key)!;
      // Exceed an ingest chunk before the malformed tail so rollback is
      // exercised after replacement rows have actually been staged.
      final rows = List.generate(
        6000,
        (i) => jsonEncode({'name': 'Replacement $i', 'stream_id': i + 2}),
      );
      vodBody = '[${rows.join(',')},broken]';
      expect((await refresh(xtream, 'vod')).hasError, isTrue);
      final retained = IptvCatalogDb.snapshot(key)!;
      expect(retained.generation, original.generation);
      expect(retained.page(offset: 0, limit: 10).single.name, 'Original movie');
      vodBody = '[{"name":"Recovered","stream_id":3}]';
      expect((await refresh(xtream, 'vod')).hasError, isFalse);
      expect(
        IptvCatalogDb.snapshot(key)!.page(offset: 0, limit: 10).single.name,
        'Recovered',
      );
    },
  );

  test('failed M3U HTTP response preserves snapshot', () async {
    expect((await refresh(m3u, 'live')).hasError, isFalse);
    final key = IptvCatalogKey.forPlaylist(m3u, 'live')!;
    final original = IptvCatalogDb.snapshot(key)!;
    m3uStatus = HttpStatus.serviceUnavailable;
    expect((await refresh(m3u, 'live')).hasError, isTrue);
    expect(IptvCatalogDb.snapshot(key)!.generation, original.generation);
    expect(
      IptvCatalogDb.snapshot(key)!.page(offset: 0, limit: 10).single.name,
      'Original channel',
    );
  });

  test(
    'Off persists, skips automatic network, and force overrides it',
    () async {
      expect(await IptvCatalogRefreshService.getIntervalHours(), 24);
      await IptvCatalogRefreshService.setIntervalHours(0);
      expect(await IptvCatalogRefreshService.getIntervalHours(), 0);
      await (await SharedPreferences.getInstance()).setStringList(
        'iptv_playlists',
        [jsonEncode(xtream.toJson()), jsonEncode(m3u.toJson())],
      );
      expect(
        (await SharedPreferences.getInstance()).getInt(
          IptvCatalogRefreshService.intervalKey,
        ),
        0,
      );
      await service.refreshDue();
      await refresh(xtream, 'vod', force: false);
      await refresh(m3u, 'live', force: false);
      expect(requests, isEmpty);
      expect((await refresh(m3u, 'live')).hasError, isFalse);
      expect(requests, ['m3u']);
    },
  );
}
