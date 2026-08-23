import 'dart:async';

import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(EpisodeTrackerSnapshotService.debugResetRefreshState);

  group('Trakt snapshot correctness', () {
    test('active rewatch playback overrides older watched history', () {
      final snapshot = EpisodeTrackerSnapshotService.debugBuildTraktSnapshot(
        watched: const {'1-1', '1-2'},
        playback: const {'1-1': 3.0, '1_2': 42.5, 'bad': 80, '1-3': -1},
      );

      expect(snapshot, const {'1_1': 3.0, '1_2': 42.5});
    });

    test('an incomplete refresh retains last-good by skipping save', () async {
      var saveCalls = 0;
      final result = await EpisodeTrackerSnapshotService.debugRefreshTrakt(
        scopeKey: 'profile-a-session-1',
        imdbId: 'tt123',
        fetchWatched: () async => const {'1-1'},
        fetchPlayback: () async => null,
        save: (_) async => saveCalls++,
      );

      expect(result, isNull);
      expect(saveCalls, 0);
    });

    test(
      'disconnect clears snapshot but transient auth failure retains it',
      () async {
        final saved = <Map<String, double>>[];

        final disconnected =
            await EpisodeTrackerSnapshotService.debugRefreshTrakt(
              scopeKey: 'profile-a-session-1',
              imdbId: 'tt123',
              connected: false,
              fetchWatched: () async =>
                  fail('must not fetch while disconnected'),
              fetchPlayback: () async =>
                  fail('must not fetch while disconnected'),
              save: (snapshot) async => saved.add(snapshot),
            );
        final temporarilyUnknown =
            await EpisodeTrackerSnapshotService.debugRefreshTrakt(
              scopeKey: 'profile-a-session-1',
              imdbId: 'tt123',
              authenticated: false,
              fetchWatched: () async => fail('must not fetch without auth'),
              fetchPlayback: () async => fail('must not fetch without auth'),
              save: (snapshot) async => saved.add(snapshot),
            );

        expect(disconnected, isEmpty);
        expect(temporarilyUnknown, isNull);
        expect(saved, [isEmpty]);
      },
    );

    test(
      'parallel refreshes coalesce and a warm result respects TTL',
      () async {
        final watchedGate = Completer<Set<String>?>();
        var watchedCalls = 0;
        var playbackCalls = 0;
        var saveCalls = 0;

        Future<Map<String, double>?> refresh() {
          return EpisodeTrackerSnapshotService.debugRefreshTrakt(
            scopeKey: 'profile-a-session-1',
            imdbId: 'tt123',
            fetchWatched: () {
              watchedCalls++;
              return watchedGate.future;
            },
            fetchPlayback: () async {
              playbackCalls++;
              return const {'1-1': 25.0};
            },
            save: (_) async => saveCalls++,
            ttl: const Duration(minutes: 1),
          );
        }

        final first = refresh();
        final second = refresh();
        expect(watchedCalls, 1);
        expect(playbackCalls, 1);

        watchedGate.complete(const {'1-2'});
        expect(await first, const {'1_1': 25.0, '1_2': 100.0});
        expect(await second, const {'1_1': 25.0, '1_2': 100.0});
        expect(saveCalls, 1);

        expect(await refresh(), const {'1_1': 25.0, '1_2': 100.0});
        expect(watchedCalls, 1);
        expect(playbackCalls, 1);
        expect(saveCalls, 1);
      },
    );

    test('cache identity includes profile session scope', () async {
      var calls = 0;

      Future<Map<String, double>?> refresh(String scope) {
        return EpisodeTrackerSnapshotService.debugRefreshTrakt(
          scopeKey: scope,
          imdbId: 'tt123',
          fetchWatched: () async {
            calls++;
            return const {'1-1'};
          },
          fetchPlayback: () async => const {},
          save: (_) async {},
          ttl: const Duration(minutes: 1),
        );
      }

      await refresh('profile-a-session-1');
      await refresh('profile-a-session-1');
      await refresh('profile-a-session-2');

      expect(calls, 2);
    });

    test('a successful mutation makes the next guide refresh fresh', () async {
      var watchedCalls = 0;

      Future<Map<String, double>?> refresh() {
        return EpisodeTrackerSnapshotService.debugRefreshTrakt(
          scopeKey: 'profile-a-session-1',
          imdbId: 'tt123',
          fetchWatched: () async {
            watchedCalls++;
            return watchedCalls == 1 ? const {'1-1'} : const {'1-2'};
          },
          fetchPlayback: () async => const {},
          save: (_) async {},
          ttl: const Duration(minutes: 1),
        );
      }

      expect(await refresh(), const {'1_1': 100.0});
      expect(await refresh(), const {'1_1': 100.0});
      expect(watchedCalls, 1);

      // Successful scrobble/history methods perform this invalidation. The
      // normal (non-force) guide refresh must now bypass its warm cache.
      EpisodeTrackerSnapshotService.debugInvalidateTitle('trakt', 'tt123');

      expect(await refresh(), const {'1_2': 100.0});
      expect(watchedCalls, 2);
    });

    test('a pre-mutation in-flight read cannot publish stale data', () async {
      final oldRead = Completer<Set<String>?>();
      var saveCalls = 0;
      var watchedCalls = 0;

      final stale = EpisodeTrackerSnapshotService.debugRefreshTrakt(
        scopeKey: 'profile-a-session-1',
        imdbId: 'tt123',
        fetchWatched: () {
          watchedCalls++;
          return oldRead.future;
        },
        fetchPlayback: () async => const {},
        save: (_) async => saveCalls++,
      );

      EpisodeTrackerSnapshotService.debugInvalidateTitle('trakt', 'tt123');
      oldRead.complete(const {'1-1'});

      expect(await stale, isNull);
      expect(saveCalls, 0);

      final fresh = await EpisodeTrackerSnapshotService.debugRefreshTrakt(
        scopeKey: 'profile-a-session-1',
        imdbId: 'tt123',
        fetchWatched: () async {
          watchedCalls++;
          return const {'1-2'};
        },
        fetchPlayback: () async => const {},
        save: (_) async => saveCalls++,
      );
      expect(fresh, const {'1_2': 100.0});
      expect(watchedCalls, 2);
      expect(saveCalls, 1);
    });

    test('different shows serialize provider-wide snapshot writes', () async {
      final releaseFirstSave = Completer<void>();
      final firstSaveStarted = Completer<void>();
      var saveCalls = 0;
      var activeSaves = 0;
      var maxActiveSaves = 0;

      Future<void> save(Map<String, double> _) async {
        saveCalls++;
        activeSaves++;
        if (activeSaves > maxActiveSaves) maxActiveSaves = activeSaves;
        if (saveCalls == 1) {
          firstSaveStarted.complete();
          await releaseFirstSave.future;
        }
        activeSaves--;
      }

      Future<Map<String, double>?> refresh(String imdbId) {
        return EpisodeTrackerSnapshotService.debugRefreshTrakt(
          scopeKey: 'profile-a-session-1',
          imdbId: imdbId,
          fetchWatched: () async => const {'1-1'},
          fetchPlayback: () async => const {},
          save: save,
        );
      }

      final first = refresh('tt111');
      await firstSaveStarted.future;
      final second = refresh('tt222');
      await Future<void>.delayed(Duration.zero);
      expect(saveCalls, 1);

      releaseFirstSave.complete();
      await Future.wait([first, second]);
      expect(saveCalls, 2);
      expect(maxActiveSaves, 1);
    });

    test(
      'forced refresh queues behind an older normal in-flight read',
      () async {
        final firstGate = Completer<Set<String>?>();
        final forcedGate = Completer<Set<String>?>();
        var watchedCalls = 0;

        Future<Set<String>?> watched() {
          watchedCalls++;
          return watchedCalls == 1 ? firstGate.future : forcedGate.future;
        }

        Future<Map<String, double>?> refresh({bool force = false}) {
          return EpisodeTrackerSnapshotService.debugRefreshTrakt(
            scopeKey: 'profile-a-session-1',
            imdbId: 'tt123',
            fetchWatched: watched,
            fetchPlayback: () async => const {},
            save: (_) async {},
            force: force,
          );
        }

        final normal = refresh();
        final forced = refresh(force: true);
        expect(watchedCalls, 1);

        firstGate.complete(const {'1-1'});
        expect(await normal, const {'1_1': 100.0});
        await Future<void>.delayed(Duration.zero);
        expect(watchedCalls, 2);

        forcedGate.complete(const {'1-2'});
        expect(await forced, const {'1_2': 100.0});
      },
    );
  });

  group('snapshot write serialization', () {
    test(
      'same profile/provider/show operations run in invocation order',
      () async {
        final firstGate = Completer<void>();
        final events = <String>[];

        final first =
            EpisodeTrackerSnapshotService.debugSerializeSnapshotOperation<int>(
              scopeKey: 'profile-a-session-1',
              provider: 'mdblist',
              imdbId: 'tt123',
              operation: () async {
                events.add('first-start');
                await firstGate.future;
                events.add('first-end');
                return 1;
              },
            );
        final second =
            EpisodeTrackerSnapshotService.debugSerializeSnapshotOperation<int>(
              scopeKey: 'profile-a-session-1',
              provider: 'mdblist',
              imdbId: 'tt123',
              operation: () async {
                events.add('second-start');
                return 2;
              },
            );

        await Future<void>.delayed(Duration.zero);
        expect(events, const ['first-start']);
        firstGate.complete();

        expect(await first, 1);
        expect(await second, 2);
        expect(events, const ['first-start', 'first-end', 'second-start']);
      },
    );
  });

  group('failure-aware Trakt parsing', () {
    test(
      'watched payload distinguishes authoritative empty from malformed',
      () {
        expect(
          TraktService.debugParseWatchedShowEpisodes(const {'seasons': []}),
          isEmpty,
        );
        expect(TraktService.debugParseWatchedShowEpisodes(const {}), isNull);
        expect(
          TraktService.debugParseWatchedShowEpisodes(const {
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1, 'completed': true},
                  {'number': 2, 'completed': false},
                ],
              },
            ],
          }),
          const {'1-1'},
        );
      },
    );

    test('playback payload rejects a malformed target-show checkpoint', () {
      const valid = [
        {
          'progress': 37.5,
          'episode': {'season': 2, 'number': 4},
          'show': {
            'ids': {'imdb': 'TT123'},
          },
        },
      ];
      const malformed = [
        {
          'episode': {'season': 2, 'number': 4},
          'show': {
            'ids': {'imdb': 'tt123'},
          },
        },
      ];

      expect(
        TraktService.debugParseEpisodePlaybackProgress(valid, 'tt123'),
        const {'2-4': 37.5},
      );
      expect(
        TraktService.debugParseEpisodePlaybackProgress(malformed, 'tt123'),
        isNull,
      );
    });
  });
}
