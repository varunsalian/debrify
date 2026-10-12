import 'dart:async';

import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart' show displayGesture;
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final forward in [false, true]) {
    testWidgets(
      'Secondary keyboard ${forward ? 'forward' : 'rewind'} seek sends the clamped target',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          if (!forward) await d.seekBeforeLanding(.81);
          await d.position(forward ? 959000 : 961000);
          await f.key(
            t,
            forward
                ? LogicalKeyboardKey.mediaFastForward
                : LogicalKeyboardKey.mediaRewind,
          );
          await d.drain();
          await d.waitCheckpoint('simkl', forward ? 1 : 2);
          await d.waitCheckpoint('mdblist', forward ? 2 : 3);
          d.expectCheckpoint(
            'simkl',
            forward ? 0 : 1,
            forward ? 'stop' : 'pause',
            (forward ? 969000 : 951000) / 12000,
          );
          d.expectCheckpoint(
            'mdblist',
            forward ? 1 : 2,
            forward ? 'stop' : 'pause',
            (forward ? 969000 : 951000) / 12000,
          );
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Secondary double tap ${forward ? 'right' : 'left'} seek reaches the original tracking caller',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(secondaryScreen());
          await d.waitCheckpoint('mdblist', 1);
          if (!forward) await d.seekBeforeLanding(.81);
          await d.position(forward ? 959000 : 961000);
          final gesture = displayGesture(t);
          gesture.onDoubleTapDown!(
            TapDownDetails(localPosition: Offset(forward ? 1000 : 200, 400)),
          );
          await d.drain();
          await d.waitCheckpoint('simkl', forward ? 1 : 2);
          await d.waitCheckpoint('mdblist', forward ? 2 : 3);
          d.expectCheckpoint(
            'simkl',
            forward ? 0 : 1,
            forward ? 'stop' : 'pause',
            (forward ? 969000 : 951000) / 12000,
          );
          d.expectCheckpoint(
            'mdblist',
            forward ? 1 : 2,
            forward ? 'stop' : 'pause',
            (forward ? 969000 : 951000) / 12000,
          );
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'Secondary horizontal pan completion sends the displayed seek target',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      try {
        await d.mount(secondaryScreen());
        await d.position(959000);
        final gesture = displayGesture(t);
        gesture.onPanStart!(
          DragStartDetails(localPosition: const Offset(640, 400)),
        );
        await d.drain();
        gesture.onPanUpdate!(
          DragUpdateDetails(
            globalPosition: const Offset(768, 400),
            localPosition: const Offset(768, 400),
            delta: const Offset(128, 0),
          ),
        );
        gesture.onPanEnd!(DragEndDetails());
        await d.drain();
        await d.waitCheckpoint('simkl', 1);
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('simkl', 0, 'stop', 971000 / 12000);
        d.expectCheckpoint('mdblist', 1, 'stop', 971000 / 12000);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets('Secondary TV scope seek forwards its target into the tracker', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    final d = SecondaryTrackerDriver(t, f);
    await d.initialize();
    try {
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.mount(secondaryScreen());
      t
          .widget<TvControlsScope>(find.byType(TvControlsScope))
          .seek(const Duration(seconds: 970));
      await d.drain();
      await d.waitCheckpoint('simkl', 1);
      await d.waitCheckpoint('mdblist', 2);
      d.expectCheckpoint('simkl', 0, 'stop', 970000 / 12000);
      d.expectCheckpoint('mdblist', 1, 'stop', 970000 / 12000);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'Secondary TV scrub confirm sends progress while the native pause is still suspended',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final pause = Completer<void>();
      final landing = Completer<void>();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mount(secondaryScreen());
        await d.position(859000);
        f.player.delays['seek'] = landing;
        await f.advance(t, const Duration(seconds: 6));
        await f.key(t, LogicalKeyboardKey.arrowRight);
        await f.key(t, LogicalKeyboardKey.arrowRight);
        f.player.delays['pause'] = pause;
        await f.key(t, LogicalKeyboardKey.arrowRight);
        await d.drain();
        expect(f.player.calls.where((call) => call.$1 == 'pause'), isNotEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        f.player.emit('duration', const Duration(milliseconds: 1080000));
        await d.drain();
        final before = d.forTracker('simkl').length;
        await f.key(t, LogicalKeyboardKey.enter);
        await d.drain();
        expect(
          d.forTracker('simkl'),
          hasLength(before + 1),
          reason:
              'seeks=${d.seeks} playing=${f.player.state.playing} calls=${f.player.calls}',
        );
        d.expectCheckpoint('simkl', before, 'stop', 869000 / 1080000 * 100);
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'stop', 869000 / 1080000 * 100);
        landing.complete();
        pause.complete();
        await d.drain();
      } finally {
        if (!landing.isCompleted) landing.complete();
        if (!pause.isCompleted) pause.complete();
        await d.close();
      }
    },
  );
}
