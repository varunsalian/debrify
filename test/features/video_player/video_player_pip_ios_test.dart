import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

List<String> visibility(FakeNativePlayer n) => n.calls
    .where(
      (c) =>
          c.$1 == 'setProperty' &&
          (c.$2 as (String, String)).$1 == 'sub-visibility',
    )
    .map((c) => (c.$2 as (String, String)).$2)
    .toList();

void main() {
  testWidgets(
    'PiP iOS entry prepares native subtitles once, sends its distinct handle and leaves auto-enter unarmed',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        final n = f.player.platform! as FakeNativePlayer;
        final before = visibility(n).length;
        final pushes = d.named('updatePlaybackState').length;
        expect(d.named('setAutoEnter'), isEmpty);
        await d.enter();
        expect(d.operations('handle'), hasLength(1));
        expect(d.named('updatePlaybackState').length, pushes + 1);
        expect(d.named('enterPip').single.arguments, {
          'playerHandle': '${f.player.handleValue}',
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
        expect(visibility(n).skip(before), ['yes', 'no']);
        expect(PipService.isOwner(d.stateOwner!), isTrue);
        expect(d.named('updatePlaybackState').last.arguments, {
          'isPlaying': true,
          'hasNext': false,
          'positionMs': 80,
          'durationMs': 1200000,
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
      } finally {
        await d.close();
      }
    },
  );
  for (final landscape in [true, false]) {
    testWidgets(
      'PiP iOS real route parks and restores the same player with landscape=$landscape orientation and native visibility',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final d = PipLifecycleDriver(t, f, ios: true);
        await d.initialize();
        try {
          await d.mount();
          if (!landscape) {
            playerControls(t).onRotate();
            await d.settle();
          }
          final player = f.player;
          final enter = playerControls(t).onPip!;
          final n = player.platform! as FakeNativePlayer;
          await d.enter();
          final parkMarker = f.channels.length;
          await d.deliver('onPipModeChanged', true);
          expect(
            f.channels
                .skip(parkMarker)
                .where((c) => c.$1 == 'flutter/platform')
                .map((c) => [c.$2.method, c.$2.arguments]),
            [
              [
                'SystemChrome.setEnabledSystemUIMode',
                'SystemUiMode.edgeToEdge',
              ],
              [
                'SystemChrome.setPreferredOrientations',
                [
                  'DeviceOrientation.portraitUp',
                  'DeviceOrientation.landscapeLeft',
                  'DeviceOrientation.portraitDown',
                  'DeviceOrientation.landscapeRight',
                ],
              ],
            ],
          );
          expect(d.route!.session.isParked, isTrue);
          final dynamic invoke = enter;
          await f.finish<dynamic>(t, invoke());
          expect(d.named('enterPip'), hasLength(1));
          expect(player.disposed.isCompleted, isFalse);
          expect(find.text('PiP browser'), findsOneWidget);
          expect(find.byType(Controls), findsNothing);
          expect(visibility(n).last, 'yes');
          final marker = f.channels.length;
          expect(
            await f.finish<Object?>(t, d.event('onPipRestore', null)),
            isTrue,
          );
          await d.settle();
          expect(d.route!.session.isParked, isFalse);
          expect(f.players, hasLength(1));
          expect(identical(f.player, player), isTrue);
          expect(PipService.isOwner(d.stateOwner!), isTrue);
          expect(
            f.channels
                .skip(marker)
                .where((c) => c.$1 == 'flutter/platform')
                .map((c) => [c.$2.method, c.$2.arguments]),
            [
              [
                'SystemChrome.setPreferredOrientations',
                landscape
                    ? [
                        'DeviceOrientation.landscapeLeft',
                        'DeviceOrientation.landscapeRight',
                      ]
                    : ['DeviceOrientation.portraitUp'],
              ],
              [
                'SystemChrome.setEnabledSystemUIMode',
                'SystemUiMode.immersiveSticky',
              ],
            ],
          );
          await d.deliver('onPipModeChanged', false);
          expect(visibility(n).last, 'no');
          expect(find.byType(Controls), findsOneWidget);
          PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
          await d.retire(expectedWake: false);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP iOS repeated true mode while parked keeps the session and dismissal completes disposal',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        final pushes = d.named('updatePlaybackState').length;
        await d.deliver('onPipModeChanged', true);
        expect(d.route!.session.isParked, isTrue);
        expect(f.player.disposed.isCompleted, isFalse);
        expect(d.named('updatePlaybackState').length, pushes + 1);
        await d.deliver('onPipModeChanged', false);
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(d.route!.session.isParked, isFalse);
        expect(find.text('PiP browser'), findsOneWidget);
        expect(PipService.isOwner(d.stateOwner!), isFalse);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP iOS timeline pushes once per changed second including the initial zero second',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        final before = d.named('updatePlaybackState').length;
        expect(before, 2);
        for (final ms in [90, 999, 1000, 1099, 2000]) {
          f.player.state = f.player.state.copyWith(
            position: Duration(milliseconds: ms),
          );
          f.player.emit('position', Duration(milliseconds: ms));
          await d.settle();
        }
        expect(
          d
              .named('updatePlaybackState')
              .skip(before)
              .map((c) => (c.arguments as Map)['positionMs']),
          [1000, 2000],
        );
        expect(
          d
              .named('updatePlaybackState')
              .where((c) => (c.arguments as Map)['positionMs'] == 80),
          isNotEmpty,
        );
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP iOS active window and a starting entry suppress background pause and catchup cancellation',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        for (final s in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          await d.lifecycle(s);
        }
        // The real mkv.Video view still contributes its independent pause.
        expect(d.operations('pause'), hasLength(1));
        expect(f.player.state.playing, isFalse);
        for (final s in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          await d.lifecycle(s);
        }
        expect(d.operations('play'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP iOS lost owner rejects a saved entry before handle delivery or starting subtitle suppression',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        final dynamic enter = playerControls(t).onPip!;
        PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
        await f.finish<dynamic>(t, enter());
        await d.settle();
        expect(d.operations('handle'), isEmpty);
        expect(d.named('enterPip'), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
