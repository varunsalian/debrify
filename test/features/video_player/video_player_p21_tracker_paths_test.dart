import 'dart:async';

import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart' show displayGesture;
import 'support/p21_controls_driver.dart' show p21Timeouts;
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

/// The fixture item is 1,200 s long; MDBList and Simkl report a seek that
/// crosses 80 % (960 s) as a stop carrying the landed target.
const _kinds = ['double tap', 'pan', 'scrub'];

class _Case {
  _Case(this.t, this.kind) : f = VideoPlayerEnvironment() {
    d = SecondaryTrackerDriver(t, f);
  }
  final WidgetTester t;
  final String kind;
  final VideoPlayerEnvironment f;
  late final SecondaryTrackerDriver d;
  bool get tv => kind == 'scrub';

  Future<void> mount() async {
    await d.initialize();
    if (tv) PlatformUtil.debugSetAndroidTvCached(true);
    await d.mount(secondaryScreen());
    await d.waitCheckpoint('mdblist', 1);
    if (tv) await f.advance(t, const Duration(seconds: 6));
  }

  Future<void> pause() async {
    await d.playing(false);
    await f.advance(t, const Duration(milliseconds: 100));
    await d.drain();
  }

  /// Parks the playhead at [from] seconds and starts the [kind] seek input
  /// toward the end, returning the target in milliseconds. A double tap and
  /// a pan move forward by 10 s and 12 s; the scrub by 70 s (two nudges and
  /// five strides) and confirms.
  Future<int> forward(int from) async {
    await d.position(from * 1000);
    final gesture = tv ? null : displayGesture(t);
    switch (kind) {
      case 'double tap':
        gesture!.onDoubleTapDown!(
          TapDownDetails(localPosition: const Offset(1000, 400)),
        );
        return (from + 10) * 1000;
      case 'pan':
        gesture!.onPanStart!(
          DragStartDetails(localPosition: const Offset(640, 400)),
        );
        await d.drain();
        gesture.onPanUpdate!(
          DragUpdateDetails(
            globalPosition: const Offset(768, 400),
            localPosition: const Offset(768, 400),
          ),
        );
        gesture.onPanEnd!(DragEndDetails());
        return (from + 12) * 1000;
      default:
        for (var i = 0; i < 7; i++) {
          await f.key(t, LogicalKeyboardKey.arrowRight);
        }
        await f.key(t, LogicalKeyboardKey.select);
        return (from + 70) * 1000;
    }
  }

  Future<void> close() async {
    PlatformUtil.debugSetAndroidTvCached(false);
    await d.close();
  }
}

/// The index of the first [tracker] stop at or after [from], once it arrives.
Future<int> _stop(SecondaryTrackerDriver d, String tracker, int from) async {
  await d.f.until(
    d.t,
    () => d.trackerActions(tracker).skip(from).contains('stop'),
    reason: '$tracker must hear a stop',
  );
  return from + d.trackerActions(tracker).skip(from).toList().indexOf('stop');
}

