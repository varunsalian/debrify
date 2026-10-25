import 'dart:convert';

import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'support/physical_resume_store.dart';

void main() {
  TraktTestTransport.install();
  for (final failure in ['marker', 'playback cleanup', 'resume cleanup']) {
    testWidgets(
      'Completion caught movie $failure failure preserves partial cleanup and spends the resume-suppression guard',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final old = SharedPreferencesStorePlatform.instance;
        CompletionWrites? store;
        try {
          final screen = completionScreen();
          await d.mount(screen);
          await f.finish(
            t,
            PhysicalResumeStore.savePlaybackStateMap({
              'target': {'type': 'video', 'imdbId': 'tt7100000'},
            }),
          );
          await f.finish(
            t,
            ContinueWatchingStorage.saveContinueWatchingItem(
              imdbId: 'tt7100000',
              title: 'Failure movie',
              contentType: 'movie',
            ),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 111,
              'durationMs': 1200000,
            }),
          );
          store = await t.runAsync(CompletionWrites.install);
          store!.reject = (key) => failure == 'marker'
              ? key.endsWith('finished_movies_v1')
              : failure == 'playback cleanup' &&
                    key.endsWith('playback_state_v1');
          final db = await f.finish(t, DebrifyTvDatabase.instance.database);
          if (failure == 'resume cleanup') {
            await f.finish(
              t,
              db.execute(
                "CREATE TRIGGER completion_fail_resume BEFORE DELETE ON video_resume BEGIN SELECT RAISE(ABORT, 'completion delete'); END",
              ),
            );
          }
          final scope = ProfileRuntime.capture();
          final revision = LocalCompletionStorage.localCompletionRevision.value;
          await d.percent(85);
          await d.drain();
          expect(d.uncaught, isEmpty);
          final finished = await store.physical(scope, 'finished_movies_v1');
          expect(finished, failure == 'marker' ? isNull : ['tt7100000']);
          final map = decodeCompletionPhysical(
            await store.physical(scope, 'playback_state_v1'),
          );
          expect(
            map.keys,
            failure == 'resume cleanup' ? isEmpty : contains('target'),
          );
          final cw =
              jsonDecode(
                    (await store.physical(scope, 'continue_watching_v1'))
                        as String,
                  )
                  as List;
          expect(
            cw.map((e) => e['imdbId']),
            failure == 'marker'
                ? contains('tt7100000')
                : isNot(contains('tt7100000')),
          );
          expect(
            await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ),
            failure == 'resume cleanup' ? isNotNull : isNull,
          );
          expect(
            LocalCompletionStorage.localCompletionRevision.value,
            revision +
                (failure == 'marker'
                    ? 0
                    : failure == 'playback cleanup'
                    ? 1
                    : 2),
          );
          store.reject = null;
          if (failure == 'resume cleanup') {
            await f.finish(
              t,
              db.execute('DROP TRIGGER completion_fail_resume'),
            );
          }
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 123,
              'durationMs': 1200000,
            }),
          );
          final writes = store.writes.length;
          await d.percent(90);
          await d.tick(const Duration(seconds: 6));
          expect(store.writes.length, writes);
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(screen.videoUrl),
            ))?['positionMs'],
            123,
          );
          expect(await store.physical(scope, 'finished_movies_v1'), finished);
        } finally {
          store?.reject = null;
          final db = await f.finish(t, DebrifyTvDatabase.instance.database);
          await f.finish(
            t,
            db.execute('DROP TRIGGER IF EXISTS completion_fail_resume'),
          );
          await d.close();
          SharedPreferencesStorePlatform.instance = old;
        }
      },
    );
  }

  testWidgets(
    'Completion caught episode failure spends position one-shot but EOF retries the physical write',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final old = SharedPreferencesStorePlatform.instance;
      CompletionWrites? store;
      try {
        await d.mount(completionScreen(type: 'series'));
        store = await t.runAsync(CompletionWrites.install);
        store!.reject = (k) => k.endsWith('playback_state_v1');
        final scope = ProfileRuntime.capture();
        final revision = LocalCompletionStorage.localCompletionRevision.value;
        await d.percent(85);
        await d.drain();
        expect(d.uncaught, isEmpty);
        final first = store.writes
            .where((w) => w.$1.endsWith('playback_state_v1'))
            .length;
        expect(first, 1);
        expect(
          decodeCompletionPhysical(
            await store.physical(scope, 'playback_state_v1'),
          ),
          isEmpty,
        );
        expect(LocalCompletionStorage.localCompletionRevision.value, revision);
        store.reject = null;
        await d.percent(86);
        await d.drain();
        expect(
          store.writes.where((w) => w.$1.endsWith('playback_state_v1')),
          hasLength(first),
        );
        await d.eof();
        await d.drain();
        expect(
          store.writes.where((w) => w.$1.endsWith('playback_state_v1')),
          hasLength(first + 1),
        );
        final data = decodeCompletionPhysical(
          await store.physical(scope, 'playback_state_v1'),
        );
        expect(
          data[d.episodeKey()]['finishedEpisodes']['2']['3']['finishedAt'],
          isA<int>(),
        );
        expect(
          LocalCompletionStorage.localCompletionRevision.value,
          revision + 1,
        );
      } finally {
        store?.reject = null;
        await d.close();
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );

  testWidgets(
    'Completion unawaited rewatch failure escapes but its flag prevents another unmark',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.framePosition = Duration.zero,
      );
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      final old = SharedPreferencesStorePlatform.instance;
      CompletionWrites? store;
      try {
        final prefs = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          prefs.setStringList('finished_movies_v1', ['tt7100000']),
        );
        store = await t.runAsync(CompletionWrites.install);
        store!.reject = (key) => key.endsWith('finished_movies_v1');
        await d.observe(() => f.mount(t, completionScreen()));
        for (var frame = 0; frame < 30 && d.uncaught.isEmpty; frame++) {
          await d.position(240000);
          await f.advance(t, const Duration(milliseconds: 100));
        }
        expect(d.uncaught, hasLength(1));
        expect(d.uncaught.single, isA<StateError>());
        expect(d.uncaught.single.toString(), contains('completion remove'));
        d.uncaught.clear();
        final scope = ProfileRuntime.capture();
        expect(await store.physical(scope, 'finished_movies_v1'), [
          'tt7100000',
        ]);
        final count = store.removes.length;
        store.reject = null;
        // SharedPreferences updated its cache before the rejected transport
        // remove. Refill that public cache so only the spent player flag can
        // suppress the next real unmark attempt.
        final refill = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          refill.setStringList('finished_movies_v1', ['tt7100000']),
        );
        await d.percent(25);
        await d.percent(30);
        await d.drain();
        expect(store.removes.length, count);
        expect(await store.physical(scope, 'finished_movies_v1'), [
          'tt7100000',
        ]);
      } finally {
        store?.reject = null;
        d.uncaught.clear();
        await d.close();
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );

  testWidgets(
    'Completion malformed threshold read is uncaught and leaves both default thresholds usable',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      try {
        final prefs = await f.finish(t, ProfilePreferences.instance());
        await f.finish(
          t,
          prefs.setString('movie_completion_threshold', 'invalid integer'),
        );
        await d.observe(() => f.mount(t, completionScreen()));
        expect(d.uncaught, hasLength(1));
        expect(d.uncaught.single, isA<TypeError>());
        d.uncaught.clear();
        await d.percent(79.99);
        await d.drain();
        final store = await f.finish(t, ProfilePreferences.instance());
        expect(store.getStringList('finished_movies_v1'), isNull);
        await d.percent(80);
        await d.drain();
        expect(store.getStringList('finished_movies_v1'), ['tt7100000']);
      } finally {
        d.uncaught.clear();
        await d.close();
      }
    },
  );
}
