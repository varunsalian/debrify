import 'dart:async';

import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'video_player_subtitle_apply_races_test.dart' show ApplyTurn;
import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_external_test.dart'
    show oldAddonTracks, removals;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_subtitle_sources_priority_test.dart' show priorityScreen;

void main() {
  for (final collision in [false, true]) {
    testWidgets(
      'subtitle forced path overrides matching audio and excludes addon collision $collision',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            if (collision) {
              p.publishTracks(
                mk.Tracks(
                  audio: p.state.tracks.audio,
                  subtitle: oldAddonTracks,
                ),
                selected: p.state.track,
              );
            }
            (p.platform as FakeNativePlayer).properties.addAll({
              'current-tracks/audio/lang': 'eng',
              'track-list/count': '1',
              'track-list/0/type': 'sub',
              'track-list/0/forced': 'yes',
              'track-list/0/external': 'no',
              'track-list/0/lang': 'eng',
              'track-list/0/id': collision ? '8' : '2',
            });
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleForcedOnly(true),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(d.player.state.track.subtitle.id, collision ? 'no' : '2');
          expect(
            d.native.calls.where(
              (c) => c.$1 == 'getProperty' && c.$2 == 'track-list/count',
            ),
            isNotEmpty,
          );
          expect(
            d.player.calls.where(
              (c) => c.$1 == 'subtitle' && (c.$2 as mk.SubtitleTrack).id == '8',
            ),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  for (final change in ['manual', 'audio']) {
    testWidgets(
      'subtitle automatic cleanup stops between ordinals after $change invalidates its caller',
      (t) async {
        final d = SubtitleSourcesDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                'fra';
            p.publishTracks(
              mk.Tracks(audio: p.state.tracks.audio, subtitle: oldAddonTracks),
              selected: p.state.track,
            );
          },
        );
        await d.setup();
        await d.register('cleanup-cancel');
        await d.order(language: 'eng');
        if (change == 'audio') {
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
          );
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
          );
        }
        final gate = Completer<void>();
        var entered = false;
        Future<void>? audio;
        try {
          await d.mount(screen: priorityScreen, publishTracks: false);
          // Mount returns before the asynchronous discovery/apply cleanup ends.
          d.native.heldOperation = (name, value) =>
              name == 'command' &&
              (value as List<String>).first == 'sub-remove' &&
              !gate.isCompleted;
          d.native.beforeOperation = (name, value) async {
            if (name == 'command' &&
                (value as List<String>).first == 'sub-remove' &&
                !entered) {
              entered = true;
              await gate.future;
            }
          };
          await d.f.until(t, () => entered);
          expect(removals(d.native), [
            ['sub-remove', '8'],
          ]);
          if (change == 'manual') {
            expect(await d.select('3'), isTrue);
          } else {
            final panel = await d.menu();
            d.native.properties['current-tracks/audio/lang'] = 'eng';
            audio = d.observe(() => panel.onAudioSelected('1', 'auto'));
            await d.f.until(t, () => d.player.state.track.subtitle.id == 'no');
          }
          expect(removals(d.native), [
            ['sub-remove', '8'],
          ]);
          gate.complete();
          if (audio != null) await d.f.finish(t, audio);
          await d.f.actions.settle(t);
          expect(removals(d.native), [
            ['sub-remove', '8'],
          ]);
          expect(
            d.logs,
            contains(
              'VideoPlayer: Content changed during addon subtitle cleanup; stopping before track 9',
            ),
          );
          if (change == 'manual') expect(d.player.state.track.subtitle.id, '3');
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle audio persistence before late restore success does not arm rollback writes',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: applyScreen.title,
          audioTrackId: '1',
          subtitleTrackId: '3',
        ),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
      );
      final read = CompletionDelivery(
        'restoreTrackPreferences',
        (v) => v == 'spa',
      );
      final turn = ApplyTurn()..armed = false;
      try {
        await turn.run(
          () => read.run(
            () => d.mount(publishTracks: false, settleInitialization: false),
          ),
        );
        await d.f.until(t, () => read.pending.isNotEmpty);
        expect(await d.select('2'), isTrue);
        expect((await d.saved())?['subtitleTrackId'], '2');
        turn.armed = true;
        read.release();
        await d.f.until(t, () => turn.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.id, '3');
        t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onClose();
        await d.f.advance(t);
        final panel = await d.menu();
        expect(panel.selectedSubtitleId, '3');
        await d.f.finish(
          t,
          d.observe(() => panel.onAudioSelected('2', panel.selectedSubtitleId)),
        );
        expect(turn.pending, hasLength(1));
        expect((await d.saved())?['subtitleTrackId'], '3');
        turn.release();
        await d.f.actions.settle(t);
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        d.observe(() => d.fail());
        await d.rollback('2');
        expect(d.player.state.track.subtitle.id, '2');
        // The pre-success audio write remains physical: restore has no later
        // persistence caller and its attempt never earned a persisted marker.
        expect((await d.saved())?['subtitleTrackId'], '3');
        expect((await d.saved())?['audioTrackId'], '2');
        expect(d.errors, isEmpty);
      } finally {
        read.release();
        turn.release();
        await removeFixture(d);
      }
    },
  );
}
