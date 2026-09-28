import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debrify/features/home/application/home_trakt_continuation_dependencies.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileScope origin, other;
  TraktContinueWatchingItem item({
    bool series = false,
    List<int> ids = const [1, 2],
  }) => TraktContinueWatchingItem(
    meta: StremioMeta(
      id: 'tt123',
      name: 'Fixture',
      type: series ? 'series' : 'movie',
    ),
    traktContentType: series ? 'episodes' : 'movies',
    playbackIds: ids,
  );
  setUp(() async {
    ProfileRuntime.debugReset();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('trakt-removal-');
    final registry = await ProfileRegistry.open(
      path: '${temp.path}/profiles.db',
    );
    addTearDown(() async {
      ProfileBootstrap.debugInstallRegistry(null);
      await registry.close();
      await temp.delete(recursive: true);
    });
    final a = await registry.createProfile(
      name: 'Origin',
      role: UserProfileRole.admin,
    );
    final b = await registry.createProfile(
      name: 'Other',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: a.id,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    origin = ProfileScope(profileId: a.id, dataGeneration: 1, sessionEpoch: 1);
    other = ProfileScope(profileId: b.id, dataGeneration: 1, sessionEpoch: 2);
    ProfileRuntime.initializeCommitted(origin);
    SharedPreferences.setMockInitialValues({
      origin.preferenceKey('trakt_access_token'): 'origin-token',
      other.preferenceKey('trakt_access_token'): 'other-token',
    });
    SecretVault.debugReset(deviceIdOverride: 'removal-fixture');
    final cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    addTearDown(DeviceKeyProvider.debugReset);
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    for (final scope in [origin, other]) {
      await registry.setActiveProfile(scope.profileId);
      ProfileRuntime.publish(scope);
      await ProfileRuntime.withCapturedScope(scope, () async {
        final resource = await resources.create(
          context: await ProfileAuthorizationContext.capture(registry),
          type: ConnectionResourceType.trakt,
          label: 'Fixture',
          publicConfig: const {},
          secretConfig: {
            'accessToken': scope == origin ? 'origin-token' : 'other-token',
            'refreshToken': 'refresh',
          },
        );
        await registry.bindResource(
          profileId: scope.profileId,
          slot: 'tracker.trakt',
          resourceId: resource.id,
        );
      });
    }
    await registry.setActiveProfile(origin.profileId);
    ProfileRuntime.publish(origin);
    TraktService.instance.resetProfileScope();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    TraktService.instance.resetProfileScope();
  });

  for (final series in [false, true]) {
    for (final statuses in [
      [204, 500, 500],
      [500, 500, 200],
      [500, 500, 500],
    ]) {
      test(
        'ordered removal retains any-success result: series=$series $statuses',
        () async {
          final container = ProviderContainer.test();
          final writer = container.read(
            homeTraktHistoryRemovalProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          final paths = <String>[];
          final client = MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer origin-token');
            paths.add(request.url.path);
            if (request.method == 'POST') {
              expect(jsonDecode(request.body), {
                series ? 'shows' : 'movies': [
                  {
                    'ids': {'imdb': 'tt123'},
                  },
                ],
              });
            }
            return http.Response('{}', statuses[paths.length - 1]);
          });
          await http.runWithClient(() async {
            final result = await ProfileRuntime.withCapturedScope(
              other,
              () => writer.remove(item(series: series), isCurrent: () => true),
            );
            expect(result, statuses.any((s) => s >= 200 && s < 300));
          }, () => client);
          expect(paths, [
            '/sync/playback/1',
            '/sync/playback/2',
            '/sync/history/remove',
          ]);
        },
      );
    }
  }

  for (final status in [204, 401]) {
    test(
      'retirement during response blocks following writes and 401 refresh: $status',
      () async {
        final container = ProviderContainer.test();
        final writer = container.read(
          homeTraktHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
        );
        final entered = Completer<void>(), release = Completer<void>();
        final paths = <String>[];
        final client = MockClient((request) async {
          paths.add(request.url.path);
          entered.complete();
          await release.future;
          return http.Response('{}', status);
        });
        await http.runWithClient(() async {
          final pending = writer.remove(item(), isCurrent: () => true);
          await entered.future.timeout(const Duration(seconds: 3));
          ProfileSessionMemory.clearAll();
          ProfileRuntime.publish(other);
          release.complete();
          expect(await pending, isNull);
        }, () => client);
        expect(paths, ['/sync/playback/1']);
      },
    );
  }

  for (final playback in [false, true]) {
    for (final retireDuringRefresh in [false, true]) {
      test(
        '401 refresh preserves owner and gates resend: playback=$playback retire=$retireDuringRefresh',
        () async {
          final container = ProviderContainer.test();
          final writer = container.read(
            homeTraktHistoryRemovalProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          var current = true;
          final requests = <String>[];
          final endpoint = playback
              ? '/sync/playback/1'
              : '/sync/history/remove';
          var sent = 0;
          final client = MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.path == '/oauth/token') {
              if (retireDuringRefresh) current = false;
              return http.Response(
                jsonEncode({
                  'access_token': 'renewed',
                  'refresh_token': 'renewed-refresh',
                  'expires_in': 3600,
                }),
                200,
              );
            }
            if (request.url.path == endpoint && ++sent == 1) {
              expect(request.headers['authorization'], 'Bearer origin-token');
              return http.Response('{}', 401);
            }
            expect(request.headers['authorization'], 'Bearer renewed');
            return http.Response('{}', request.method == 'DELETE' ? 204 : 200);
          });
          await http.runWithClient(() async {
            expect(
              await writer.remove(
                item(ids: playback ? [1] : []),
                isCurrent: () => current,
              ),
              retireDuringRefresh ? isNull : isTrue,
            );
          }, () => client);
          expect(requests, [
            endpoint,
            '/oauth/token',
            if (!retireDuringRefresh) ...[
              endpoint,
              if (playback) '/sync/history/remove',
            ],
          ]);
        },
      );
    }
  }

  test('up-next item removes history without requiring playback IDs', () async {
    final container = ProviderContainer.test();
    final writer = container.read(
      homeTraktHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    final paths = <String>[];
    await http.runWithClient(
      () async {
        expect(
          await writer.remove(
            item(series: true, ids: []),
            isCurrent: () => true,
          ),
          isTrue,
        );
      },
      () => MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );
    expect(paths, ['/sync/history/remove']);
  });

  test(
    'retirement prevents credential migration after a held preference commit',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues({
        'trakt_access_token': 'legacy-token',
      });
      final container = ProviderContainer.test();
      final writer = container.read(
        homeTraktHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var requests = 0;
      await http.runWithClient(
        () async {
          final pending = writer.remove(item(), isCurrent: () => true);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          ProfileSessionMemory.clearAll();
          release.complete();
          await snapshot;
          expect(await pending, isNull);
        },
        () => MockClient((_) async {
          requests++;
          return http.Response('{}', 204);
        }),
      );
      expect(requests, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('trakt_access_token'),
        'legacy-token',
      );
    },
  );

  test(
    'view retirement after accepted history write still invalidates same-profile state',
    () async {
      final container = ProviderContainer.test();
      final writer = container.read(
        homeTraktHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      var current = true;
      final revision = StorageService.movieFinishedRevision.value;
      await http.runWithClient(
        () async {
          expect(
            await writer.remove(item(ids: []), isCurrent: () => current),
            isNull,
          );
        },
        () => MockClient((request) async {
          expect(request.url.path, '/sync/history/remove');
          current = false;
          return http.Response('{}', 200);
        }),
      );
      expect(StorageService.movieFinishedRevision.value, revision + 1);
    },
  );

  test('retired owner or view sends nothing', () async {
    final container = ProviderContainer.test();
    final writer = container.read(
      homeTraktHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        expect(await writer.remove(item(), isCurrent: () => false), isNull);
        ProfileSessionMemory.clearAll();
        expect(await writer.remove(item(), isCurrent: () => true), isNull);
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{}', 204);
      }),
    );
    expect(requests, 0);
  });
}
