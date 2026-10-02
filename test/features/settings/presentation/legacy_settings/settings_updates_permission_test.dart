import 'dart:async';

import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/storage/device_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'denied update actions stop before mount, state or storage access',
    () async {
      SharedPreferences.setMockInitialValues({});
      final summaries = SettingsSummaries();
      final requests = <ProfileFeature>[];
      final updates = SettingsUpdates(summaries, (
        ensureProfileFeature: (feature) async {
          requests.add(feature);
          return false;
        },
        showReleaseDetails: (_) async => fail('No release should be opened'),
        showSnack: (_) => fail('No snackbar should be dispatched'),
        mounted: () => throw StateError('Permission must be checked first'),
        setState: (_) => fail('Denied actions must not change state'),
      ));

      await updates.checkForAppUpdates();
      await updates.toggleAutoUpdateChecks(false);
      await updates.toggleIncludeAlphaUpdates(true);

      expect(requests, List.filled(3, ProfileFeature.appUpdates));
      expect(summaries.checkingUpdates, isFalse);
      expect(summaries.autoUpdateChecksEnabled, isTrue);
      expect(summaries.includeAlphaUpdates, isFalse);
      expect(await DeviceStorage.getUpdateAutoCheckEnabled(), isTrue);
      expect(await DeviceStorage.getUpdateIncludeAlphaEnabled(), isFalse);
      updates.dispose();
    },
  );

  test(
    'a retired State rejects an action whose permission completes later',
    () async {
      SharedPreferences.setMockInitialValues({});
      final summaries = SettingsSummaries();
      final permission = Completer<bool>();
      var mounted = true;
      var publications = 0;
      final updates = SettingsUpdates(summaries, (
        ensureProfileFeature: (_) => permission.future,
        showReleaseDetails: (_) async => fail('No release should be opened'),
        showSnack: (_) => fail('No snackbar should be dispatched'),
        mounted: () => mounted,
        setState: (mutation) {
          publications++;
          mutation();
        },
      ));

      final pending = updates.toggleIncludeAlphaUpdates(true);
      mounted = false;
      updates.dispose();
      permission.complete(true);
      await pending;

      expect(publications, 0);
      expect(summaries.includeAlphaUpdates, isFalse);
      expect(await DeviceStorage.getUpdateIncludeAlphaEnabled(), isFalse);
    },
  );
}
