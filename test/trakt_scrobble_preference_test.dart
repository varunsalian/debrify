import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = TraktService.instance;

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'trakt-scrobble-test');
    service.resetProfileScope();
    await StorageService.setTraktSession(
      accessToken: 'test-access',
      refreshToken: 'test-refresh',
      expiryMs: 9000000000000,
    );
    await StorageService.setTrackingScrobbleTargets({
      TrackingSource.local,
      TrackingSource.trakt,
    });
  });

  tearDown(() {
    service.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final episode in [false, true]) {
    final actions = <String, Future<bool> Function()>{
      'start': () => service.scrobbleStart(
        'tt1234567',
        5,
        season: episode ? 1 : null,
        episode: episode ? 2 : null,
      ),
      'pause': () => service.scrobblePause(
        'tt1234567',
        40,
        season: episode ? 1 : null,
        episode: episode ? 2 : null,
      ),
      'stop': () => service.scrobbleStop(
        'tt1234567',
        95,
        season: episode ? 1 : null,
        episode: episode ? 2 : null,
      ),
    };
    for (final action in actions.entries) {
      test('disabled Trakt blocks ${action.key} (episode=$episode)', () async {
        // A connected account and another enabled tracker must not override
        // the user's Trakt switch, even if a caller has a stale enabled flag.
        await StorageService.setTrackingScrobbleTargets({
          TrackingSource.local,
          TrackingSource.simkl,
        });
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 201);
        });
        await http.runWithClient(() async {
          expect(await action.value(), isFalse);
        }, () => client);
        expect(requests, isEmpty);
      });
    }
  }

  test(
    'switching off an active session blocks later updates and exit',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 201);
      });
      await http.runWithClient(() async {
        expect(
          await service.scrobbleStart('tt1234567', 5, season: 1, episode: 2),
          isTrue,
        );
        await StorageService.setTrackingScrobbleTargets({TrackingSource.local});

        expect(
          await service.scrobbleStart('tt1234567', 35, season: 1, episode: 2),
          isFalse,
        );
        expect(
          await service.scrobblePause('tt1234567', 40, season: 1, episode: 2),
          isFalse,
        );
        expect(
          await service.scrobbleStop('tt1234567', 95, season: 1, episode: 2),
          isFalse,
        );
        expect(paths, ['/scrobble/start']);

        // A deliberate re-enable admits subsequent playback updates again.
        await StorageService.setTrackingScrobbleTargets({
          TrackingSource.local,
          TrackingSource.trakt,
        });
        expect(
          await service.scrobbleStart('tt1234567', 10, season: 1, episode: 3),
          isTrue,
        );
      }, () => client);
      expect(paths, ['/scrobble/start', '/scrobble/start']);
    },
  );

  for (final disableDuringRefresh in [false, true]) {
    test('retry checks current switch after token refresh '
        '(disabled=$disableDuringRefresh)', () async {
      final requests = <http.Request>[];
      var scrobbles = 0;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/oauth/token') {
          if (disableDuringRefresh) {
            await StorageService.setTrackingScrobbleTargets({
              TrackingSource.local,
            });
          }
          return http.Response(
            jsonEncode({
              'access_token': 'test-new-access',
              'refresh_token': 'test-new-refresh',
              'expires_in': 3600,
            }),
            200,
          );
        }
        expect(request.url.path, '/scrobble/stop');
        scrobbles++;
        return http.Response('{}', scrobbles == 1 ? 401 : 201);
      });
      await http.runWithClient(() async {
        expect(
          await service.scrobbleStop('tt1234567', 95, season: 1, episode: 2),
          !disableDuringRefresh,
        );
      }, () => client);
      expect(requests.map((request) => request.url.path), [
        '/scrobble/stop',
        '/oauth/token',
        if (!disableDuringRefresh) '/scrobble/stop',
      ]);
      if (!disableDuringRefresh) {
        expect(
          requests.last.headers['authorization'],
          'Bearer test-new-access',
        );
        expect(jsonDecode(requests.last.body)['episode'], {
          'season': 1,
          'number': 2,
        });
      }
    });
  }

  test(
    'explicit Trakt history actions still work with scrobbling off',
    () async {
      await StorageService.setTrackingScrobbleTargets({TrackingSource.local});
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 201);
      });
      await http.runWithClient(() async {
        expect(await service.markEpisodeWatched('tt1234567', 1, 2), isTrue);
        expect(await service.addToHistory('tt1234567', 'movie'), isTrue);
      }, () => client);
      expect(paths, ['/sync/history', '/sync/history']);
    },
  );
}
