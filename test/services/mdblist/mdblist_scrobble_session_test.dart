import 'dart:async';

import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_scrobble_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const movie = MdblistScrobbleTarget.movie(MdblistMediaIds(imdb: 'tt0111161'));
  const episode = MdblistScrobbleTarget.episode(
    MdblistMediaIds(imdb: 'tt0903747'),
    season: 1,
    episode: 2,
  );

  test('uses pause checkpoints and never start', () async {
    final calls = <String>[];
    final session = MdblistScrobbleSession(
      target: movie,
      budgetAvailable: () => true,
      sender: (action, target, progress) async {
        calls.add('$action:${progress.toStringAsFixed(0)}');
        return const MdblistResult.success({});
      },
    );

    session.updatePosition(Duration.zero, const Duration(minutes: 100));
    session.play();
    await session.flush();
    session.updatePosition(
      const Duration(minutes: 30),
      const Duration(minutes: 100),
    );
    session.pause();
    await session.flush();

    expect(calls, ['pause:1', 'pause:30']);
  });

  test('80 percent is inclusive completion and stop is exactly once', () async {
    final calls = <String>[];
    final session = MdblistScrobbleSession(
      target: movie,
      budgetAvailable: () => true,
      sender: (action, target, progress) async {
        calls.add('$action:${progress.toStringAsFixed(0)}');
        return const MdblistResult.success({});
      },
    );
    session.updatePosition(
      const Duration(minutes: 79),
      const Duration(minutes: 100),
    );
    session.seek(const Duration(minutes: 80), const Duration(minutes: 100));
    session.complete();
    session.exit();
    await session.flush();

    expect(calls, ['stop:80']);
  });

  test(
    'episode switch retries a failed completion before replacing target',
    () async {
      final calls = <String>[];
      var stopAttempts = 0;
      final session = MdblistScrobbleSession(
        target: episode,
        budgetAvailable: () => true,
        sender: (action, target, progress) async {
          calls.add(
            '${target.season}-${target.episode}:$action:${progress.toStringAsFixed(0)}',
          );
          if (action == 'stop' && stopAttempts++ == 0) {
            return const MdblistResult.failure(
              MdblistResultKind.transientFailure,
              statusCode: 503,
            );
          }
          return const MdblistResult.success({});
        },
      );
      session.updatePosition(
        const Duration(minutes: 81),
        const Duration(minutes: 100),
      );
      session.complete();

      await session.switchTarget(
        const MdblistScrobbleTarget.episode(
          MdblistMediaIds(imdb: 'tt0903747'),
          season: 1,
          episode: 3,
        ),
      );

      expect(calls, ['1-2:stop:100', '1-2:stop:100']);
    },
  );

  test('player close retries a failed completion once', () async {
    final calls = <String>[];
    var stopAttempts = 0;
    final session = MdblistScrobbleSession(
      target: episode,
      budgetAvailable: () => true,
      sender: (action, target, progress) async {
        calls.add(action);
        if (stopAttempts++ == 0) {
          return const MdblistResult.failure(
            MdblistResultKind.transientFailure,
            statusCode: 503,
          );
        }
        return const MdblistResult.success({});
      },
    );
    session.updatePosition(
      const Duration(minutes: 90),
      const Duration(minutes: 100),
    );

    await session.close();

    expect(calls, ['stop', 'stop']);
  });

  test('seek back below completion restores a durable checkpoint', () async {
    final calls = <String>[];
    final session = MdblistScrobbleSession(
      target: movie,
      budgetAvailable: () => true,
      sender: (action, target, progress) async {
        calls.add('$action:${progress.toStringAsFixed(0)}');
        return const MdblistResult.success({});
      },
    );
    session.updatePosition(
      const Duration(minutes: 79),
      const Duration(minutes: 100),
    );
    session.seek(const Duration(minutes: 81), const Duration(minutes: 100));
    session.seek(const Duration(minutes: 50), const Duration(minutes: 100));
    await session.flush();

    expect(calls, ['stop:81', 'pause:50']);
  });

  test(
    'episode switch preserves the old identity before checkpointing new',
    () async {
      final calls = <String>[];
      final session = MdblistScrobbleSession(
        target: movie,
        budgetAvailable: () => true,
        sender: (action, target, progress) async {
          calls.add('${target.isEpisode ? 'episode' : 'movie'}:$action');
          return const MdblistResult.success({});
        },
      );
      session.updatePosition(
        const Duration(minutes: 10),
        const Duration(minutes: 100),
      );
      session.play();
      await session.flush();
      await session.switchTarget(
        episode,
        position: const Duration(minutes: 2),
        duration: const Duration(minutes: 40),
      );
      await session.flush();

      expect(calls, ['movie:pause', 'episode:pause']);
    },
  );

  test(
    'exit below completion persists a pause instead of orphaned stop',
    () async {
      final calls = <String>[];
      final session = MdblistScrobbleSession(
        target: movie,
        budgetAvailable: () => true,
        sender: (action, target, progress) async {
          calls.add('$action:${progress.toStringAsFixed(0)}');
          return const MdblistResult.success({});
        },
      );

      session.updatePosition(
        const Duration(minutes: 8),
        const Duration(minutes: 100),
      );
      session.exit();
      await session.close();

      expect(calls, ['pause:8']);
    },
  );

  test('progress is rounded to the two decimals accepted by MDBList', () async {
    final calls = <double>[];
    final session = MdblistScrobbleSession(
      target: movie,
      budgetAvailable: () => true,
      sender: (action, target, progress) async {
        calls.add(progress);
        return const MdblistResult.success({});
      },
    );

    session.updatePosition(
      const Duration(milliseconds: 14257),
      const Duration(seconds: 100),
    );
    session.exit();
    await session.flush();

    expect(calls, [14.26]);
  });

  test('quota floor shuts down periodic checkpointing', () async {
    final calls = <String>[];
    final session = MdblistScrobbleSession(
      target: movie,
      budgetAvailable: () => false,
      sender: (action, target, progress) async {
        calls.add(action);
        return const MdblistResult.success({});
      },
    );
    session.updatePosition(
      const Duration(minutes: 10),
      const Duration(minutes: 100),
    );
    session.play();
    await session.flush();

    expect(calls, isEmpty);
  });

  group('Android TV bridge contract', () {
    test(
      'first native checkpoint uses the resolved starting episode',
      () async {
        final calls = <String>[];
        final session = MdblistScrobbleSession(
          target: const MdblistScrobbleTarget.episode(
            MdblistMediaIds(imdb: 'tt2707408'),
            season: 1,
            episode: 8,
          ),
          budgetAvailable: () => true,
          sender: (action, target, progress) async {
            calls.add(
              'S${target.season}E${target.episode}:$action:'
              '${progress.toStringAsFixed(0)}',
            );
            return const MdblistResult.success({});
          },
        );

        // Mirrors the native bridge's first progress frame after startIndex has
        // selected index 7 from a season pack.
        session.seek(const Duration(seconds: 1), const Duration(minutes: 50));
        session.play();
        await session.flush();

        expect(calls, hasLength(1));
        expect(calls.single, startsWith('S1E8:pause:'));
      },
    );

    test(
      'native episode change finalizes old identity before new checkpoint',
      () async {
        final calls = <String>[];
        final session = MdblistScrobbleSession(
          target: const MdblistScrobbleTarget.episode(
            MdblistMediaIds(imdb: 'tt2707408'),
            season: 1,
            episode: 8,
          ),
          budgetAvailable: () => true,
          sender: (action, target, progress) async {
            calls.add(
              'S${target.season}E${target.episode}:$action:'
              '${progress.toStringAsFixed(0)}',
            );
            return const MdblistResult.success({});
          },
        );

        session.updatePosition(
          const Duration(minutes: 49),
          const Duration(minutes: 50),
        );
        session.play();
        await session.flush();
        await session.switchTarget(
          const MdblistScrobbleTarget.episode(
            MdblistMediaIds(imdb: 'tt2707408'),
            season: 1,
            episode: 9,
          ),
          position: const Duration(seconds: 1),
          duration: const Duration(minutes: 50),
        );
        await session.flush();

        expect(calls, hasLength(2));
        expect(calls.first, 'S1E8:stop:98');
        expect(calls.last, startsWith('S1E9:pause:'));
      },
    );

    test(
      'native finish waits for final scrobble before return refresh',
      () async {
        final requestStarted = Completer<void>();
        final releaseResponse = Completer<void>();
        var returnedToFlutter = false;
        final session = MdblistScrobbleSession(
          target: const MdblistScrobbleTarget.episode(
            MdblistMediaIds(imdb: 'tt2707408'),
            season: 1,
            episode: 8,
          ),
          budgetAvailable: () => true,
          sender: (action, target, progress) async {
            requestStarted.complete();
            await releaseResponse.future;
            return const MdblistResult.success({});
          },
        );
        session.updatePosition(
          const Duration(minutes: 49),
          const Duration(minutes: 50),
        );

        // _handlePlaybackFinished awaits close() before the native activity's
        // return notification is allowed to refresh Home/detail state.
        final finish = session.close().then((_) => returnedToFlutter = true);
        await requestStarted.future;
        expect(returnedToFlutter, isFalse);

        releaseResponse.complete();
        await finish;
        expect(returnedToFlutter, isTrue);
      },
    );
  });
}
