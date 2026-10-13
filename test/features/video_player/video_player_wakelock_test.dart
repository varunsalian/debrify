import 'dart:async';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'support/fake_player.dart';

import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'support/pip_lifecycle_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'PiP wakelock follows initial acquisition, playing and pause, while buffering does not release it',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        expect(d.wake.writes, isNotEmpty);
        expect(d.wake.writes.every((v) => v), isTrue);
        final before = d.wake.attempts.length;
        f.player.emit('buffering', true);
        await d.settle();
        expect(d.wake.attempts.length, before);
        await d.flushWake();
        expect(d.wake.writes.last, isTrue);
        await f.player.pause();
        await d.settle();
        await d.flushWake();
        expect(d.wake.writes.last, isFalse);
        await f.player.play();
        await d.settle();
        await d.flushWake();
        expect(d.wake.writes.last, isTrue);
        await d.retire(expectedWake: false);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP wakelock independent owner prevents a pause or disposal release until that owner leaves',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final owner = Object();
      d.owners.add(owner);
      try {
        await d.mount();
        await f.finish<void>(
          t,
          PlayerDisplayControls.instance.setWakelockOwner(owner, true),
        );
        await f.player.pause();
        await d.settle();
        await d.flushWake();
        expect(d.wake.writes.last, isTrue);
        await d.retire(expectedWake: true);
        await f.finish<void>(
          t,
          PlayerDisplayControls.instance.setWakelockOwner(owner, false),
        );
        expect(d.wake.writes.last, isFalse);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP wakelock held first toggle samples latest queued playback requests after rapid pause play and disposal',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final gate = Completer<void>();
      try {
        d.wake.barrier = gate;
        d.wake.holdWhen = (v) => v;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(navigatorKey: f.navigator, home: pipScreen),
          ),
        );
        await f.until(t, () => f.players.isNotEmpty);
        f.player.deliverReady();
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
        await f.until(t, () => d.wake.attempts.length == 2);
        expect(d.wake.attempts, [true, true]);
        expect(d.wake.writes, isEmpty);
        await f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await f.player.pause();
        await d.settle();
        await f.player.play();
        await d.settle();
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(d.wake.attempts, [true, true, false, true, false]);
        expect(d.wake.writes, [false, false]);
        gate.complete();
        d.wake.release();
        await d.flushWake();
        expect(d.wake.writes.take(2), [false, false]);
        expect(d.wake.writes.skip(2).take(3), [true, true, true]);
        expect(d.wake.writes.skip(5).every((v) => !v), isTrue);
        expect(d.wake.writes.last, isFalse);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        d.wake.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP wakelock native rejection is swallowed and subsequent queued requests still complete',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        await f.player.pause();
        await d.settle();
        await d.flushWake();
        d.wake.failure = StateError('native wake rejected');
        Object? failure;
        await f.finish<void>(
          t,
          d
              .observe(() => PlayerDisplayControls.instance.setWakelock(false))
              .then(
                (_) {},
                onError: (Object e) {
                  failure = e;
                },
              ),
        );
        expect(
          failure,
          isNull,
          reason: 'A rejected queued native toggle must be swallowed',
        );
        await d.flushWake();
        expect(d.errors, isEmpty);
        expect(d.wake.writes.last, isFalse);
        await f.player.play();
        await d.settle();
        await d.flushWake();
        expect(d.wake.writes.last, isTrue);
      } finally {
        await d.close();
      }
    },
  );
  for (final playingFalse in [false, true]) {
    testWidgets(
      'PiP wakelock EOF playing-false=$playingFalse releases only on the playing stream',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        try {
          await d.mount();
          final before = d.wake.attempts.length;
          f.player.emit('completed', true);
          await d.settle();
          expect(d.wake.attempts.length, before);
          if (playingFalse) {
            await f.player.pause();
            await d.settle();
          }
          await d.flushWake();
          expect(d.wake.writes.last, !playingFalse);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP detached owner handoff keeps playback wake requested when the old parked session closes',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        expect(d.route!.session.wasReplaced, isFalse);
        PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
        await f.until(t, () => f.player.disposed.isCompleted);
        await d.flushWake();
        expect(d.wake.writes.last, isTrue);
        expect(d.route!.session.wasReplaced, isFalse);
        expect(d.route!.session.isParked, isFalse);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP replaced parked route keeps wake for a hidden-options incoming player while its setup is held',
    (t) async {
      final gate = Completer<void>();
      var created = 0;
      final f = VideoPlayerEnvironment(
        native: true,
        configurePlayer: (p) {
          if (++created == 2) {
            final n = p.platform! as FakeNativePlayer;
            n.heldOperation = (name, v) =>
                name == 'setProperty' &&
                (v as (String, String)).$1 == 'alang' &&
                !gate.isCompleted;
            n.beforeOperation = (name, v) =>
                n.heldOperation!(name, v) ? gate.future : null;
          }
        },
      );
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      await f.finish(t, SubtitleSettingsStorage.setDefaultAudioLanguage('en'));
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        final old = f.player;
        final owner = d.stateOwner!;
        expect(PipService.isOwner(owner), isTrue);
        f.navigator.currentState!.push(
          IosPipPlayerRoute<Object?>(
            builder: (_) => const VideoPlayerScreen(
              videoUrl: 'https://player.test/hidden-new.mp4',
              title: 'Hidden incoming',
              hideOptions: true,
            ),
          ),
        );
        await f.until(
          t,
          () => f.players.length == 2 && old.disposed.isCompleted,
        );
        await d.flushWake();
        expect(d.route!.session.wasReplaced, isTrue);
        expect(gate.isCompleted, isFalse);
        expect(d.wake.writes.last, isTrue);
        gate.complete();
        f.player.deliverReady();
        await f.until(t, () => d.operations('open').isNotEmpty);
        await d.settle();
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        await d.close();
      }
    },
  );
}
