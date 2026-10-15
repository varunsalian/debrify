import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; no dependency changes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final stage in ['admitted database', 'open transaction']) {
    for (final disposed in [false, true]) {
      testWidgets(
        'Resume P14 $stage stays in its admitted profile after B handoff disposed=$disposed',
        (t) async {
          final f = VideoPlayerEnvironment();
          await t.runAsync(f.initialize);
          final display = DisplayModeDriver(t, f);
          final old = SharedPreferencesStorePlatform.instance;
          CompletionWrites? store;
          final read = CompletionDelivery(
            stage == 'admitted database'
                ? 'IptvMediaStore._runScoped'
                : 'upsertVideoResume',
            (v) => stage == 'admitted database' ? v == null : v is List,
          );
          read.armed = false;
          final notifications = <String>[];
          void checkpoint() =>
              notifications.add(ProfileRuntime.capture().profileId);
          MainPageBridge.addPlaybackCheckpointListener(checkpoint);
          const url = 'https://player.test/p14-database.mp4';
          try {
            final a = ProfileRuntime.capture();
            final b = await completionIncomingProfile(t, f);
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'B_unrelated': {'type': 'video', 'title': 'B'},
              }),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(url, {
                'positionMs': 222,
              }, sourceId: 'source-b'),
            );
            await completionActivate(t, f, a);
            await display.defaults();
            await f.mount(
              t,
              const VideoPlayerScreen(videoUrl: url, title: 'P14 database'),
            );
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'A_unrelated': {'type': 'video', 'title': 'A'},
              }),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(url, {
                'positionMs': 111,
              }, sourceId: 'source-a'),
            );
            store = await t.runAsync(CompletionWrites.install);
            f.player.state = f.player.state.copyWith(
              position: const Duration(minutes: 5),
            );
            f.player.emit('position', f.player.state.position);
            await f.advance(t);
            final menu = await display.menu(PlayerMenuSection.speed);
            notifications.clear();
            read.armed = true;
            read.run(() => menu.onSpeedSelected(1.5));
            await f.until(t, () => read.pending.isNotEmpty);
            expect(notifications, isEmpty);
            expect(
              decodeCompletionPhysical(
                await store!.physical(a, 'playback_state_v1'),
              )['video_p14_database'],
              containsPair('positionMs', 300000),
            );
            await completionActivate(t, f, b);
            if (disposed) {
              await t.pumpWidget(const SizedBox.shrink());
              await f.until(t, () => f.player.disposed.isCompleted);
              expect(notifications, isEmpty);
            }
            read.release();
            await f.until(t, () => notifications.isNotEmpty);
            expect(
              notifications.first,
              b.profileId,
              reason:
                  'The existing notification has no captured profile parameter',
            );
            final ar = await t.runAsync(
              () => completionPhysicalResume(f, a, url),
            );
            final br = await t.runAsync(
              () => completionPhysicalResume(f, b, url),
            );
            expect(ar?['position_ms'], 300000);
            expect(ar?['speed'], 1.5);
            expect(ar?['source_id'], 'source-a');
            if (!disposed) {
              expect(br?['position_ms'], 222);
              expect(br?['source_id'], 'source-b');
              expect(
                decodeCompletionPhysical(
                  await store.physical(b, 'playback_state_v1'),
                ).keys,
                ['B_unrelated'],
              );
            } else {
              await f.actions.settle(t);
              // The independently queued exit save resolves the now active B;
              // it does not redirect the already admitted transaction in A.
              final exit = await t.runAsync(
                () => completionPhysicalResume(f, b, url),
              );
              expect(exit?['position_ms'], 300000);
              expect(exit?['source_id'], 'source-b');
            }
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
}
