import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_loader.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reload reads the current overrides through the borrowed getter',
    () async {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      final summaries = SettingsSummaries();
      var overrideReads = 0;
      Map<String, Future<Object?> Function()> overrides = {
        'App version': () async => PackageInfo(
          appName: 'Debrify',
          packageName: 'test.debrify',
          version: '1.0',
          buildNumber: '11',
        ),
      };
      void unexpectedAccount(dynamic account) {
        fail('Empty credentials must not publish an account');
      }

      final loader = SettingsSummaryLoader(summaries, (
        applyAllDebridUserInfo: unexpectedAccount,
        applyPremiumizeUserInfo: unexpectedAccount,
        applyRdUserInfo: unexpectedAccount,
        applyTorboxUserInfo: unexpectedAccount,
        pendingCredentialTypes: () async => <ConnectionResourceType>{},
        activeProfileMayExportDiagnostics: () async => false,
        mounted: () => true,
        setState: (update) => update(),
        summaryReadOverrides: () {
          overrideReads++;
          return overrides;
        },
      ));
      expect(overrideReads, 0);
      await loader.loadSummariesForCurrentProfile();
      expect(summaries.appVersion, '1.0 (11)');
      expect(overrideReads, 1);

      overrides = {
        'App version': () async => PackageInfo(
          appName: 'Debrify',
          packageName: 'test.debrify',
          version: '2.0',
          buildNumber: '22',
        ),
      };
      await loader.loadSummariesForCurrentProfile();
      expect(summaries.appVersion, '2.0 (22)');
      expect(overrideReads, 2);
    },
  );
}
