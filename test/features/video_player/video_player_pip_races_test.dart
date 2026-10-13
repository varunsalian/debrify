import 'dart:async';

import 'package:debrify/services/pip_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

void main() {
  for (final stage in ['handle', 'subtitle', 'entry']) {
    for (final handoff in ['dispose', 'owner', 'profile']) {
      testWidgets(
        'PiP iOS held $stage across $handoff preserves original entry and finalization boundaries',
        (t) async {
          final f = VideoPlayerEnvironment(native: true);
          final d = PipLifecycleDriver(t, f, ios: true);
          await d.initialize();
          final gate = Completer<void>();
          Future<dynamic>? pending;
          try {
            await d.mount();
            final old = f.player;
            final native = old.platform! as FakeNativePlayer;
            final before = native.calls.length;
            if (stage == 'handle') {
              old.delays['handle'] = gate;
            }
            if (stage == 'subtitle') {
              native.heldOperation = (name, value) =>
                  name == 'setProperty' &&
                  value == ('sub-visibility', 'yes') &&
                  !gate.isCompleted;
              native.beforeOperation = (name, value) {
                if (native.heldOperation!(name, value)) {
                  return gate.future;
                }
              };
            }
            if (stage == 'entry') {
              d.handler = (call) => call.method == 'enterPip'
                  ? gate.future.then((_) => true)
                  : call.method == 'isSupported'
                  ? true
                  : null;
            }
            final dynamic enter = playerControls(t).onPip!;
            pending = d.observe<Future<dynamic>>(() => enter());
            await f.until(
              t,
              () => stage == 'handle'
                  ? d.operations('handle', old).length == 1
                  : stage == 'subtitle'
                  ? native.calls
                        .skip(before)
                        .any(
                          (c) =>
                              c.$1 == 'setProperty' &&
                              c.$2 == ('sub-visibility', 'yes'),
                        )
                  : d.named('enterPip').isNotEmpty,
            );
            expect(gate.isCompleted, isFalse);
            final requestsBefore = d.named('enterPip').length;
            if (handoff == 'dispose') {
              await d.retire();
            }
            if (handoff == 'owner') {
              PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
            }
            if (handoff == 'profile') {
              await incomingProfile(t, f);
            }
            gate.complete();
            old.delays.remove('handle');
            await f.finish<dynamic>(t, pending);
            await d.settle();
            expect(
              d.named('enterPip').length,
              stage == 'handle' && handoff != 'profile' ? 0 : 1,
            );
            expect(
              d
                  .named('enterPip')
                  .skip(requestsBefore)
                  .map((c) => (c.arguments as Map)['playerHandle']),
              stage != 'entry' && !(stage == 'handle' && handoff != 'profile')
                  ? ['${old.handleValue}']
                  : isEmpty,
            );
            final visibility = native.calls
                .skip(before)
                .where(
                  (c) =>
                      c.$1 == 'setProperty' &&
                      (c.$2 as (String, String)).$1 == 'sub-visibility',
                )
                .map((c) => (c.$2 as (String, String)).$2)
                .toList();
            expect(
              visibility,
              handoff == 'owner'
                  ? (stage == 'handle' ? ['yes'] : ['yes', 'yes'])
                  : stage == 'handle' && handoff == 'dispose'
                  ? isEmpty
                  : handoff == 'profile'
                  ? ['yes', 'no']
                  : ['yes'],
            );
            expect(d.errors, isEmpty);
          } finally {
            if (!gate.isCompleted) {
              gate.complete();
            }
            if (f.players.isNotEmpty) {
              f.players.first.delays.remove('handle');
            }
            if (pending != null) {
              await f.finish<dynamic>(t, pending);
            }
            await d.close();
          }
        },
      );
    }
  }
  for (final handoff in ['dispose', 'owner', 'profile']) {
    testWidgets(
      'PiP iOS restore orientation held across $handoff continues platform writes then checks State ownership',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final d = PipLifecycleDriver(t, f, ios: true);
        await d.initialize();
        final gate = Completer<void>();
        Future<Object?>? pending;
        var first = true;
        try {
          await d.mount();
          await d.enter();
          await d.deliver('onPipModeChanged', true);
          d.systemHandler = (call) {
            if (first &&
                call.method == 'SystemChrome.setPreferredOrientations') {
              first = false;
              return gate.future;
            }
            return null;
          };
          final marker = f.channels.length;
          pending = d.event('onPipRestore', null);
          await f.until(t, () => !first);
          expect(gate.isCompleted, isFalse);
          expect(d.route!.session.isParked, isFalse);
          if (handoff == 'dispose') {
            await d.retire();
          }
          if (handoff == 'owner') {
            PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
          }
          if (handoff == 'profile') {
            await incomingProfile(t, f);
          }
          final afterHandoff = f.channels.length;
          gate.complete();
          expect(await f.finish<Object?>(t, pending), handoff == 'profile');
          await d.settle();
          expect(
            f.channels
                .skip(afterHandoff)
                .where(
                  (c) => c.$2.method == 'SystemChrome.setEnabledSystemUIMode',
                )
                .map((c) => c.$2.arguments),
            ['SystemUiMode.immersiveSticky'],
          );
          expect(
            f.channels
                .skip(marker)
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
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          if (pending != null) {
            await f.finish<Object?>(t, pending);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP iOS starting handle prevents duplicate entries and background pauses until completion',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final gate = Completer<void>();
      Future<dynamic>? pending;
      try {
        await d.mount();
        f.player.delays['handle'] = gate;
        final dynamic enter = playerControls(t).onPip!;
        pending = d.observe<Future<dynamic>>(() => enter());
        await f.until(t, () => d.operations('handle').length == 1);
        await f.finish<dynamic>(t, enter());
        await background(d);
        expect(d.operations('handle'), hasLength(1));
        expect(d.operations('pause'), hasLength(1));
        expect(d.named('enterPip'), isEmpty);
        gate.complete();
        f.player.delays.remove('handle');
        await f.finish<dynamic>(t, pending);
        await foreground(d);
        await d.enter();
        expect(d.named('enterPip'), hasLength(2));
        expect(d.operations('handle'), hasLength(2));
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (f.players.isNotEmpty) {
          f.player.delays.remove('handle');
        }
        if (pending != null) {
          await f.finish<dynamic>(t, pending);
        }
        await d.close();
      }
    },
  );
  for (final failure in ['handle', 'subtitle', 'entry']) {
    testWidgets(
      'PiP iOS $failure rejection resets starting state and displays the original retry message',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final d = PipLifecycleDriver(t, f, ios: true);
        await d.initialize();
        final previousPrint = debugPrint;
        try {
          await d.mount();
          final n = f.player.platform! as FakeNativePlayer;
          final diagnostics = <String?>[];
          debugPrint = (message, {wrapWidth}) {
            diagnostics.add(message);
            previousPrint(message, wrapWidth: wrapWidth);
          };
          if (failure == 'handle') {
            f.player.failures['handle'] = StateError('handle rejected');
          }
          if (failure == 'subtitle') {
            n.failures['setProperty'] = StateError(
              'subtitle preparation rejected',
            );
          }
          if (failure == 'entry') {
            d.handler = (call) => call.method == 'enterPip'
                ? false
                : call.method == 'isSupported'
                ? true
                : null;
          }
          await d.enter();
          expect(
            find.text('Picture in Picture could not start. Please try again.'),
            findsOneWidget,
          );
          expect(d.errors, isEmpty);
          if (failure == 'handle') {
            expect(
              diagnostics,
              contains('PiP entry failed: Bad state: handle rejected'),
            );
          }
          f.player.failures.remove('handle');
          d.handler = null;
          await d.enter();
          expect(d.operations('handle'), hasLength(2));
          expect(d.named('enterPip').length, failure == 'entry' ? 2 : 1);
        } finally {
          debugPrint = previousPrint;
          if (f.players.isNotEmpty) {
            f.player.failures.remove('handle');
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP failed iOS entry while background pause is held invokes the State fallback before retry toast and resume',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final entry = Completer<bool>();
      final pause = Completer<void>();
      Future<dynamic>? pending;
      try {
        await d.mount();
        d.handler = (c) => c.method == 'enterPip'
            ? entry.future
            : c.method == 'isSupported'
            ? true
            : null;
        f.player.delays['pause'] = pause;
        final dynamic enter = playerControls(t).onPip!;
        pending = d.observe<Future<dynamic>>(() => enter());
        await f.until(t, () => d.named('enterPip').isNotEmpty);
        await background(d);
        expect(d.operations('pause'), hasLength(1));
        expect(pause.isCompleted, isFalse);
        entry.complete(false);
        await f.finish<dynamic>(t, pending);
        await d.settle();
        expect(d.operations('pause'), hasLength(2));
        await foreground(d);
        await d.settle();
        expect(
          find.text('Picture in Picture could not start. Please try again.'),
          findsOneWidget,
        );
        expect(d.operations('play'), hasLength(1));
        pause.complete();
        f.player.delays.remove('pause');
        await d.settle();
        expect(f.player.state.playing, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!entry.isCompleted) {
          entry.complete(false);
        }
        if (!pause.isCompleted) {
          pause.complete();
        }
        if (f.players.isNotEmpty) {
          f.player.delays.remove('pause');
        }
        if (pending != null) {
          await f.finish<dynamic>(t, pending);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP restore waits for the frame and observes owner replacement in that frame',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        var handedOff = false;
        d.systemHandler = (c) {
          if (c.method == 'SystemChrome.setEnabledSystemUIMode') {
            t.binding.addPostFrameCallback((_) {
              handedOff = true;
              PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
            });
          }
          return null;
        };
        expect(
          await f.finish<Object?>(t, d.event('onPipRestore', null)),
          isFalse,
        );
        expect(handedOff, isTrue);
        expect(d.route!.session.isParked, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP rejected restore orientation propagates its channel error after reattaching and before immersive mode',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      try {
        await d.mount();
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        final marker = f.channels.length;
        d.systemHandler = (c) {
          if (c.method == 'SystemChrome.setPreferredOrientations') {
            throw PlatformException(
              code: 'restore-rejected',
              message: 'orientation rejected',
            );
          }
          return null;
        };
        await f.finish(
          t,
          expectLater(
            d.event('onPipRestore', null),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'restore-rejected',
              ),
            ),
          ),
        );
        expect(d.route!.session.isParked, isFalse);
        expect(
          f.channels
              .skip(marker)
              .where(
                (c) => c.$2.method == 'SystemChrome.setEnabledSystemUIMode',
              ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        d.systemHandler = null;
        await d.close();
      }
    },
  );
}
