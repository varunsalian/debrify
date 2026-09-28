import 'package:debrify/services/storage_service.dart';
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

import 'package:debrify/features/home/application/home_simkl_continuation_dependencies.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileScope origin, other;
  setUp(() async {
    ProfileRuntime.debugReset();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await Directory.systemTemp.createTemp('simkl-removal-');
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
      origin.preferenceKey('simkl_access_token'): 'origin-token',
      other.preferenceKey('simkl_access_token'): 'other-token',
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
          type: ConnectionResourceType.simkl,
          label: 'Fixture',
          publicConfig: const {},
          secretConfig: {
            'accessToken': scope == origin ? 'origin-token' : 'other-token',
            'refreshToken': 'refresh',
          },
        );
        await registry.bindResource(
          profileId: scope.profileId,
          slot: 'tracker.simkl',
          resourceId: resource.id,
        );
      });
    }
    await registry.setActiveProfile(origin.profileId);
    ProfileRuntime.publish(origin);
    SimklService.instance.resetProfileScope();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    SimklService.instance.resetProfileScope();
  });

  for (final series in [false, true]) {
    for (final deletionFails in [false, true]) {
      test(
        'removal preserves series best-effort / movie result: $series $deletionFails',
        () async {
          final container = ProviderContainer.test();
          final writer = container.read(
            homeSimklHistoryRemovalProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          final writes = <String>[];
          final client = MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer origin-token');
            final path = request.url.path;
            if (request.method != 'GET') writes.add(path);
            if (path == '/sync/add-to-list') {
              expect(jsonDecode(request.body), {
                'shows': [
                  {
                    'to': 'hold',
                    'ids': {'imdb': 'tt123'},
                  },
                ],
              });
              return http.Response('{}', 201);
            }
            if (request.method == 'DELETE') {
              return http.Response('{}', deletionFails ? 500 : 204);
            }
            return http.Response(
              jsonEncode([
                {
                  'id': path.endsWith('movies') ? 2 : 1,
                  path.endsWith('movies') ? 'movie' : 'show': {
                    'ids': {'imdb': 'tt123'},
                  },
                },
                {
                  'id': 9,
                  'movie': {
                    'ids': {'imdb': 'tt-other'},
                  },
                },
              ]),
              200,
            );
          });
          await http.runWithClient(() async {
            expect(
              await ProfileRuntime.withCapturedScope(
                other,
                () => writer.remove(
                  'tt123',
                  series ? 'series' : 'movie',
                  isCurrent: () => true,
                ),
              ),
              series || !deletionFails,
            );
          }, () => client);
          expect(writes, [
            if (series) '/sync/add-to-list',
            '/sync/playback/${series ? 1 : 2}',
          ]);
        },
      );
    }
  }

  test('failed hold does not fetch or delete playback', () async {
    final container = ProviderContainer.test();
    final writer = container.read(
      homeSimklHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    final paths = <String>[];
    await http.runWithClient(
      () async {
        expect(
          await writer.remove('tt123', 'series', isCurrent: () => true),
          isFalse,
        );
      },
      () => MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('{}', 500);
      }),
    );
    expect(paths, ['/sync/add-to-list']);
  });

  for (final retireAt in ['hold', 'read', 'delete']) {
    test('retirement at $retireAt stops remaining remote writes', () async {
      final container = ProviderContainer.test();
      final writer = container.read(
        homeSimklHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <String>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method != 'GET') writes.add(path);
        final hold = retireAt == 'hold' && request.method == 'POST';
        final read = retireAt == 'read' && request.method == 'GET';
        final delete = retireAt == 'delete' && request.method == 'DELETE';
        if (hold || read || delete) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
        if (request.method != 'GET') return http.Response('{}', 200);
        return http.Response(
          jsonEncode(
            path.endsWith('movies')
                ? []
                : [
                    for (final id in [1, 2])
                      {
                        'id': id,
                        'show': {
                          'ids': {'imdb': 'tt123'},
                        },
                      },
                  ],
          ),
          200,
        );
      });
      await http.runWithClient(() async {
        final pending = writer.remove('tt123', 'series', isCurrent: () => true);
        await entered.future.timeout(const Duration(seconds: 3));
        ProfileSessionMemory.clearAll();
        ProfileRuntime.publish(other);
        release.complete();
        expect(await pending, isNull);
      }, () => client);
      expect(writes, [
        '/sync/add-to-list',
        if (retireAt == 'delete') '/sync/playback/1',
      ]);
    });
  }

  test(
    'view retirement preserves same-profile invalidation after accepted hold',
    () async {
      final container = ProviderContainer.test();
      final writer = container.read(
        homeSimklHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      var current = true;
      final revision = StorageService.movieFinishedRevision.value;
      await http.runWithClient(
        () async {
          expect(
            await writer.remove('tt123', 'series', isCurrent: () => current),
            isNull,
          );
        },
        () => MockClient((request) async {
          expect(request.url.path, '/sync/add-to-list');
          current = false;
          return http.Response('{}', 201);
        }),
      );
      expect(StorageService.movieFinishedRevision.value, revision + 1);
    },
  );

  test(
    'view retirement after delete invalidates cached paused sessions',
    () async {
      final container = ProviderContainer.test();
      final writer = container.read(
        homeSimklHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      var current = true, movieReads = 0;
      await http.runWithClient(
        () async {
          expect(
            await writer.remove('tt123', 'movie', isCurrent: () => current),
            isNull,
          );
          await SimklService.instance.fetchMoviePlaybackSessions();
        },
        () => MockClient((request) async {
          if (request.method == 'DELETE') {
            current = false;
            return http.Response('{}', 204);
          }
          if (request.url.path.endsWith('movies')) {
            movieReads++;
            return http.Response(
              jsonEncode([
                {
                  'id': 1,
                  'movie': {
                    'ids': {'imdb': 'tt123'},
                  },
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      expect(movieReads, 2);
    },
  );

  test('retired view/profile starts no IO', () async {
    final container = ProviderContainer.test();
    final writer = container.read(
      homeSimklHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        expect(
          await writer.remove('tt123', 'movie', isCurrent: () => false),
          isNull,
        );
        ProfileSessionMemory.clearAll();
        expect(
          await writer.remove('tt123', 'series', isCurrent: () => true),
          isNull,
        );
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    expect(requests, 0);
  });
}
