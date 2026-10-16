import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  testWidgets(
    'Resume P14 held restore after provider list shrink skips stale series metadata and reads the mirrored title',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final policy = CompletionDelivery(
        'maybeRestoreResume',
        (v) => v is TrackingSourcePolicy,
      )..armed = false;
      final a = source(
        'P14.Bounds.Show.S01E02.mkv',
        'https://player.test/p14-restore-bounds-a2.mp4',
      );
      final b = source(
        'P14.Bounds.Show.S01E02.mkv',
        'https://player.test/p14-restore-bounds-b2.mp4',
      );
      final incoming = [
        const PlaylistEntry(
          url: 'https://player.test/p14-restore-bounds-b1.mp4',
          title: 'P14.Bounds.Show.S01E01.mkv',
        ),
        PlaylistEntry(url: b.directUrl!, title: b.name),
      ];
      final original = List<PlaylistEntry>.of(incoming);
      try {
        await f.finish(
          t,
          VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: 'P14 restore bounds',
            videoUrl: a.directUrl!,
            positionMs: 180000,
            durationMs: 1200000,
            speed: 1.5,
            aspect: 'contain',
          ),
        );
        await policy.run(
          () => f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'P14 restore bounds',
              playlist: [
                const PlaylistEntry(
                  url: 'https://player.test/p14-restore-bounds-a1.mp4',
                  title: 'P14.Bounds.Show.S01E01.mkv',
                ),
                PlaylistEntry(url: a.directUrl!, title: a.name),
              ],
              contentType: 'series',
              startIndex: 1,
              disableAutoResume: true,
              stremioSources: [a, b],
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: (s, {canContinue}) async => incoming,
            ),
          ),
        );
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        final callback = sheet.onSourceSelected as dynamic;
        policy.armed = true;
        final selected = policy.run(
          () => f.actions.start('restore held before list mutation', () async {
            final result = callback(1, url);
            if (result is Future) await result;
          }, held: true),
        );
        await f.until(t, () => policy.pending.isNotEmpty);
        incoming.removeLast();
        policy.release();
        await f.finish(t, selected.future);
        await f.actions.settle(t);
        expect(f.player.state.playlist.medias.first.uri, b.directUrl);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 3),
        ]);
        expect(
          f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
          contains(1.5),
        );
      } finally {
        incoming
          ..clear()
          ..addAll(original);
        policy.release();
        await f.actions.settle(t);
        await f.close(t);
      }
    },
  );
}
