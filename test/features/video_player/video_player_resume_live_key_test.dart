import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/display_mode_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final shape in ['zap to zero', 'borrowed list shrinks']) {
    testWidgets(
      'Resume P14 live key $shape uses the actual channel or safe launch fallback',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final display = DisplayModeDriver(t, f);
        const a = 'https://iptv.test/p14-key-a.ts',
            b = 'https://iptv.test/p14-key-b.ts';
        final channels = [
          IptvChannel(name: 'A', url: a, contentType: 'live', attributes: {}),
          IptvChannel(name: 'B', url: b, contentType: 'live', attributes: {}),
        ];
        final originalChannels = List<IptvChannel>.of(channels);
        final errors = <Object>[];
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        try {
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(a, {'positionMs': 456}),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(b, {'positionMs': 123}),
          );
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: b,
              title: 'P14 live key',
              iptvChannels: channels,
              iptvStartIndex: 1,
            ),
          );
          if (shape == 'zap to zero') {
            await f.key(t, LogicalKeyboardKey.channelDown);
            await f.until(
              t,
              () => f.player.state.playlist.medias.first.uri == a,
            );
            await f.actions.settle(t);
          }
          final menu = await display.menu(PlayerMenuSection.speed);
          if (shape == 'borrowed list shrinks') channels.removeLast();
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          checkpoints = 0;
          runZoned(
            () => menu.onSpeedSelected(1.5),
            zoneSpecification: ZoneSpecification(
              handleUncaughtError: (self, parent, zone, error, stack) =>
                  errors.add(error),
            ),
          );
          await f.until(t, () => errors.isNotEmpty || checkpoints > 0);
          expect(errors, isEmpty);
          expect(checkpoints, 1);
          final current = shape == 'zap to zero' ? a : b;
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(current),
            ))?['positionMs'],
            300000,
          );
          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(current),
            ))?['speed'],
            1.5,
          );
          if (shape == 'zap to zero') {
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(b),
              ))?['positionMs'],
              123,
            );
          } else {
            expect(
              (await f.finish(
                t,
                VideoResumeStorage.getVideoResume(a),
              ))?['positionMs'],
              456,
            );
          }
        } finally {
          channels
            ..clear()
            ..addAll(originalChannels);
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
        }
      },
    );
  }
}
