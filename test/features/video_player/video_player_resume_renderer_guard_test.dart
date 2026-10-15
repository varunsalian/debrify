import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 renderer replacement re-arms a held bookmark on the fresh player without verification',
    (t) async {
      final f = VideoPlayerEnvironment(
        native: true,
        configurePlayer: (p) => p.seekAcknowledgementPosition = Duration.zero,
      );
      final lifecycle = PipLifecycleDriver(t, f);
      await lifecycle.initialize();
      final display = DisplayModeDriver(t, f);
      final verifier = ResumeVerifierDriver(t, f);
      final poll = CompletionDelivery('resumeSeekLanded', (v) => v == null);
      const url = 'https://player.test/p14-renderer-guard.mp4';
      try {
        await f.finish(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await poll.run(
          () => verifier.observe(
            () => lifecycle.mount(
              const VideoPlayerScreen(
                videoUrl: url,
                title: 'P14 renderer guard',
                traktProgressPercent: 25,
              ),
            ),
          ),
        );
        await f.until(t, () => poll.pending.isNotEmpty);
        final old = f.player;
        expect(old.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
        ]);
        expect(old.state.position, Duration.zero);
        final before = verifier.timers.length;
        old.emit('error', 'synthetic MediaCodec video output failure');
        await f.until(t, () => f.players.length == 2);
        final fresh = f.player;
        fresh.deliverReady();
        await f.until(t, () => fresh.calls.any((c) => c.$1 == 'open'));
        await f.until(
          t,
          () =>
              fresh.calls.any((c) => c.$1 == 'seek') &&
              fresh.state.position == Duration.zero,
        );
        await f.advance(t, const Duration(milliseconds: 20));
        expect(old.disposed.isCompleted, isTrue);
        expect(fresh.calls.where((c) => c.$1 == 'seek').map((c) => c.$2), [
          const Duration(minutes: 5),
        ]);
        expect(fresh.state.position, Duration.zero);
        expect(
          verifier.timers.length,
          before,
          reason:
              'Renderer recovery uses the default non-verifying carried seek, while the old verifier aborts on its changed epoch',
        );
        poll.release();
        await verifier.drain();
        await lifecycle.settle();
        final menu = await display.menu(PlayerMenuSection.speed);
        menu.onSpeedSelected(1.5);
        await f.actions.settle(t);
        final saved = await f.finish(t, VideoResumeStorage.getVideoResume(url));
        expect(saved?['positionMs'], 300000);
        expect(saved?['speed'], 1.5);
      } finally {
        poll.release();
        await lifecycle.close();
        await f.advance(t, const Duration(milliseconds: 800));
        await verifier.drain();
      }
    },
  );
}
