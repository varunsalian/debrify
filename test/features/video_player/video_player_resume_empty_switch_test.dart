import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final record in ['absent', 'preferences only', 'at duration']) {
    testWidgets(
      'Resume P14 local preferred switch with $record bookmark never invents a tiny seek',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final a = source(
          'P14 empty A.mkv',
          'https://player.test/p14-empty-a.mp4',
        );
        final b = source(
          'P14 empty B.mkv',
          'https://player.test/p14-empty-b.mp4',
        );
        try {
          if (record != 'absent') {
            final key = 'P14 empty B'.hashCode.toString();
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'video_$key': {
                  'type': 'video',
                  'title': key,
                  if (record == 'at duration') 'positionMs': 1200000,
                  if (record == 'at duration') 'durationMs': 1200000,
                  'speed': 1.5,
                  'aspect': 'contain',
                },
              }),
            );
          }
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: a.name,
              playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
              traktProgressPercent: 20,
              stremioSources: [a, b],
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(url: s.directUrl!, title: s.name),
              ],
            ),
          );
          expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
            const Duration(minutes: 4),
          ]);
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final url = (await f.finish(t, sheet.resolveSource(b)))!;
          final callback = sheet.onSourceSelected as dynamic;
          final selected = f.actions.start('fresh source switch', () async {
            final result = callback(1, url);
            if (result is Future) await result;
          });
          await f.finish(t, selected.future);
          await f.actions.settle(t);
          expect(f.player.state.playlist.medias.first.uri, b.directUrl);
          expect(f.player.state.position, const Duration(milliseconds: 80));
          expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
            const Duration(minutes: 4),
          ]);
          if (record != 'absent') {
            expect(
              f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
              contains(1.5),
            );
          }
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
