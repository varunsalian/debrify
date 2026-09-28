import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final addon = StremioAddon(
  id: 'detail-fixture',
  name: 'Detail fixture',
  manifestUrl: 'https://detail.test/manifest.json',
  baseUrl: 'https://detail.test',
  resources: const ['meta', 'stream'],
  types: const ['movie', 'series'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = StremioService.instance;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
    });
    service.invalidateCache();
  });
  tearDown(() {
    service.invalidateCache();
    ProfileRuntime.debugReset();
  });

  for (final metadata in [false, true]) {
    Future<Object?> read({bool Function()? current}) => metadata
        ? service.fetchMetaDetails(
            imdbId: 'tt1234567',
            type: 'movie',
            canContinue: current,
          )
        : service.getRecommendations(
            imdbId: 'tt1234567',
            type: 'movie',
            canContinue: current,
          );
    http.Response response(String name, {bool playable = false}) =>
        http.Response(
          jsonEncode(
            metadata
                ? {
                    'meta': {
                      'id': 'tt4567890',
                      'type': 'movie',
                      'name': name,
                      'year': '2024',
                    },
                  }
                : {
                    'streams': [
                      if (playable)
                        {'url': 'https://video.test/movie.mp4'}
                      else
                        {
                          'externalUrl': 'stremio:///detail/movie/tt4567890',
                          'name': name,
                        },
                    ],
                  },
          ),
          200,
        );
    String? name(Object? result) => metadata
        ? (result as StremioMeta?)?.name
        : (result as List<StremioMeta>).firstOrNull?.name;

    test('detail cache reuses active results: metadata=$metadata', () async {
      var requests = 0;
      await http.runWithClient(
        () async {
          expect(name(await read()), 'Active');
          expect(name(await read()), 'Active');
          expect(requests, 1);
        },
        () => MockClient((_) async {
          requests++;
          return response('Active');
        }),
      );
    });

    for (final change in ['invalidate', 'session', 'route']) {
      test(
        'detail cache rejects old response after $change: metadata=$metadata',
        () async {
          final entered = Completer<void>();
          final release = Completer<http.Response>();
          var requests = 0;
          var active = true;
          await http.runWithClient(
            () async {
              final old = read(current: () => active);
              await entered.future.timeout(const Duration(seconds: 5));
              switch (change) {
                case 'invalidate':
                  service.invalidateCache();
                case 'session':
                  ProfileSessionMemory.clearAll();
                case 'route':
                  active = false;
              }
              expect(name(await read()), 'New');
              release.complete(response('Old'));
              expect(name(await old), isNull);
              expect(name(await read()), 'New');
              expect(requests, 2);
            },
            () => MockClient((_) async {
              requests++;
              if (requests == 1) {
                entered.complete();
                return release.future;
              }
              return response('New');
            }),
          );
        },
      );
    }

    test(
      'detail cache is cleared on profile lifecycle invalidation: metadata=$metadata',
      () async {
        var requests = 0;
        await http.runWithClient(
          () async {
            expect(name(await read()), 'First');
            service.invalidateCache();
            expect(name(await read()), 'Second');
            expect(requests, 2);
          },
          () => MockClient(
            (_) async => response(++requests == 1 ? 'First' : 'Second'),
          ),
        );
      },
    );

    test(
      'retired detail route does not borrow warm cache: metadata=$metadata',
      () async {
        var requests = 0;
        await http.runWithClient(
          () async {
            expect(name(await read()), 'Active');
            expect(name(await read(current: () => false)), isNull);
            expect(name(await read()), 'Active');
            expect(requests, 1);
          },
          () => MockClient((_) async {
            requests++;
            return response('Active');
          }),
        );
      },
    );

    test(
      'foreign captured profile cannot read detail caches: metadata=$metadata',
      () async {
        final origin = ProfileScope(
          profileId: 'origin',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
        final other = ProfileScope(
          profileId: 'other',
          dataGeneration: 1,
          sessionEpoch: 2,
        );
        ProfileRuntime.initializeCommitted(other);
        var requests = 0;
        await http.runWithClient(
          () async {
            expect(
              name(await ProfileRuntime.withCapturedScope(origin, read)),
              isNull,
            );
            expect(requests, 0);
          },
          () => MockClient((_) async {
            requests++;
            return response('Unexpected');
          }),
        );
      },
    );

    if (!metadata) {
      test(
        'late non-recommendation result cannot poison new skip list',
        () async {
          final entered = Completer<void>();
          final release = Completer<http.Response>();
          var requests = 0;
          await http.runWithClient(
            () async {
              final old = read();
              await entered.future.timeout(const Duration(seconds: 5));
              service.invalidateCache();
              release.complete(response('Playable', playable: true));
              expect(name(await old), isNull);
              expect(name(await read()), 'New');
              expect(requests, 2);
            },
            () => MockClient((_) async {
              requests++;
              if (requests == 1) {
                entered.complete();
                return release.future;
              }
              return response('New');
            }),
          );
        },
      );
    }
  }
}
