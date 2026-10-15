import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport, unchanged app dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets('Resume P14 empty IPTV list preserves the single URL key', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    const url = 'https://player.test/p14-empty-iptv.mp4';
    try {
      await f.finish(
        t,
        VideoResumeStorage.upsertVideoResume(url, {
          'positionMs': 180000,
          'speed': 1.0,
          'aspect': 'contain',
        }),
      );
      await f.mount(
        t,
        const VideoPlayerScreen(
          videoUrl: url,
          title: 'P14 empty IPTV',
          iptvChannels: [],
        ),
      );
      expect(
        f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
        contains(const Duration(minutes: 3)),
      );
      playerControls(t).onPlayPause();
      await f.actions.settle(t);
      expect(
        (await f.finish(
          t,
          VideoResumeStorage.getVideoResume(url),
        ))?['positionMs'],
        180000,
      );
    } finally {
      await f.close(t);
    }
  });
  testWidgets(
    'Resume P14 IPTV transition rejects saves and zap keys the live channel with source precedence',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final old = SharedPreferencesStorePlatform.instance;
      final gate = Completer<void>();
      var checkpoints = 0;
      void checkpoint() => checkpoints++;
      MainPageBridge.addPlaybackCheckpointListener(checkpoint);
      const a = 'https://iptv.test/p14-a.ts', b = 'https://iptv.test/p14-b.ts';
      try {
        final scope = ProfileRuntime.capture();
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: a,
            title: 'P14 IPTV',
            iptvSourceId: 'widget-source',
            iptvChannels: [
              IptvChannel(
                name: 'A',
                url: a,
                contentType: 'live',
                attributes: {
                  'series_playlist_id': 'series-a',
                  'source_playlist_id': 'playlist-a',
                },
              ),
              IptvChannel(
                name: 'B',
                url: b,
                contentType: 'live',
                attributes: {'source_playlist_id': 'playlist-b'},
              ),
            ],
          ),
        );
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 5),
        );
        f.player.emit('position', f.player.state.position);
        await f.advance(t);
        checkpoints = 0;
        playerControls(t).onPlayPause();
        await f.until(t, () => checkpoints == 1);
        final ar = await t.runAsync(
          () => completionPhysicalResume(f, scope, a),
        );
        expect(ar?['position_ms'], 300000);
        expect(ar?['source_id'], 'series-a');
        final store = (await t.runAsync(SleepResumeWrites.install))!;
        f.player.delays['open'] = gate;
        await f.key(t, LogicalKeyboardKey.channelUp);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        expect(gate.isCompleted, isFalse);
        await f.player.play();
        await f.advance(t);
        checkpoints = 0;
        playerControls(t).onPlayPause();
        await f.advance(t, const Duration(seconds: 6));
        expect(checkpoints, 0);
        expect(
          store.writes.where((v) => v.$1.endsWith('playback_state_v1')),
          isEmpty,
        );
        gate.complete();
        await f.until(t, () => f.player.state.playlist.medias.first.uri == b);
        await f.actions.settle(t);
        f.player.state = f.player.state.copyWith(
          position: const Duration(minutes: 10),
        );
        f.player.emit('position', f.player.state.position);
        await f.player.play();
        await f.advance(t);
        final started = DateTime.now().millisecondsSinceEpoch;
        playerControls(t).onPlayPause();
        await f.until(t, () => checkpoints == 1);
        final br = await t.runAsync(
          () => completionPhysicalResume(f, scope, b),
        );
        expect(br?['position_ms'], 600000);
        expect(br?['source_id'], 'playlist-b');
        expect(
          br?['updated_at'],
          inInclusiveRange(started, DateTime.now().millisecondsSinceEpoch),
        );
        final unchanged = await t.runAsync(
          () => completionPhysicalResume(f, scope, a),
        );
        expect(unchanged?['position_ms'], 300000);
        expect(unchanged?['source_id'], 'series-a');
      } finally {
        if (!gate.isCompleted) gate.complete();
        MainPageBridge.removePlaybackCheckpointListener(checkpoint);
        await f.close(t);
        SharedPreferencesStorePlatform.instance = old;
      }
    },
  );
  for (final blockAt in ['request', 'admission']) {
    testWidgets(
      'Resume P14 IPTV $blockAt gate cannot revive a blocked queued checkpoint',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final read = CompletionDelivery(
          'saveVideoPlaybackState',
          (v) => v is Map<String, dynamic>,
        );
        read.armed = false;
        final open = Completer<void>();
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        const a = 'https://iptv.test/p14-queue-a.ts',
            b = 'https://iptv.test/p14-queue-b.ts';
        try {
          final scope = ProfileRuntime.capture();
          await read.run(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: a,
                title: 'P14 queued IPTV',
                iptvChannels: [
                  IptvChannel(
                    name: 'A',
                    url: a,
                    contentType: 'live',
                    attributes: {'source_playlist_id': 'source-a'},
                  ),
                  IptvChannel(
                    name: 'B',
                    url: b,
                    contentType: 'live',
                    attributes: {'source_playlist_id': 'source-b'},
                  ),
                ],
              ),
            ),
          );
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          checkpoints = 0;
          read.armed = true;
          read.run(() => playerControls(t).onPlayPause());
          await f.until(t, () => read.pending.isNotEmpty);
          if (blockAt == 'admission') {
            playerControls(t).onPlayPause();
            await f.advance(t);
            playerControls(t).onPlayPause();
            await f.advance(t);
          }
          f.player.delays['open'] = open;
          await f.key(t, LogicalKeyboardKey.channelUp);
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          await f.player.play();
          await f.advance(t);
          playerControls(t).onPlayPause();
          await f.advance(t);
          expect(checkpoints, 0);
          if (blockAt == 'admission') {
            read.release();
            await f.until(t, () => checkpoints == 1);
            await f.actions.settle(t);
            expect(
              checkpoints,
              1,
              reason: 'The queued request is rechecked at lock admission',
            );
            open.complete();
            await f.until(
              t,
              () => f.player.state.playlist.medias.first.uri == b,
            );
          } else {
            open.complete();
            await f.until(
              t,
              () => f.player.state.playlist.medias.first.uri == b,
            );
            await f.actions.settle(t);
            read.release();
            await f.until(t, () => checkpoints == 1);
          }
          await f.actions.settle(t);
          expect(
            checkpoints,
            1,
            reason:
                'A transition-time request must be dropped before acquiring the lock, not revived when it becomes free',
          );
          final ar = await t.runAsync(
            () => completionPhysicalResume(f, scope, a),
          );
          final br = await t.runAsync(
            () => completionPhysicalResume(f, scope, b),
          );
          expect(ar, isNull);
          expect(
            br?['position_ms'],
            300000,
            reason:
                'The admitted A save samples its position early but reads the live B legacy key after enhanced persistence',
          );
          expect(br?['source_id'], 'source-b');
        } finally {
          read.release();
          if (!open.isCompleted) open.complete();
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
        }
      },
    );
  }
}
