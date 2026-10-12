import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final threshold in [50, 70, 80, 100]) {
    testWidgets(
      'Completion movie threshold $threshold uses equality and performs cleanup only once',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.thresholds(threshold, 90);
          final screen = completionScreen();
          await d.mount(screen);
          await f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'video_completion': {
                'type': 'video',
                'imdbId': 'tt7100000',
                'positionMs': 100,
                'durationMs': 1200000,
              },
              'video_other': {
                'type': 'video',
                'imdbId': 'tt7199999',
                'positionMs': 200,
                'durationMs': 1200000,
              },
            }),
          );
          await f.finish(
            t,
            ContinueWatchingStorage.saveContinueWatchingItem(
              imdbId: 'tt7100000',
              title: 'Completion title',
              contentType: 'movie',
            ),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 100,
              'durationMs': 1200000,
            }),
          );
          final before = LocalCompletionStorage.localCompletionRevision.value;
          await d.percent(threshold - .01);
          await d.drain();
          expect(
            await f.finish(
              t,
              MovieProgressStorage.isMovieFinished('tt7100000'),
            ),
            isFalse,
          );
          expect(LocalCompletionStorage.localCompletionRevision.value, before);
          await d.percent(threshold.toDouble());
          await d.drain();
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            {'tt7100000'},
          );
          expect(
            await f.finish(
              t,
              ContinueWatchingStorage.getContinueWatchingItems(),
            ),
            isEmpty,
          );
          expect((await d.stateMap()).keys, ['video_other']);
          expect(
            await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ),
            isNull,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            before + 2,
          );
          // Recreate a public bookmark while credits continue. Position dispatch
          // must not repeat cleanup and periodic saves must not overwrite it.
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 123,
              'durationMs': 1200000,
            }),
          );
          await d.percent(threshold.toDouble());
          await d.tick(const Duration(seconds: 6));
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ))?['positionMs'],
            123,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            before + 2,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion movie rewatch removes the marker once and preserves a subsequent external marker',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final old = SharedPreferencesStorePlatform.instance;
      CompletionWrites? store;
      try {
        final prefs = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          prefs.setStringList('finished_movies_v1', ['tt7100000', 'tt7199999']),
        );
        store = await t.runAsync(CompletionWrites.install);
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        await d.mount(completionScreen());
        await d.percent(20);
        await d.drain();
        expect(await f.finish(t, MovieProgressStorage.getFinishedMovieIds()), {
          'tt7199999',
        });
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
        expect(
          store!.writes.where((w) => w.$1.endsWith('finished_movies_v1')),
          hasLength(1),
        );
        await f.finish(
          t,
          (await f.finish(
            t,
            ProfilePreferences.instance(),
          )).setStringList('finished_movies_v1', ['tt7100000', 'tt7199999']),
        );
        final count = store.writes.length;
        await d.percent(25);
        await d.percent(30);
        await d.drain();
        expect(await f.finish(t, MovieProgressStorage.getFinishedMovieIds()), {
          'tt7100000',
          'tt7199999',
        });
        expect(store.writes.length, count);
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
      } finally {
        await d.close();
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );

  for (final identity in [null, '', '   ']) {
    testWidgets(
      'Completion blank movie identity ${identity == null ? 'null' : identity.length} leaves ordinary resume active',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          final screen = completionScreen(id: identity);
          await d.mount(screen);
          await d.percent(85);
          await d.tick(const Duration(seconds: 6));
          expect(
            await f.finish(t, MovieProgressStorage.getFinishedMovieIds()),
            isEmpty,
          );
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ))?['positionMs'],
            1020000,
          );
          expect(await d.finishedEpisode(), isNull);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final title in ['Clean supplied title', null]) {
    testWidgets(
      'Completion single-file series chooses ${title == null ? 'fallback' : 'content'} title and exact episode coordinates',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        try {
          await d.thresholds(95, 70);
          await d.mount(
            completionScreen(
              type: 'series',
              contentTitle: title,
              title: 'Fallback no parser',
            ),
          );
          await d.percent(69.99);
          await d.drain();
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          expect(
            await d.finishedEpisode(title: title ?? 'Fallback no parser'),
            isNull,
          );
          await d.percent(70);
          await d.drain();
          final entry = await d.finishedEpisode(
            title: title ?? 'Fallback no parser',
          );
          expect(entry?['finishedAt'], isA<int>());
          final map = await d.stateMap();
          final data =
              map[d.episodeKey(title: title ?? 'Fallback no parser')] as Map;
          expect(data['imdbId'], 'tt7100000');
          expect(data['title'], title ?? 'Fallback no parser');
          expect((data['seasons'] as Map)['2']['3']['positionMs'], 0);
          expect((data['seasons'] as Map)['2']['3']['durationMs'], 1);
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision + 1,
          );
          await d.percent(75);
          await d.percent(79);
          await d.drain();
          expect(
            (await d.finishedEpisode(
              title: title ?? 'Fallback no parser',
            ))?['finishedAt'],
            entry?['finishedAt'],
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision + 1,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Completion movie identity is trimmed before local completion and suppressing resume',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        final screen = completionScreen(id: '  tt7100000  ');
        await d.mount(screen);
        await d.percent(80);
        await d.drain();
        await d.tick(const Duration(seconds: 6));
        expect(await f.finish(t, MovieProgressStorage.getFinishedMovieIds()), {
          'tt7100000',
        });
        expect(
          await f.finish(t, VideoResumeStorage.getVideoResume(screen.videoUrl)),
          isNull,
        );
      } finally {
        await d.close();
      }
    },
  );
}
