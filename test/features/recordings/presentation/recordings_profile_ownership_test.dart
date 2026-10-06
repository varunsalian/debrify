import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

void main() {
  testWidgets('committed profile owns schedules and desktop captures', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      final profiles = await t.runAsync(f.profiles);
      final b = await t.runAsync(() async {
        final actor = await profiles!.registry.getProfile(profiles.a);
        return profiles.registry.createProfile(
          name: 'B',
          role: UserProfileRole.admin,
          actingProfileId: profiles.a,
          actingAuthorizationRevision: actor!.authorizationRevision,
          actingSessionEpoch: 1,
        );
      });
      await f.seedSchedules([
        f.schedule('A', owner: profiles!.a),
        f.schedule('B', owner: b!.id),
      ]);
      await t.runAsync(f.capture);
      await f.mount(t);
      expect(find.text('Channel A'), findsOneWidget);
      expect(find.text('Channel B'), findsNothing);
      expect(recordingsType('_LiveCard'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      ProfileRuntime.publish(
        ProfileScope(profileId: b.id, dataGeneration: 1, sessionEpoch: 2),
      );
      await f.mount(t);
      expect(
        find.text('Channel B'),
        findsOneWidget,
        reason: 'incoming profile schedule is selected',
      );
      expect(
        find.text('Channel A'),
        findsNothing,
        reason: 'outgoing schedule is not exposed',
      );
      expect(
        recordingsType('_LiveCard'),
        findsNothing,
        reason: 'outgoing desktop capture is not exposed',
      );
    });
  });

  testWidgets(
    'battery dismissal preference is device-wide across committed profiles',
    (t) async {
      await recordingsCase(t, (f) async {
        final profiles = await t.runAsync(f.profiles);
        final b = await t.runAsync(() async {
          final actor = await profiles!.registry.getProfile(profiles.a);
          return profiles.registry.createProfile(
            name: 'B',
            role: UserProfileRole.admin,
            actingProfileId: profiles.a,
            actingAuthorizationRevision: actor!.authorizationRevision,
            actingSessionEpoch: 1,
          );
        });
        const key = 'recording_battery_nudge_dismissed_at';
        final prefs = await DevicePreferences.instance();
        await prefs.setInt(key, 1234567);
        ProfileRuntime.publish(
          ProfileScope(profileId: b!.id, dataGeneration: 1, sessionEpoch: 2),
        );
        expect(
          (await DevicePreferences.instance()).getInt(key),
          1234567,
          reason: 'device dismissal round-trips across profile switch',
        );
        await (await DevicePreferences.instance()).setInt(key, 2345678);
        ProfileRuntime.publish(
          ProfileScope(
            profileId: profiles!.a,
            dataGeneration: 1,
            sessionEpoch: 3,
          ),
        );
        expect((await DevicePreferences.instance()).getInt(key), 2345678);
      });
    },
  );
}