/// Phase 21a Step 0c, class 3: every seek input of the controls runtime
/// reports its landed target to the trackers whether playback is paused or
/// playing at the commit, reports the clamped target near the end, and
/// reports either after (double tap) or without waiting for (pan, scrub)
/// the player seek.
void main() {
  p21Timeouts();
  TraktTestTransport.install();

  for (final kind in _kinds) {
    for (final paused in [true, false]) {
      testWidgets(
        'P21 a ${paused ? 'paused' : 'playing'} $kind seek across 80 % reports its target as an MDBList stop${paused ? ' and Simkl hears nothing' : ''}',
        (t) async {
          final c = _Case(t, kind);
          try {
            await c.mount();
            final d = c.d;
            if (paused) await c.pause();
            final simkl = d.forTracker('simkl').length;
            final mdblist = d.forTracker('mdblist').length;
            final target = await c.forward(kind == 'scrub' ? 900 : 955);
            await d.drain();
            final stop = await _stop(d, 'mdblist', mdblist);
            // A playing scrub's begin paused first: that checkpoint precedes.
            expect(
              d.trackerActions('mdblist').sublist(mdblist, stop),
              kind == 'scrub' && !paused ? ['pause'] : isEmpty,
            );
            d.expectCheckpoint('mdblist', stop, 'stop', target / 12000);
            if (paused) {
              expect(d.trackerActions('simkl').skip(simkl), isEmpty);
            } else if (kind != 'scrub') {
              await d.waitCheckpoint('simkl', simkl + 1);
              d.expectCheckpoint('simkl', simkl, 'stop', target / 12000);
            }
          } finally {
            await c.close();
          }
        },
      );
    }
  }

  for (final kind in ['double tap', 'pan']) {
    testWidgets(
      'P21 a playing $kind seek near the end reports the clamped end to Simkl',
      (t) async {
        final c = _Case(t, kind);
        try {
          await c.mount();
          final d = c.d;
          final simkl = d.forTracker('simkl').length;
          await c.forward(1195);
          await d.drain();
          expect(c.d.seeks.last, const Duration(seconds: 1200));
          await d.waitCheckpoint('simkl', simkl + 1);
          d.expectCheckpoint('simkl', simkl, 'stop', 100);
        } finally {
          await c.close();
        }
      },
    );
  }

  testWidgets(
    'P21 a double tap reports to Simkl and MDBList only once its held seek completes',
    (t) async {
      final c = _Case(t, 'double tap');
      final seek = Completer<void>();
      try {
        await c.mount();
        final d = c.d;
        final simkl = d.forTracker('simkl').length;
        final mdblist = d.forTracker('mdblist').length;
        c.f.player.delays['seek'] = seek;
        final target = await c.forward(955);
        await d.drain();
        expect(d.seeks, [Duration(milliseconds: target)]);
        expect(d.forTracker('simkl'), hasLength(simkl));
        expect(d.forTracker('mdblist'), hasLength(mdblist));
        seek.complete();
        await d.drain();
        await d.waitCheckpoint('simkl', simkl + 1);
        await d.waitCheckpoint('mdblist', mdblist + 1);
        d.expectCheckpoint('simkl', simkl, 'stop', target / 12000);
        d.expectCheckpoint('mdblist', mdblist, 'stop', target / 12000);
      } finally {
        if (!seek.isCompleted) seek.complete();
        await c.close();
      }
    },
  );

  for (final kind in ['pan', 'scrub']) {
    testWidgets(
      'P21 a $kind reports its target without waiting for its held seek',
      (t) async {
        final c = _Case(t, kind);
        final seek = Completer<void>();
        try {
          await c.mount();
          final d = c.d;
          final mdblist = d.forTracker('mdblist').length;
          late int landed;
          if (kind == 'pan') {
            c.f.player.delays['seek'] = seek;
            landed = await c.forward(955);
          } else {
            // Two nudges first; every seek from the scrub on is held.
            await d.position(900000);
            await c.f.key(t, LogicalKeyboardKey.arrowRight);
            await c.f.key(t, LogicalKeyboardKey.arrowRight);
            c.f.player.delays['seek'] = seek;
            for (var i = 0; i < 5; i++) {
              await c.f.key(t, LogicalKeyboardKey.arrowRight);
            }
            await c.f.key(t, LogicalKeyboardKey.select);
            landed = 970000;
          }
          await d.drain();
          expect(seek.isCompleted, isFalse);
          expect(d.seeks.last, Duration(milliseconds: landed));
          final stop = await _stop(d, 'mdblist', mdblist);
          d.expectCheckpoint('mdblist', stop, 'stop', landed / 12000);
          seek.complete();
          await d.drain();
        } finally {
          if (!seek.isCompleted) seek.complete();
          await c.close();
        }
      },
    );
  }

  testWidgets(
    'P21 a double tap reports the target it computed at the tap even if the playhead moves during its seek',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      final seek = Completer<void>();
      await d.initialize();
      try {
        await d.mount(secondaryScreen());
        await d.waitCheckpoint('mdblist', 1);
        await d.position(955000);
        final simkl = d.forTracker('simkl').length;
        final mdblist = d.forTracker('mdblist').length;
        f.player.publishPositionOnSeekAcknowledgement = false;
        f.player.delays['seek'] = seek;
        displayGesture(t).onDoubleTapDown!(
          TapDownDetails(localPosition: const Offset(1000, 400)),
        );
        await d.drain();
        // The playhead moves back while the seek is still in flight.
        await d.position(950000);
        seek.complete();
        await d.drain();
        expect(d.seeks, [const Duration(seconds: 965)]);
        await d.waitCheckpoint('simkl', simkl + 1);
        await d.waitCheckpoint('mdblist', mdblist + 1);
        d.expectCheckpoint('simkl', simkl, 'stop', 965000 / 12000);
        d.expectCheckpoint('mdblist', mdblist, 'stop', 965000 / 12000);
      } finally {
        if (!seek.isCompleted) seek.complete();
        f.player.publishPositionOnSeekAcknowledgement = true;
        await d.close();
      }
    },
  );
}
