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
      await StorageService.setSkipSegmentProvider('removed-provider');

      expect(await StorageService.getSkipSegmentsEnabled(), isFalse);
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
