import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Completion first eligible movie position at exact threshold never starts a rewatch unmark',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (player) => player.framePosition = Duration.zero,
      );
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      try {
        final prefs = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          prefs.setStringList('finished_movies_v1', ['tt7100000']),
        );
        final writes = (await t.runAsync(CompletionWrites.install))!;
        await d.observe(
          () => f.mount(t, completionScreen(disableAutoResume: true)),
        );
        await d.percent(80);
        await d.drain();
        await d.percent(80);
        await d.drain();
        expect(
          writes.removes.where((key) => key.endsWith('finished_movies_v1')),
          isEmpty,
        );
        expect(
          await writes.physical(ProfileRuntime.capture(), 'finished_movies_v1'),
          ['tt7100000'],
        );
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
  for (final missing in ['season', 'episode', 'identity', 'type']) {
    testWidgets(
      'Completion missing single-file $missing does not spend the guard and public widget delivery retries',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            completionScreen(
              type: missing == 'type' ? null : 'series',
              season: missing == 'season' ? null : 2,
              episode: missing == 'episode' ? null : 3,
              id: missing == 'identity' ? null : 'tt7100000',
              contentTitle: 'Old title',
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(await d.finishedEpisode(title: 'Old title'), isNull);
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              theme: ThemeData.dark(),
              home: completionScreen(
                type: 'series',
                contentTitle: 'Arrived title',
              ),
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(await d.finishedEpisode(title: 'Arrived title'), isNotNull);
          expect(await d.finishedEpisode(title: 'Old title'), isNull);
          expect(f.players, hasLength(1));
          expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final tracker in ['trakt', 'simkl', 'mdblist']) {
    testWidgets(
      'Completion live $tracker widget selector permits local progress when the flag retires',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.mount(
            completionScreen(
              trakt: tracker == 'trakt',
              simkl: tracker == 'simkl',
              mdblist: tracker == 'mdblist',
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            isEmpty,
          );
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              theme: ThemeData.dark(),
              home: completionScreen(),
            ),
          );
          await d.percent(85);
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            {'tt7100000'},
          );
          expect(f.players, hasLength(1));
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final type in ['movie', 'series']) {
    testWidgets(
      'Completion early $type initializer remains below 80 then marks at exact default equality before delivery',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final reads = CompletionDelivery(
          'loadLocalCompletionThresholds',
          (v) => v is List<int> && v.length == 2,
        );
        try {
          await d.thresholds(50, 50);
          await d.observe(
            () => reads.run(() => f.mount(t, completionScreen(type: type))),
          );
          await f.until(t, () => reads.pending.isNotEmpty);
          await d.percent(79.99);
          await d.drain();
          await d.percent(79.99);
          await d.drain();
          if (type == 'movie') {
            expect(
              await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
              isEmpty,
            );
          } else {
            expect(await d.finishedEpisode(), isNull);
          }
          await d.percent(80);
          await d.drain();
          if (type == 'movie') {
            expect(
              await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
              {'tt7100000'},
            );
          } else {
            expect(await d.finishedEpisode(), isNotNull);
          }
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          reads.release();
          await d.drain();
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision,
          );
        } finally {
          reads.release();
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion position and EOF while startup open is held obey validation even with known duration',
    (t) async {
      final open = Completer<void>();
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.delays['open'] = open,
      );
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        await d.observe(() => f.mount(t, completionScreen()));
        f.player.state = f.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        f.player.emit('duration', f.player.state.duration);
        await d.percent(85);
        await d.drain();
        await d.eof();
        expect(
          await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
          isEmpty,
        );
        open.complete();
        await d.drain();
        for (
          var i = 0;
          i < 20 &&
              (await f.finish(
                t,
                MovieProgressStorage.getFinishedMovieIds(),
              )).isEmpty;
          i++
        ) {
          await d.percent(85);
          await d.drain();
        }
        expect(await f.finish(t, MovieProgressStorage.getFinishedMovieIds()), {
          'tt7100000',
        });
      } finally {
        if (!open.isCompleted) {
          open.complete();
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'Completion held rewatch unmark can remove the marker after a later completion without reviving resume saves',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.framePosition = Duration.zero,
      );
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final old = SharedPreferencesStorePlatform.instance;
      CompletionWrites? store;
      final reads = CompletionDelivery(
        'unmarkMovieAsFinished',
        (v) => v is Set<String>,
      );
      try {
        final prefs = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          prefs.setStringList('finished_movies_v1', ['tt7100000']),
        );
        store = await t.runAsync(CompletionWrites.install);
        await d.observe(() => reads.run(() => f.mount(t, completionScreen())));
        for (var i = 0; i < 20 && reads.pending.isEmpty; i++) {
          await d.percent(20);
          await d.drain();
        }
        await f.until(t, () => reads.pending.isNotEmpty);
        await d.percent(85);
        await d.drain();
        final scope = ProfileRuntime.capture();
        expect(await store!.physical(scope, 'finished_movies_v1'), [
          'tt7100000',
        ]);
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        reads.release();
        await d.drain();
        expect(await store.physical(scope, 'finished_movies_v1'), isNull);
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(
            'https://player.test/completion.mp4',
            {'positionMs': 123, 'durationMs': 1200000},
          ),
        );
        await d.tick(const Duration(seconds: 6));
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(
              'https://player.test/completion.mp4',
            ),
          ))?['positionMs'],
          123,
        );
      } finally {
        reads.release();
        await d.close();
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );
}
