import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 latched fetch clears the previous-action curtain while the older resolver stays held',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final resolver = Completer<void>();
      var entered = false;
      var searches = 0;
      final candidate = episodeSource('Show.S01E03');
      Future<dynamic>? older;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E02.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 2,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 2,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 1),
              searchEpisodes: (s, e) async {
                searches++;
                return [candidate];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async {
              entered = true;
              await resolver.future;
              return [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)];
            },
          ),
        );
        final browser = await d.browser();
        older =
            d.observe<dynamic>(() => browser.onEpisodeSelected(1, 3))
                as Future<dynamic>;
        await d.f.until(t, () => entered);
        expect(find.text('Fetching S01E03…'), findsOneWidget);
        expect(
          t
              .widget<SnackBar>(
                find.widgetWithText(SnackBar, 'Fetching S01E03…'),
              )
              .duration,
          const Duration(seconds: 2),
        );
        final dynamic previous = playerControls(t).onPrevious!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => previous()));
        await d.f.advance(t);
        expect(resolver.isCompleted, isFalse);
        expect(searches, 1);
        expect(d.opens, hasLength(1));
        expect(find.byType(mkv.Video), findsOneWidget);
        resolver.complete();
        await d.f.finish(t, older);
        expect(d.player.state.playlist.medias.single.uri, candidate.directUrl);
        expect(d.errors, isEmpty);
      } finally {
        if (!resolver.isCompleted) resolver.complete();
        if (older != null) await d.f.finish(t, older);
        await d.close();
      }
    },
  );
}
