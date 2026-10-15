import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved fixture transport; application dependencies are unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final shape in ['raw fallback', 'raw parsed', 'series', 'sample only']) {
    testWidgets(
      'Resume P14 collection save $shape preserves physical mirrors and coordinates',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final previousPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (message, {wrapWidth}) {
          logs.add(message ?? '');
          previousPrint(message, wrapWidth: wrapWidth);
        };
        final parsed = shape == 'series' || shape == 'raw parsed';
        final titles = shape == 'sample only'
            ? ['film.sample.mkv']
            : parsed
            ? ['P14.Mixed.Show.S02E03.mkv', 'P14.Mixed.Show.S02E04.mkv']
            : ['File one', 'File two'];
        final index = shape == 'raw fallback' ? 1 : 0;
        final playlist = [
          for (var i = 0; i < titles.length; i++)
            PlaylistEntry(
              url: 'https://player.test/p14-collection-$i.mp4',
              title: titles[i],
            ),
        ];
        final resumeId = titles[index]
            .replaceFirst(RegExp(r'\.[^.]+$'), '')
            .hashCode
            .toString();
        try {
          final scope = ProfileRuntime.capture();
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: playlist[index].url,
              title: 'P14 collection',
              playlist: playlist,
              startIndex: index,
              disableAutoResume: true,
              viewMode: shape == 'series'
                  ? PlaylistViewMode.series
                  : PlaylistViewMode.raw,
              contentImdbId: 'tt1419001',
            ),
          );
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          playerControls(t).onPlayPause();
          await f.actions.settle(t);
          final raw = (await t.runAsync(
            SharedPreferencesStorePlatform.instance.getAll,
          ))!['flutter.${scope.preferenceKey('playback_state_v1')}'];
          final physical = decodeCompletionPhysical(raw);
          final rows = physical.values.whereType<Map>().toList();
          final series = rows.where((v) => v['type'] == 'series').toList();
          final videos = rows.where((v) => v['type'] == 'video').toList();
          if (shape == 'sample only') {
            expect(series, isEmpty);
            expect(
              logs,
              contains(
                '❌ Collection Save SKIPPED: seriesPlaylist is null or has no title',
              ),
            );
          } else {
            expect(series, hasLength(1));
            final seasons = series.single['seasons'] as Map;
            expect(seasons.keys, [parsed ? '2' : '0']);
            final episodes = seasons.values.single as Map;
            expect(episodes.keys, [parsed ? '3' : '2']);
            final episode = episodes.values.single as Map;
            expect(episode, containsPair('positionMs', 300000));
            expect(episode, containsPair('durationMs', 1200000));
            expect(series.single, containsPair('imdbId', 'tt1419001'));
            expect(episode, containsPair('speed', 1.0));
            if (shape != 'series') {
              expect(
                logs,
                contains(
                  '✅ Collection Save: title="P14 collection" S${parsed ? '02' : '00'}E${parsed ? '03' : '02'} (index=$index) filename="${titles[index]}"',
                ),
              );
            }
          }
          if (shape == 'series') {
            expect(videos, isEmpty);
          } else {
            expect(videos, hasLength(1));
            expect(
              logs,
              contains(
                '💾 Collection Save Check: seriesPlaylist=true, seriesTitle="${shape == 'sample only' ? 'null' : 'P14 collection'}", isSeries=false',
              ),
            );
            expect(videos.single, containsPair('title', resumeId));
            expect(videos.single, containsPair('url', playlist[index].url));
            expect(videos.single, containsPair('positionMs', 300000));
          }
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(resumeId),
            ))?['positionMs'],
            300000,
          );
          final cache = await f.finish(
            t,
            PlaybackStateStore.getPlaybackStateMap(),
          );
          expect(cache, physical);
        } finally {
          debugPrint = previousPrint;
          await f.close(t);
        }
      },
    );
  }
}
