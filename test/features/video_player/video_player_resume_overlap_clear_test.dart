import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  testWidgets(
    'Resume P14 old near-finished restore clears the newer same-State held target',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
      );
      await t.runAsync(f.initialize);
      final read = CompletionDelivery(
        'maybeRestoreResume',
        (v) => v is Map<String, dynamic> && v.containsKey('positionMs'),
      );
      final display = DisplayModeDriver(t, f);
      final a = source(
        'P14 clear A.mkv',
        'https://player.test/p14-clear-a.mp4',
      );
      final b = source(
        'P14 clear B.mkv',
        'https://player.test/p14-clear-b.mp4',
      );
      try {
        for (final (id, position) in [
          ('pikpak_clear-a', 120000),
          ('pikpak_clear-b', 300000),
        ]) {
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(id, {
              'positionMs': position,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
        }
        await read.run(
          () => f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: a.name,
              playlist: [
                PlaylistEntry(
                  url: a.directUrl!,
                  title: a.name,
                  provider: 'pikpak',
                  pikpakFileId: 'clear-a',
                ),
              ],
              traktProgressPercent: 80,
              stremioSources: [a, b],
              stremioCurrentSourceIndex: 0,
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: (s, {canContinue}) async => [
                PlaylistEntry(
                  url: s.directUrl!,
                  title: s.name,
                  provider: 'pikpak',
                  pikpakFileId: 'clear-b',
                ),
              ],
            ),
          ),
        );
        await f.until(t, () => read.pending.isNotEmpty);
        expect(f.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        final callback = sheet.onSourceSelected as dynamic;
        final selected = f.actions.start('newer held-target restore', () async {
          final result = callback(1, url);
          if (result is Future) await result;
        });
        await f.finish(t, selected.future);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
        ]);
        expect(f.player.state.position, Duration.zero);
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume('pikpak_clear-a'),
          ))?['positionMs'],
          80,
          reason:
              'The source replacement checkpoints outgoing A before installing B',
        );
        read.release();
        await f.actions.settle(t);
        expect(f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
          const Duration(minutes: 16),
        ]);
        expect(f.player.state.playlist.medias.first.uri, b.directUrl);
        final menu = await display.menu(PlayerMenuSection.speed);
        menu.onSpeedSelected(1.5);
        await f.actions.settle(t);
        final saved = await f.finish(
          t,
          VideoResumeStorage.getVideoResume('pikpak_clear-b'),
        );
        expect(
          saved?['positionMs'],
          0,
          reason:
              'The late 80% seek clears B\'s earlier 5-minute guard instead of inheriting it',
        );
        expect(saved?['speed'], 1.5);
      } finally {
        read.release();
        await f.actions.settle(t);
        await f.close(t);
      }
    },
  );
}
