import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  testWidgets(
    'Resume P14 sample-index source uses the first parsed episode for restore and save as in the original',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final a = source(
        'Launch stream.mkv',
        'https://player.test/p14-fallback-launch.mp4',
      );
      final b = source(
        'Fallback pack',
        'https://player.test/p14-fallback-sample.mp4',
      );
      final incoming = [
        PlaylistEntry(url: b.directUrl!, title: 'sample.mkv'),
        const PlaylistEntry(
          url: 'https://player.test/p14-fallback-e2.mp4',
          title: 'P14.Fallback.Show.S01E02.mkv',
        ),
        const PlaylistEntry(
          url: 'https://player.test/p14-fallback-e3.mp4',
          title: 'P14.Fallback.Show.S01E03.mkv',
        ),
      ];
      try {
        for (final (episode, position) in [(2, 180000), (3, 360000)]) {
          await f.finish(
            t,
            SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: 'P14 Fallback Show',
              season: 1,
              episode: episode,
              positionMs: position,
              durationMs: 1200000,
              speed: 1.5,
              aspect: 'contain',
            ),
          );
        }
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P14 fallback show',
            contentType: 'series',
            viewMode: PlaylistViewMode.series,
            playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveStremioSource: (s) async => s.directUrl,
            resolveSourceToPlaylist: (s, {canContinue}) async => incoming,
          ),
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        final callback = sheet.onSourceSelected as dynamic;
        final selected = f.actions.start(
          'sample-index source selection',
          () async {
            final result = callback(1, url);
            if (result is Future) await result;
          },
        );
        await f.finish(t, selected.future);
        await f.actions.settle(t);
        expect(f.player.state.playlist.medias.first.uri, b.directUrl);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 3),
        ]);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        playerControls(t).onPlayPause();
        await f.actions.settle(t);
        expect(
          (await f.finish(
            t,
            SeriesProgressStorage.getSeriesPlaybackState(
              seriesTitle: 'P14 Fallback Show',
              season: 1,
              episode: 2,
            ),
          ))?['positionMs'],
          300000,
        );
        expect(
          (await f.finish(
            t,
            SeriesProgressStorage.getSeriesPlaybackState(
              seriesTitle: 'P14 Fallback Show',
              season: 1,
              episode: 3,
            ),
          ))?['positionMs'],
          360000,
        );
      } finally {
        await f.close(t);
      }
    },
  );
}
