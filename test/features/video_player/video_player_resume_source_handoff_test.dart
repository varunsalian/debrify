import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  for (final position in [1, 500, 300000, 1110000]) {
    testWidgets(
      'Resume P14 same-content source switch restores exact $position outside the ordinary window and spends launch promises',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final a = source(
          'P14 switch.mkv',
          'https://player.test/p14-switch-a.mp4',
        );
        final b = source(
          'P14 switch.mkv',
          'https://player.test/p14-switch-b.mp4',
        );
        final verifier = ResumeVerifierDriver(t, f);
        try {
          await verifier.observe(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: a.directUrl!,
                title: a.name,
                playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
                traktProgressPercent: 20,
                simklProgressPercent: 30,
                mdblistProgressPercent: 40,
                stremioSources: [a, b],
                stremioCurrentSourceIndex: 0,
                resolveStremioSource: (s) async => s.directUrl,
                resolveSourceToPlaylist: (s, {canContinue}) async => [
                  PlaylistEntry(url: s.directUrl!, title: s.name),
                ],
              ),
            ),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            contains(const Duration(minutes: 8)),
          );
          await f.advance(t, const Duration(milliseconds: 800));
          await verifier.drain();
          final timerCount = verifier.timers.length;
          final controls = playerControls(t);
          controls.onSeekBarChanged(position / 1200000);
          controls.onSeekBarChangeEnd();
          await f.until(
            t,
            () => f.player.state.position == Duration(milliseconds: position),
          );
          await f.actions.settle(t);
          final seeksBeforeSwitch = f.player.calls
              .where((c) => c.$1 == 'seek')
              .length;
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
          final resolved = (await f.finish(t, sheet.resolveSource(b)))!;
          final callback = sheet.onSourceSelected as dynamic;
          final action = verifier.observe(
            () => f.actions.start('source switch', () async {
              final result = callback(1, resolved);
              if (result is Future) await result;
            }),
          );
          await f.finish(t, action.future);
          await f.until(
            t,
            () =>
                f.player.state.playlist.medias.first.uri == b.directUrl &&
                f.player.state.position == Duration(milliseconds: position),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').last.$2,
            Duration(milliseconds: position),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek'),
            hasLength(seeksBeforeSwitch + 1),
            reason:
                'The local-preferred branch returns after its single carried seek',
          );
          expect(
            verifier.timers.length,
            timerCount,
            reason: 'Mid-session restore keeps verification opt-in false',
          );
          final key = 'P14 switch'.hashCode.toString();
          final state = await f.finish(
            t,
            VideoProgressStorage.getVideoPlaybackState(videoTitle: key),
          );
          expect(state?['positionMs'], position);
          expect(
            state?['url'],
            a.directUrl,
            reason:
                'The checkpoint is outgoing, before replacing the playlist and stream',
          );
        } finally {
          await f.close(t);
          await f.advance(t, const Duration(milliseconds: 800));
          await verifier.drain();
        }
      },
    );
  }
}
