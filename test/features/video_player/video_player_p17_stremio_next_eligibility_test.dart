import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final action in ['manual', 'EOF']) {
    for (final kind in [
      'null',
      'empty',
      'empty id',
      if (action == 'EOF') 'null id',
      if (action == 'EOF') 'missing provider',
    ]) {
      testWidgets(
        'P17 Stremio $action next eligibility $kind preserves its caller fallback',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          var requests = 0;
          var fetches = 0;
          final candidate = episodeSource('Show.S01E02');
          final fetchExpected =
              action == 'manual' && kind == 'empty id' ||
              kind == 'null id' ||
              kind == 'missing provider';
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'Show.S01E01.mkv',
                contentType: 'series',
                contentSeason: 1,
                contentEpisode: 1,
                stremioTvCurrentChannelId: kind == 'null id'
                    ? null
                    : kind == 'empty id'
                    ? ''
                    : 'a',
                stremioTvNextProvider: kind == 'missing provider'
                    ? null
                    : (id) async {
                        requests++;
                        return kind == 'empty' ? {'url': ''} : null;
                      },
                seriesSourceFetcher: SeriesSourceFetcher(
                  season: 1,
                  episode: 1,
                  resolveAdjacentEpisode: (s, e, direction) async =>
                      (season: 1, episode: 2),
                  searchEpisodes: (s, e) async {
                    fetches++;
                    return [candidate];
                  },
                  searchPacks: (s, e) async => [],
                ),
                resolveSourceToPlaylist: (s, {canContinue}) async => [
                  PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
                ],
              ),
            );
            final before = d.player.calls.length;
            if (action == 'manual') {
              final dynamic next = playerControls(t).onNext!;
              await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
            } else {
              d.player.state = d.player.state.copyWith(
                playing: false,
                completed: true,
              );
              d.player.emit('playing', false);
              d.player.emit('completed', true);
              await d.f.until(
                t,
                () => fetchExpected
                    ? d.opens.length == 2
                    : d.logs.contains(
                        'Player: Stremio TV auto-next unavailable; leaving playback ended.',
                      ),
              );
            }
            await d.f.actions.settle(t);
            expect(
              requests,
              ['empty id', 'null id', 'missing provider'].contains(kind)
                  ? 0
                  : 1,
            );
            expect(fetches, fetchExpected ? 1 : 0);
            expect(d.opens, hasLength(fetchExpected ? 2 : 1));
            expect(
              d.opens.last.uri,
              fetchExpected ? candidate.directUrl : 'https://player.test/a.mp4',
            );
            if (!fetchExpected) {
              expect(d.player.state.playing, action == 'manual');
              expect(
                d.player.calls.skip(before).where((c) => c.$1 == 'play'),
                hasLength(action == 'manual' ? 1 : 0),
              );
            }
            expect(find.byType(mkv.Video), findsOneWidget);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }
  }
  testWidgets(
    'P17 Stremio EOF provider delivered after disposal stays silent and opens nothing',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final payload = Completer<Map<String, dynamic>?>();
      var entered = false;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvCurrentChannelId: 'a',
            stremioTvNextProvider: (id) {
              entered = true;
              return payload.future;
            },
          ),
        );
        d.player.state = d.player.state.copyWith(
          playing: false,
          completed: true,
        );
        d.player.emit('playing', false);
        d.player.emit('completed', true);
        await d.f.until(t, () => entered);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        final start = d.logs.length;
        payload.complete({'url': 'https://player.test/b.mp4'});
        await d.f.advance(t);
        await d.f.actions.settle(t);
        expect(d.opens, hasLength(1));
        expect(
          d.logs
              .skip(start)
              .where(
                (line) => line.contains('Stremio TV auto-next unavailable'),
              ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!payload.isCompleted) payload.complete(null);
        await d.close();
      }
    },
  );
}
