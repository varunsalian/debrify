import 'dart:async';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart' show boundaryScreen;

void main() {
  for (final setup in [
    'stored',
    'no preference',
    'off',
    'language',
    'foreign off',
    'forced',
  ]) {
    testWidgets(
      'subtitle initialization reaches the $setup original apply caller',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            p.state = p.state.copyWith(
              tracks: const mk.Tracks(
                audio: [mk.AudioTrack('1', 'English audio', 'eng')],
                subtitle: applyTracks,
              ),
            );
            final native = p.platform as FakeNativePlayer;
            native.properties['sid'] = '2';
            native.properties['current-tracks/audio/lang'] = 'eng';
          },
        );
        await d.initialize();
        try {
          if (setup == 'stored') {
            await d.f.finish(
              t,
              TrackPreferencesStorage.saveVideoTrackPreferences(
                videoTitle: applyScreen.title,
                audioTrackId: '1',
                subtitleTrackId: '2',
              ),
            );
          }
          if (setup == 'off') {
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setDefaultSubtitleLanguage('off'),
            );
          }
          if (setup == 'language') {
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setDefaultSubtitleLanguage('fr'),
            );
          }
          if (setup == 'foreign off') {
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setDefaultAudioLanguage('en'),
            );
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
            );
          }
          if (setup == 'forced') {
            await d.f.finish(
              t,
              SubtitleSettingsStorage.setSubtitleForcedOnly(true),
            );
          }
          await d.mount(publishTracks: false);
          final expected = setup == 'stored' || setup == 'no preference'
              ? '2'
              : setup == 'language'
              ? '3'
              : 'no';
          expect(d.player.state.track.subtitle.id, expected);
          expect(
            d.player.calls
                .where((v) => v.$1 == 'subtitle')
                .map((v) => (v.$2 as mk.SubtitleTrack).id),
            contains(expected),
          );
          expect(d.native.properties['sub-visibility'], 'no');
          if (setup == 'foreign off') {
            expect(
              d.player.calls
                  .where((v) => v.$1 == 'subtitle')
                  .map((v) => (v.$2 as mk.SubtitleTrack).id),
              ['no', 'no'],
            );
          }
          d.fail();
          await d.rollback('no');
          if (setup == 'stored') {
            expect((await d.saved())?['subtitleTrackId'], '2');
          } else {
            expect(await d.saved(), isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle live audio policy uses the off apply caller before source priority reselects',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(
              audio: [
                mk.AudioTrack('1', 'English', 'eng'),
                mk.AudioTrack('2', 'Spanish', 'spa'),
              ],
              subtitle: applyTracks,
            ),
            track: const mk.Track(audio: mk.AudioTrack('2', 'Spanish', 'spa')),
          );
          (p.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'spa';
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('en'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('fr'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
        );
        await d.mount(publishTracks: false);
        expect(d.player.state.track.subtitle.id, '3');
        final panel = await d.menu();
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        d.player.calls.clear();
        await d.f.finish(t, d.observe(() => panel.onAudioSelected('1', '3')));
        expect(
          d.player.calls
              .where((v) => v.$1 == 'subtitle')
              .map((v) => (v.$2 as mk.SubtitleTrack).id),
          ['no'],
        );
        expect(d.player.state.track.subtitle.id, 'no');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final caller in [
    'magic next',
    'next channel',
    'guide channel',
    'Stremio guide',
  ]) {
    testWidgets(
      'subtitle $caller open uses its diagnostic no-track caller and preserves rollback',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: applyScreen.videoUrl,
              title: applyScreen.title,
              requestMagicNext: caller == 'magic next'
                  ? () async => {
                      'url': 'https://player.test/next.mp4',
                      'title': 'Next',
                    }
                  : null,
              requestNextChannel: caller == 'next channel'
                  ? () async => {
                      'firstUrl': 'https://player.test/next.mp4',
                      'firstTitle': 'Next',
                    }
                  : null,
              requestChannelById: caller == 'guide channel'
                  ? (id) async => {
                      'firstUrl': 'https://player.test/next.mp4',
                      'firstTitle': 'Next',
                    }
                  : null,
              channelDirectory: caller == 'guide channel'
                  ? [
                      {'id': 'a', 'name': 'A'},
                      {'id': 'b', 'name': 'B'},
                    ]
                  : null,
              stremioTvChannels: caller == 'Stremio guide'
                  ? [
                      {'id': 'a', 'name': 'A'},
                      {'id': 'b', 'name': 'B'},
                    ]
                  : null,
              stremioTvCurrentChannelId: caller == 'Stremio guide' ? 'a' : null,
              stremioTvChannelSwitchProvider: caller == 'Stremio guide'
                  ? (id) async => null
                  : null,
            ),
          );
          d.player.failures['subtitle'] = StateError(
            'channel no-track rejection',
          );
          if (caller == 'magic next') {
            final dynamic next = playerControls(t).onNext!;
            await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          } else if (caller == 'next channel') {
            final dynamic next = playerControls(t).onNextChannel!;
            await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          } else if (caller == 'guide channel') {
            playerControls(t).onShowGuide!();
            await d.f.until(
              t,
              () => find.byType(ChannelGuide).evaluate().isNotEmpty,
            );
            final guide = t.widget<ChannelGuide>(find.byType(ChannelGuide));
            d.observe(() => guide.onChannelSelected(guide.channels.last));
          } else {
            playerControls(t).onShowGuide!();
            await d.f.until(
              t,
              () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
            );
            final guide = t.widget<StremioTvGuideSheet>(
              find.byType(StremioTvGuideSheet),
            );
            d.observe(
              () => guide.onChannelSwitched(
                'b',
                'https://player.test/next.mp4',
                'Next',
              ),
            );
          }
          final source = {
            'magic next': 'debrify-tv-open-disable-auto',
            'next channel': 'next-channel-disable-auto',
            'guide channel': 'channel-switch-disable-auto',
            'Stremio guide': 'stremio-tv-switch-disable-auto',
          }[caller]!;
          await d.f.until(
            t,
            () => d.logs.any(
              (v) => v.startsWith(
                '[SubtitleDiag] set FAILED source=$source requestedId=no error=Bad state: channel no-track rejection',
              ),
            ),
          );
          expect(
            d.logs.where(
              (v) => v.startsWith(
                '[SubtitleDiag] user notified source=$source reason=Bad state: channel no-track rejection',
              ),
            ),
            hasLength(1),
          );
          expect(d.player.state.track.subtitle.id, '1');
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/next.mp4',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle automatic language apply rejects its old content after held visibility without setting a second track',
    (t) async {
      final gate = Completer<void>();
      var entered = false;
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(
              audio: [mk.AudioTrack('1', 'English', 'eng')],
              subtitle: applyTracks,
            ),
          );
          final n = p.platform as FakeNativePlayer;
          n.beforeOperation = (name, value) async {
            if (!entered &&
                name == 'setProperty' &&
                value == ('sub-visibility', 'no') &&
                StackTrace.current.toString().contains(
                  'setNativeSubtitleVisibilityForTrack',
                )) {
              entered = true;
              await gate.future;
            }
          };
          n.heldOperation = (name, value) =>
              entered &&
              !gate.isCompleted &&
              name == 'setProperty' &&
              value == ('sub-visibility', 'no');
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('fr'),
        );
        await d.mount(
          screen: boundaryScreen,
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(t, () => entered);
        expect(d.player.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        final applied = d.player.calls.where((v) => v.$1 == 'subtitle').length;
        expect(gate.isCompleted, isFalse);
        gate.complete();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        await d.f.actions.settle(t);
        expect(d.player.calls.where((v) => v.$1 == 'subtitle').length, applied);
        expect(d.player.state.track.subtitle.id, '3');
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

  testWidgets(
    'subtitle startup automatic apply superseded by a manual choice returns false to the original restore diagnostic',
    (t) async {
      final gate = Completer<void>();
      var entered = false;
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(
              audio: [mk.AudioTrack('1', 'English', 'eng')],
              subtitle: applyTracks,
            ),
          );
          final n = p.platform as FakeNativePlayer;
          n.beforeOperation = (name, value) async {
            if (!entered &&
                name == 'setProperty' &&
                value == ('sub-visibility', 'no') &&
                StackTrace.current.toString().contains(
                  'setNativeSubtitleVisibilityForTrack',
                )) {
              entered = true;
              await gate.future;
            }
          };
          n.heldOperation = (name, value) =>
              entered &&
              !gate.isCompleted &&
              name == 'setProperty' &&
              value == ('sub-visibility', 'no');
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('fr'),
        );
        await d.mount(
          screen: boundaryScreen,
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(t, () => entered);
        expect(d.player.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
        final panel = await d.menu();
        expect(await d.select('2', panel: panel), isTrue);
        expect(d.player.state.track.subtitle.id, '2');
        final applied = d.player.calls.where((v) => v.$1 == 'subtitle').length;
        expect(gate.isCompleted, isFalse);
        gate.complete();
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        await d.f.actions.settle(t);
        expect(d.player.calls.where((v) => v.$1 == 'subtitle').length, applied);
        expect(d.player.state.track.subtitle.id, '2');
        expect((await d.saved())?['subtitleTrackId'], '2');
        expect(
          d.logs.where(
            (v) =>
                v ==
                'SubAuto: restore done — embeddedSubtitleApplied=false → running addon auto-select',
          ),
          hasLength(1),
        );
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
  testWidgets(
    'subtitle stored preference rejection preserves its restore-specific diagnostic source',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(
              audio: [mk.AudioTrack('1', 'English', 'eng')],
              subtitle: applyTracks,
            ),
          );
          (p.platform as FakeNativePlayer).properties['sid'] = '2';
          p.failures['subtitle'] = StateError('stored apply rejected');
        },
      );
      await d.initialize();
      try {
        await d.f.finish(
          t,
          TrackPreferencesStorage.saveVideoTrackPreferences(
            videoTitle: applyScreen.title,
            audioTrackId: '1',
            subtitleTrackId: '2',
          ),
        );
        await d.mount(publishTracks: false);
        expect(
          d.logs.where(
            (v) => v.startsWith(
              '[SubtitleDiag] set FAILED source=restore-stored-embedded requestedId=2 error=Bad state: stored apply rejected',
            ),
          ),
          hasLength(1),
        );
        expect(
          d.logs.where(
            (v) =>
                v ==
                '[SubtitleDiag] user notified source=restore-stored-embedded reason=Bad state: stored apply rejected',
          ),
          hasLength(1),
        );
        expect((await d.saved())?['subtitleTrackId'], '2');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
