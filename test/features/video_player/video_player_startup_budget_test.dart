import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

void main() {
  // A media-server source asks its server for watch state before the file
  // opens. On a slow or remote server that took most of the 12 s budget, and
  // the player then gave up on episodes an external player plays fine (#103).
  testWidgets('slow setup before the open does not spend the startup budget', (
    t,
  ) async {
    final d = StartupDriver(t, native: true);
    await d.initialize();
    final a = startupSource('slow-setup');
    d.prearm = Completer<void>();
    try {
      await d.begin(d.screen(sources: [a]));
      await d.f.until(t, () => d.prearmEntered);
      // The budget is wall-clock (a Stopwatch), so setup must really outlast
      // it; fake time alone would not show the bug.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 12200)),
      );
      await d.tick(const Duration(seconds: 13));
      expect(d.opens, isEmpty);
      d.prearm!.complete();
      await d.openEntered();

      // The first frame arrives 5 s after the file opened.
      await d.tick(const Duration(seconds: 5));
      expect(d.event('candidate_result'), isEmpty);
      d.player.state = d.player.state.copyWith(
        width: 1280,
        position: const Duration(milliseconds: 1),
      );
      d.player.emit<int?>('width', 1280);
      d.player.emit('position', const Duration(milliseconds: 1));
      await d.committed();
      expect(
        d.event('candidate_result').single,
        contains('ok=true reason=decoded_video'),
      );
      d.frame();
      await d.settle();
    } finally {
      d.frame();
      await d.close();
    }
  });
}
