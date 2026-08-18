import 'package:debrify/services/storage_service.dart';
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

  test(
    'disconnected Simkl account returns an explicit empty snapshot',
    () async {
      final snapshot = await SimklService.instance.fetchCompletedTitleIds();

      expect(snapshot, isNotNull);
      expect(snapshot!.movies, isEmpty);
      expect(snapshot.series, isEmpty);
    },
  );
}
