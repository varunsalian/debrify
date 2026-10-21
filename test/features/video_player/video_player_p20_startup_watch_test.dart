import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

final _wakeDrain = Object();
const _failed = 'No playable source could be started.';

VideoPlayerScreen _slot(StartupDriver d, String name) => VideoPlayerScreen(
  videoUrl: 'https://watch.test/$name.mp4',
  title: 'P20 $name',
  // A random start is not deferred: its seek runs right after readiness.
  startFromRandom: true,
  randomStartMaxPercent: 10,
  stremioTvChannels: const [
    {'id': 'slot', 'name': 'P20 slot'},
  ],
  stremioTvCurrentChannelId: 'slot',
);

Future<void> _drain(WidgetTester t) => t.runAsync(
  () => PlayerDisplayControls.instance.setWakelockOwner(_wakeDrain, false),
);

void main() {
  testWidgets(
    'P20 a Stremio TV watch that fails before readiness stops startup before its resume seek',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: 'P20 watch-fail',
            videoUrl: 'https://watch.test/watch-fail.mp4',
            positionMs: 240000,
            durationMs: 1200000,
          ),
        );
        await d.begin(_slot(d, 'watch-fail'));
        await d.openEntered();
        d.player.emit('error', 'fixture watch failure');
        await d.tick();
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(_failed),
          ),
          findsWidgets,
        );
        // Duration arrives only after the failure; readiness then passes.
        d.frame();
        await d.tick(const Duration(seconds: 1));
        await d.settle();
        expect(d.player.calls.where((c) => c.$1 == 'seek'), isEmpty);
        await d.f.until(t, () => d.routeReturned);
      } finally {
        await d.close();
        await _drain(t);
      }
    },
  );

  testWidgets(
    'P20 a Stremio TV seek that throws after a completed open, while its watch is still pending, is logged without failing the watch',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      try {
        await d.begin(_slot(d, 'late-throw'));
        d.player.failures['seek'] = StateError('seek failed');
        await d.openEntered();
        // Duration without a sized frame: readiness passes, the watch waits.
        d.player.state = d.player.state.copyWith(
          duration: const Duration(minutes: 20),
        );
        d.player.emit('duration', const Duration(minutes: 20));
        await d.settle();
        await d.tick(const Duration(seconds: 1));
        expect(
          d.logs.where(
            (l) => l.startsWith('VideoPlayer: initial open failed:'),
          ),
          hasLength(1),
        );
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(_failed),
          ),
          findsNothing,
        );
        d.frame();
        await d.settle();
      } finally {
        await d.close();
        await _drain(t);
      }
    },
  );
}
