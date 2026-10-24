import 'dart:async';

import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart' show displayGesture;
import 'support/p21_controls_driver.dart' show p21Timeouts;
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

/// The controls runtime's seek inputs (double tap, pan end, TV scrub
/// confirm) each report the landed target to all three trackers.
void main() {
  p21Timeouts();
  TraktTestTransport.install();

  testWidgets('P21 a pan end reports its target to Trakt', (t) async {
    final f = VideoPlayerEnvironment();
    final d = TraktPlayerDriver(t, f);
    await d.initialize();
    try {
      await d.mount(traktScreen());
      await d.position(300000);
      final gesture = displayGesture(t);
      gesture.onPanStart!(
        DragStartDetails(localPosition: const Offset(640, 400)),
      );
      await d.drain();
      gesture.onPanUpdate!(
        DragUpdateDetails(
          globalPosition: const Offset(512, 400),
          localPosition: const Offset(512, 400),
        ),
      );
      final before = d.requests.length;
      gesture.onPanEnd!(DragEndDetails());
      await d.drain();
      expect(d.requests, hasLength(before + 1));
      d.expectRequest(before, 'start', 288000 / 1200000 * 100);
    } finally {
      await d.close();
    }
  });

  testWidgets('P21 a TV scrub confirm reports its target to Trakt once', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    final d = TraktPlayerDriver(t, f);
    final pause = Completer<void>();
    await d.initialize();
    try {
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.mount(traktScreen());
      await d.position(300000);
      await f.advance(t, const Duration(seconds: 6));
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      // Trakt only hears a seek while playing: hold the scrub's pause so the
      // player still reports playing at the confirm (the legacy case's setup).
      f.player.delays['pause'] = pause;
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      await d.drain();
      final before = d.requests.length;
      await f.key(t, LogicalKeyboardKey.select);
      await d.drain();
      expect(d.requests, hasLength(before + 1));
      // 300 - 10 - 10 (nudges) - 10 - 10 (scrub strides) = 260 s.
      d.expectRequest(before, 'start', 260000 / 1200000 * 100);
      pause.complete();
      await d.drain();
    } finally {
      if (!pause.isCompleted) pause.complete();
      PlatformUtil.debugSetAndroidTvCached(false);
      await d.close();
    }
  });

  for (final kind in ['double tap', 'pan']) {
    testWidgets('P21 a $kind seek reports its target to Simkl and MDBList', (
      t,
    ) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen());
        await d.waitCheckpoint('mdblist', 1);
        await d.position(959000);
        final gesture = displayGesture(t);
        late int target;
        final simkl = d.forTracker('simkl').length;
        final mdblist = d.forTracker('mdblist').length;
        if (kind == 'double tap') {
          gesture.onDoubleTapDown!(
            TapDownDetails(localPosition: const Offset(1000, 400)),
          );
          target = 969000;
        } else {
          gesture.onPanStart!(
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
          target = 971000;
        }
        await d.drain();
        await d.waitCheckpoint('simkl', simkl + 1);
        await d.waitCheckpoint('mdblist', mdblist + 1);
        final percent = target / 12000;
        d.expectCheckpoint('simkl', simkl, 'stop', percent);
        d.expectCheckpoint('mdblist', mdblist, 'stop', percent);
      } finally {
        await d.close();
      }
    });
  }
}
