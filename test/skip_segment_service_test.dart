import 'dart:async';

import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AutoSkipSegmentProvider', () {
    test(
      'queries every provider in parallel and falls back per segment type',
      () async {
        final requestedHosts = <String>{};
        final allRequestsStarted = Completer<void>();
        final provider = AutoSkipSegmentProvider(
          client: MockClient((request) async {
            requestedHosts.add(request.url.host);
            if (requestedHosts.length == 3 && !allRequestsStarted.isCompleted) {
              allRequestsStarted.complete();
            }
            await allRequestsStarted.future;

            switch (request.url.host) {
              case 'api.skipdb.tv':
                return http.Response('''
                {
                  "segments": {
                    "intro": {"start_ms": 10000, "end_ms": 20000},
                    "outro": null
                  }
                }
              ''', 200);
              case 'api.theintrodb.org':
                return http.Response('''
                {
                  "intro": [{"start_ms": 30000, "end_ms": 40000}],
                  "credits": [{"start_ms": 900000, "end_ms": null}]
                }
              ''', 200);
              case 'api.introdb.app':
                return http.Response('''
                {
                  "intro": {"start_ms": 50000, "end_ms": 60000},
                  "outro": {"start_ms": 800000, "end_ms": 950000}
                }
              ''', 200);
              default:
                return http.Response('not found', 404);
            }
          }),
        );

        final result = await provider.fetch(
          imdbId: 'tt0903747',
          season: 1,
          episode: 1,
          duration: const Duration(seconds: 1000),
        );

        expect(requestedHosts, {
          'api.skipdb.tv',
          'api.theintrodb.org',
          'api.introdb.app',
        });
        expect(result.intro?.start, const Duration(seconds: 10));
        expect(result.outro?.start, const Duration(seconds: 900));
      },
    );
  });

  group('SkipDbSegmentProvider', () {
    test(
      'requests a duration-aware episode and parses intro/outro markers',
      () async {
        late Uri requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response('''
          {
            "segments": {
              "intro": {
                "start_ms": 61000,
                "end_ms": 91000,
                "confidence": 0.93,
                "match": "exact"
              },
              "outro": {
                "start_ms": 2760000,
                "end_ms": 2820000,
                "confidence": 0.75,
                "match": "shifted"
              }
            }
          }
        ''', 200);
        });
        final provider = SkipDbSegmentProvider(client: client);

        final result = await provider.fetch(
          imdbId: 'tt0903747',
          season: 1,
          episode: 1,
          duration: const Duration(seconds: 2820),
        );

        expect(requested.host, 'api.skipdb.tv');
        expect(requested.queryParameters, {
          'imdb_id': 'tt0903747',
          'season': '1',
          'episode': '1',
          'duration': '2820',
        });
        expect(result.intro?.start, const Duration(seconds: 61));
        expect(result.intro?.end, const Duration(seconds: 91));
        expect(result.intro?.confidence, 0.93);
        expect(result.outro?.end, const Duration(seconds: 2820));
        expect(
          result.segmentAt(const Duration(seconds: 70))?.type,
          SkipSegmentType.intro,
        );
        expect(result.segmentAt(const Duration(seconds: 100)), isNull);
      },
    );

    test(
      'suppresses timestamps marked out-of-range for this release',
      () async {
        final provider = SkipDbSegmentProvider(
          client: MockClient(
            (_) async => http.Response('''
            {
              "segments": {
                "intro": {
                  "start_ms": 1000,
                  "end_ms": 90000,
                  "match": "out-of-range"
                },
                "outro": null
              }
            }
          ''', 200),
          ),
        );

        final result = await provider.fetch(
          imdbId: 'tt1',
          season: 1,
          episode: 1,
          duration: const Duration(minutes: 42),
        );

        expect(result.intro, isNull);
        expect(result.outro, isNull);
      },
    );

    test('fails closed on a non-success response', () async {
      final provider = SkipDbSegmentProvider(
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );

      final result = await provider.fetch(
        imdbId: 'tt1',
        season: 1,
        episode: 1,
        duration: const Duration(minutes: 42),
      );

      expect(result.intro, isNull);
      expect(result.outro, isNull);
    });
  });

  group('IntroDbSegmentProvider', () {
    test(
      'requests an episode and parses bounded intro/outro markers',
      () async {
        late Uri requested;
        final provider = IntroDbSegmentProvider(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response('''
            {
              "intro": {
                "start_ms": 437000,
                "end_ms": 531000,
                "confidence": 0.95
              },
              "outro": {
                "start_ms": 3631500,
                "end_ms": 3699500,
                "confidence": 1
              }
            }
          ''', 200);
          }),
        );

        final result = await provider.fetch(
          imdbId: 'tt0944947',
          season: 1,
          episode: 1,
          duration: const Duration(seconds: 3720),
        );

        expect(requested.host, 'api.introdb.app');
        expect(requested.queryParameters, {
          'imdb_id': 'tt0944947',
          'season': '1',
          'episode': '1',
        });
        expect(result.intro?.start, const Duration(seconds: 437));
        expect(result.intro?.confidence, 0.95);
        expect(result.outro?.end, const Duration(milliseconds: 3699500));
      },
    );

    test('rejects markers outside the current video duration', () async {
      final provider = IntroDbSegmentProvider(
        client: MockClient(
          (_) async => http.Response('''
            {
              "intro": {"start_ms": 1000, "end_ms": 30000},
              "outro": {"start_ms": 3431000, "end_ms": 3501000}
            }
          ''', 200),
        ),
      );

      final result = await provider.fetch(
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 3500),
      );

      expect(result.intro, isNotNull);
      expect(result.outro, isNull);
    });
  });

  group('TheIntroDbSegmentProvider', () {
    test(
      'parses multiple markers and normalizes media boundary nulls',
      () async {
        late Uri requested;
        final provider = TheIntroDbSegmentProvider(
          client: MockClient((request) async {
            requested = request.url;
            return http.Response('''
            {
              "intro": [
                {"start_ms": null, "end_ms": 31000},
                {"start_ms": 50000, "end_ms": 60000},
                {"start_ms": 50000, "end_ms": 60000}
              ],
              "credits": [
                {"start_ms": 3431000, "end_ms": null}
              ]
            }
          ''', 200);
          }),
        );

        final result = await provider.fetch(
          imdbId: 'tt0903747',
          season: 1,
          episode: 1,
          duration: const Duration(seconds: 3500),
        );

        expect(requested.host, 'api.theintrodb.org');
        expect(requested.queryParameters['duration_ms'], '3500000');
        expect(result.intros, hasLength(2));
        expect(result.intro?.start, Duration.zero);
        expect(
          result.segmentAt(const Duration(seconds: 55))?.type,
          SkipSegmentType.intro,
        );
        expect(result.outro?.end, const Duration(seconds: 3500));
      },
    );

    test('fails closed on API errors and out-of-duration credits', () async {
      var returnServerError = false;
      final provider = TheIntroDbSegmentProvider(
        client: MockClient((_) async {
          if (returnServerError) return http.Response('server error', 500);
          return http.Response('''
            {
              "credits": [{"start_ms": 1746000, "end_ms": null}]
            }
          ''', 200);
        }),
      );

      final invalid = await provider.fetch(
        imdbId: 'tt0386676',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 1380),
      );
      expect(invalid.outro, isNull);

      returnServerError = true;
      final failed = await provider.fetch(
        imdbId: 'tt0386676',
        season: 99,
        episode: 99,
        duration: const Duration(seconds: 1380),
      );
      expect(failed.intros, isEmpty);
      expect(failed.outros, isEmpty);
    });

    test('rejects omitted boundaries but accepts explicit nulls', () async {
      final provider = TheIntroDbSegmentProvider(
        client: MockClient(
          (_) async => http.Response('''
            {
              "intro": [
                {"end_ms": 31000},
                {"start_ms": null, "end_ms": 32000}
              ],
              "credits": [
                {"start_ms": 3431000},
                {"start_ms": 3432000, "end_ms": null}
              ]
            }
          ''', 200),
        ),
      );

      final result = await provider.fetch(
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 3500),
      );

      expect(result.intros, hasLength(1));
      expect(result.intro?.start, Duration.zero);
      expect(result.intro?.end, const Duration(seconds: 32));
      expect(result.outros, hasLength(1));
      expect(result.outro?.start, const Duration(seconds: 3432));
      expect(result.outro?.end, const Duration(seconds: 3500));
    });
  });

  group('mid-episode credits gate', () {
    // The providers do return outros that sit in the middle of the episode, and
    // "Skip credits" was appearing halfway through a watch as a result. A
    // marker that cannot be the credits must never reach the button, whichever
    // provider produced it.

    test('drops a SkipDB outro that starts before 90% of the runtime', () async {
      final provider = SkipDbSegmentProvider(
        client: MockClient(
          (_) async => http.Response('''
            {
              "segments": {
                "intro": {"start_ms": 60000, "end_ms": 90000},
                "outro": {"start_ms": 1800000, "end_ms": 1860000}
              }
            }
          ''', 200),
        ),
      );

      // Outro at 50% of a 60-minute episode: in bounds, and nonsense.
      final result = await provider.fetch(
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 3600),
      );

      expect(result.outro, isNull);
      // The intro is judged on its own merits and survives.
      expect(result.intro?.start, const Duration(seconds: 60));
    });

    test('keeps an outro at exactly 90% and drops one just under', () async {
      Future<SkipSegments> fetchWithOutroStart(int startMs) {
        return IntroDbSegmentProvider(
          client: MockClient(
            (_) async => http.Response('''
              {
                "outro": {"start_ms": $startMs, "end_ms": 1000000}
              }
            ''', 200),
          ),
        ).fetch(
          imdbId: 'tt0903747',
          season: 1,
          episode: 1,
          duration: const Duration(seconds: 1000),
        );
      }

      // The boundary is inclusive, so 90% exactly is a credits marker.
      expect(
        (await fetchWithOutroStart(900000)).outro?.start,
        const Duration(seconds: 900),
      );
      expect((await fetchWithOutroStart(899999)).outro, isNull);
    });

    test('gates TheIntroDB credits, including media-end nulls', () async {
      final provider = TheIntroDbSegmentProvider(
        client: MockClient(
          (_) async => http.Response('''
            {
              "intro": [{"start_ms": null, "end_ms": 31000}],
              "credits": [
                {"start_ms": 1200000, "end_ms": null},
                {"start_ms": 3400000, "end_ms": null}
              ]
            }
          ''', 200),
        ),
      );

      final result = await provider.fetch(
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 3500),
      );

      // A null end means "to the end of the media", which would have made the
      // 34% marker a skip over two thirds of the episode.
      expect(result.outros, hasLength(1));
      expect(result.outro?.start, const Duration(seconds: 3400));
      expect(result.intro?.end, const Duration(seconds: 31));
    });

    test('a gated outro leaves nothing to offer mid-episode', () async {
      final provider = IntroDbSegmentProvider(
        client: MockClient(
          (_) async => http.Response('''
            {
              "outro": {"start_ms": 1740000, "end_ms": 1800000}
            }
          ''', 200),
        ),
      );

      final result = await provider.fetch(
        imdbId: 'tt0903747',
        season: 1,
        episode: 1,
        duration: const Duration(seconds: 3600),
      );

      // What the player actually asks: is there a segment under the playhead?
      expect(result.segmentAt(const Duration(seconds: 1750)), isNull);
      expect(result.outros, isEmpty);
    });
  });

  test('provider registry exposes and creates every native provider', () {
    expect(SkipSegmentProviders.labels.keys, {
      SkipSegmentProviders.auto,
      SkipSegmentProviders.skipDb,
      SkipSegmentProviders.introDb,
      SkipSegmentProviders.theIntroDb,
    });
    expect(
      SkipSegmentProviders.create(SkipSegmentProviders.introDb),
      isA<IntroDbSegmentProvider>(),
    );
    expect(
      SkipSegmentProviders.create(SkipSegmentProviders.theIntroDb),
      isA<TheIntroDbSegmentProvider>(),
    );
    expect(
      SkipSegmentProviders.create(
        SkipSegmentProviders.auto,
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      isA<AutoSkipSegmentProvider>(),
    );
  });

  group('skip segment preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('manual skip buttons default on with Auto selected', () async {
      expect(await StorageService.getSkipSegmentsEnabled(), isTrue);
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderAuto,
      );
    });

    test('persists enablement and normalizes unsupported providers', () async {
      await StorageService.setSkipSegmentsEnabled(false);
      await StorageService.setSkipSegmentProvider(
        StorageService.skipSegmentProviderIntroDb,
      );

      expect(await StorageService.getSkipSegmentsEnabled(), isFalse);
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderIntroDb,
      );

      await StorageService.setSkipSegmentProvider(
        StorageService.skipSegmentProviderTheIntroDb,
      );
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderTheIntroDb,
      );

      await StorageService.setSkipSegmentProvider('removed-provider');
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderAuto,
      );
    });
  });

  testWidgets('skip button uses the segment-specific label', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SkipSegmentButton(
            type: SkipSegmentType.outro,
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('Skip credits'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-segment-button')));
    expect(pressed, isTrue);
  });
}
