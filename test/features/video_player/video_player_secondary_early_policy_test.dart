import 'dart:async';

import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies remain frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/display_defaults_reads.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'Secondary early policy await follows incoming profile credentials for the still-mounted outgoing route',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final original = ProfileRuntime.capture();
      final outgoing = await t.runAsync(
        () => f.registry!.getProfile(original.profileId),
      );
      final oldStore = SharedPreferencesStorePlatform.instance;
      DisplayDefaultsReads? reads;
      try {
        await incomingProfile(t, f);
        final next = ProfileRuntime.capture();
        final incoming = await t.runAsync(
          () => f.registry!.getProfile(next.profileId),
        );
        await t.runAsync(() async {
          await SimklStorage.setSimklAccessToken(
            'vplayer-synthetic-incoming-simkl',
          );
          await MdblistStorage.saveMdblistApiKey(
            'vplayer-synthetic-incoming-mdblist',
          );
          await TrackingSourceStorage.setTrackingScrobbleTargets({
            TrackingSource.simkl,
            TrackingSource.mdblist,
          });
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.smart,
          );
          await f.registry!.setActiveProfile(original.profileId);
        });
        ProfileRuntime.publish(
          ProfileScope(
            profileId: original.profileId,
            dataGeneration: 1,
            sessionEpoch: ProfileRuntime.nextEpoch,
          ),
        );
        ProfilePolicyGuard.updateActiveProfile(outgoing);
        reads = await t.runAsync(DisplayDefaultsReads.install);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: secondaryScreen(),
          ),
        );
        await f.until(t, () => reads!.entered);
        expect(f.players, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.forTracker('mdblist'), isEmpty);
        await t.runAsync(() => f.registry!.setActiveProfile(next.profileId));
        ProfileRuntime.publish(
          ProfileScope(
            profileId: next.profileId,
            dataGeneration: 1,
            sessionEpoch: ProfileRuntime.nextEpoch,
          ),
        );
        ProfilePolicyGuard.updateActiveProfile(incoming);
        d.cipher.hold = true;
        reads!.unblock();
        await f.mount(t, secondaryScreen());
        d.cipher.releaseAll();
        await d.drain();
        await d.waitCheckpoint('mdblist', 1);
        d.expectCheckpoint(
          'mdblist',
          0,
          'pause',
          0.01,
          apiKey: 'vplayer-synthetic-incoming-mdblist',
        );
        await d.position(300000);
        await d.playing(false);
        await d.waitCheckpoint('simkl', 1);
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint(
          'simkl',
          0,
          'pause',
          25,
          token: 'vplayer-synthetic-incoming-simkl',
        );
        d.expectCheckpoint(
          'mdblist',
          1,
          'pause',
          25,
          apiKey: 'vplayer-synthetic-incoming-mdblist',
        );
      } finally {
        reads?.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'Secondary dispose during policy preferences await starts no player heartbeat or send',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final errors = <Object>[];
      final oldStore = SharedPreferencesStorePlatform.instance;
      DisplayDefaultsReads? reads;
      try {
        reads = await t.runAsync(DisplayDefaultsReads.install);
        await runZonedGuarded(
          () => t.pumpWidget(MaterialApp(home: secondaryScreen())),
          (error, stack) => errors.add(error),
        );
        await f.until(t, () => reads!.entered);
        expect(f.players, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.forTracker('mdblist'), isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        reads!.unblock();
        await d.drain();
        await f.advance(t, const Duration(minutes: 2));
        await d.drain();
        expect(f.players, isEmpty);
        expect(d.forTracker('simkl'), isEmpty);
        expect(d.forTracker('mdblist'), isEmpty);
        expect(errors, isEmpty);
      } finally {
        reads?.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );
}
