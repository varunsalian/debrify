import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/secondary_tracker_driver.dart';
import 'support/mdblist_capability_reads.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Simkl heartbeat exact interval force pause keeps live marker then stops above eighty with exact diagnostics',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.mount(secondaryScreen(mdblist: false));
        await d.position(960000);
        await d.tick(const Duration(seconds: 119));
        expect(d.forTracker('simkl'), isEmpty);
        await d.tick(const Duration(seconds: 1));
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 80);
        expect(logs, contains('Simkl: Heartbeat pause checkpoint at 80.0%'));
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('simkl', 2);
        d.expectCheckpoint('simkl', 1, 'pause', 80);
        await d.position(972000);
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('simkl', 3);
        d.expectCheckpoint('simkl', 2, 'stop', 81);
        expect(logs, contains('Simkl: Heartbeat stop at 81.0% (>80%)'));
        expect(d.trackerActions('simkl'), ['pause', 'pause', 'stop']);
        expect(d.heartbeats.where((t) => t.isActive), isEmpty);
        await d.playing(false);
        await d.retired();
        await d.tick(const Duration(minutes: 4));
        expect(d.forTracker('simkl'), hasLength(3));
      } finally {
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );

  for (final gate in ['duration', 'identity', 'coordinates']) {
    testWidgets(
      'Simkl heartbeat live $gate gate keeps original armed timer silent until disposal',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(mdblist: false));
          if (gate == 'duration') {
            f.player.emit('duration', Duration.zero);
            await d.drain();
          } else {
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: f.navigator,
                home: secondaryScreen(
                  mdblist: false,
                  id: gate == 'identity' ? null : 'tt5100000',
                  season: gate == 'coordinates' ? null : 2,
                ),
              ),
            );
          }
          await d.tick(const Duration(minutes: 2));
          expect(d.forTracker('simkl'), isEmpty);
          expect(d.heartbeats.where((t) => t.isActive), hasLength(1));
          await d.retired();
          expect(d.heartbeats.where((t) => t.isActive), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final caller in ['pause', 'seek']) {
    testWidgets(
      'Simkl live null widget identity at $caller never reuses its initialized identity',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen(mdblist: false));
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              home: secondaryScreen(mdblist: false, id: null),
            ),
          );
          if (caller == 'pause') await d.playing(false);
          if (caller == 'seek') await d.seek(.9);
          expect(d.forTracker('simkl'), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'Simkl auth before playing and duration stays inert until the original validation release caller',
    (t) async {
      final opening = Completer<void>();
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.delays['open'] = opening,
      );
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mountHeld(secondaryScreen(mdblist: false));
        expect(f.player.state.playing, isFalse);
        expect(f.player.state.duration, Duration.zero);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats, isEmpty);
        opening.complete();
        await f.until(t, () => d.heartbeats.isNotEmpty);
        expect(d.heartbeats.where((t) => t.isActive), hasLength(1));
        expect(d.forTracker('simkl'), isEmpty);
        await d.position(300000);
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 25);
      } finally {
        if (!opening.isCompleted) opening.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'Simkl auth finishing paused with positive duration does not arm a checkpoint',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        d.cipher.hold = true;
        await d.mountHeld(secondaryScreen(mdblist: false));
        await d.playing(false);
        d.cipher.releaseAll();
        await d.drain();
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        await d.playing(true);
        expect(d.heartbeats.where((t) => t.isActive), hasLength(1));
        await d.position(300000);
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 25);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'Secondary zero-duration session starts MDBList on the first usable duration and Simkl on a playing edge',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final capability = MdblistCapabilityReads();
      try {
        d.cipher.hold = true;
        await capability.run(() => d.mountHeld(secondaryScreen()));
        await f.until(t, () => capability.pending.isNotEmpty);
        f.player.emit('duration', Duration.zero);
        await d.drain();
        d.cipher.releaseAll();
        capability.release();
        await d.drain();
        expect(d.heartbeats, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.forTracker('mdblist'), isEmpty);
        await d.playing(true);
        expect(d.heartbeats, isEmpty);
        f.player.emit('duration', const Duration(minutes: 20));
        await d.drain();
        await d.waitCheckpoint('mdblist', 1);
        d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.heartbeats.where((t) => t.isActive), hasLength(1));
        await d.playing(true);
        expect(d.heartbeats.where((t) => t.isActive), hasLength(2));
        await d.position(300000);
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('simkl', 1);
        d.expectCheckpoint('simkl', 0, 'pause', 25);
      } finally {
        capability.release();
        await d.close();
      }
    },
  );
}
