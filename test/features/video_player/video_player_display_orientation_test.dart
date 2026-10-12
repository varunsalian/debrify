import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/display_mode_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'display desktop landscape seed ignores phone portrait preference and toggles both directions',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await t.runAsync(
          () => PlayerSettingsStorage.setPlayerStartPortrait(true),
        );
        await f.mount(t, displayScreen());
        expect(playerControls(t).isLandscape, isTrue);
        expect(
          f.channels
              .where(
                (c) => c.$2.method == 'SystemChrome.setPreferredOrientations',
              )
              .first
              .$2
              .arguments,
          [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
        );
        final o = DisplayOrientationDriver(f);
        await o.toggle(playerControls(t));
        await f.advance(t);
        expect(playerControls(t).isLandscape, isFalse);
        expect(o.orientations, [
          ['DeviceOrientation.portraitUp'],
        ]);
        expect(o.calls.map((c) => c.method), [
          'SystemChrome.setPreferredOrientations',
          'SystemChrome.setEnabledSystemUIMode',
        ]);
        expect(o.calls[0].arguments, ['DeviceOrientation.portraitUp']);
        expect(o.calls[1].arguments, 'SystemUiMode.immersiveSticky');
        expect(o.hideTimers, hasLength(1));
        expect(o.hideTimers.single.isActive, isTrue);
        await o.toggle(playerControls(t));
        await f.advance(t);
        expect(playerControls(t).isLandscape, isTrue);
        expect(o.orientations.last, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        expect(o.hideTimers, hasLength(2));
        expect(o.hideTimers.first.isActive, isFalse);
        expect(o.hideTimers.last.isActive, isTrue);
        await f.advance(t, const Duration(seconds: 3));
        expect(o.hideTimers.every((timer) => !timer.isActive), isTrue);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display overlapping orientation toggles read the same initial lock and rearm one hide timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      DisplayOrientationDriver? o;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        o = DisplayOrientationDriver(f)..hold = true;
        final first = o.toggle(playerControls(t));
        final second = o.toggle(playerControls(t));
        await f.until(t, () => o!.pending.length == 2);
        expect(o.orientations, [
          ['DeviceOrientation.portraitUp'],
          ['DeviceOrientation.portraitUp'],
        ]);
        expect(playerControls(t).isLandscape, isTrue);
        expect(o.hideTimers, isEmpty);
        o.pending[1].complete();
        await firstOrSecond(t, f, second);
        expect(playerControls(t).isLandscape, isFalse);
        expect(o.hideTimers, hasLength(1));
        o.pending[0].complete();
        await firstOrSecond(t, f, first);
        expect(playerControls(t).isLandscape, isFalse);
        expect(o.hideTimers, hasLength(2));
        expect(o.hideTimers.first.isActive, isFalse);
        expect(o.hideTimers.last.isActive, isTrue);
        await f.advance(t, const Duration(seconds: 3));
        expect(o.hideTimers.every((timer) => !timer.isActive), isTrue);
      } finally {
        o?.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display orientation completed after dispose still sends immersive mode and creates a drained timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      DisplayOrientationDriver? o;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        o = DisplayOrientationDriver(f)..hold = true;
        final pending = o.toggle(playerControls(t));
        await f.until(t, () => o!.pending.length == 1);
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(o.hideTimers, isEmpty);
        final marker = o.calls.length;
        Object? completionError;
        final completed = pending.catchError((Object error) {
          completionError = error;
        });
        o.pending.first.complete();
        await firstOrSecond(t, f, completed);
        expect(completionError, isNull);
        expect(o.calls.skip(marker).map((c) => (c.method, c.arguments)), [
          (
            'SystemChrome.setEnabledSystemUIMode',
            'SystemUiMode.immersiveSticky',
          ),
        ]);
        expect(o.hideTimers, hasLength(1));
        expect(o.hideTimers.single.isActive, isTrue);
        await f.advance(t, const Duration(seconds: 3));
        expect(o.hideTimers.single.isActive, isFalse);
        expect(t.takeException(), isNull);
      } finally {
        o?.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display rejected orientation propagates without lock change immersive call or hide timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      DisplayOrientationDriver? o;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        o = DisplayOrientationDriver(f)..hold = true;
        final pending = o.toggle(playerControls(t));
        final rejected = expectLater(
          pending,
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'orientation-fixture',
            ),
          ),
        );
        await f.until(t, () => o!.pending.length == 1);
        o.pending.first.completeError(
          PlatformException(code: 'orientation-fixture'),
        );
        await rejected;
        await f.advance(t);
        expect(playerControls(t).isLandscape, isTrue);
        expect(o.orientations, [
          ['DeviceOrientation.portraitUp'],
        ]);
        expect(o.calls, hasLength(1));
        expect(o.hideTimers, isEmpty);
      } finally {
        o?.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display portrait-to-landscape orientation waits for the held channel before lock and timer changes',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      DisplayOrientationDriver? o;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        o = DisplayOrientationDriver(f);
        await o.toggle(playerControls(t));
        await f.advance(t);
        expect(playerControls(t).isLandscape, isFalse);
        final oldTimer = o.hideTimers.single;
        o.hold = true;
        final pending = o.toggle(playerControls(t));
        await f.until(t, () => o!.pending.length == 1);
        expect(o.orientations.last, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
        expect(playerControls(t).isLandscape, isFalse);
        expect(o.hideTimers, hasLength(1));
        expect(oldTimer.isActive, isTrue);
        expect(
          o.calls.where(
            (c) => c.method == 'SystemChrome.setEnabledSystemUIMode',
          ),
          hasLength(1),
        );
        o.pending.single.complete();
        await firstOrSecond(t, f, pending);
        expect(playerControls(t).isLandscape, isTrue);
        expect(o.hideTimers, hasLength(2));
        expect(oldTimer.isActive, isFalse);
        expect(o.hideTimers.last.isActive, isTrue);
        expect(o.calls.last.method, 'SystemChrome.setEnabledSystemUIMode');
        expect(o.calls.last.arguments, 'SystemUiMode.immersiveSticky');
        await f.advance(t, const Duration(seconds: 3));
        expect(o.hideTimers.every((timer) => !timer.isActive), isTrue);
      } finally {
        o?.releaseAll();
        await f.close(t);
      }
    },
  );
}

Future<void> firstOrSecond(
  WidgetTester t,
  VideoPlayerEnvironment f,
  Future<void> operation,
) async {
  await f.finish(t, operation);
  await f.advance(t);
}
