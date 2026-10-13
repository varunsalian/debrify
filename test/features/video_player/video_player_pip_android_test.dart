import 'package:debrify/services/pip_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';

import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'PiP Android readiness arms aspect, State identity and explicit entry payload',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        expect(PipService.isOwner(d.stateOwner!), isTrue);
        expect(PipService.isOwner(Object()), isFalse);
        expect(d.named('setAutoEnter'), hasLength(1));
        expect(d.named('setAutoEnter').last.arguments, {
          'enabled': true,
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
        await d.enter();
        expect(d.named('enterPip').single.arguments, {
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
        expect(d.operations('handle'), isEmpty);
        expect(d.named('updatePlaybackState').last.arguments, {
          'isPlaying': true,
          'hasNext': false,
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP Android mode collapses chrome, cancels auto-hide and preserves active owner on exit',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        final before = d.named('updatePlaybackState').length;
        final hides = d.timed
            .where(
              (v) =>
                  v.$1 == VideoPlayerTimingConstants.controlsAutoHideDuration,
            )
            .map((v) => v.$2)
            .toList();
        expect(hides.any((v) => v.isActive), isTrue);
        await d.deliver('onPipModeChanged', true);
        expect(find.byType(Controls), findsNothing);
        expect(hides.every((v) => !v.isActive), isTrue);
        expect(d.named('updatePlaybackState').length, before + 1);
        await d.deliver('onPipModeChanged', false);
        expect(PipService.isOwner(d.stateOwner!), isTrue);
        expect(
          t
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(Controls),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          0,
        );
        expect(d.named('updatePlaybackState').length, before + 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final supported in [false, true]) {
    testWidgets(
      'PiP Android hidden options registration stays absent supported=$supported',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        d.handler = (c) => c.method == 'isSupported' ? supported : null;
        try {
          await d.mount(
            const VideoPlayerScreen(
              videoUrl: 'https://player.test/hidden.mp4',
              title: 'Hidden PiP',
              hideOptions: true,
            ),
          );
          expect(d.named('isSupported'), isEmpty);
          expect(d.named('setAutoEnter'), isEmpty);
          expect(PipService.isOwner(d.stateOwner!), isFalse);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final action in [
    'play',
    'pause',
    'playpause',
    'next',
    'unknown',
    'seek:NaN',
    'seek:Infinity',
    'seek:oops',
    'seek',
  ]) {
    testWidgets(
      'PiP Android action $action pins action dispatch and invalid seek gates',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        try {
          await d.mount();
          if (action == 'play') {
            await f.player.pause();
            await d.settle();
          }
          final before = f.player.calls.length;
          await d.acceptedEvent('onPipAction', action);
          await d.settle();
          final names = f.player.calls
              .skip(before)
              .map((c) => c.$1)
              .where((s) => ['play', 'pause', 'seek', 'open'].contains(s))
              .toList();
          expect(
            names,
            action == 'play'
                ? ['play']
                : ['pause', 'playpause'].contains(action)
                ? ['pause']
                : isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final (seconds, expected) in [
    (-10000.0, 0),
    (-.2506, 59749),
    (12.3456, 72346),
    (10000.0, 1200000),
  ]) {
    testWidgets(
      'PiP Android relative seek $seconds rounds milliseconds and clamps to the engine duration',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        try {
          await d.mount();
          await f.player.seek(const Duration(seconds: 60));
          await d.settle();
          final before = d.operations('seek').length;
          await d.deliver('onPipAction', 'seek:$seconds');
          expect(d.operations('seek').skip(before).map((c) => c.$2), [
            Duration(milliseconds: expected),
          ]);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP Android lost owner prevents entry, auto-enter and playing state pushes',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        final saved = playerControls(t).onPip!;
        PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
        final enters = d.named('enterPip').length;
        final pushes = d.named('updatePlaybackState').length;
        final arms = d.named('setAutoEnter').length;
        saved();
        await f.player.pause();
        await d.settle();
        f.player.configuration.ready?.call();
        await d.settle();
        expect(d.named('enterPip').length, enters);
        expect(d.named('updatePlaybackState').length, pushes);
        expect(d.named('setAutoEnter').length, arms);
      } finally {
        await d.close();
      }
    },
  );
}
