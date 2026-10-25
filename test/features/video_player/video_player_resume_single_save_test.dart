import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'support/physical_resume_store.dart';

void main() {
  for (final shape in [
    'complete series',
    'season only',
    'episode only',
    'movie',
  ]) {
    testWidgets(
      'Resume P14 single save $shape preserves its physical row kind and coordinates',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        const url = 'https://player.test/p14-single-save.mp4';
        try {
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: url,
              title: 'Launch label',
              contentTitle: 'Content show',
              contentType: shape == 'movie' ? 'movie' : 'series',
              contentSeason: shape == 'episode only' ? null : 2,
              contentEpisode: shape == 'season only' ? null : 3,
            ),
          );
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          playerControls(t).onPlayPause();
          await f.actions.settle(t);
          final map = await f.finish(
            t,
            PhysicalResumeStore.getPlaybackStateMap(),
          );
          final rows = map.values.whereType<Map>().toList();
          expect(rows, hasLength(1));
          if (shape == 'complete series') {
            expect(rows.single['type'], 'series');
            expect(rows.single['title'], 'Content show');
            final seasons = rows.single['seasons'] as Map;
            expect(seasons.keys, ['2']);
            final episodes = seasons['2'] as Map;
            expect(episodes.keys, ['3']);
            expect(episodes['3'], containsPair('positionMs', 300000));
            expect(episodes['3'], containsPair('durationMs', 1200000));
          } else {
            expect(rows.single['type'], 'video');
            expect(rows.single['title'], 'Launch label');
            expect(rows.single['url'], url);
            expect(rows.single['positionMs'], 300000);
          }
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(url),
            ))?['positionMs'],
            300000,
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
