// Invoke the original retained RawKey/Focus callback without migrating its API.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport, unchanged application dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

Future<void> background(PipLifecycleDriver d) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    await d.lifecycle(state);
  }
}

Future<void> foreground(PipLifecycleDriver d) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    await d.lifecycle(state);
  }
}

void main() {
  for (final ios in [false, true]) {
    testWidgets(
      'PiP lifecycle ${ios ? 'iOS' : 'Android'} valid transitions pause only at paused and clear the latch before play without saving',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f, ios: ios);
        final previous = SharedPreferencesStorePlatform.instance;
        SleepResumeWrites? writes;
        await d.initialize();
        try {
          await d.mount();
          writes = await t.runAsync(SleepResumeWrites.install);
          await d.lifecycle(AppLifecycleState.inactive);
          expect(d.operations('pause'), isEmpty);
          expect(f.player.state.playing, isTrue);
          await d.lifecycle(AppLifecycleState.hidden);
          expect(d.operations('pause'), isEmpty);
          expect(f.player.state.playing, isTrue);
          await d.lifecycle(AppLifecycleState.paused);
          expect(d.operations('pause'), hasLength(2));
          expect(f.player.state.playing, isFalse);
          await foreground(d);
          await d.settle();
          expect(d.operations('play'), hasLength(1));
          expect(d.operations('pause'), hasLength(2));
          expect(f.player.state.playing, isTrue);
          expect(
            writes!.writes.where((w) => w.$1.endsWith('playback_state_v1')),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          SharedPreferencesStorePlatform.instance = previous;
        }
      },
    );
  }
  testWidgets(
    'PiP lifecycle preserves a user pause and its real held resume write across background and foreground',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      final previous = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? writes;
      await d.initialize();
      try {
        await d.mount();
        await f.player.seek(const Duration(minutes: 3));
        await f.advance(t);
        writes = await t.runAsync(SleepResumeWrites.install);
        writes!.barrier = Completer<void>();
        playerControls(t).onPlayPause();
        await f.until(t, () => writes!.entered);
        expect(d.operations('pause'), hasLength(1));
        await background(d);
        await foreground(d);
        await d.settle();
        expect(d.operations('pause'), hasLength(1));
        expect(d.operations('play'), isEmpty);
        expect(
          writes.resumed.where((key) => key.endsWith('playback_state_v1')),
          isEmpty,
        );
        writes.release();
        await f.until(
          t,
          () => writes!.resumed.any((key) => key.endsWith('playback_state_v1')),
        );
        final saved = await f.finish(
          t,
          VideoProgressStorage.getVideoPlaybackState(
            videoTitle: pipScreen.title,
          ),
        );
        expect(saved?['positionMs'], 180000);
        expect(saved?['url'], pipScreen.videoUrl);
        expect(f.player.state.playing, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        writes?.release();
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
  testWidgets(
    'PiP lifecycle resume may play before an older background pause completes and the late pause wins',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      final pause = Completer<void>();
      await d.initialize();
      try {
        await d.mount();
        f.player.delays['pause'] = pause;
        await background(d);
        expect(d.operations('pause'), hasLength(2));
        expect(pause.isCompleted, isFalse);
        expect(f.player.state.playing, isTrue);
        await foreground(d);
        await d.settle();
        expect(d.operations('play'), hasLength(1));
        expect(d.operations('pause'), hasLength(2));
        expect(f.player.state.playing, isTrue);
        pause.complete();
        f.player.delays.remove('pause');
        await f.until(t, () => !f.player.state.playing);
        await d.flushWake();
        expect(d.wake.writes.last, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!pause.isCompleted) {
          pause.complete();
        }
        f.player.delays.remove('pause');
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP lifecycle rejected background pause remains uncaught and resume still plays once',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        f.player.failures['pause'] = StateError('background pause rejected');
        await background(d);
        await f.until(t, () => d.errors.isNotEmpty);
        expect(
          d.errors.single.toString(),
          contains('background pause rejected'),
        );
        f.player.failures.remove('pause');
        await foreground(d);
        await d.settle();
        expect(d.operations('play'), hasLength(1));
        expect(f.player.state.playing, isTrue);
      } finally {
        f.player.failures.remove('pause');
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP lifecycle sleep stop between background and foreground suppresses automatic play',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        final menu = await sleepMenu(t, f);
        await background(d);
        menu.onSleepSelected(
          const SleepTimerSelection(SleepTimerMode.countdown),
        );
        await f.advance(t, const Duration(seconds: 1));
        await f.until(t, () => d.operations('pause').length == 3);
        await foreground(d);
        await d.settle();
        expect(d.operations('play'), isEmpty);
        expect(f.player.state.playing, isFalse);
        playerControls(t).onPlayPause();
        await d.settle();
        expect(d.operations('play'), hasLength(1));
        expect(f.player.state.playing, isTrue);
      } finally {
        await d.close();
      }
    },
  );
  for (final handoff in ['profile', 'dispose']) {
    testWidgets(
      'PiP pending user-pause save across $handoff and lifecycle writes its captured physical profile once',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        final previous = SharedPreferencesStorePlatform.instance;
        SleepResumeWrites? writes;
        try {
          await d.mount();
          await f.player.seek(const Duration(minutes: 3));
          await d.settle();
          final outgoing = ProfileRuntime.capture();
          writes = await t.runAsync(SleepResumeWrites.install);
          writes!.barrier = Completer<void>();
          playerControls(t).onPlayPause();
          await f.until(t, () => writes!.entered);
          final keys = writes.writes
              .where((w) => w.$1.endsWith('playback_state_v1'))
              .map((w) => w.$1)
              .toList();
          expect(keys, hasLength(1));
          expect(keys.single, contains(outgoing.profileId));
          await background(d);
          if (handoff == 'profile') {
            await incomingProfile(t, f);
          }
          if (handoff == 'dispose') {
            await d.retire();
          }
          expect(
            writes.resumed.where((k) => k.endsWith('playback_state_v1')),
            isEmpty,
          );
          writes.release();
          await f.until(t, () => writes!.resumed.contains(keys.single));
          final physical = await f.finish(t, writes.getAll());
          final saved = jsonDecode(physical[keys.single] as String) as Map;
          expect(saved.values.single['positionMs'], 180000);
          expect(saved.values.single['url'], pipScreen.videoUrl);
          if (handoff == 'profile') {
            final incoming = ProfileRuntime.capture();
            expect(incoming.profileId, isNot(outgoing.profileId));
            expect(
              physical.keys.where(
                (k) =>
                    k.contains(incoming.profileId) &&
                    k.endsWith('playback_state_v1'),
              ),
              isEmpty,
            );
            expect(
              await f.finish(
                t,
                VideoProgressStorage.getVideoPlaybackState(
                  videoTitle: pipScreen.title,
                ),
              ),
              isNull,
            );
          }
          await foreground(d);
          await d.settle();
          expect(d.operations('play'), isEmpty);
        } finally {
          writes?.release();
          await d.close();
          SharedPreferencesStorePlatform.instance = previous;
        }
      },
    );
  }
  testWidgets(
    'PiP early callbacks while a prior output lease is held ignore actions and do not latch the first background open',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final previous = await f.finish(
        t,
        VideoOutputLease.acquire(debugLabel: 'prior trailer'),
      );
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(navigatorKey: f.navigator, home: pipScreen),
          ),
        );
        await d.settle();
        final owner = t.state(find.byType(VideoPlayerScreen));
        expect(PipService.isOwner(owner), isTrue);
        expect(f.players, isEmpty);
        for (final action in ['playpause', 'seek:1', 'next']) {
          await d.acceptedEvent('onPipAction', action);
        }
        expect(d.errors, isEmpty);
        await background(d);
        expect(f.players, isEmpty);
        previous.release();
        await f.until(t, () => f.controllers.isNotEmpty);
        f.player.deliverReady();
        await f.until(t, () => d.operations('open').isNotEmpty);
        await d.settle();
        expect(
          f.player.state.playing,
          isTrue,
          reason:
              'The original early no-player pause returns without latching startup',
        );
        await foreground(d);
        expect(d.operations('play'), isEmpty);
        expect(d.errors, isEmpty);
        // Finish the initializer after the early-window assertions; its six-
        // second autosave must exist before disposal can cancel it.
        await f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.retire();
        expect(d.periodic.every((v) => !v.$2.isActive), isTrue);
      } finally {
        previous.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP early next-key transition before output creation still ignores a synchronous background callback',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final lease = await f.finish(
        t,
        VideoOutputLease.acquire(debugLabel: 'prior output'),
      );
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              home: const VideoPlayerScreen(
                videoUrl: 'https://player.test/early-a.mp4',
                title: 'Early A',
                playlist: [
                  PlaylistEntry(
                    url: 'https://player.test/early-a.mp4',
                    title: 'A',
                  ),
                  PlaylistEntry(
                    url: 'https://player.test/early-b.mp4',
                    title: 'B',
                  ),
                ],
                startIndex: 0,
              ),
            ),
          ),
        );
        await d.settle();
        expect(f.players, isEmpty);
        final focus = t.widget<Focus>(
          find
              .descendant(
                of: find.byType(VideoPlayerScreen),
                matching: find.byWidgetPredicate(
                  (w) => w is Focus && w.onKey != null,
                ),
              )
              .first,
        );
        // Dispatch the real retained keyboard callback synchronously, leaving
        // its async playlist action pending while the lifecycle changes.
        final node = focus.focusNode!;
        final key = RawKeyDownEvent(
          data: RawKeyEventDataMacOs(
            keyCode: 45,
            characters: 'n',
            charactersIgnoringModifiers: 'n',
            modifiers: 0,
          ),
        );
        expect(
          d.observe(() => focus.onKey!(node, key)),
          KeyEventResult.handled,
        );
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          expect(
            () => d.observe(
              () => t.binding.handleAppLifecycleStateChanged(state),
            ),
            returnsNormally,
          );
        }
        expect(t.takeException(), isNull);
        expect(d.errors, isEmpty);
        expect(f.players, isEmpty);
        lease.release();
        await foreground(d);
        await f.until(t, () => f.controllers.isNotEmpty);
        f.player.deliverReady();
        await f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
      } finally {
        lease.release();
        await d.close();
      }
    },
  );
}
