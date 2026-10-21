import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/lease_steps.dart';

/// Own file (own isolate): the timeout is a lazily sampled `static final`,
/// read on the first contended claim — which here happens with tvOS set.
void main() {
  testWidgets(
    'P19 tvOS waits 10 s for a held slot before proceeding without it',
    (t) async {
      final d = EngineDriver(t, tvos: true);
      await d.initialize();
      final trailer = await d.f.finish(
        t,
        VideoOutputLease.acquire(debugLabel: 'trailer'),
      );
      try {
        await pumpScreen(d);
        final waited = await elapsedUntil(d, () => d.f.players.isNotEmpty);
        expect(waited, greaterThanOrEqualTo(const Duration(seconds: 10)));
        expect(waited, lessThan(const Duration(milliseconds: 10300)));
        expect(
          d.logs,
          contains(
            'VideoOutputLease: player proceeding without the slot — a '
            'previous video output has not released after 10s.',
          ),
        );
        await finishMount(d);
        trailer.release();
        await d.f.advance(t);
        expect(VideoOutputLease.isHeld, isTrue);
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );
}
