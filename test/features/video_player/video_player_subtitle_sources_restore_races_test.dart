import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  for (final event in [
    'manual',
    'reset',
    'profile',
    'dispose',
    'replacement',
  ]) {
    testWidgets(
      'subtitle stored language read held across $event retains original captured selection',
      (t) async {
        final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
        await d.initialize();
        await d.f.finish(
          t,
          TrackPreferencesStorage.saveVideoTrackPreferences(
            videoTitle: boundaryScreen.title,
            audioTrackId: '1',
            subtitleTrackId: '3',
          ),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
        );
        final autosaves = <Timer>[];
        final capture = ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            if (duration == const Duration(seconds: 6) &&
                StackTrace.current.toString().contains('initializePlayer')) {
              autosaves.add(timer);
            }
            return timer;
          },
        );
        final held = CompletionDelivery(
          'restoreTrackPreferences',
          (v) => v == 'spa',
        );
        try {
          if (event == 'replacement') {
            VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
            await d.f.finish(
              t,
              PlayerSettingsStorage.setAndroidVideoRendererMode(
                AndroidVideoRendererMode.directSurface,
              ),
            );
          }
          await runZoned(
            () => held.run(
              () => d.mount(
                screen: boundaryScreen,
                publishTracks: false,
                settleInitialization: false,
              ),
            ),
            zoneSpecification: capture,
          );
          await d.f.until(t, () => held.pending.isNotEmpty);
          expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
          final old = d.player;
          if (event == 'manual') {
            expect(await d.select('1'), isTrue);
          } else {
            await crossBoundary(d, event);
          }
          final doneBefore = d.logs
              .where((s) => s.contains('restore done'))
              .length;
          final before = d.player.calls.where((c) => c.$1 == 'subtitle').length;
          expect(held.pending, hasLength(1));
          held.release();
          await d.f.actions.settle(t);
          await d.f.advance(t, const Duration(milliseconds: 200));
          if (event == 'dispose') {
            expect(old.calls.where((c) => c.$1 == 'subtitle'), hasLength(1));
            expect(old.state.track.subtitle.id, '3');
          } else {
            expect(d.player.state.track.subtitle.id, '3');
            expect(
              d.player.calls.where((c) => c.$1 == 'subtitle').length,
              greaterThan(before),
            );
          }
          expect(
            d.logs.where(
              (s) => s.contains('applying STORED subtitle track id=3'),
            ),
            isNotEmpty,
          );
          if (event == 'dispose') {
            await d.f.until(t, () => autosaves.any((timer) => timer.isActive));
            expect(autosaves.where((timer) => timer.isActive), hasLength(1));
            // Original initialization creates this timer after disposal. Assert
            // the leak first, then release exactly its test-clock handle.
            autosaves.singleWhere((timer) => timer.isActive).cancel();
          }
          if (event == 'reset') {
            expect(
              d.logs,
              contains('SubAuto: restore aborted post-apply (content changed)'),
            );
            expect(
              d.logs.where((s) => s.contains('restore done')),
              hasLength(doneBefore),
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          VpS2Hooks.install(null);
          await removeFixture(d);
        }
      },
    );
  }
  for (final event in [
    'manual',
    'reset',
    'profile',
    'dispose',
    'replacement',
  ]) {
    testWidgets(
      'subtitle native audio read held across $event uses captured tracks and live player',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                'fra';
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        final autosaves = <Timer>[];
        final capture = ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            if (duration == const Duration(seconds: 6) &&
                StackTrace.current.toString().contains('initializePlayer')) {
              autosaves.add(timer);
            }
            return timer;
          },
        );
        final held = CompletionDelivery(
          'applyDefaultAudioLanguage',
          (v) => v == 'fra',
        );
        try {
          if (event == 'replacement') {
            VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
            await d.f.finish(
              t,
              PlayerSettingsStorage.setAndroidVideoRendererMode(
                AndroidVideoRendererMode.directSurface,
              ),
            );
          }
          await runZoned(
            () => held.run(
              () => d.mount(
                screen: boundaryScreen,
                publishTracks: false,
                settleInitialization: false,
              ),
            ),
            zoneSpecification: capture,
          );
          await d.f.until(t, () => held.pending.isNotEmpty);
          final old = d.player;
          expect(old.state.track.audio.id, '2');
          if (event == 'manual') {
            final panel = await d.menu();
            await d.f.finish(
              t,
              d.observe(() => panel.onAudioSelected('3', 'no')),
            );
          } else {
            await crossBoundary(d, event);
          }
          final target = d.player;
          final before = target.calls.where((c) => c.$1 == 'audio').length;
          held.release();
          await d.f.actions.settle(t);
          expect(target.state.track.audio.id, '1');
          expect(
            target.calls.where((c) => c.$1 == 'audio').length,
            greaterThan(before),
          );
          if (event == 'replacement') {
            expect(identical(old, target), isFalse);
          }
          if (event == 'dispose') {
            await d.f.until(t, () => autosaves.any((timer) => timer.isActive));
            expect(autosaves.where((timer) => timer.isActive), hasLength(1));
            // Original initialization creates this timer after disposal. Assert
            // the leak first, then release exactly its test-clock handle.
            autosaves.singleWhere((timer) => timer.isActive).cancel();
          }
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          VpS2Hooks.install(null);
          await removeFixture(d);
        }
      },
    );
  }
}
