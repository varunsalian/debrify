// Opt-in integration checks against the isolated local test servers.
// DEBRIFY_MEDIA_SERVER_LIVE=1 flutter test --no-pub test/media_server_live_test.dart
// Test account passwords come from environment variables or macOS Keychain.
// Only the synthetic test library's watch state is modified.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _WatchRequest {
  const _WatchRequest(this.path, this.body);
  final String path;
  final Map<String, dynamic> body;
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.reports);
  final List<_WatchRequest> reports;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        request is http.Request &&
        request.method == 'POST' &&
        (request.url.path.contains('/Sessions/Playing') ||
            request.url.path.contains('/PlayedItems/'))) {
      reports.add(
        _WatchRequest(
          request.url.path,
          request.body.isEmpty
              ? {}
              : jsonDecode(request.body) as Map<String, dynamic>,
        ),
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

Future<String> _password(MediaServerKind kind) async {
  final fromEnvironment =
      Platform.environment['DEBRIFY_${kind.name.toUpperCase()}_PASSWORD'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  if (Platform.isMacOS) {
    final result = await Process.run('security', [
      'find-generic-password',
      '-s',
      'Debrify Test ${kind.label}',
      '-a',
      'debrify-test',
      '-w',
    ]);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  }
  throw StateError('Missing ${kind.label} synthetic test account password');
}

Future<void> _eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('Watch report did not complete');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['DEBRIFY_MEDIA_SERVER_LIVE'] == '1';

  group(
    'local media-server integration',
    () {
      late Directory directory;
      late ProfileRegistry registry;
      late HttpOverrides? originalOverrides;
      final reports = <_WatchRequest>[];

      setUpAll(() {
        originalOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      });
      tearDownAll(() => HttpOverrides.global = originalOverrides);

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        ProfileRuntime.debugReset();
        DeviceKeyProvider.debugReset();
        directory = await Directory.systemTemp.createTemp(
          'debrify-live-server-',
        );
        registry = await ProfileRegistry.open(
          path: '${directory.path}/profiles.db',
        );
        final admin = await registry.createProfile(
          name: 'Integration test',
          role: UserProfileRole.admin,
        );
        await registry.commitBootstrap(
          activeProfileId: admin.id,
          migratedLegacyInstall: false,
        );
        final cipher = MemoryDeviceSecretCipher(
          List.generate(32, (index) => index),
        );
        await cipher.initialize();
        DeviceKeyProvider.debugInstallCipher(cipher);
        ProfileBootstrap.debugInstallRegistry(registry);
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: admin.id, dataGeneration: 1, sessionEpoch: 1),
        );
        reports.clear();
        MediaServerService.clientFactory = () =>
            MediaServerClient(client: _RecordingClient(reports));
        MediaServerWatchSync.clientFactory = () =>
            MediaServerClient(client: _RecordingClient(reports));
      });

      tearDown(() async {
        MediaServerService.clientFactory = MediaServerClient.new;
        MediaServerWatchSync.clientFactory = () =>
            MediaServerClient(timeout: const Duration(seconds: 5));
        ProfileRuntime.debugReset();
        ProfileBootstrap.debugInstallRegistry(null);
        DeviceKeyProvider.debugReset();
        await registry.close();
        await directory.delete(recursive: true);
      });

      Future<Torrent> connectAndFind(
        MediaServerKind kind, {
        bool movie = true,
        int episode = 1,
      }) async {
        final base =
            Platform.environment['DEBRIFY_${kind.name.toUpperCase()}_URL'] ??
            (kind == MediaServerKind.jellyfin
                ? 'http://127.0.0.1:8096'
                : 'http://127.0.0.1:8097/emby');
        final infoResponse = await http.get(
          MediaServerClient.endpoint(base, 'System/Info/Public'),
        );
        final info = jsonDecode(infoResponse.body) as Map<String, dynamic>;
        expect(
          info['ServerName'],
          'Debrify Test ${kind.label}',
          reason: 'Never modify watch state on a personal/production server',
        );
        await MediaServerService.connect(
          kind: kind,
          label: 'Live ${kind.label}',
          baseUrl: base,
          username: 'debrify-test',
          password: await _password(kind),
        );
        final result = await MediaServerService.search(
          id: movie ? 'tt1254207' : 'tt0903747',
          isMovie: movie,
          season: movie ? null : 1,
          episode: movie ? null : episode,
        );
        final sources = result['torrents'] as List<Torrent>;
        expect(sources, hasLength(1));
        final source = sources.single;
        expect(
          source.displayTitle,
          contains(movie ? 'Debrify Test Movie' : 'Synthetic Test Episode'),
        );
        final account = MediaServerService.watchTargetFor(source)!.account;
        final userResponse = await http.get(
          MediaServerClient.endpoint(base, 'Users/${account.userId}'),
          headers: source.httpHeaders,
        );
        expect(userResponse.statusCode, 200);
        final user = jsonDecode(userResponse.body) as Map<String, dynamic>;
        expect(user['Name'], 'debrify-test');
        expect(user['Policy']['IsAdministrator'], false);
        await MediaServerWatchSync.setEnabled(true);
        return source;
      }

      Future<void> seed(Torrent source, int positionMs) async {
        final target = MediaServerService.watchTargetFor(source)!;
        final client = MediaServerClient();
        try {
          final reset = await http.delete(
            MediaServerClient.endpoint(
              target.account.baseUrl,
              'Users/${target.account.userId}/PlayedItems/${target.itemId}',
            ),
            headers: source.httpHeaders,
          );
          expect(reset.statusCode, inInclusiveRange(200, 299));
          final sessionId =
              await client.watchSessionId(target.account, target.itemId) ??
              'live-seed-session';
          for (final action in ['start', 'progress', 'stop']) {
            await client.reportWatchProgress(
              target.account,
              itemId: target.itemId,
              mediaSourceId: target.mediaSourceId,
              playSessionId: sessionId,
              action: action,
              positionMs: positionMs,
              paused: action != 'start',
            );
          }
          final state = await client.watchState(target.account, target.itemId);
          expect(state.positionMs, positionMs);
          expect(state.played, false);
        } finally {
          client.close();
        }
      }

      for (final kind in MediaServerKind.values) {
        for (final movie in [true, false]) {
          test(
            '${kind.label} ${movie ? 'movie' : 'episode'} resume, stop, EOF and replay',
            () async {
              final source = await connectAndFind(kind, movie: movie);
              final target = MediaServerService.watchTargetFor(source)!;
              final client = MediaServerClient();
              addTearDown(client.close);
              await seed(source, 240000);
              addTearDown(() => seed(source, 240000));
              final controller = MediaServerWatchController();
              addTearDown(controller.close);
              await controller.prepare(
                source,
                contentTitle: 'Debrify Test Series',
              );
              final local = movie
                  ? await StorageService.getVideoPlaybackStateByImdbId(
                      'tt1254207',
                    )
                  : await StorageService.getSeriesPlaybackState(
                      seriesTitle: 'Debrify Test Series',
                      imdbId: 'tt0903747',
                      season: 1,
                      episode: 1,
                    );
              expect(local?['positionMs'], 240000);
              expect(
                reports,
                isEmpty,
                reason: 'Preparing does not report playback',
              );
              controller.commit(source);
              controller.observe(
                source,
                positionMs: 300000,
                durationMs: 600000,
                playing: true,
                season: 1,
                episode: 1,
              );
              controller.observe(
                source,
                positionMs: 310000,
                durationMs: 600000,
                playing: false,
                season: 1,
                episode: 1,
              );
              await controller.close();
              expect(
                (await client.watchState(
                  target.account,
                  target.itemId,
                )).positionMs,
                310000,
              );
              expect(reports.first.path, endsWith('/Sessions/Playing'));
              expect(reports.last.path, endsWith('/Sessions/Playing/Stopped'));

              final replayController = MediaServerWatchController();
              addTearDown(replayController.close);
              await replayController.prepare(
                source,
                contentTitle: 'Debrify Test Series',
              );
              replayController.commit(source);
              replayController.observe(
                source,
                positionMs: 320000,
                durationMs: 600000,
                playing: true,
                season: 1,
                episode: 1,
              );
              replayController.observe(
                source,
                positionMs: 600000,
                durationMs: 600000,
                playing: false,
                completed: true,
                season: 1,
                episode: 1,
              );
              await _eventually(
                () => reports.any(
                  (report) => report.path.contains('/PlayedItems/'),
                ),
              );
              expect(
                (await client.watchState(target.account, target.itemId)).played,
                true,
              );
              final previousStart = reports.lastWhere(
                (report) => report.path.endsWith('/Playing'),
              );
              replayController.observe(
                source,
                positionMs: 120000,
                durationMs: 600000,
                playing: true,
                season: 1,
                episode: 1,
              );
              replayController.observe(
                source,
                positionMs: 180000,
                durationMs: 600000,
                playing: false,
                season: 1,
                episode: 1,
              );
              await replayController.close();
              final lastStart = reports.lastWhere(
                (report) => report.path.endsWith('/Playing'),
              );
              expect(
                lastStart.body['PlaySessionId'],
                isNot(previousStart.body['PlaySessionId']),
              );
              expect(
                (await client.watchState(
                  target.account,
                  target.itemId,
                )).positionMs,
                180000,
              );
              expect(
                reports.where(
                  (report) => report.path.contains('/PlayedItems/'),
                ),
                hasLength(1),
              );
            },
          );
        }

        test(
          '${kind.label} direct stream accepts player headers and range seeks',
          () async {
            final source = await connectAndFind(kind);
            final transport = http.Client();
            addTearDown(transport.close);
            final request = http.Request('GET', Uri.parse(source.directUrl!))
              ..followRedirects = false
              ..headers.addAll({
                ...source.httpHeaders!,
                'Range': 'bytes=0-1023',
              });
            await DirectSourceAuthorization.authorize(source);
            final response = await http.Response.fromStream(
              await transport.send(request),
            );
            expect(response.statusCode, 206);
            expect(response.bodyBytes, hasLength(1024));
            expect(ascii.decode(response.bodyBytes.sublist(4, 8)), 'ftyp');
            expect(
              source.directUrl,
              isNot(
                contains(
                  MediaServerService.watchTargetFor(source)!.account.token,
                ),
              ),
            );
            final pin = MediaServerService.bindingFor(source)!;
            expect(
              (await MediaServerService.resolvePinned(pin))?.directUrl,
              source.directUrl,
            );
          },
        );

        test(
          '${kind.label} disconnect prevents prepared watch writes and stale playback',
          () async {
            final source = await connectAndFind(kind);
            await seed(source, 240000);
            final controller = MediaServerWatchController();
            addTearDown(controller.close);
            await controller.prepare(source);
            controller.commit(source);
            await MediaServerService.remove(
              (await MediaServerService.connections()).single,
            );
            await expectLater(
              DirectSourceAuthorization.authorize(source),
              throwsA(anything),
            );
            controller.observe(
              source,
              positionMs: 300000,
              durationMs: 600000,
              playing: true,
            );
            await controller.close();
            expect(reports, isEmpty);
          },
        );
      }
    },
    skip: enabled
        ? false
        : 'Set DEBRIFY_MEDIA_SERVER_LIVE=1 for isolated live servers',
  );
}
