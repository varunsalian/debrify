import 'package:debrify/features/home/application/home_series_resume_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_playback_readers.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
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
  const movie = StremioMeta(id: 'tt123', name: 'Fixture', type: 'movie');
  String library([String status = 'completed']) => jsonEncode({
    'movies': [
      {
        'status': status,
        'movie': {
          'ids': {'imdb': 'tt123'},
        },
      },
    ],
  });
  for (final scenario in [
    'completed',
    'watching',
    'retire-read',
    'profile-read',
    'retire-write',
    'profile-write',
    'failed-write',
    'not-found',
  ]) {
    test(
      'rewatch preparation preserves owner and response rules: $scenario',
      () async {
        final readers = HomeCatalogPlaybackReaders(
          ProfileSessionMemory.captureOwner(),
        );
        var current = true;
        final requests = <String>[];
        var revisionBeforeReply = StorageService.movieFinishedRevision.value;
        await http.runWithClient(
          () => ProfileRuntime.withCapturedScope(
            other,
            () => readers.prepareMovieRewatch(
              movie,
              'tt123',
              isCurrent: () => current,
            ),
          ),
          () => MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer origin-token');
            requests.add(request.method);
            if (request.method == 'GET') {
              expect(request.url.path, '/sync/all-items/all/all');
              if (scenario == 'retire-read') current = false;
              if (scenario == 'profile-read') {
                ProfileSessionMemory.clearAll();
                ProfileRuntime.publish(other);
              }
              revisionBeforeReply = StorageService.movieFinishedRevision.value;
              return http.Response(
                library(scenario == 'watching' ? 'watching' : 'completed'),
                200,
              );
            }
            expect(request.url.path, '/sync/history/remove');
            expect(jsonDecode(request.body), {
              'movies': [
                {
                  'ids': {'imdb': 'tt123'},
                },
              ],
            });
            if (scenario == 'retire-write') current = false;
            if (scenario == 'profile-write') {
              ProfileSessionMemory.clearAll();
              ProfileRuntime.publish(other);
            }
            revisionBeforeReply = StorageService.movieFinishedRevision.value;
            return http.Response(
              scenario == 'not-found' ? '{"not_found":{"movies":[{}]}}' : '{}',
              scenario == 'failed-write' ? 500 : 200,
            );
          }),
        );
        final writes = ![
          'watching',
          'retire-read',
          'profile-read',
        ].contains(scenario);
        expect(requests, ['GET', if (writes) 'POST']);
        expect(
          StorageService.movieFinishedRevision.value,
          revisionBeforeReply +
              (['completed', 'retire-write'].contains(scenario) ? 1 : 0),
        );
      },
    );
  }
  test(
    'timed-out status response cannot submit a late write or warm library cache',
    () async {
      final readers = HomeCatalogPlaybackReaders(
        ProfileSessionMemory.captureOwner(),
      );
      final release = Completer<http.Response>();
      var reads = 0, writes = 0;
      await http.runWithClient(
        () async {
          await readers.prepareMovieRewatch(
            movie,
            'tt123',
            isCurrent: () => true,
          );
          expect(reads, 1);
          release.complete(http.Response(library(), 200));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await SimklService.instance.fetchTitleStatus(
            'tt123',
            contentType: 'movie',
          );
          expect(reads, 2);
          expect(writes, 0);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return http.Response('{}', 200);
          }
          reads++;
          return reads == 1 ? release.future : http.Response(library(), 200);
        }),
      );
    },
  );
  test(
    'timed-out accepted write still invalidates its originating profile cache',
    () async {
      final readers = HomeCatalogPlaybackReaders(
        ProfileSessionMemory.captureOwner(),
      );
      final release = Completer<http.Response>();
      var reads = 0;
      final revision = StorageService.movieFinishedRevision.value;
      await http.runWithClient(
        () async {
          await readers.prepareMovieRewatch(
            movie,
            'tt123',
            isCurrent: () => true,
          );
          expect(StorageService.movieFinishedRevision.value, revision);
          release.complete(http.Response('{}', 200));
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(StorageService.movieFinishedRevision.value, revision + 1);
          await SimklService.instance.fetchTitleStatus(
            'tt123',
            contentType: 'movie',
          );
          expect(reads, 2);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') return release.future;
          reads++;
          return http.Response(library(), 200);
        }),
      );
    },
  );
  test(
    'write timeout retires credential migration waiting on the preference barrier',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues({});
      await StorageService.setSimklAccessToken('legacy-token');
      final readers = HomeCatalogPlaybackReaders(
        ProfileSessionMemory.captureOwner(),
      );
      final release = Completer<void>(), entered = Completer<void>();
      Future<void>? snapshot;
      var writes = 0;
      await http.runWithClient(
        () async {
          await readers.prepareMovieRewatch(
            movie,
            'tt123',
            isCurrent: () => true,
          );
          expect(entered.isCompleted, isTrue);
          release.complete();
          await snapshot;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          expect(writes, 0);
          expect(
            (await SharedPreferences.getInstance()).getString(
              'simkl_access_token',
            ),
            'unsealed-token',
          );
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return http.Response('{}', 200);
          }
          await (await SharedPreferences.getInstance()).setString(
            'simkl_access_token',
            'unsealed-token',
          );
          snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          return http.Response(library(), 200);
        }),
      );
    },
  );
  const resumeShow = StremioMeta(id: 'tt123', name: 'Fixture', type: 'series');
  String pausedBody(int progress) => jsonEncode([
    {
      'show': {
        'ids': {'imdb': 'tt123', 'tmdb': 123},
      },
      'episode': {'season': 2, 'number': 3},
      'progress': progress,
      'paused_at': '2026-01-01T00:00:00Z',
    },
  ]);

  test(
    'shared resume read survives one view closing and warms the same-profile cache',
    () async {
      final reader = ProviderContainer.test().read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      final entered = Completer<void>(), release = Completer<void>();
      var firstCurrent = true;
      var requests = 0;
      await http.runWithClient(
        () async {
          final first = ProfileRuntime.withCapturedScope(
            other,
            () => reader.simklPaused(resumeShow, isCurrent: () => firstCurrent),
          );
          await entered.future.timeout(const Duration(seconds: 3));
          final second = reader.simklPaused(resumeShow, isCurrent: () => true);
          await Future<void>.delayed(Duration.zero);
          firstCurrent = false;
          release.complete();
          expect(await first, isNull);
          expect((await second)!.progress, 42);
          expect(
            (await reader.simklPaused(
              resumeShow,
              isCurrent: () => true,
            ))!.progress,
            42,
          );
          expect(requests, 1);
          // A captured foreign scope cannot borrow the active profile's cache.
          expect(
            await ProfileRuntime.withCapturedScope(
              other,
              () => SimklService.instance.fetchShowPlaybackSelection('tt123'),
            ),
            isNull,
          );
          expect(requests, 1);
        },
        () => MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer origin-token');
          requests++;
          entered.complete();
          await release.future;
          return http.Response(pausedBody(42), 200);
        }),
      );
    },
  );

  test(
    'late old-profile resume cannot join or replace the new-profile cache',
    () async {
      final container = ProviderContainer.test();
      final oldReader = container.read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      final entered = Completer<void>(), release = Completer<void>();
      var requests = 0;
      await http.runWithClient(
        () async {
          final oldRead = oldReader.simklPaused(
            resumeShow,
            isCurrent: () => true,
          );
          await entered.future.timeout(const Duration(seconds: 3));
          ProfileRuntime.publish(other);
          final newReader = container.read(
            homeSeriesResumeRepositoryProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          expect(
            (await newReader.simklPaused(
              resumeShow,
              isCurrent: () => true,
            ))!.progress,
            80,
          );
          release.complete();
          expect(await oldRead, isNull);
          expect(
            (await newReader.simklPaused(
              resumeShow,
              isCurrent: () => true,
            ))!.progress,
            80,
          );
          expect(requests, 2);
        },
        () => MockClient((request) async {
          requests++;
          if (request.headers['authorization'] == 'Bearer origin-token') {
            entered.complete();
            await release.future;
            return http.Response(pausedBody(42), 200);
          }
          expect(request.headers['authorization'], 'Bearer other-token');
          return http.Response(pausedBody(80), 200);
        }),
      );
    },
  );

  for (final retireProfile in [false, true]) {
    test(
      'resume owns generation before held credentials: profile retired=$retireProfile',
      () async {
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        SharedPreferences.setMockInitialValues({
          'simkl_access_token': 'legacy-token',
        });
        final reader = ProviderContainer.test().read(
          homeSeriesResumeRepositoryProvider(
            ProfileSessionMemory.captureOwner(),
          ),
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
            final pending = reader.simklPaused(
              resumeShow,
              isCurrent: () => true,
            );
            await Future<void>.delayed(const Duration(milliseconds: 50));
            SimklService.instance.resetProfileScope();
            if (retireProfile) ProfileSessionMemory.clearAll();
            release.complete();
            await snapshot;
            final result = await pending;
            if (retireProfile) {
              expect(result, isNull);
              expect(requests, 0);
              expect(
                (await SharedPreferences.getInstance()).getString(
                  'simkl_access_token',
                ),
                'legacy-token',
              );
            } else {
              expect(result!.progress, 42);
              expect(
                (await reader.simklPaused(
                  resumeShow,
                  isCurrent: () => true,
                ))!.progress,
                80,
              );
              expect(requests, 2);
            }
          },
          () => MockClient((_) async {
            requests++;
            return http.Response(pausedBody(requests == 1 ? 42 : 80), 200);
          }),
        );
      },
    );
  }

  for (final kind in ['paused-native', 'next-native', 'next']) {
    for (final retire in [false, true]) {
      test(
        '$kind resume preserves lookup and stops retired follow-up: $retire',
        () async {
          final reader = ProviderContainer.test().read(
            homeSeriesResumeRepositoryProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          final entered = Completer<void>(), release = Completer<void>();
          var current = true;
          var requests = 0;
          final meta = StremioMeta(
            id: kind.endsWith('native') ? 'tmdb:123' : 'tt123',
            name: 'Fixture',
            type: 'series',
          );
          await http.runWithClient(
            () async {
              final pending = ProfileRuntime.withCapturedScope(other, () async {
                if (kind == 'paused-native') {
                  final result = await reader.simklPaused(
                    meta,
                    isCurrent: () => current,
                  );
                  return result == null
                      ? null
                      : (result.season, result.episode);
                }
                final result = await reader.simklNext(
                  meta,
                  isCurrent: () => current,
                );
                return result == null ? null : (result.season, result.episode);
              });
              await entered.future.timeout(const Duration(seconds: 3));
              current = !retire;
              release.complete();
              expect(await pending, retire ? isNull : (2, 3));
              expect(requests, retire || kind == 'next' ? 1 : 2);
            },
            () => MockClient((request) async {
              expect(request.headers['authorization'], 'Bearer origin-token');
              requests++;
              if (requests == 1) {
                entered.complete();
                await release.future;
              }
              if (request.url.path.endsWith('/episodes')) {
                return http.Response(pausedBody(42), 200);
              }
              if (request.url.path.endsWith('/watching')) {
                expect(request.url.queryParameters['next_watch_info'], 'yes');
              }
              return http.Response(
                jsonEncode({
                  'shows': [
                    {
                      'show': {
                        'ids': {'tmdb': 123, 'imdb': 'tt123'},
                      },
                      'next_to_watch': 'S02E03',
                    },
                  ],
                }),
                200,
              );
            }),
          );
        },
      );
    }
  }
}
