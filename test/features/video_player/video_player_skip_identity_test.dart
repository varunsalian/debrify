import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/skip_segment_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_boundaries_test.dart' show skipPlaylist;

void main() {
  testWidgets(
    'skip rejects invalid guide IMDb before using valid trimmed fallback',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(
          t,
          skipScreen(id: null, type: null, playlist: skipPlaylist),
        );
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final guide = t
            .widget<SeriesBrowser>(find.byType(SeriesBrowser))
            .seriesPlaylist;
        guide.imdbId = 'invalid123';
        await d.tick();
        expect(d.requests, isEmpty);
        guide.imdbId = '  tt7654321  ';
        await t.tapAt(const Offset(10, 10));
        await f.advance(t, const Duration(milliseconds: 400));
        await d.tick();
        expect(d.requests, hasLength(1));
        d.expectQuery(id: 'tt7654321', season: 1, episode: 1);
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip custom launch identity prevents request even when guide later has IMDb',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(
          t,
          skipScreen(
            id: const CustomSeriesIdentity('fixture', 'local').id,
            playlist: skipPlaylist,
          ),
        );
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        t
                .widget<SeriesBrowser>(find.byType(SeriesBrowser))
                .seriesPlaylist
                .imdbId =
            'tt7654321';
        await t.tapAt(const Offset(10, 10));
        await f.advance(t, const Duration(milliseconds: 400));
        await d.tick();
        expect(d.requests, isEmpty);
        d.expectButton(false);
      } finally {
        await f.close(t);
      }
    },
  );

  for (final partial in [false, true]) {
    testWidgets(
      'skip channel effective identity ${partial ? 'fills only missing parsed episode' : 'wins over launch and parsed metadata'}',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = SkipSegmentDriver(t, f);
        try {
          await d.configure(hold: true);
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: 'https://player.test/skip.mp4',
              title: 'Launch.S09E08.mkv',
              contentImdbId: 'tt4100000',
              contentType: 'series',
              stremioTvChannels: const [
                {'id': 'a', 'name': 'A'},
                {'id': 'b', 'name': 'B'},
              ],
              stremioTvCurrentChannelId: 'a',
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          d.expectQuery(season: 9, episode: 8);
          playerControls(t).onShowGuide!();
          await f.until(
            t,
            () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
          );
          t
              .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
              .onChannelSwitched(
                'b',
                'https://player.test/channel-b.mp4',
                'Incoming.S05E06.mkv',
                contentImdbId: 'tt7654321',
                contentType: 'series',
                contentSeason: 4,
                contentEpisode: partial ? null : 7,
              );
          for (var frame = 0; frame < 20; frame++) {
            await f.advance(t, const Duration(milliseconds: 100));
            await d.tick();
          }
          expect(d.requests, hasLength(2));
          // The parser fallback uses the original launch title, not dynamic title.
          d.expectQuery(
            id: 'tt7654321',
            season: 4,
            episode: partial ? 8 : 7,
            index: 1,
          );
          await d.release(1);
          d.expectButton(true);
          await d.release(0);
          d.expectButton(true);
        } finally {
          d.releaseAll();
          await f.close(t);
        }
      },
    );
  }
  for (final field in ['IMDb', 'season', 'episode']) {
    testWidgets('skip cache key independently partitions channel $field', (
      t,
    ) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: 'https://player.test/skip.mp4',
            title: 'Identity keys',
            contentImdbId: 'tt4100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioTvChannels: const [
              {'id': 'a', 'name': 'A'},
              {'id': 'b', 'name': 'B'},
            ],
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        await d.tick();
        d.expectButton(true);
        playerControls(t).onShowGuide!();
        await f.until(
          t,
          () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
        );
        final change = t
            .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
            .onChannelSwitched;
        change(
          'b',
          'https://player.test/b.mp4',
          'B',
          contentImdbId: field == 'IMDb' ? 'tt7654321' : 'tt4100000',
          contentType: 'series',
          contentSeason: field == 'season' ? 4 : 2,
          contentEpisode: field == 'episode' ? 7 : 3,
        );
        for (var frame = 0; frame < 20; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
        }
        expect(d.requests, hasLength(2));
        d.expectQuery(
          id: field == 'IMDb' ? 'tt7654321' : 'tt4100000',
          season: field == 'season' ? 4 : 2,
          episode: field == 'episode' ? 7 : 3,
          index: 1,
        );
        change(
          'a',
          'https://player.test/skip.mp4',
          'A',
          contentImdbId: 'tt4100000',
          contentType: 'series',
          contentSeason: 2,
          contentEpisode: 3,
        );
        for (var frame = 0; frame < 20; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
        }
        expect(d.requests, hasLength(2));
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    });
  }
}
