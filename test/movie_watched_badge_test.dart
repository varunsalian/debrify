import 'dart:io';

import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/simkl/simkl_item_transformer.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/widgets/movie_watched_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('badge follows local movie completion changes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MovieWatchedBadge(imdbId: 'tt-badge')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await StorageService.markMovieAsFinished('tt-badge');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await StorageService.unmarkMovieAsFinished('tt-badge');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('local completion does not mark a series title watched', (
    tester,
  ) async {
    await StorageService.markMovieAsFinished('tt-series-local');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MovieWatchedBadge(
            imdbId: 'tt-series-local',
            contentType: 'series',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('Home-scoped badge follows Home tick sources only', (
    tester,
  ) async {
    await StorageService.markMovieAsFinished('tt-home-mask');
    await StorageService.setHomeTickSources(<TrackingSource>{});

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MovieWatchedBadge(imdbId: 'tt-home-mask'),
              MovieWatchedBadge(imdbId: 'tt-home-mask', tickPolicyScoped: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Detail/search consumers remain merged; only the Home instance is masked.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await StorageService.setHomeTickSources(<TrackingSource>{
      TrackingSource.local,
    });
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });

  test(
    'disconnected Simkl account returns an explicit empty snapshot',
    () async {
      final snapshot = await SimklService.instance.fetchCompletedTitleIds();

      expect(snapshot, isNotNull);
      expect(snapshot!.movies, isEmpty);
      expect(snapshot.series, isEmpty);
    },
  );

  test('Simkl caught-up series ignores unaired episodes and Season 0 next', () {
    final animeMovie = <String, dynamic>{
      'status': 'completed',
      'anime_type': 'movie',
      'show': {
        'title': 'Anime Film',
        'ids': {'imdb': 'tt-anime-movie'},
      },
    };
    final snapshot = SimklService.debugParseCompletedTitleIds({
      'movies': [
        {
          'status': 'completed',
          'movie': {
            'ids': {'imdb': 'TT-MOVIE'},
          },
        },
      ],
      'shows': [
        {
          // Ongoing shows remain in Watching on Simkl even when the member has
          // watched every currently aired regular episode.
          'status': 'watching',
          'next_to_watch': 'S00E01',
          'watched_episodes_count': 34,
          'total_episodes_count': 35,
          'not_aired_episodes_count': 1,
          'show': {
            'ids': {'imdb': 'TT15677150'},
          },
        },
        {
          'status': 'watching',
          'watched_episodes_count': 33,
          'total_episodes_count': 35,
          'not_aired_episodes_count': 1,
          'show': {
            'ids': {'imdb': 'TT-INCOMPLETE'},
          },
        },
      ],
      'anime': [animeMovie],
    });

    expect(snapshot.movies, {'tt-movie', 'tt-anime-movie'});
    expect(snapshot.series, {'tt15677150'});
    expect(
      SimklItemTransformer.transformItem(
        animeMovie,
        inferredType: 'series',
      )?.type,
      'movie',
    );
    expect(SimklService.parseSimklEpisodeCode('S00E01'), isNull);
    expect(SimklService.parseSimklEpisodeCode('S03E12'), (
      season: 3,
      episode: 12,
    ));
  });

  test(
    'in-flight refresh hands a watched mutation to the deferred refresh',
    () {
      final source = File(
        'lib/services/watched_status_service.dart',
      ).readAsStringSync();
      final completion = source.substring(
        source.indexOf('void _startRefresh()'),
      );

      expect(
        completion,
        contains('else if (_mdblistDirty && _mdblistDirtyAt != null)'),
      );
      expect(completion, contains('_consumeMdblistDirty();'));
      expect(
        completion,
        contains(
          'API failures leave dirtyAt null and deliberately do not auto-loop.',
        ),
      );
    },
  );
}
