import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/video_player_environment.dart';
import 'support/physical_resume_store.dart';

void main() {
  testWidgets(
    'Resume P14 early keyboard aspect action with known duration cannot save before instance readiness',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final display = DisplayModeDriver(t, f);
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      const url = 'https://player.test/p14-not-ready.mp4';
      try {
        await display.defaults();
        t.view.physicalSize = const Size(1280, 800);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: const VideoPlayerScreen(
              videoUrl: url,
              title: 'P14 not ready',
            ),
          ),
        );
        await f.until(t, () => f.controllers.isNotEmpty);
        await f.until(t, () => f.player.calls.any((c) => c.$1 == 'open'));
        for (var i = 0; i < 20; i++) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        expect(f.player.readyDelivered, isFalse);
        expect(f.player.state.duration, const Duration(minutes: 20));
        await t.sendKeyEvent(LogicalKeyboardKey.keyA);
        await f.actions.settle(t);
        expect(find.text('Cover'), findsOneWidget);
        expect(checkpoints, 0);
        expect(
          await f.finish(t, VideoResumeStorage.getVideoResume(url)),
          isNull,
        );
        expect(
          (await f.finish(
            t,
            PhysicalResumeStore.getPlaybackStateMap(),
          ))['video_p14_not_ready'],
          isNull,
        );
        f.player.deliverReady();
        await f.advance(t);
      } finally {
        if (f.players.isNotEmpty && !f.player.readyDelivered) {
          f.player.deliverReady();
        }
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
      }
    },
  );
}
