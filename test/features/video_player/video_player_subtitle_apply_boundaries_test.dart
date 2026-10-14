import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_apply_races_test.dart' show ApplyTurn;

const boundaryScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/apply-original.mp4',
  title: 'Subtitle apply original',
  viewMode: PlaylistViewMode.raw,
  playlist: [
    PlaylistEntry(
      url: 'https://player.test/apply-original.mp4',
      title: 'First',
    ),
    PlaylistEntry(url: 'https://player.test/apply-next.mp4', title: 'Second'),
  ],
);

Future<void> crossBoundary(SubtitleApplyDriver d, String event) async {
  final t = d.t;
  if (event == 'profile') {
    await incomingProfile(t, d.f);
  } else if (event == 'dispose') {
    await d.observe(() => t.pumpWidget(const SizedBox()));
    await d.f.until(t, () => d.player.disposed.isCompleted);
  } else if (event == 'reset') {
    final opens = d.player.calls.where((v) => v.$1 == 'open').length;
    final dynamic next = playerControls(t).onNext;
    final dynamic task = d.observe<dynamic>(() => next());
    if (task is Future) await d.f.finish<dynamic>(t, task);
    await d.f.until(
      t,
      () => d.player.calls.where((v) => v.$1 == 'open').length == opens + 1,
    );
  } else {
    final old = d.player;
    old.state = old.state.copyWith(position: Duration.zero);
    old.emit('position', Duration.zero);
    await d.f.advance(t);
    old.emit('error', 'synthetic MediaCodec video output failure');
    await d.f.until(t, () => d.f.players.length == 2);
    d.player.deliverReady();
    await d.f.until(t, () => d.player.calls.any((v) => v.$1 == 'open'));
    expect(old.disposed.isCompleted, isTrue);
  }
}

void main() {
  for (final boundary in [
    'apply visibility',
    'apply track',
    'rollback visibility',
    'rollback track',
    'success turn',
  ]) {
    for (final event in ['reset', 'profile', 'dispose', 'replacement']) {
      testWidgets(
        'subtitle $boundary held across $event preserves the original admitted work',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final gate = Completer<void>();
          final turn = ApplyTurn();
          var entered = false;
          var completed = false;
          final rollback = boundary.startsWith('rollback');
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
            if (rollback) expect(await d.select('2', panel: panel), isTrue);
            final target = rollback ? '1' : '2';
            old.calls.clear();
            native.calls.clear();
            bool blocked(String name, Object? value) =>
                !entered &&
                (boundary.endsWith('visibility')
                    ? name == 'setProperty' &&
                          (value as (String, String)).$1 == 'sub-visibility'
                    : name == 'subtitle' &&
                          (value as mk.SubtitleTrack).id == target);
            Future<void> hold(String name, Object? value) async {
              if (blocked(name, value)) {
                entered = true;
                await gate.future;
              }
            }

            if (boundary.endsWith('visibility')) {
              native.beforeOperation = hold;
              native.heldOperation = (name, value) =>
                  name == 'setProperty' &&
                  (value as (String, String)).$1 == 'sub-visibility' &&
                  !gate.isCompleted;
            } else if (boundary.endsWith('track')) {
              old.beforeOperation = hold;
              old.heldOperation = (name, value) =>
                  name == 'subtitle' &&
                  (value as mk.SubtitleTrack).id == target &&
                  !gate.isCompleted;
            }
            Future<bool>? action;
            if (rollback) {
              d.fail();
            } else {
              action = turn.run(
                () =>
                    d.observe(() => panel.onEmbeddedSubtitleSelected('2', '1')),
              );
              action!.then((_) => completed = true);
            }
            await d.f.until(
              t,
              () => boundary == 'success turn'
                  ? turn.pending.isNotEmpty
                  : entered,
            );
            expect(completed, isFalse);
            expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
            expect(
              old.state.track.subtitle.id,
              rollback || boundary == 'success turn' ? '2' : '1',
            );
            if (!rollback && boundary != 'success turn') {
              expect(turn.pending, isEmpty);
            }
            await crossBoundary(d, event);
            final incomingApplications = d.player.calls
                .where((v) => v.$1 == 'subtitle')
                .length;
            expect(completed, isFalse);
            expect(gate.isCompleted, isFalse);
            if (boundary == 'success turn') expect(turn.pending, hasLength(1));
            gate.complete();
            if (!rollback && boundary != 'success turn') {
              await d.f.until(t, () => turn.pending.isNotEmpty);
            }
            turn.release();
            if (action != null) {
              expect(await d.f.finish(t, action), isTrue);
            } else {
              await d.f.actions.settle(t);
            }
            final selectedPlayer =
                event == 'replacement' && boundary.endsWith('visibility')
                ? d.player
                : old;
            expect(
              selectedPlayer.calls
                  .where((v) => v.$1 == 'subtitle')
                  .map((v) => (v.$2 as mk.SubtitleTrack).id),
              contains(target),
            );
            if (event == 'replacement' && boundary.endsWith('visibility')) {
              expect(
                d.player.calls.where((v) => v.$1 == 'subtitle').length,
                incomingApplications + 1,
              );
            }
            if (event == 'replacement' && boundary == 'apply visibility') {
              expect(old.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
              expect(d.player.state.track.subtitle.id, '2');
              expect(native.properties['sub-visibility'], 'no');
            }
            if (event == 'replacement' && boundary == 'apply track') {
              expect(
                d.player.calls.where(
                  (v) =>
                      v.$1 == 'subtitle' &&
                      (v.$2 as mk.SubtitleTrack).id == '2',
                ),
                isEmpty,
              );
              expect(old.state.track.subtitle.id, '2');
            }
            expect((await d.saved())?['subtitleTrackId'], rollback ? '1' : '2');
            expect(
              d.logs.where((v) => v.contains('user notified')),
              hasLength(rollback && event != 'dispose' ? 1 : 0),
            );
            expect(d.errors, isEmpty);
          } finally {
            if (!gate.isCompleted) gate.complete();
            turn.release();
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
}
