import 'dart:async';

import 'package:debrify/features/home/data/home_trakt_continuation_repository.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:flutter_test/flutter_test.dart';

TraktContinueWatchingItem item(String id) => TraktContinueWatchingItem(
  meta: StremioMeta(id: id, name: id, type: 'movie'),
  traktContentType: 'movies',
);

void main() {
  test(
    'disconnection does not read feeds and returns explicit empty shelves',
    () async {
      var calls = 0;
      final repository = HomeTraktContinuationRepository(
        isAuthenticated: () async {
          calls++;
          return false;
        },
        readMovies: () => throw StateError('unexpected movie read'),
        readShows: () => throw StateError('unexpected show read'),
      );
      expect(calls, 0);
      final result = await repository.read(isCurrent: () => true);
      expect(calls, 1);
      expect(result!.authenticated, isFalse);
      expect(result.movies, isEmpty);
      expect(result.shows, isEmpty);
    },
  );

  test(
    'authenticated feeds start concurrently and detach returned containers',
    () async {
      final calls = <String>[];
      final movieRead = Completer<List<TraktContinueWatchingItem>?>();
      final showRead = Completer<List<TraktContinueWatchingItem>?>();
      final started = Completer<void>();
      final repository = HomeTraktContinuationRepository(
        isAuthenticated: () async {
          calls.add('auth');
          return true;
        },
        readMovies: () {
          calls.add('movies');
          return movieRead.future;
        },
        readShows: () {
          calls.add('shows');
          started.complete();
          return showRead.future;
        },
      );
      final request = repository.read(isCurrent: () => true);
      await started.future;
      expect(calls, ['auth', 'movies', 'shows']);
      final movies = [item('first'), item('second')];
      final shows = [item('show')];
      movieRead.complete(movies);
      showRead.complete(shows);
      final result = (await request)!;
      expect(result.authenticated, isTrue);
      expect(result.movies.map((row) => row.id), ['first', 'second']);
      expect(result.shows.single, same(shows.single));
      movies.clear();
      shows.clear();
      expect(result.movies.length, 2);
      expect(result.shows.length, 1);
      expect(result.movies.clear, throwsUnsupportedError);
      expect(result.shows.clear, throwsUnsupportedError);
    },
  );

  for (final failed in ['movies', 'shows']) {
    test('null $failed feed fails the entire refresh without retry', () async {
      var reads = 0;
      final repository = HomeTraktContinuationRepository(
        isAuthenticated: () async => true,
        readMovies: () async {
          reads++;
          return failed == 'movies' ? null : [];
        },
        readShows: () async {
          reads++;
          return failed == 'shows' ? null : [];
        },
      );
      await expectLater(
        repository.read(isCurrent: () => true),
        throwsStateError,
      );
      expect(reads, 2);
    });
  }

  for (final failingStage in ['auth', 'feed']) {
    test('$failingStage exception propagates without retry', () async {
      final error = StateError('failure');
      var authCalls = 0;
      var feedCalls = 0;
      final repository = HomeTraktContinuationRepository(
        isAuthenticated: () async {
          authCalls++;
          if (failingStage == 'auth') throw error;
          return true;
        },
        readMovies: () async {
          feedCalls++;
          throw error;
        },
        readShows: () async {
          feedCalls++;
          return [];
        },
      );
      await expectLater(
        repository.read(isCurrent: () => true),
        throwsA(same(error)),
      );
      expect(authCalls, 1);
      expect(feedCalls, failingStage == 'auth' ? 0 : 2);
    });
  }

  for (final retiredAt in ['before', 'auth', 'feeds']) {
    test(
      'retirement at $retiredAt rejects data and prevents later reads',
      () async {
        var current = retiredAt != 'before';
        var authCalls = 0;
        var feedCalls = 0;
        final repository = HomeTraktContinuationRepository(
          isAuthenticated: () async {
            authCalls++;
            if (retiredAt == 'auth') current = false;
            return true;
          },
          readMovies: () async {
            feedCalls++;
            if (retiredAt == 'feeds') current = false;
            return [item('old')];
          },
          readShows: () async {
            feedCalls++;
            return [];
          },
        );
        expect(await repository.read(isCurrent: () => current), isNull);
        expect(authCalls, retiredAt == 'before' ? 0 : 1);
        expect(feedCalls, retiredAt == 'feeds' ? 2 : 0);
      },
    );
  }
}
