import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/mdblist_capability_reads.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_policy_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

void main() {
  TraktTestTransport.install();
  for (final retire in ['none', 'dispose']) {
    testWidgets(
      'MDBList startup policy precedes suspended player setup and $retire preserves the captured setting',
      (t) async {
        final opening = Completer<void>();
        final f = VideoPlayerEnvironment(
          configurePlayer: (player) => player.delays['open'] = opening,
        );
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final policy = TraktPolicyReads(() => true);
        final oldPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          await d.observe(
            () => policy.run(
              () => t.pumpWidget(
                MaterialApp(
                  navigatorKey: f.navigator,
                  home: secondaryScreen(simkl: false),
                ),
              ),
            ),
          );
          await f.until(t, () => policy.pending.isNotEmpty);
          await f.until(t, () => f.controllers.isNotEmpty);
          expect(f.player.readyDelivered, isFalse);
          expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
          expect(d.forTracker('mdblist'), isEmpty);
          expect(
            logs.where(
              (s) => s.startsWith('[MDBListDiag] player session ready'),
            ),
            isEmpty,
          );
          await t.runAsync(
            () => TrackingSourceStorage.setTrackingScrobbleTargets({}),
          );
          policy.release();
          await d.drain();
          expect(d.forTracker('mdblist'), isEmpty);
          if (retire == 'dispose') await d.retired();
          f.player.deliverReady();
          opening.complete();
          await d.drain();
          if (retire == 'none') {
            await d.waitCheckpoint('mdblist', 1);
            d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
            expect(
              logs,
              contains(
                '[MDBListDiag] player session ready imdb=tt5100000 episode=true playing=true positionMs=80 durationMs=1200000',
              ),
            );
          } else {
            expect(d.forTracker('mdblist'), isEmpty);
            expect(
              logs.where(
                (s) => s.startsWith('[MDBListDiag] player session ready'),
              ),
              isEmpty,
            );
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          }
        } finally {
          policy.release();
          if (!opening.isCompleted) opening.complete();
          if (f.players.isNotEmpty && !f.player.readyDelivered) {
            f.player.deliverReady();
          }
          if (retire == 'dispose') {
            // The original player setup polls readiness up to 100 times even
            // after its subscriptions are canceled. Drain those real polls;
            // never cancel a production timer to hide this disposal behavior.
            for (var i = 0; i < 110; i++) {
              await f.advance(t, const Duration(milliseconds: 100));
            }
            await d.drain();
            expect(d.forTracker('mdblist'), isEmpty);
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          }
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }

  for (final race in ['widget', 'profile', 'dispose']) {
    testWidgets(
      'MDBList captured target before capability $race completion retains original allocation and guards',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = MdblistCapabilityReads();
        final oldPrint = debugPrint;
        final logs = <String>[];
        final revision = MdblistService.instance.playbackRevision.value;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          await d.observe(
            () => reads.run(() => f.mount(t, secondaryScreen(simkl: false))),
          );
          await f.until(t, () => reads.pending.isNotEmpty);
          expect(d.forTracker('mdblist'), isEmpty);
          expect(d.heartbeats, isEmpty);
          if (race == 'widget') {
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: f.navigator,
                home: secondaryScreen(
                  simkl: false,
                  id: 'tt5200000',
                  type: 'movie',
                ),
              ),
            );
          }
          if (race == 'profile') {
            await incomingProfile(t, f);
            await t.runAsync(
              () => MdblistStorage.saveMdblistApiKey(
                'vplayer-synthetic-incoming-mdblist',
              ),
            );
          }
          if (race == 'dispose') await d.retired();
          reads.release();
          await d.drain();
          if (race == 'widget') {
            await d.waitCheckpoint('mdblist', 1);
            d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
            expect(
              logs,
              contains(
                '[MDBListDiag] player session ready imdb=tt5100000 episode=true playing=true positionMs=80 durationMs=1200000',
              ),
            );
          } else if (race == 'profile') {
            expect(
              logs,
              contains(
                '[MDBListDiag] player session ready imdb=tt5100000 episode=true playing=true positionMs=80 durationMs=1200000',
              ),
            );
            await f.until(
              t,
              () => logs.any((s) => s.contains('scrobble result')),
            );
            expect(
              logs.where((s) => s.contains('kind=transientFailure')),
              hasLength(1),
            );
            expect(d.heartbeats, hasLength(1));
            expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
            expect(d.forTracker('mdblist'), isEmpty);
            expect(MdblistService.instance.playbackRevision.value, revision);
          } else {
            expect(
              logs,
              contains('[MDBListDiag] player init abandoned: player unmounted'),
            );
            expect(d.forTracker('mdblist'), isEmpty);
            expect(d.heartbeats, isEmpty);
          }
        } finally {
          reads.release();
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'MDBList only catches player initialization failure and never allocates a session for the failed controller',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final failure = StateError('synthetic video controller initialization');
      final oldPrint = debugPrint;
      final logs = <String>[];
      final errors = <Object>[];
      var attempted = false;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        VideoPlayerScreenTestHooks.install(
          VideoPlayerScreenTestHooks(
            ensureInitialized: () => f.creationOrder.add('media-kit-init'),
            createPlayer: (configuration) {
              final player = FakePlayer(configuration);
              f.players.add(player);
              return player;
            },
            createVideoController: (player, configuration) {
              attempted = true;
              throw failure;
            },
          ),
        );
        await d.observe(
          () => t.pumpWidget(MaterialApp(home: secondaryScreen(simkl: false))),
          errors: errors,
        );
        await f.until(t, () => attempted);
        await d.drain();
        expect(errors, isEmpty);
        expect(
          logs,
          contains(
            '[MDBListDiag] player init skipped: player setup failed $failure',
          ),
        );
        expect(
          logs.where((s) => s.startsWith('[MDBListDiag] player session ready')),
          isEmpty,
        );
        expect(d.forTracker('mdblist'), isEmpty);
        expect(d.heartbeats, isEmpty);
        expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );
}
