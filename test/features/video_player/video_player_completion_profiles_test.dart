import 'dart:convert';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
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
  for (final action in ['episode', 'mark', 'unmark']) {
    for (final disposed in [false, true]) {
      testWidgets(
        'Completion held $action read from A writes its map into B disposed=$disposed and pins physical cleanup and resume ownership',
        (t) async {
          final f = VideoPlayerEnvironment(
            configurePlayer: (p) => p.framePosition = action == 'unmark'
                ? Duration.zero
                : const Duration(milliseconds: 80),
          );
          final d = LocalCompletionDriver(t, f);
          await d.initialize();
          final oldStore = SharedPreferencesStorePlatform.instance;
          final store = (await t.runAsync(CompletionWrites.install))!;
          final reads = CompletionDelivery(
            action == 'episode'
                ? 'markEpisodeAsFinished'
                : action == 'mark'
                ? 'markMovieAsFinished'
                : 'unmarkMovieAsFinished',
            (v) => action == 'episode'
                ? v is Map<String, dynamic>
                : v is Set<String>,
          );
          reads.armed = false;
          try {
            final a = ProfileRuntime.capture();
            final b = await completionIncomingProfile(t, f);
            final bp = await f.finish(t, ProfilePreferences.instance());
            await f.finish(
              t,
              bp.setStringList('finished_movies_v1', ['tt7299999']),
            );
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'B_unrelated': {
                  'type': 'video',
                  'title': 'B only',
                  'imdbId': 'tt7299999',
                },
                'B_target': {
                  'type': 'video',
                  'title': 'B target',
                  'imdbId': 'tt7100000',
                },
              }),
            );
            await f.finish(
              t,
              ContinueWatchingStorage.saveContinueWatchingItem(
                imdbId: 'tt7100000',
                title: 'B target',
                contentType: 'movie',
              ),
            );
            final screen = completionScreen(
              type: action == 'episode' ? 'series' : 'movie',
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
                'positionMs': 222,
                'durationMs': 1200000,
              }),
            );
            final outgoing = await completionActivate(t, f, a);
            final ap = await f.finish(t, ProfilePreferences.instance());
            await f.finish(
              t,
              ap.setStringList(
                'finished_movies_v1',
                action == 'unmark' ? ['tt7100000', 'tt7199999'] : ['tt7199999'],
              ),
            );
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'A_unrelated': {
                  'type': 'video',
                  'title': 'A only',
                  'imdbId': 'tt7199999',
                },
                'A_target': {
                  'type': 'video',
                  'title': 'A target',
                  'imdbId': 'tt7100000',
                },
              }),
            );
            await f.finish(
              t,
              ContinueWatchingStorage.saveContinueWatchingItem(
                imdbId: 'tt7100000',
                title: 'A target',
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
            await d.observe(() => reads.run(() => f.mount(t, screen)));
            reads.armed = true;
            final started = DateTime.now().millisecondsSinceEpoch;
            await d.percent(action == 'unmark' ? 20 : 85);
            await d.drain();
            if (reads.pending.isEmpty) {
              await d.percent(action == 'unmark' ? 20 : 85);
              await d.drain();
            }
            await f.until(t, () => reads.pending.isNotEmpty);
            final heldAt = DateTime.now().millisecondsSinceEpoch;
            final revision =
                LocalCompletionStorage.localCompletionRevision.value;
            final captured = jsonDecode(
              jsonEncode(
                reads.values.single is Set
                    ? (reads.values.single as Set).toList()
                    : reads.values.single,
              ),
            );
            if (disposed) {
              await d.retired();
            }
            final incoming = await completionActivate(t, f, b);
            expect(await store.physical(incoming, 'finished_movies_v1'), [
              'tt7299999',
            ]);
            expect(
              decodeCompletionPhysical(
                await store.physical(incoming, 'playback_state_v1'),
              ).keys,
              contains('B_unrelated'),
            );
            reads.release();
            await d.drain();
            final af = await store.physical(outgoing, 'finished_movies_v1');
            final bf = await store.physical(incoming, 'finished_movies_v1');
            final am = decodeCompletionPhysical(
              await store.physical(outgoing, 'playback_state_v1'),
            );
            final bm = decodeCompletionPhysical(
              await store.physical(incoming, 'playback_state_v1'),
            );
            if (action == 'episode') {
              expect(af, ['tt7199999']);
              expect(bf, ['tt7299999']);
              expect(am['A_unrelated'], {
                'type': 'video',
                'title': 'A only',
                'imdbId': 'tt7199999',
              });
              expect(
                (am[d.episodeKey()] as Map?)?['finishedEpisodes'],
                anyOf(isNull, isEmpty),
              );
              expect(bm.keys, contains('A_unrelated'));
              expect(bm.keys, isNot(contains('B_unrelated')));
              expect(bm['A_unrelated'], (captured as Map)['A_unrelated']);
              expect(bm.keys, contains(d.episodeKey()));
              final finish =
                  bm[d.episodeKey()]['finishedEpisodes']['2']['3']['finishedAt']
                      as int;
              expect(finish, inInclusiveRange(started, heldAt));
              expect(
                LocalCompletionStorage.localCompletionRevision.value,
                revision + 1,
              );
            } else {
              expect(
                af,
                action == 'unmark' ? ['tt7100000', 'tt7199999'] : ['tt7199999'],
              );
              expect(
                bf,
                action == 'unmark' ? ['tt7199999'] : ['tt7100000', 'tt7199999'],
              );
              expect(am.keys, contains('A_target'));
              expect(bm.keys, contains('B_unrelated'));
              expect(
                bm.keys,
                action == 'mark'
                    ? isNot(contains('B_target'))
                    : contains('B_target'),
              );
              final acw =
                  jsonDecode(
                        (await store.physical(outgoing, 'continue_watching_v1'))
                            as String,
                      )
                      as List;
              final bcw =
                  jsonDecode(
                        (await store.physical(incoming, 'continue_watching_v1'))
                            as String,
                      )
                      as List;
              expect(acw.map((e) => e['imdbId']), contains('tt7100000'));
              expect(
                bcw.map((e) => e['imdbId']),
                action == 'mark'
                    ? isNot(contains('tt7100000'))
                    : contains('tt7100000'),
              );
              expect(
                LocalCompletionStorage.localCompletionRevision.value,
                revision + (action == 'mark' ? 2 : 1),
              );
            }
            final ar = await f.finish(
              t,
              completionPhysicalResume(f, outgoing, screen.videoUrl),
            );
            final br = await f.finish(
              t,
              completionPhysicalResume(f, incoming, screen.videoUrl),
            );
            expect(ar, action == 'mark' ? isNull : isNotNull);
            expect(
              br?['position_ms'],
              222,
              reason:
                  'Completion resume deletion captures the outgoing DB scope',
            );
            if (!disposed) {
              await d.retired();
            }
            expect(await store.physical(outgoing, 'finished_movies_v1'), af);
            expect(await store.physical(incoming, 'finished_movies_v1'), bf);
          } finally {
            reads.release();
            await d.close();
            SharedPreferencesStorePlatform.instance = oldStore;
          }
        },
      );
    }
  }
}
