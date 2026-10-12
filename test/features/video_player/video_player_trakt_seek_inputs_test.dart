import 'dart:async';

import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart' show displayGesture;
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final forward in [false, true]) {
    testWidgets(
      'Trakt keyboard ${forward ? 'forward' : 'rewind'} seek sends the clamped target',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          await d.position(300000);
          await f.key(
            t,
            forward
                ? LogicalKeyboardKey.mediaFastForward
                : LogicalKeyboardKey.mediaRewind,
          );
          await d.drain();
          expect(d.actions, ['start', 'start']);
          d.expectRequest(
            1,
            'start',
            (forward ? 310000 : 290000) / 1200000 * 100,
          );
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'Trakt double tap ${forward ? 'right' : 'left'} seek reaches the original tracking caller',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = TraktPlayerDriver(t, f);
        await d.initialize();
        try {
          await d.mount(traktScreen());
          await d.position(300000);
          final gesture = displayGesture(t);
          gesture.onDoubleTapDown!(
            TapDownDetails(localPosition: Offset(forward ? 1000 : 200, 400)),
          );
          await d.drain();
          expect(d.actions, ['start', 'start']);
          d.expectRequest(
            1,
            'start',
            (forward ? 310000 : 290000) / 1200000 * 100,
          );
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'Trakt horizontal pan completion sends the displayed seek target',
    (t) async {
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
            globalPosition: const Offset(768, 400),
            localPosition: const Offset(768, 400),
            delta: const Offset(128, 0),
          ),
        );
        gesture.onPanEnd!(DragEndDetails());
        await d.drain();
        expect(d.actions, ['start', 'start']);
        d.expectRequest(1, 'start', 312000 / 1200000 * 100);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets('Trakt TV scope seek forwards its target into the tracker', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    final d = TraktPlayerDriver(t, f);
    await d.initialize();
    try {
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.mount(traktScreen());
      t
          .widget<TvControlsScope>(find.byType(TvControlsScope))
          .seek(const Duration(seconds: 300));
      await d.drain();
      expect(d.actions, ['start', 'start']);
      d.expectRequest(1, 'start', 25);
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'Trakt TV scrub confirm sends progress while the native pause is still suspended',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      await d.initialize();
      final pause = Completer<void>();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mount(traktScreen());
        await d.position(300000);
        await f.advance(t, const Duration(seconds: 6));
        await f.key(t, LogicalKeyboardKey.arrowRight);
        await f.key(t, LogicalKeyboardKey.arrowRight);
        f.player.delays['pause'] = pause;
        await f.key(t, LogicalKeyboardKey.arrowRight);
        await d.drain();
        expect(f.player.calls.where((call) => call.$1 == 'pause'), isNotEmpty);
        final before = d.requests.length;
        await f.key(t, LogicalKeyboardKey.enter);
        await d.drain();
        expect(d.requests, hasLength(before + 1));
        d.expectRequest(before, 'start', 330000 / 1200000 * 100);
        pause.complete();
        await d.drain();
      } finally {
        if (!pause.isCompleted) pause.complete();
        await d.close();
      }
    },
  );
}
