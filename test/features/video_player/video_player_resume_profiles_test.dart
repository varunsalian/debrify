import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved test transport; application dependencies remain unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_mode_driver.dart';
import 'support/local_completion_driver.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final stage in ['map delivery', 'physical write']) {
    for (final crossing in [
      'A to B',
      'A to B to A',
      'dispose in B',
      'delete A in B',
    ]) {
      testWidgets(
        'Resume P14 $stage crosses $crossing with physical profile maps and rows',
        (t) async {
          final f = VideoPlayerEnvironment();
          await t.runAsync(f.initialize);
          final display = DisplayModeDriver(t, f);
          final oldStore = SharedPreferencesStorePlatform.instance;
          const url = 'https://player.test/p14-profile.mp4';
          final read = CompletionDelivery(
            'saveVideoPlaybackState',
            (v) => v is Map<String, dynamic>,
          );
          read.armed = false;
          SleepResumeWrites? physical;
          var checkpoints = 0;
          void checkpoint() => checkpoints++;
          MainPageBridge.addPlaybackCheckpointListener(checkpoint);
          try {
            final a = ProfileRuntime.capture();
            final b = await completionIncomingProfile(t, f);
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'B_unrelated': {
                  'type': 'video',
                  'title': 'B only',
                  'positionMs': 222,
                },
              }),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(url, {'positionMs': 222}),
            );
            await completionActivate(t, f, a);
            await display.defaults();
            await f.mount(
              t,
              const VideoPlayerScreen(
                videoUrl: url,
                title: 'P14 profile target',
              ),
            );
            await f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'A_unrelated': {
                  'type': 'video',
                  'title': 'A only',
                  'positionMs': 111,
                },
              }),
            );
            await f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(url, {'positionMs': 111}),
            );
            final inspect = (await t.runAsync(CompletionWrites.install))!;
            f.player.state = f.player.state.copyWith(
              position: const Duration(minutes: 5),
            );
            f.player.emit('position', f.player.state.position);
            await f.advance(t);
            final menu = await display.menu(PlayerMenuSection.speed);
            checkpoints = 0;
            if (stage == 'map delivery') {
              read.armed = true;
              read.run(() => menu.onSpeedSelected(1.5));
              await f.until(t, () => read.pending.isNotEmpty);
              expect((read.values.single as Map).keys, ['A_unrelated']);
            } else {
              physical = await t.runAsync(SleepResumeWrites.install);
              physical!.barrier = Completer<void>();
              menu.onSpeedSelected(1.5);
              await f.until(t, () => physical!.entered);
            }
            expect(
              checkpoints,
              0,
              reason: 'Notification is after the awaited persistence',
            );
            expect(
              decodeCompletionPhysical(
                await inspect.physical(b, 'playback_state_v1'),
              ).keys,
              ['B_unrelated'],
            );
            await completionActivate(t, f, b);
            if (crossing == 'A to B to A') await completionActivate(t, f, a);
            if (crossing == 'delete A in B') {
              final actor = await f.finish(
                t,
                ProfileAuthorizationContext.capture(f.registry!),
              );
              await f.finish(
                t,
                f.registry!.deleteProfileWithDisposition(
                  id: a.profileId,
                  deleteOwnedResources: true,
                  detachPublicArtifacts: true,
                  actingProfileId: actor.profileId,
                  actingAuthorizationRevision: actor.authorizationRevision,
                  actingSessionEpoch: actor.sessionEpoch,
                ),
              );
              expect(
                await f.finish(t, f.registry!.getProfile(a.profileId)),
                isNull,
              );
            }
            if (crossing == 'dispose in B') {
              await t.pumpWidget(const SizedBox.shrink());
              await f.until(t, () => f.player.disposed.isCompleted);
              expect(checkpoints, 0);
            }
            read.release();
            physical?.release();
            await f.until(t, () => checkpoints > 0);
            await f.actions.settle(t);
            final store = SharedPreferencesStorePlatform.instance;
            final raw = await t.runAsync(store.getAll);
            Map<String, dynamic> map(scope) => decodeCompletionPhysical(
              raw!['flutter.${scope.preferenceKey('playback_state_v1')}'],
            );
            final aMap = map(a), bMap = map(b);
            final nativeOwnerIsA =
                stage == 'physical write' || crossing == 'A to B to A';
            final saved = nativeOwnerIsA ? aMap : bMap;
            expect(
              saved['video_p14_profile_target'],
              containsPair('positionMs', 300000),
            );
            expect(
              saved['video_p14_profile_target'],
              containsPair('durationMs', 1200000),
            );
            expect(
              saved['video_p14_profile_target'],
              containsPair('speed', 1.5),
            );
            expect(
              saved['video_p14_profile_target'],
              containsPair('aspect', 'contain'),
            );
            expect(aMap, contains('A_unrelated'));
            if (stage == 'map delivery' && crossing != 'A to B to A') {
              expect(bMap, contains('A_unrelated'));
              expect(
                bMap,
                isNot(contains('B_unrelated')),
                reason:
                    'Original late save overwrites B with the map read from A',
              );
            } else {
              expect(bMap, contains('B_unrelated'));
            }
            final dbOwnerIsA = crossing == 'A to B to A';
            final ar = await t.runAsync(
              () => completionPhysicalResume(f, a, url),
            );
            final br = await t.runAsync(
              () => completionPhysicalResume(f, b, url),
            );
            expect(ar?['position_ms'], dbOwnerIsA ? 300000 : 111);
            expect(br?['position_ms'], dbOwnerIsA ? 222 : 300000);
          } finally {
            read.release();
            physical?.release();
            MainPageBridge.removePlaybackCheckpointListener(checkpoint);
            await f.close(t);
            SharedPreferencesStorePlatform.instance = oldStore;
          }
        },
      );
    }
  }
}
