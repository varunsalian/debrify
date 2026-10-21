import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  testWidgets(
    'Resume P14 late initial restore clears a newer guard before awaiting policy',
    (t) async {
      final f = VideoPlayerEnvironment(
        configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
      );
      await t.runAsync(f.initialize);
      final initial = CompletionDelivery(
        'initializePlayer',
        (v) =>
            v == null &&
            f.players.isNotEmpty &&
            f.player.calls.any((c) => c.$1 == 'open'),
      );
      final policy = CompletionDelivery(
        'maybeRestoreResume',
        (v) => v is TrackingSourcePolicy,
      );
      policy.armed = false;
      final display = DisplayModeDriver(t, f);
      final a = source('P14 late A.mkv', 'https://player.test/p14-late-a.mp4');
      final b = source('P14 late B.mkv', 'https://player.test/p14-late-b.mp4');
      final key = 'P14 late B'.hashCode.toString();
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      try {
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(key, {
            'positionMs': 300000,
            'speed': 1.0,
            'aspect': 'contain',
          }),
        );
        await initial.run(
          () => policy.run(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: a.directUrl!,
                title: a.name,
                playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
                stremioSources: [a, b],
                stremioCurrentSourceIndex: 0,
                resolveStremioSource: (s) async => s.directUrl,
                resolveSourceToPlaylist: (s, {canContinue}) async => [
                  PlaylistEntry(url: s.directUrl!, title: s.name),
                ],
              ),
            ),
          ),
        );
        await f.until(t, () => initial.pending.isNotEmpty);
        expect(
          initial.values,
          [isNull],
          reason: 'The startup continuation await is intercepted exactly once',
        );
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        final callback = sheet.onSourceSelected as dynamic;
        final switchTask = f.actions.start('newer source', () async {
          final value = callback(1, url);
          if (value is Future) await value;
        });
        await f.finish(t, switchTask.future);
        await f.until(
          t,
          () => f.player.calls.any(
            (c) => c.$1 == 'seek' && c.$2 == const Duration(minutes: 5),
          ),
        );
        expect(f.player.state.position, Duration.zero);
        policy.armed = true;
        initial.release();
        await f.until(t, () => policy.pending.isNotEmpty);
        checkpoints = 0;
        final menu = await display.menu(PlayerMenuSection.speed);
        menu.onSpeedSelected(1.5);
        await f.until(t, () => checkpoints == 1);
        expect(
          (await f.finish(
            t,
            VideoResumeStorage.getVideoResume(key),
          ))?['positionMs'],
          0,
          reason:
              'The older restore enters after B armed a target; its initial clear executes before the policy await',
        );
        policy.release();
        await f.actions.settle(t);
        expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
      } finally {
        initial.release();
        policy.release();
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.actions.settle(t);
        await f.close(t);
      }
    },
  );
}
