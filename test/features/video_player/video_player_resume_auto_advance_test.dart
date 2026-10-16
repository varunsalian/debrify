import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 EOF advance skips saved B then clears its latch before a manual saved A restore',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      try {
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/p14-auto-a.mp4',
            title: 'P14 Auto Show',
            contentType: 'series',
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/p14-auto-a.mp4',
                title: 'P14.Auto.Show.S01E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/p14-auto-b.mp4',
                title: 'P14.Auto.Show.S01E02.mkv',
              ),
            ],
          ),
        );
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        final title = browser.seriesPlaylist.seriesTitle!;
        f.navigator.currentState!.pop();
        await f.advance(t);
        await f.finish(
          t,
          SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: title,
            imdbId: browser.seriesPlaylist.imdbId,
            season: 1,
            episode: 2,
            positionMs: 240000,
            durationMs: 1200000,
          ),
        );
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 20),
          completed: true,
        );
        f.player.emit('position', f.player.state.position);
        f.player.emit('completed', true);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await f.actions.settle(t);
        expect(
          f.player.state.playlist.medias.first.uri,
          'https://player.test/p14-auto-b.mp4',
        );
        expect(f.player.state.position, const Duration(milliseconds: 80));
        expect(
          f.player.calls.where((c) => c.$1 == 'seek'),
          isEmpty,
          reason: 'Automatic advance ignores the saved target',
        );
        await f.finish(
          t,
          SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: title,
            imdbId: browser.seriesPlaylist.imdbId,
            season: 1,
            episode: 1,
            positionMs: 180000,
            durationMs: 1200000,
          ),
        );
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final current = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        final task = f.actions.start(
          'manual saved return',
          () => current.onEpisodeSelected(1, 1),
        );
        await f.finish(t, task.future);
        expect(
          f.player.state.playlist.medias.first.uri,
          'https://player.test/p14-auto-a.mp4',
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 3),
        ]);
      } finally {
        await f.close(t);
      }
    },
  );
}
