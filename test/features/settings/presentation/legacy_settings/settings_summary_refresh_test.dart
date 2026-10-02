import 'dart:async';

import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_refresh.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'owner', dataGeneration: 1, sessionEpoch: 1),
    );
    ProfileLockController.instance.lockedProfileId.value = null;
  });
  tearDown(() {
    ProfileLockController.instance.lockedProfileId.value = null;
    ProfileRuntime.debugReset();
  });

  for (final boundary in [
    'current',
    'disposal',
    'same-ID epoch change',
    'lock',
  ]) {
    test('summary failure publication respects $boundary', () async {
      final completion = Completer<void>();
      final summaries = SettingsSummaries();
      var mounted = true;
      var publications = 0;
      final refresh = SettingsSummaryRefresh(summaries, (
        loadSummariesForCurrentProfile: () => completion.future,
        defaultDownloadLocationLabel: () => 'Default',
        downloadLocationSupported: () => false,
        downloadLocationUsesSaf: () => false,
        mounted: () => mounted,
        setState: (update) {
          publications++;
          update();
        },
      ));
      final pending = refresh.loadSummaries();
      if (boundary == 'disposal') mounted = false;
      if (boundary == 'same-ID epoch change') {
        ProfileRuntime.publish(
          ProfileScope(profileId: 'owner', dataGeneration: 1, sessionEpoch: 2),
        );
      }
      if (boundary == 'lock') {
        ProfileLockController.instance.lockedProfileId.value = 'owner';
      }
      completion.completeError(StateError('summary unavailable'));
      await pending;

      final current = boundary == 'current';
      expect(summaries.summaryLoadFailed, current);
      expect(summaries.loading, !current);
      expect(publications, current ? 1 : 0);
    });
  }
}
