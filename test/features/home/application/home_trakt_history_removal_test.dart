import 'package:debrify/features/home/application/home_series_resume_dependencies.dart';
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
  // Resume reads exercise the same real two-account credential fixture as writes.
  for (final stage in ['next', 'page', 'native', 'unauthorized']) {
    for (final retirement in ['active', 'view', 'profile']) {
      if (stage == 'unauthorized' && retirement == 'active') continue;
      test(
        'cached resume $stage retains origin and stops after $retirement retirement',
        () async {
          final container = ProviderContainer.test();
          final reader = container.read(
            homeSeriesResumeRepositoryProvider(
              ProfileSessionMemory.captureOwner(),
            ),
          );
          final meta = StremioMeta(
            id: stage == 'native' ? 'tmdb:123' : 'tt123',
            name: 'Fixture',
            type: 'series',
          );
          final cached = TraktContinueWatchingItem(
            meta: meta,
            traktContentType: 'episodes',
            season: stage == 'page' || stage == 'unauthorized' ? 2 : null,
            episode: stage == 'page' || stage == 'unauthorized' ? 3 : null,
            progress: 42,
            pausedAtMs: 9876,
          );
          final entered = Completer<void>(), release = Completer<void>();
          var current = true;
          final paths = <String>[];
          await http.runWithClient(
            () async {
              final pending = ProfileRuntime.withCapturedScope(
                other,
                () => reader.traktSelection(
                  meta,
                  cached: cached,
                  isCurrent: () => current,
                ),
              );
              await entered.future;
              if (retirement == 'view') current = false;
              if (retirement == 'profile') ProfileRuntime.publish(other);
              release.complete();
              final result = await pending;
              if (retirement == 'active') {
                expect(result!.sel.imdbId, meta.id);
                expect((result.sel.season, result.sel.episode), (2, 3));
                expect(result.sel.traktProgressPercent, 67);
                expect(result.sel.traktSource, isTrue);
                expect(result.tsMs, 9876);
                expect(paths.length, stage == 'native' ? 3 : 2);
              } else {
                expect(result, isNull);
                expect(paths, hasLength(1));
              }
            },
            () => MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.headers['authorization'], 'Bearer origin-token');
              paths.add(request.url.path);
              if (paths.length == 1) {
                entered.complete();
                await release.future;
                if (stage == 'unauthorized') return http.Response('{}', 401);
              }
              if (request.url.path.startsWith('/search/')) {
                return http.Response(
                  jsonEncode([
                    {
                      'type': 'show',
                      'show': {
                        'ids': {'tmdb': 123, 'trakt': 42},
                      },
                    },
                  ]),
                  200,
                );
              }
              if (request.url.path.contains('/progress/watched')) {
                return http.Response(
                  jsonEncode({
                    'next_episode': {'season': 2, 'number': 3},
                  }),
                  200,
                );
              }
              expect(request.url.path, '/sync/playback/episodes');
              expect(request.url.queryParameters['limit'], '250');
              return http.Response(
                jsonEncode([
                  {
                    'progress': 67,
                    'show': {
                      'ids': stage == 'native'
                          ? {'tmdb': 123}
                          : {'imdb': 'tt123'},
                    },
                    'episode': {'season': 2, 'number': 3},
                  },
                ]),
                200,
                headers: {
                  'x-pagination-page-count': stage == 'page' ? '2' : '1',
                },
              );
            }),
          );
        },
      );
    }
  }

  test(
    'retired cached resume cannot seal credentials or send GET after a snapshot barrier',
    () async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      SharedPreferences.setMockInitialValues({
        'trakt_access_token': 'legacy-token',
      });
      final container = ProviderContainer.test();
      final reader = container.read(
        homeSeriesResumeRepositoryProvider(ProfileSessionMemory.captureOwner()),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var current = true;
      var requests = 0;
      const meta = StremioMeta(id: 'tt123', name: 'Fixture', type: 'series');
      await http.runWithClient(
        () async {
          final pending = reader.traktSelection(
            meta,
            cached: const TraktContinueWatchingItem(
              meta: meta,
              traktContentType: 'episodes',
              season: 2,
              episode: 3,
            ),
            isCurrent: () => current,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          current = false;
          release.complete();
          await snapshot;
          expect(await pending, isNull);
        },
        () => MockClient((_) async {
          requests++;
          return http.Response('[]', 200);
        }),
      );
      expect(requests, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('trakt_access_token'),
        'legacy-token',
      );
    },
  );
  for (final retirement in ['active', 'view', 'profile']) {
    test(
      'cached resume refresh retries only while $retirement action is current',
      () async {
        final container = ProviderContainer.test();
        final reader = container.read(
          homeSeriesResumeRepositoryProvider(
            ProfileSessionMemory.captureOwner(),
          ),
        );
        const meta = StremioMeta(id: 'tt123', name: 'Fixture', type: 'series');
        var current = true;
        var gets = 0;
        var refreshes = 0;
        await http.runWithClient(
          () async {
            final result = await ProfileRuntime.withCapturedScope(
              other,
              () => reader.traktSelection(
                meta,
                cached: const TraktContinueWatchingItem(
                  meta: meta,
                  traktContentType: 'episodes',
                  season: 2,
                  episode: 3,
                  progress: 42,
                ),
                isCurrent: () => current,
              ),
            );
            if (retirement == 'active') {
              expect(result!.sel.traktProgressPercent, 42);
              expect(gets, 2);
            } else {
              expect(result, isNull);
              expect(gets, 1);
            }
            expect(refreshes, 1);
          },
          () => MockClient((request) async {
            if (request.method == 'POST') {
              expect(request.url.path, '/oauth/token');
              expect(jsonDecode(request.body)['refresh_token'], 'refresh');
              refreshes++;
              if (retirement == 'view') current = false;
              if (retirement == 'profile') ProfileRuntime.publish(other);
              return http.Response(
                jsonEncode({
                  'access_token': 'updated-token',
                  'refresh_token': 'updated-refresh',
                  'expires_in': 3600,
                }),
                200,
              );
            }
            gets++;
            expect(
              request.headers['authorization'],
              gets == 1 ? 'Bearer origin-token' : 'Bearer updated-token',
            );
            return gets == 1
                ? http.Response('{}', 401)
                : http.Response('[]', 200);
          }),
        );
      },
    );
  }
}
