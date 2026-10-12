import 'dart:async';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final tracker in ['simkl', 'mdblist']) {
    final simkl = tracker == 'simkl';
    for (final gate in [
      'flag',
      'target',
      'credential',
      'identity',
      'type',
      'season',
      'episode',
    ]) {
      testWidgets(
        'Secondary $tracker initialization $gate gate preserves absent checkpoints',
        (t) async {
          final f = VideoPlayerEnvironment();
          final d = SecondaryTrackerDriver(t, f);
          await d.initialize(target: gate != 'target');
          try {
            if (gate == 'credential') {
              await t.runAsync(
                simkl
                    ? SimklStorage.clearSimklAuth
                    : MdblistStorage.clearMdblistAuth,
              );
              // Disconnect also updates policy; restore the target to isolate auth.
              await t.runAsync(
                () => TrackingSourceStorage.setTrackingScrobbleTargets({
                  simkl ? TrackingSource.simkl : TrackingSource.mdblist,
                }),
              );
            }
            await d.mount(
              secondaryScreen(
                simkl: simkl && gate != 'flag',
                mdblist: !simkl && gate != 'flag',
                id: gate == 'identity' ? null : 'tt5100000',
                type: gate == 'type' ? 'channel' : 'series',
                season: gate == 'season' ? null : 2,
                episode: gate == 'episode' ? null : 3,
              ),
            );
            await d.position(972000);
            await d.playing(false);
            await d.playing(true);
            await d.tick(const Duration(minutes: 2));
            await d.seek(.9);
            expect(d.forTracker(tracker), isEmpty);
            // Simkl arms before checking unresolved coordinates; that live timer
            // silently rejects them. MDBList refuses to allocate an invalid target.
            final unresolved = simkl && ['season', 'episode'].contains(gate);
            expect(
              d.heartbeats.where((timer) => timer.isActive),
              hasLength(unresolved || (!simkl && gate == 'credential') ? 1 : 0),
            );
            await d.retired();
            expect(d.forTracker(tracker), isEmpty);
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
    testWidgets(
      'Secondary $tracker disabled at startup stays disabled after target enablement',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize(target: false);
        try {
          await d.mount(secondaryScreen(simkl: simkl, mdblist: !simkl));
          await t.runAsync(
            () => TrackingSourceStorage.setTrackingScrobbleTargets({
              simkl ? TrackingSource.simkl : TrackingSource.mdblist,
            }),
          );
          await d.position(300000);
          await d.playing(false);
          await d.playing(true);
          await d.seek(.9);
          await d.tick(const Duration(minutes: 2));
          await d.retired();
          expect(d.forTracker(tracker), isEmpty);
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Secondary $tracker disabling an active target preserves pause heartbeat seek and exit continuation',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(simkl: simkl, mdblist: !simkl));
          if (!simkl) await d.waitCheckpoint(tracker, 1);
          await t.runAsync(
            () => TrackingSourceStorage.setTrackingScrobbleTargets({}),
          );
          await d.position(300000);
          await d.playing(false);
          final offset = simkl ? 0 : 1;
          await d.waitCheckpoint(tracker, offset + 1);
          d.expectCheckpoint(tracker, offset, 'pause', 25);
          await d.playing(true);
          await d.position(600000);
          await d.tick(const Duration(minutes: 2));
          await d.waitCheckpoint(tracker, offset + 2);
          d.expectCheckpoint(tracker, offset + 1, 'pause', 50);
          final landing = Completer<void>();
          f.player.delays['seek'] = landing;
          try {
            await d.seek(.81);
          } finally {
            landing.complete();
            f.player.delays.remove('seek');
          }
          await d.drain();
          await d.waitCheckpoint(tracker, offset + 3);
          d.expectCheckpoint(tracker, offset + 2, 'stop', 81);
          await d.retired();
          expect(d.forTracker(tracker), hasLength(offset + 3));
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Secondary held Simkl auth observes false enablement and null timer before pause and late dispose completion',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false), errors: errors);
        expect(d.cipher.held, isNotEmpty);
        await d.playing(false);
        expect(d.trackerActions('simkl'), isEmpty);
        expect(d.heartbeats, isEmpty);
        await d.retired();
        d.cipher.releaseAll();
        await d.drain();
        expect(errors, isEmpty);
        expect(d.trackerActions('simkl'), isEmpty);
        await d.tick(const Duration(minutes: 2));
        expect(d.trackerActions('simkl'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Secondary Simkl auth finishing paused with zero duration retains null dedup for the first real pause',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false));
        await d.playing(false);
        f.player.emit('duration', Duration.zero);
        await f.advance(t);
        d.cipher.releaseAll();
        await d.drain();
        await d.playing(true);
        expect(d.heartbeats, isEmpty);
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 0);
        expect(d.trackerActions('simkl'), ['pause']);
        expect(d.heartbeats, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Secondary Simkl auth storage failure propagates before enablement and never becomes an HTTP failure',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      final failure = StateError('synthetic Simkl auth storage failure');
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false), errors: errors);
        expect(d.cipher.held, isNotEmpty);
        d.cipher.failure = failure;
        d.cipher.releaseAll();
        await d.drain();
        expect(errors, [same(failure)]);
        d.cipher.failure = null;
        await d.playing(false);
        await d.playing(true);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats, isEmpty);
      } finally {
        d.cipher.failure = null;
        await d.close();
      }
    },
  );
}
