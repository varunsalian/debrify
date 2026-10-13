import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pip_lifecycle_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

void main() {
  testWidgets(
    'PiP background cancels an active live recovery and clears its reconnect pill before resuming',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final gate = Completer<void>();
      final live = IptvChannel(
        name: 'Recovery live',
        url: 'https://recovery-live.test/live/321.ts',
        contentType: 'live',
      );
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
          ),
        );
        f.player.delays['open'] = gate;
        f.player.emit('error', 'synthetic stream failure');
        await d.settle();
        await f.until(t, () => d.operations('open').length == 2);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)),
        );
        await f.advance(t, const Duration(seconds: 20));
        await d.settle();
        expect(find.text('Reconnecting…'), findsOneWidget);
        final active = d.timed
            .where(
              (v) =>
                  v.$1 == const Duration(seconds: 20) ||
                  v.$1 == const Duration(seconds: 1),
            )
            .map((v) => v.$2)
            .where((v) => v.isActive)
            .toList();
        expect(active, isNotEmpty);
        expect(gate.isCompleted, isFalse);
        await background(d);
        expect(active.every((v) => !v.isActive), isTrue);
        await foreground(d);
        await d.settle();
        expect(find.text('Reconnecting…'), findsNothing);
        gate.complete();
        f.player.delays.remove('open');
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (f.players.isNotEmpty) f.player.delays.remove('open');
        await d.close();
      }
    },
  );
}
