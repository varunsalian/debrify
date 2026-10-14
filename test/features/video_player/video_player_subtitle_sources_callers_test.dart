import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'support/fake_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/player_actions.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_subtitle_apply_boundaries_test.dart' show crossBoundary;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  for (final playlist in [false, true]) {
    for (final rejected in [false, true]) {
      testWidgets(
        'subtitle ${playlist ? 'playlist' : 'direct'} source ${rejected ? 'rollback' : 'commit'} restores its subtitle selection through its retained caller',
        (t) async {
          final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
          await d.initialize();
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
          );
          final original = source(
            'Original.mkv',
            'https://player.test/old-source.mp4',
          );
          final incoming = source(
            'Incoming.mkv',
            'https://player.test/new-source.mp4',
          );
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: original.directUrl!,
                title: applyScreen.title,
                viewMode: PlaylistViewMode.raw,
                stremioSources: [original, incoming],
                stremioCurrentSourceIndex: 0,
                resolveStremioSource: (s) async => s.directUrl,
                resolveSourceToPlaylist: playlist
                    ? (s, {canContinue}) async => [
                        PlaylistEntry(url: s.directUrl!, title: s.name),
                      ]
                    : null,
              ),
              publishTracks: false,
            );
            expect(await d.select('3'), isTrue);
            (await d.menu()).onClose();
            await d.f.advance(t);
            final appliedBefore = d.player.calls
                .where(
                  (c) =>
                      c.$1 == 'subtitle' &&
                      (c.$2 as mk.SubtitleTrack).id == '3',
                )
                .length;
            final restores = d.logs
                .where((s) => s.contains('_restoreTrackPreferences entered'))
                .length;
            d.player.onOpen = () {
              d.player.state = d.player.state.copyWith(
                track: const mk.Track(
                  audio: mk.AudioTrack('1', 'English audio', 'eng'),
                  subtitle: mk.SubtitleTrack('no', null, null),
                ),
              );
              if (rejected &&
                  d.player.state.playlist.medias.single.uri ==
                      incoming.directUrl) {
                d.player.state = d.player.state.copyWith(
                  duration: Duration.zero,
                  videoParams: const mk.VideoParams(),
                  width: 0,
                  height: 0,
                );
                d.player.emit('error', 'Failed to open media: HTTP 404');
              } else {
                d.player.publishFrame();
                d.f.controllers.last.publishFrame();
              }
            };
            playerControls(t).onShowStremioSources!();
            await d.f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final url = await d.f.finish(t, sheet.resolveSource(incoming));
            expect(url, incoming.directUrl);
            final dynamic selected = d.observe<dynamic>(
              () => (sheet.onSourceSelected as dynamic)(1, url!),
            );
            if (selected is Future) {
              await d.f.finish<dynamic>(t, selected);
            }
            await d.f.until(
              t,
              () =>
                  d.logs
                      .where(
                        (s) => s.contains('_restoreTrackPreferences entered'),
                      )
                      .length >
                  restores,
            );
            await d.f.actions.settle(t);
            await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
            expect(
              d.player.state.playlist.medias.single.uri,
              rejected ? original.directUrl : incoming.directUrl,
            );
            expect(d.player.state.track.audio.id, '1');
            expect(
              d.player.calls
                  .where(
                    (c) =>
                        c.$1 == 'subtitle' &&
                        (c.$2 as mk.SubtitleTrack).id == '3',
                  )
                  .length,
              greaterThan(appliedBefore),
            );
            expect(
              d.logs.where(
                (s) => s.contains(
                  playlist
                      ? 'matched EMBEDDED track id=3'
                      : 'applying STORED subtitle track id=3',
                ),
              ),
              isNotEmpty,
            );
            expect(d.errors, isEmpty);
          } finally {
            await removeFixture(d);
          }
        },
      );
    }
  }
  testWidgets(
    'subtitle renderer replacement restores remembered tracks through the retained fallback caller',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await d.mount(publishTracks: false);
        expect(await d.select('3'), isTrue);
        final old = d.player;
        await crossBoundary(d, 'replacement');
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        expect(identical(old, d.player), isFalse);
        expect(old.disposed.isCompleted, isTrue);
        expect(d.player.state.track.audio.id, '1');
        expect((await d.saved())?['subtitleTrackId'], '3');
        expect(d.errors, isEmpty);
      } finally {
        VpS2Hooks.install(null);
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle PikPak initial open restores tracks through its retained continuation',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
      );
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/pikpak.mp4',
            title: 'PikPak original',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/pikpak.mp4',
                title: 'PikPak original',
                provider: 'pikpak',
              ),
            ],
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['3'],
        );
        expect(
          d.logs.any((s) => s.contains('_restoreTrackPreferences entered')),
          isTrue,
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle non-policy stored choice allows fallback on replacement with a missing ordinal',
    (t) async {
      var creations = 0;
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          creations++;
          if (creations == 2) {
            p.state = p.state.copyWith(
              tracks: mk.Tracks(
                audio: p.state.tracks.audio,
                subtitle: p.state.tracks.subtitle
                    .where((s) => s.id != '3')
                    .toList(),
              ),
            );
          }
        },
      );
      await d.initialize();
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: applyScreen.title,
          audioTrackId: '2',
          subtitleTrackId: '3',
        ),
      );
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await d.mount(publishTracks: false);
        expect(d.player.state.track.subtitle.id, '3');
        await crossBoundary(d, 'replacement');
        await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
        expect(
          d.logs,
          contains(
            'SubAuto: stored subtitle id=3 not in this file → default-language path',
          ),
        );
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['2'],
        );
        expect(d.errors, isEmpty);
      } finally {
        VpS2Hooks.install(null);
        await removeFixture(d);
      }
    },
  );
  for (final stored in [false, true]) {
    testWidgets(
      'subtitle forced renderer rejection keeps ${stored ? 'stored auto' : 'no preferences'} restore and replacement ordering',
      (t) async {
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            p.state = p.state.copyWith(
              tracks: const mk.Tracks(
                audio: [mk.AudioTrack('1', 'English', 'eng')],
                subtitle: [
                  mk.SubtitleTrack('auto', null, null),
                  mk.SubtitleTrack('no', null, null),
                  ...applyTracks,
                ],
              ),
            );
            (p.platform as FakeNativePlayer).properties.addAll({
              'track-list/count': '1',
              'track-list/0/type': 'sub',
              'track-list/0/forced': 'yes',
              'track-list/0/external': 'no',
              'track-list/0/lang': 'eng',
              'track-list/0/id': '4',
            });
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleForcedOnly(true),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
        );
        if (stored) {
          await d.f.finish(
            t,
            TrackPreferencesStorage.saveVideoTrackPreferences(
              videoTitle: applyScreen.title,
              audioTrackId: '1',
              subtitleTrackId: 'auto',
            ),
          );
        }
        VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
        await d.f.finish(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        int rejected() => d.logs
            .where(
              (s) => s.startsWith(
                '[SubtitleDiag] apply rejected source=forced-only-embedded',
              ),
            )
            .length;
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          expect(rejected(), 3);
          expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
          await crossBoundary(d, 'replacement');
          await d.f.until(t, () => rejected() > 3);
          await d.f.actions.settle(t);
          // A stored audio ordinal changes the new player's auto placeholder,
          // dispatching one extra forced-policy refresh through stream.track.
          expect(rejected(), stored ? 7 : 6);
          expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          VpS2Hooks.install(null);
          await removeFixture(d);
        }
      },
    );
  }
}
