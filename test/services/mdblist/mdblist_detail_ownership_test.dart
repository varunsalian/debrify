import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response response(http.Request request, {bool dropped = true}) {
  if (request.url.path.startsWith('/imdb/')) {
    return http.Response(
      jsonEncode({
        'ids': {'tmdb': 55},
      }),
      200,
    );
  }
  if (request.url.path.startsWith('/sync/state/')) {
    return http.Response(
      jsonEncode({
        'items': [
          {'id': 55, 'rating': 8},
        ],
      }),
      200,
    );
  }
  return http.Response(
    jsonEncode(
      dropped
          ? [
              {
                'show': {
                  'ids': {'imdb': 'tt1234567'},
                },
              },
            ]
          : [],
    ),
    200,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  for (final stage in ['/imdb/show/tt1234567/', '/sync/dropped']) {
    for (final retire in ['none', 'route', 'profile']) {
      test(
        'detail shared $stage survives only its owning session: $retire',
        () async {
          final entered = Completer<void>(), release = Completer<void>();
          var calls = 0, held = false, active = true;
          final service = MdblistService.forTesting(
            apiKeyProvider: () async => 'key',
            client: MockClient((request) async {
              if (request.url.path == stage) {
                calls++;
                if (!held) {
                  held = true;
                  entered.complete();
                  await release.future;
                }
              }
              return response(request);
            }),
          );
          final first = service.fetchTitleStatus(
            'tt1234567',
            'series',
            canContinue: () => active,
          );
          await entered.future.timeout(const Duration(seconds: 5));
          final sibling = retire == 'profile'
              ? null
              : service.fetchTitleStatus('tt1234567', 'series');
          if (retire == 'route') active = false;
          if (retire == 'profile') ProfileSessionMemory.clearAll();
          release.complete();
          final result = await first;
          if (retire == 'none') {
            expect(result?.rating, 8);
            expect(result?.dropped, isTrue);
          } else {
            expect(result, isNull);
          }
          if (sibling != null) {
            expect((await sibling)?.dropped, isTrue);
            expect(calls, 1); // A closing view cannot cancel the shared read.
          }
          expect(
            (await service.fetchTitleStatus('tt1234567', 'series'))?.dropped,
            isTrue,
          );
          expect(calls, retire == 'profile' ? 2 : 1);
        },
      );
    }
  }

  for (final invalidation in ['bucket', 'reset', 'mutation']) {
    test(
      'late dropped response cannot refill invalidated cache: invalidation=$invalidation',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        var calls = 0;
        final service = MdblistService.forTesting(
          apiKeyProvider: () async => 'key',
          client: MockClient((request) async {
            if (request.url.path == '/sync/dropped/remove') {
              return http.Response('', 204);
            }
            if (request.url.path != '/sync/dropped') return response(request);
            calls++;
            if (calls == 1) {
              entered.complete();
              await release.future;
              return response(request);
            }
            return response(request, dropped: false);
          }),
        );
        final old = service.fetchTitleStatus('tt1234567', 'series');
        await entered.future.timeout(const Duration(seconds: 5));
        if (invalidation == 'reset') {
          service.resetProfileScope();
        } else if (invalidation == 'mutation') {
          expect(
            await service.setDropped(
              const MdblistMediaIds(imdb: 'tt1234567', tmdb: 55),
              dropped: false,
            ),
            isTrue,
          );
        } else {
          service.invalidateSyncBuckets({'dropped'});
        }
        expect(
          (await service.fetchTitleStatus('tt1234567', 'series'))?.dropped,
          isFalse,
        );
        release.complete();
        expect((await old)?.dropped, isNull);
        expect(
          (await service.fetchTitleStatus('tt1234567', 'series'))?.dropped,
          isFalse,
        );
        expect(calls, 2);
      },
    );
  }

  test(
    'route retirement during identity preparation prevents shared lookup',
    () async {
      var active = true, requests = 0;
      final service = MdblistService.forTesting(
        apiKeyProvider: () async => 'key',
        client: MockClient((request) async {
          requests++;
          return response(request);
        }),
      );
      final pending = service.fetchTitleStatus(
        'tt1234567',
        'movie',
        canContinue: () => active,
      );
      active = false;
      expect(await pending, isNull);
      expect(requests, 0);
    },
  );

  test(
    'profile retirement during API key read prevents outbound request',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var requests = 0;
      final service = MdblistService.forTesting(
        apiKeyProvider: () async {
          entered.complete();
          await release.future;
          return 'key';
        },
        client: MockClient((request) async {
          requests++;
          return response(request);
        }),
      );
      final pending = service.fetchTitleStatus('tt1234567', 'movie');
      await entered.future.timeout(const Duration(seconds: 5));
      ProfileSessionMemory.clearAll();
      release.complete();
      expect(await pending, isNull);
      expect(requests, 0);
    },
  );

  for (final stage in ['credential', 'response']) {
    for (final retirement in ['none', 'view', 'profile']) {
      test('mutation $stage ownership: $retirement', () async {
        final entered = Completer<void>(), release = Completer<void>();
        var active = true, requests = 0;
        final service = MdblistService.forTesting(
          apiKeyProvider: () async {
            if (stage == 'credential') {
              entered.complete();
              await release.future;
            }
            return 'key';
          },
          client: MockClient((request) async {
            requests++;
            if (stage == 'response') {
              entered.complete();
              await release.future;
            }
            return http.Response('{}', 200);
          }),
        );
        final pending = service.markWatched(
          const MdblistMediaIds(imdb: 'tt1234567'),
          'movie',
          canContinue: () => active,
        );
        await entered.future;
        if (retirement == 'view') active = false;
        if (retirement == 'profile') ProfileSessionMemory.clearAll();
        release.complete();
        final accepted =
            retirement == 'none' ||
            (retirement == 'view' && stage == 'response');
        expect(await pending, accepted);
        expect(requests, stage == 'response' || retirement == 'none' ? 1 : 0);
        expect(service.libraryRevision.value, accepted ? 1 : 0);
        expect(service.watchedRevision.value, accepted ? 1 : 0);
      });
    }
  }

  test(
    'mutation listener retirement stops later watched notifications',
    () async {
      final service = MdblistService.forTesting(
        apiKeyProvider: () async => 'key',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      service.libraryRevision.addListener(ProfileSessionMemory.clearAll);
      expect(
        await service.markWatched(
          const MdblistMediaIds(imdb: 'tt1234567'),
          'movie',
        ),
        isFalse,
      );
      expect(service.libraryRevision.value, 1);
      expect(service.watchedRevision.value, 0);
    },
  );

  test('production key migration stops at retired session barrier', () async {
    SharedPreferences.setMockInitialValues({'mdblist_api_key': 'legacy-key'});
    SecretVault.debugReset(deviceIdOverride: 'mdblist-detail-fixture');
    addTearDown(SecretVault.debugReset);
    final entered = Completer<void>(), release = Completer<void>();
    final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final pending = MdblistService.instance.fetchTitleStatus(
      'tt1234567',
      'movie',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ProfileSessionMemory.clearAll();
    release.complete();
    await barrier;
    expect(await pending, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('mdblist_api_key'),
      'legacy-key',
    );
    MdblistService.instance.resetProfileScope();
  });
}
