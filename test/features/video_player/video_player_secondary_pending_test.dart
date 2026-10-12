import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  TraktTestTransport.install();
  for (final retire in ['episode', 'dispose', 'profile']) {
    testWidgets(
      'MDBList pending outgoing checkpoint across $retire preserves payload owner revisions and timer cleanup',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reply = Completer<http.Response>();
        Future<void>? selection;
        var completed = false;
        try {
          await d.mount(
            secondaryScreen(
              simkl: false,
              playlist: traktPlaylist,
              season: 1,
              episode: 1,
            ),
          );
          await d.waitCheckpoint('mdblist', 1);
          final b = await traktBrowser(t, f);
          f.network.handler = (r) {
            if (r.url.host == 'api.mdblist.com' &&
                r.url.path == '/scrobble/pause' &&
                (jsonDecode(r.body) as Map)['progress'] == 25) {
              return reply.future;
            }
            return secondaryReply(r);
          };
          await d.position(300000);
          await d.tick(const Duration(minutes: 2));
          await d.waitCheckpoint('mdblist', 2);
          d.expectCheckpoint('mdblist', 1, 'pause', 25, season: 1, episode: 1);
          final revision = MdblistService.instance.playbackRevision.value;
          if (retire == 'episode') {
            selection = b.onEpisodeSelected(1, 2);
            selection!.then((_) => completed = true);
            await d.drain();
            expect(completed, isFalse);
            expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
          }
          if (retire == 'dispose') await d.retired();
          if (retire == 'profile') await incomingProfile(t, f);
          expect(d.forTracker('mdblist'), hasLength(2));
          expect(MdblistService.instance.playbackRevision.value, revision);
          reply.complete(http.Response('{}', 201));
          if (selection != null) await f.finish(t, selection);
          await d.drain();
          if (retire == 'episode') {
            await d.waitCheckpoint('mdblist', 3);
            d.expectCheckpoint('mdblist', 2, 'pause', 1, season: 1, episode: 2);
            expect(completed, isTrue);
            expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
            await f.until(
              t,
              () =>
                  MdblistService.instance.playbackRevision.value ==
                  revision + 2,
            );
          } else {
            await f.until(
              t,
              () => f.network.pendingByClient.values.every((p) => p.isEmpty),
            );
            expect(d.forTracker('mdblist'), hasLength(2));
            expect(
              MdblistService.instance.playbackRevision.value,
              revision + (retire == 'dispose' ? 1 : 0),
            );
          }
          if (retire != 'episode') {
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          }
          if (retire == 'profile') await d.retired();
          if (retire != 'episode') {
            await d.tick(const Duration(minutes: 4));
            expect(d.forTracker('mdblist'), hasLength(2));
          }
        } finally {
          if (!reply.isCompleted) reply.complete(http.Response('{}', 201));
          if (selection != null) await f.finish(t, selection);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'MDBList close awaits failed outgoing completion and retries its captured target before finishing disposal',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final reply = Completer<http.Response>();
      try {
        await d.mount(secondaryScreen(simkl: false));
        await d.waitCheckpoint('mdblist', 1);
        var stops = 0;
        f.network.handler = (r) {
          if (r.url.host == 'api.mdblist.com' &&
              r.url.path == '/scrobble/stop') {
            stops++;
            if (stops == 1) return reply.future;
          }
          return secondaryReply(r);
        };
        await d.seekBeforeLanding(.9);
        await d.waitCheckpoint('mdblist', 2);
        final revision = MdblistService.instance.playbackRevision.value;
        await d.retired();
        expect(d.trackerActions('mdblist'), ['pause', 'stop']);
        expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        reply.complete(http.Response('{}', 503));
        await d.waitCheckpoint('mdblist', 3);
        d.expectCheckpoint('mdblist', 1, 'stop', 90);
        d.expectCheckpoint('mdblist', 2, 'stop', 90);
        await f.until(
          t,
          () => MdblistService.instance.playbackRevision.value == revision + 1,
        );
        await d.tick(const Duration(minutes: 4));
        expect(d.trackerActions('mdblist'), ['pause', 'stop', 'stop']);
      } finally {
        if (!reply.isCompleted) reply.complete(http.Response('{}', 503));
        await d.close();
      }
    },
  );

  for (final response in [201, 409]) {
    for (final retire in ['dispose', 'profile']) {
      testWidgets(
        'Simkl held $response stop across $retire pins response revisions and service-owned recovery',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = SecondaryTrackerDriver(t, f);
          await d.initialize();
          final reply = Completer<http.Response>();
          try {
            await d.mount(secondaryScreen(mdblist: false));
            var stops = 0;
            f.network.handler = (r) {
              if (r.url.host == 'api.simkl.com' &&
                  r.url.path == '/scrobble/stop') {
                stops++;
                if (stops == 1) return reply.future;
              }
              return secondaryReply(r);
            };
            await d.seek(.81);
            await d.waitCheckpoint('simkl', 1);
            final revision = EpisodeTrackerSnapshotRevision.identity(
              'simkl',
              'tt5100000',
            );
            if (retire == 'dispose') {
              await d.retired();
            } else {
              await incomingProfile(t, f);
              await t.runAsync(
                () => SimklStorage.setSimklAccessToken(
                  'vplayer-synthetic-incoming-simkl',
                ),
              );
            }
            expect(d.trackerActions('simkl'), ['stop']);
            reply.complete(http.Response('{}', response));
            await f.until(
              t,
              () => f.network.pendingByClient.values.every((p) => p.isEmpty),
            );
            await d.drain();
            if (response == 201) {
              expect(
                EpisodeTrackerSnapshotRevision.identity('simkl', 'tt5100000'),
                revision + 1,
              );
            } else {
              expect(
                EpisodeTrackerSnapshotRevision.identity('simkl', 'tt5100000'),
                revision,
              );
              await d.tick(const Duration(seconds: 24));
              expect(d.trackerActions('simkl'), ['stop']);
              await d.tick(const Duration(seconds: 1));
              if (retire == 'dispose') {
                await d.waitCheckpoint('simkl', 2);
                d.expectCheckpoint('simkl', 1, 'stop', 81);
                await f.until(
                  t,
                  () =>
                      EpisodeTrackerSnapshotRevision.identity(
                        'simkl',
                        'tt5100000',
                      ) ==
                      revision + 1,
                );
                expect(
                  f.network.requests.where(
                    (r) =>
                        r.url.host == 'api.simkl.com' &&
                        r.url.path == '/sync/playback/episodes',
                  ),
                  hasLength(1),
                );
              } else {
                expect(d.trackerActions('simkl'), ['stop']);
                expect(
                  EpisodeTrackerSnapshotRevision.identity('simkl', 'tt5100000'),
                  revision,
                );
              }
            }
            if (retire == 'profile') await d.retired();
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          } finally {
            if (!reply.isCompleted) {
              reply.complete(http.Response('{}', response));
            }
            await d.tick(const Duration(seconds: 26));
            await d.close();
          }
        },
      );
    }
  }
}
