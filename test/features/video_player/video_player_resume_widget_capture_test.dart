import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; app dependencies unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/video_player_environment.dart';
import 'support/physical_resume_store.dart';

void main() {
  for (final incomingCustom in [false, true]) {
    testWidgets(
      'Resume P14 widget update during enhanced write captures legacy identity late custom=$incomingCustom',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final old = SharedPreferencesStorePlatform.instance;
        final display = DisplayModeDriver(t, f);
        final read = CompletionDelivery(
          'saveVideoPlaybackState',
          (v) => v is Map<String, dynamic>,
        );
        read.armed = false;
        var checkpoints = 0;
        void checkpoint() => checkpoints++;
        MainPageBridge.addPlaybackCheckpointListener(checkpoint);
        const a = 'https://player.test/p14-live-a.mp4',
            b = 'https://player.test/p14-live-b.mp4';
        try {
          final scope = ProfileRuntime.capture();
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(a, {
              'positionMs': 111,
            }, sourceId: 'prior-a'),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(b, {
              'positionMs': 222,
            }, sourceId: 'prior-b'),
          );
          await f.mount(
            t,
            const VideoPlayerScreen(
              videoUrl: a,
              title: 'P14 live A',
              contentImdbId: 'tt1418001',
              contentType: 'movie',
              iptvSourceId: 'before-update',
            ),
          );
          final owner = t.state(find.byType(VideoPlayerScreen));
          await f.finish(
            t,
            PhysicalResumeStore.savePlaybackStateMap({
              'keep': {'type': 'video', 'title': 'Unrelated'},
            }),
          );
          final store = (await t.runAsync(CompletionWrites.install))!;
          f.player.state = f.player.state.copyWith(
            position: const Duration(minutes: 5),
          );
          f.player.emit('position', f.player.state.position);
          await f.advance(t);
          final menu = await display.menu(PlayerMenuSection.speed);
          checkpoints = 0;
          read.armed = true;
          read.run(() => menu.onSpeedSelected(1.5));
          await f.until(t, () => read.pending.isNotEmpty);
          expect(checkpoints, 0);
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigator,
              theme: ThemeData.dark(),
              home: VideoPlayerScreen(
                videoUrl: b,
                title: 'P14 live B',
                contentImdbId: incomingCustom
                    ? const CustomSeriesIdentity('p14', 'late').id
                    : 'tt1418002',
                contentType: 'movie',
                iptvSourceId: 'after-update',
              ),
            ),
          );
          expect(t.state(find.byType(VideoPlayerScreen)), same(owner));
          expect(
            f.player.state.playlist.medias.first.uri,
            a,
            reason: 'didUpdateWidget refreshes controls, not media',
          );
          read.release();
          await f.until(t, () => checkpoints == 1);
          final map = decodeCompletionPhysical(
            await store.physical(scope, 'playback_state_v1'),
          );
          expect(map['video_p14_live_a'], containsPair('imdbId', 'tt1418001'));
          expect(map['video_p14_live_a'], containsPair('positionMs', 300000));
          expect(map['video_p14_live_a'], containsPair('url', a));
          expect(map, contains('keep'));
          expect(map, isNot(contains('video_p14_live_b')));
          final ar = await t.runAsync(
            () => completionPhysicalResume(f, scope, a),
          );
          final br = await t.runAsync(
            () => completionPhysicalResume(f, scope, b),
          );
          expect(ar?['position_ms'], 111);
          expect(br?['position_ms'], incomingCustom ? 222 : 300000);
          expect(br?['source_id'], incomingCustom ? 'prior-b' : 'after-update');
        } finally {
          read.release();
          MainPageBridge.removePlaybackCheckpointListener(checkpoint);
          await f.close(t);
          SharedPreferencesStorePlatform.instance = old;
        }
      },
    );
  }
}
