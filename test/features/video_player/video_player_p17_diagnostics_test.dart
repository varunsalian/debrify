import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'by id', 'Stremio guide', 'Stremio next']) {
    for (final boundary in ['provider', 'open']) {
      if (route == 'Stremio guide' && boundary == 'provider') continue;
      testWidgets(
        'P17 $route $boundary failure preserves the original diagnostic context',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          // Deliberately synthetic: this observes the legacy exception spelling.
          const detail =
              'p17 fixture https://player.test/failure?token=synthetic';
          Future<Map<String, dynamic>?> provider() async {
            if (boundary == 'provider') throw StateError(detail);
            return {
              'url': 'https://player.test/b.mp4',
              'title': 'B',
              'channelId': 'b',
            };
          }

          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'A',
                channelDirectory: route == 'by id' ? tvDirectory : null,
                requestChannelById: route == 'by id'
                    ? (id) => provider()
                    : null,
                requestNextChannel: route == 'next' ? provider : null,
                stremioTvChannels: route == 'Stremio guide'
                    ? tvDirectory
                    : null,
                stremioTvChannelSwitchProvider: route == 'Stremio guide'
                    ? (id) async => null
                    : null,
                stremioTvCurrentChannelId: route.startsWith('Stremio')
                    ? 'a'
                    : null,
                stremioTvNextProvider: route == 'Stremio next'
                    ? (id) => provider()
                    : null,
              ),
            );
            if (boundary == 'open')
              d.player.failures['open'] = StateError(detail);
            if (route == 'next') {
              await d.nextChannel();
            } else if (route == 'by id') {
              final guide = await d.debrifyGuide();
              await d.byId(guide, guide.channels.last);
            } else if (route == 'Stremio guide') {
              final guide = await d.stremioGuide();
              await d.stremioPick(guide, 'b');
            } else {
              final dynamic action = playerControls(t).onNext!;
              await d.f.finish<dynamic>(t, d.observe<dynamic>(() => action()));
            }
            final prefix = switch ((route, boundary)) {
              ('next', 'provider') => 'Player: Next channel request failed',
              ('next', _) => 'Player: Failed to open next channel stream',
              ('by id', 'provider') => 'Player: Channel switch by ID failed',
              ('by id', _) => 'Player: Failed to open channel stream',
              ('Stremio next', 'provider') => 'Player: Stremio TV next failed',
              _ => 'Player: Stremio TV channel switch failed',
            };
            expect(d.logs, contains('$prefix: Bad state: $detail'));
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
  for (final outcome in ['no_playlist', 'committed']) {
    testWidgets(
      'P17 candidate $outcome diagnostics carry the selected index and target coordinates',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final candidate = episodeSource('Show.S02E03');
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S02E02.mkv',
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 2,
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 2,
                episode: 2,
                searchEpisodes: (s, e) async => [candidate],
                searchPacks: (s, e) async => [],
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async =>
                  outcome == 'no_playlist'
                  ? null
                  : [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)],
            ),
          );
          final browser = await d.browser();
          await d.f.finish<dynamic>(
            t,
            d.observe<dynamic>(() => browser.onEpisodeSelected(2, 3)),
          );
          final traces = d.logs
              .where(
                (v) =>
                    v.startsWith('SourceSelect: event=next_episode_candidate'),
              )
              .toList();
          expect(traces, hasLength(2));
          expect(
            traces.first,
            contains('event=next_episode_candidate sourceId='),
          );
          expect(
            traces.last,
            contains(
              'event=next_episode_candidate_${outcome == 'no_playlist' ? 'rejected' : 'outcome'} sourceId=',
            ),
          );
          expect(traces.last, contains('reason=$outcome player=mpv'));
          for (final trace in traces) {
            expect(
              trace,
              contains(
                'index=0 previous=null season=2 episode=3 transport=directUrl',
              ),
            );
            expect(trace, endsWith('player=mpv'));
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
