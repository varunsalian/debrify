import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/resume_server_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'Resume P14 server watch ignores position frames before instance readiness',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final server = ResumeServerDriver(t, f);
      try {
        await server.prepare();
        t.view.physicalSize = const Size(1280, 800);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: server.screen(),
          ),
        );
        await f.until(t, () => f.controllers.isNotEmpty);
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
        for (var i = 0; i < 20; i++) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        expect(f.player.readyDelivered, isFalse);
        expect(server.reports, isEmpty);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
          playing: true,
        );
        f.player.emit('playing', true);
        f.player.emit('position', f.player.state.position);
        await f.actions.settle(t);
        expect(
          server.reports,
          isEmpty,
          reason:
              'A prepared server target is not playable progress before the native ready callback',
        );
        f.player.deliverReady();
        await f.advance(t);
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
        if (f.players.isNotEmpty && !f.player.readyDelivered) {
          f.player.deliverReady();
        }
        await f.close(t);
        server.restoreFactories();
      }
    },
  );
}
