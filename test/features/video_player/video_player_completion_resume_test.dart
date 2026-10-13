import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final finished in [false, true]) {
    testWidgets(
      'Completion local movie identity gates legacy resume and speed restoration finished=$finished',
      (t) async {
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) => p.framePosition = Duration.zero,
        );
        final d = LocalCompletionDriver(t, f);
        await d.initialize();
        final thresholds = CompletionDelivery(
          'loadLocalCompletionThresholds',
          (v) => v is List<int> && v.length == 2,
        );
        final status = CompletionDelivery(
          'maybeRestoreResume',
          (v) => v is bool,
        );
        try {
          final screen = completionScreen();
          final prefs = await f.finish(t, ProfilePreferences.instance());
          await f.finish(
            t,
            prefs.setStringList(
              'finished_movies_v1',
              finished ? ['tt7100000'] : [],
            ),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(screen.videoUrl, {
              'positionMs': 150000,
              'durationMs': 1200000,
              'speed': 1.5,
              'aspect': 'cover',
            }),
          );
          await d.observe(
            () => thresholds.run(() => status.run(() => f.mount(t, screen))),
          );
          await d.position(1000);
          await f.until(
            t,
            () => status.pending.isNotEmpty,
            reason:
                'Original local-finished read must complete before applying saved progress',
          );
          expect(status.values.single, finished);
          expect(d.seeks, isEmpty);
          status.release();
          await d.drain();
          expect(
            d.seeks,
            finished ? isEmpty : contains(const Duration(milliseconds: 150000)),
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
            finished ? isEmpty : contains(1.5),
          );
          expect(playerControls(t).speed, finished ? 1.0 : 1.5);
        } finally {
          status.release();
          thresholds.release();
          await d.close();
        }
      },
    );
  }
}
