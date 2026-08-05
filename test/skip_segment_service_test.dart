import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  test('provider registry exposes and creates every native provider', () {
    expect(SkipSegmentProviders.labels.keys, {
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
  });

  group('skip segment preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('manual skip buttons default on with SkipDB selected', () async {
      expect(await StorageService.getSkipSegmentsEnabled(), isTrue);
      expect(
        await StorageService.getSkipSegmentProvider(),
        StorageService.skipSegmentProviderSkipDb,
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
        StorageService.skipSegmentProviderSkipDb,
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
