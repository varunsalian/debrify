import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;

void main() {
  for (final stage in ['visibility', 'track']) {
    for (final event in ['reset', 'profile', 'dispose', 'replacement']) {
      testWidgets(
        'subtitle late $stage exception after $event obeys only the original failure admission guard',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final gate = Completer<void>();
          var entered = false;
          try {
            if (event == 'replacement') {
              VpS2Hooks.install(
                VpS2Hooks(android: () => true, ios: () => false),
              );
              await d.f.finish(
                t,
                PlayerSettingsStorage.setAndroidVideoRendererMode(
                  AndroidVideoRendererMode.directSurface,
                ),
              );
            }
            await d.mount(screen: boundaryScreen);
            final old = d.player;
            final native = old.platform as FakeNativePlayer;
            final panel = await d.menu();
            Future<void> hold(String name, Object? value) async {
              final match = stage == 'visibility'
                  ? name == 'setProperty' && value == ('sub-visibility', 'no')
                  : name == 'subtitle' && (value as mk.SubtitleTrack).id == '2';
              if (!entered && match) {
                entered = true;
                await gate.future;
                throw StateError('late boundary rejection');
              }
            }

            if (stage == 'visibility') {
              native.beforeOperation = hold;
              native.heldOperation = (name, value) =>
                  name == 'setProperty' &&
                  value == ('sub-visibility', 'no') &&
                  !gate.isCompleted;
            } else {
              old.beforeOperation = hold;
              old.heldOperation = (name, value) =>
                  name == 'subtitle' &&
                  (value as mk.SubtitleTrack).id == '2' &&
                  !gate.isCompleted;
            }
            var completed = false;
            final action = d.observe(
              () => panel.onEmbeddedSubtitleSelected('2', '1'),
            );
            action.then((_) => completed = true);
            await d.f.until(t, () => entered);
            expect(completed, isFalse);
            await crossBoundary(d, event);
            expect(completed, isFalse);
            gate.complete();
            expect(await d.f.finish(t, action), isFalse);
            await d.f.actions.settle(t);
            expect(await d.saved(), isNull);
            expect(
              d.logs.where(
                (v) => v.startsWith(
                  '[SubtitleDiag] set FAILED source=player-menu-embedded requestedId=2 error=Bad state: late boundary rejection',
                ),
              ),
              hasLength(1),
            );
            expect(
              d.logs.where((v) => v.contains('user notified')),
              hasLength(event == 'profile' ? 1 : 0),
            );
            if (event == 'profile') {
              expect(
                d.player.calls
                    .where((v) => v.$1 == 'subtitle')
                    .map((v) => (v.$2 as mk.SubtitleTrack).id),
                contains('1'),
              );
              expect(d.player.state.track.subtitle.id, '1');
            }
            expect(d.errors, isEmpty);
          } finally {
            if (!gate.isCompleted) gate.complete();
            for (final player in d.f.players) {
              player.beforeOperation = null;
              player.heldOperation = null;
              final native = player.platform as FakeNativePlayer;
              native.beforeOperation = null;
              native.heldOperation = null;
            }
            await d.close();
            VpS2Hooks.install(null);
          }
        },
      );
    }
  }
  testWidgets(
    'subtitle manual addon admitted apply continues across content reset before its outer guard rejects persistence',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      var entered = false;
      try {
        await d.mount(screen: boundaryScreen);
        final panel = await d.menu();
        d.native.beforeOperation = (name, value) async {
          if (!entered &&
              name == 'setProperty' &&
              value == ('sub-visibility', 'no')) {
            entered = true;
            await gate.future;
          }
        };
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' &&
            value == ('sub-visibility', 'no') &&
            !gate.isCompleted;
        final action = d.startAddon('stale-addon', panel);
        await d.f.until(t, () => entered);
        await crossBoundary(d, 'reset');
        expect(gate.isCompleted, isFalse);
        gate.complete();
        expect(await d.f.finish(t, action), isFalse);
        expect(
          d.player.calls.where(
            (v) => v.$1 == 'subtitle' && (v.$2 as mk.SubtitleTrack).uri,
          ),
          isNotEmpty,
        );
        expect(await d.saved(), isNull);
        expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        d.native.beforeOperation = null;
        d.native.heldOperation = null;
        await d.close();
      }
    },
  );
}
