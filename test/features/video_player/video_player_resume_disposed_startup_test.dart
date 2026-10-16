import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/resume_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 direct startup resumed after disposal still registers its original late autosave timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final read = CompletionDelivery(
        'maybeRestoreResume',
        (v) => v is TrackingSourcePolicy,
      );
      final timers = ResumeVerifierDriver(t, f);
      try {
        await timers.observe(
          () => read.run(
            () => f.mount(
              t,
              const VideoPlayerScreen(
                videoUrl: 'https://player.test/p14-disposed-start.mp4',
                title: 'P14 disposed start',
              ),
            ),
          ),
        );
        await f.until(t, () => read.pending.isNotEmpty);
        expect(
          timers.periodic.where((v) => v.$1 == const Duration(seconds: 6)),
          isEmpty,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(read.pending, isNotEmpty);
        read.release();
        for (
          var i = 0;
          i < 20 &&
              !timers.periodic.any((v) => v.$1 == const Duration(seconds: 6));
          i++
        ) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        final leaked = timers.periodic
            .where((v) => v.$1 == const Duration(seconds: 6))
            .toList();
        expect(
          leaked,
          hasLength(1),
          reason:
              'Preserve the original late startup continuation, including its timer registered after dispose already cancelled timers',
        );
        expect(leaked.single.$2.isActive, isTrue);
        expect(f.player.disposed.isCompleted, isTrue);
        // Assert the defect first, then cancel only the exact observed test-clock
        // timer so it cannot leak into another scenario. Production is unchanged.
        leaked.single.$2.cancel();
        // The same late continuation schedules a three-second hide callback;
        // let its original mounted guard run instead of cancelling it.
        await f.advance(t, const Duration(seconds: 3));
        await f.actions.settle(t);
      } finally {
        read.release();
        for (final (duration, timer) in timers.periodic) {
          if (duration == const Duration(seconds: 6)) timer.cancel();
        }
        await f.close(t);
      }
    },
  );
}
