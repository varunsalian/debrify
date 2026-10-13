import 'dart:async';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

void main() {
  for (final handoff in ['dispose', 'owner', 'profile']) {
    testWidgets(
      'PiP held support across $handoff preserves original late registration',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        final gate = Completer<bool>();
        try {
          d.handler = (c) => c.method == 'isSupported' ? gate.future : null;
          await d.mount();
          final old = d.stateOwner!;
          expect(PipService.isOwner(old), isFalse);
          expect(d.named('setAutoEnter'), isEmpty);
          expect(playerControls(t).onPip, isNull);
          if (handoff == 'dispose') {
            await d.retire();
          }
          if (handoff == 'owner') {
            PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
          }
          if (handoff == 'profile') {
            await incomingProfile(t, f);
          }
          gate.complete(true);
          await d.settle();
          expect(PipService.isOwner(old), handoff != 'dispose');
          expect(d.named('setAutoEnter').length, handoff == 'dispose' ? 0 : 1);
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(false);
          }
          await d.close();
        }
      },
    );
  }
  for (final supported in [false, true]) {
    testWidgets(
      'PiP Android resolved support=$supported controls public entry availability',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        try {
          d.handler = (c) => c.method == 'isSupported' ? supported : false;
          await d.mount();
          expect(d.named('isSupported'), hasLength(1));
          expect(PipService.isOwner(d.stateOwner!), supported);
          expect(playerControls(t).onPip != null, supported);
          expect(d.named('setAutoEnter').length, supported ? 1 : 0);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final stage in ['handle', 'subtitle', 'entry', 'orientation']) {
    testWidgets(
      'PiP iOS held $stage across real route replacement preserves handles and wake exemption',
      (t) async {
        final setup = Completer<void>();
        var created = 0;
        final f = VideoPlayerEnvironment(
          native: true,
          configurePlayer: (p) {
            if (++created == 2) {
              final n = p.platform! as FakeNativePlayer;
              n.heldOperation = (name, v) =>
                  name == 'setProperty' &&
                  (v as (String, String)).$1 == 'alang' &&
                  !setup.isCompleted;
              n.beforeOperation = (name, v) =>
                  name == 'setProperty' &&
                      (v as (String, String)).$1 == 'alang' &&
                      !setup.isCompleted
                  ? setup.future
                  : null;
            }
          },
        );
        final d = PipLifecycleDriver(t, f, ios: true);
        await d.initialize();
        await f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('en'),
        );
        final gate = Completer<void>();
        Future<dynamic>? pending;
        try {
          await d.mount();
          final old = f.player;
          final oldRoute = d.route!;
          final oldOwner = d.stateOwner!;
          final n = old.platform! as FakeNativePlayer;
          if (stage == 'orientation') {
            await d.enter();
            await d.deliver('onPipModeChanged', true);
            var held = false;
            d.systemHandler = (c) {
              if (!held &&
                  c.method == 'SystemChrome.setPreferredOrientations') {
                held = true;
                return gate.future;
              }
              return null;
            };
            pending = d.event('onPipRestore', null);
            await f.until(t, () => held);
            // Restoring removes the parked entry before awaiting the channel.
            // Park it again through the public native mode event, then replace it.
            await d.deliver('onPipModeChanged', true);
          } else {
            await d.enter();
            final nativeBefore = n.calls.length;
            if (stage == 'handle') {
              old.delays['handle'] = gate;
            }
            if (stage == 'subtitle') {
              n.heldOperation = (name, v) =>
                  name == 'setProperty' &&
                  v == ('sub-visibility', 'yes') &&
                  !gate.isCompleted;
              n.beforeOperation = (name, v) =>
                  n.heldOperation!(name, v) ? gate.future : null;
            }
            if (stage == 'entry') {
              d.handler = (c) => c.method == 'enterPip'
                  ? gate.future.then((_) => true)
                  : c.method == 'isSupported'
                  ? true
                  : null;
            }
            final dynamic callback = playerControls(t).onPip!;
            pending = d.observe<Future<dynamic>>(() => callback());
            await f.until(
              t,
              () => stage == 'handle'
                  ? d.operations('handle', old).length == 2
                  : stage == 'subtitle'
                  ? n.calls
                        .skip(nativeBefore)
                        .any(
                          (c) =>
                              c.$1 == 'setProperty' &&
                              c.$2 == ('sub-visibility', 'yes'),
                        )
                  : d.named('enterPip').isNotEmpty,
            );
            // Native may report the mode while the entry Future is outstanding.
            await d.deliver('onPipModeChanged', true);
          }
          expect(oldRoute.session.isParked, isTrue);
          expect(gate.isCompleted, isFalse);
          final next = IosPipPlayerRoute<void>(
            builder: (_) => const VideoPlayerScreen(
              videoUrl: 'https://player.test/replacement.mp4',
              title: 'Replacement PiP',
            ),
          );
          f.navigator.currentState!.push(next);
          await f.until(
            t,
            () => f.players.length == 2 && old.disposed.isCompleted,
          );
          final fresh = f.player;
          await d.flushWake();
          expect(
            d.wake.writes.last,
            isTrue,
            reason:
                'Replaced PiP disposal cannot release the incoming init request while audio setup remains held',
          );
          expect(setup.isCompleted, isFalse);
          setup.complete();
          fresh.deliverReady();
          await f.until(t, () => d.operations('open', fresh).isNotEmpty);
          await d.settle();
          await d.flushWake();
          expect(oldRoute.session.wasReplaced, isTrue);
          expect(fresh.handleValue, isNot(old.handleValue));
          expect(PipService.isOwner(oldOwner), isFalse);
          gate.complete();
          old.delays.remove('handle');
          final result = await f.finish<dynamic>(t, pending);
          if (stage == 'orientation') {
            expect(result, isFalse);
          }
          expect(
            d.named('enterPip').length,
            stage == 'handle' || stage == 'orientation' ? 1 : 2,
          );
          expect(
            d
                .named('enterPip')
                .map((c) => (c.arguments as Map)['playerHandle']),
            stage == 'handle' || stage == 'orientation'
                ? ['${old.handleValue}']
                : ['${old.handleValue}', '${old.handleValue}'],
          );
          final changes = d.named('updatePlaybackState').length;
          await d.deliver('onPipAction', 'pause', from: old);
          // The original late subtitle path overwrites the service handle even
          // after a new State became owner; its old action then pauses the new player.
          expect(fresh.state.playing, stage != 'subtitle');
          await fresh.play();
          await d.settle();
          await d.enter();
          expect(d.named('enterPip').last.arguments, ({
            'playerHandle': '${fresh.handleValue}',
            'aspectWidth': 1280,
            'aspectHeight': 720,
          }));
          await d.deliver('onPipAction', 'pause', from: old);
          expect(fresh.state.playing, isTrue);
          await d.deliver('onPipAction', 'pause', from: fresh);
          expect(fresh.state.playing, isFalse);
          expect(d.named('updatePlaybackState').length, greaterThan(changes));
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          if (!setup.isCompleted) {
            setup.complete();
          }
          for (final p in f.players) {
            p.delays.remove('handle');
          }
          if (pending != null) {
            await f.finish<dynamic>(t, pending);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP held support across real route replacement cannot reclaim the fresh State or handle',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final gate = Completer<bool>();
      var requests = 0;
      try {
        d.handler = (c) => c.method == 'isSupported'
            ? (++requests == 1 ? gate.future : true)
            : c.method == 'enterPip'
            ? true
            : null;
        await d.mount();
        final old = f.player;
        final oldOwner = d.stateOwner!;
        expect(PipService.isOwner(oldOwner), isFalse);
        expect(gate.isCompleted, isFalse);
        final next = IosPipPlayerRoute<Object?>(
          builder: (_) => const VideoPlayerScreen(
            videoUrl: 'https://player.test/support-new.mp4',
            title: 'Support replacement',
          ),
        );
        await d.observe(() async {
          f.navigator.currentState!.replace(oldRoute: d.route!, newRoute: next);
          await f.until(
            t,
            () => f.players.length == 2 && old.disposed.isCompleted,
          );
          f.player.deliverReady();
          await f.until(t, () => d.operations('open').isNotEmpty);
          await d.settle();
        });
        final freshOwner = t.state(find.byType(VideoPlayerScreen));
        expect(PipService.isOwner(freshOwner), isTrue);
        expect(f.player.handleValue, isNot(old.handleValue));
        gate.complete(true);
        await d.settle();
        expect(PipService.isOwner(oldOwner), isFalse);
        expect(PipService.isOwner(freshOwner), isTrue);
        expect(requests, 2);
        expect(d.errors, isEmpty);
        await d.enter();
        expect(d.named('enterPip').single.arguments, {
          'playerHandle': '${f.player.handleValue}',
          'aspectWidth': 1280,
          'aspectHeight': 720,
        });
      } finally {
        if (!gate.isCompleted) gate.complete(false);
        await d.close();
      }
    },
  );
}
