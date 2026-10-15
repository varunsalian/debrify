import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/player_actions.dart';
import 'support/menu_metadata_driver.dart';
import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_sources_driver.dart';

void main() {
  testWidgets(
    'p13 menu factory publishes filtered track options and live selections',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        d.player.publishTracks(
          mk.Tracks(
            audio: [
              mk.AudioTrack.auto(),
              mk.AudioTrack.no(),
              mk.AudioTrack('1', 'English audio', 'eng'),
              mk.AudioTrack('2', 'Spanish audio', 'spa'),
            ],
            subtitle: [
              mk.SubtitleTrack.auto(),
              mk.SubtitleTrack.no(),
              mk.SubtitleTrack('1', 'English captions', 'eng'),
              mk.SubtitleTrack('2', 'Spanish captions', 'spa'),
            ],
          ),
          selected: const mk.Track(
            audio: mk.AudioTrack('2', 'Spanish audio', 'spa'),
            subtitle: mk.SubtitleTrack('1', 'English captions', 'eng'),
          ),
        );
        await d.f.advance(t);
        final panel = await d.menu();
        expect(panel.audioTracks.map((track) => track.id), ['auto', '1', '2']);
        expect(panel.audioTracks.first.label, contains('Auto'));
        expect(panel.audioTracks[1].label, contains('English'));
        expect(panel.embeddedSubtitles.map((track) => track.id), ['1', '2']);
        expect(panel.selectedAudioId, '2');
        expect(panel.selectedSubtitleId, '1');
        expect(panel.audioPassthrough, isNull);
        expect(panel.onAudioPassthroughChanged, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 menu tracks and quick sections preserve parsed series coordinates over launch fallback',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/show.mp4',
            title: 'Show.S03E04.mkv',
            contentType: 'series',
            contentImdbId: 'tt1300001',
            contentSeason: 7,
            contentEpisode: 9,
          ),
        );
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final quick = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(quick.initialSection, PlayerMenuSection.speed);
        expect(quick.contentImdbId, 'tt1300001');
        expect(quick.contentType, 'series');
        expect(quick.contentSeason, 3);
        expect(quick.contentEpisode, 4);
        quick.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final tracks = await d.menu();
        expect(tracks.initialSection, PlayerMenuSection.subtitles);
        expect(tracks.contentImdbId, 'tt1300001');
        expect(tracks.contentType, 'series');
        expect(tracks.contentSeason, 3);
        expect(tracks.contentEpisode, 4);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 quick menu reuses live tracks movie metadata without another fetch',
    (t) async {
      final d = MenuMetadataDriver(t);
      await d.setup();
      try {
        await d.mountMovies();
        d.tracks();
        await d.f.until(t, () => d.pending.length >= 2);
        d.release();
        await d.shown();
        expect(d.panel.contentImdbId, 'tt1300001');
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final searches = d.searches.length;
        playerControls(t).onSpeed();
        await d.shown();
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1300001');
        expect(d.panel.contentType, 'movie');
        expect(d.panel.contentSeason, isNull);
        expect(d.panel.contentEpisode, isNull);
        expect(d.searches, hasLength(searches));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 TV system Back delegates pane navigation then closes through the facade host',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mount();
        await d.menu();
        await d.f.key(t, LogicalKeyboardKey.arrowRight);
        await t.binding.handlePopRoute();
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsOneWidget);
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        await t.binding.handlePopRoute();
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsNothing);
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'p13 TV close restores root focus before the panel-removal frame',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.mount();
        final panel = await d.menu();
        await d.f.key(t, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('tvPlayerRoot'),
        );
        panel.onClose();
        await t.idle();
        expect(
          find.byType(PlayerMenuPanel),
          findsOneWidget,
          reason: 'no removal frame has run',
        );
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvPlayerRoot');
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'p13 quick menu keeps cached addon slots plus launch captions without another fetch',
    (t) async {
      final d = SubtitleSourcesDriver(t);
      await d.setup();
      const launch = StremioSubtitle(
        id: 'launch-caption',
        url: 'https://player.test/launch.srt',
        lang: 'eng',
        source: 'Launch captions',
      );
      try {
        await d.register('p13-quick-cache');
        await d.order();
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/cache.mp4',
            title: 'Quick cache',
            contentImdbId: 'tt1100001',
            contentType: 'movie',
            initialSubtitles: [launch],
          ),
        );
        final tracks = await d.menu();
        expect(
          tracks.cachedAddonSlots?.any((slot) => slot.addonId == 'injected'),
          isTrue,
        );
        final fetched = await d.f.finish(
          t,
          StremioSubtitleService.instance.fetchSubtitleSlots(
            type: 'movie',
            imdbId: 'tt1100001',
          ),
        );
        expect(fetched, hasLength(1));
        tracks.onAddonSlotsFetched!(fetched);
        await d.f.actions.settle(t);
        tracks.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final requests = d.f.network.requests
            .where((r) => r.url.path.startsWith('/subtitles/'))
            .length;
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final quick = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        expect(quick.cachedAddonSlots?.map((slot) => slot.addonId), [
          fetched.single.addonId,
          'injected',
        ]);
        expect(quick.cachedAddonSlots!.last.subtitles.single.id, launch.id);
        expect(
          d.f.network.requests.where(
            (r) => r.url.path.startsWith('/subtitles/'),
          ),
          hasLength(requests),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
