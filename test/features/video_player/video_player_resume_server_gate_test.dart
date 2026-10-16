import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 ready server playback stays gated while initial resume policy delivery is held',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final server = ResumeServerDriver(t, f);
      final policy = CompletionDelivery(
        'maybeRestoreResume',
        (v) => v is TrackingSourcePolicy,
      );
      try {
        await server.prepare();
        await policy.run(() => f.mount(t, server.screen()));
        await f.until(t, () => policy.pending.isNotEmpty);
        expect(f.player.readyDelivered, isTrue);
        expect(server.reports, isEmpty);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
          playing: true,
        );
        f.player.emit('playing', true);
        f.player.emit('position', f.player.state.position);
        await f.actions.settle(t);
        expect(policy.pending, hasLength(1));
        expect(
          server.reports,
          isEmpty,
          reason:
              'Readiness and an active server target do not bypass the initial validation gate',
        );
        policy.release();
        await f.actions.settle(t);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 6),
        );
        f.player.emit('position', f.player.state.position);
        await f.until(t, () => server.reports.isNotEmpty);
        expect(
          server.body(server.reports.first)['PositionTicks'],
          360000 * 10000,
        );
        await server.disposePlayback();
      } finally {
        policy.release();
        await f.actions.settle(t);
        await f.close(t);
        server.restoreFactories();
      }
    },
  );
}
