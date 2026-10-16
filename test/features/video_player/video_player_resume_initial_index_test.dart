import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 latest non-series playlist entry is selected using each provider resume id',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      const a = 'https://player.test/p14-latest-a.mp4',
          b = 'https://player.test/p14-latest-b.mp4';
      try {
        for (final (key, url, pos) in [
          ('torbox_web_11_33', a, 60000),
          ('pikpak_p14-latest', b, 180000),
        ]) {
          await f.finish(
            t,
            VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: key,
              videoUrl: url,
              positionMs: pos,
              durationMs: 1200000,
              speed: 1.5,
              aspect: 'contain',
            ),
          );
        }
        final map = await f.finish(t, PlaybackStateStore.getPlaybackStateMap());
        for (final raw in map.values) {
          final row = raw as Map;
          row['updatedAt'] = row['title'] == 'torbox_web_11_33' ? 100 : 200;
        }
        await f.finish(t, PlaybackStateStore.savePlaybackStateMap(map));
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: a,
            title: 'P14 latest collection',
            playlist: [
              PlaylistEntry(
                url: a,
                title: 'First film.mkv',
                provider: 'Torbox',
                torboxWebDownloadId: 11,
                torboxFileId: 33,
              ),
              PlaylistEntry(
                url: b,
                title: 'Latest film.mkv',
                provider: 'Pikpak',
                pikpakFileId: 'p14-latest',
              ),
            ],
          ),
        );
        await f.actions.settle(t);
        expect(f.player.state.playlist.medias.first.uri, b);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 3),
        ]);
        expect(
          f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
          contains(1.5),
        );
      } finally {
        await f.close(t);
      }
    },
  );
}
