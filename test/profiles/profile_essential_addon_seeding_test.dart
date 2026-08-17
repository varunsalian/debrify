import 'package:debrify/services/app_migration_service.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ProfileRuntime.debugReset);

  test('legacy compatibility still seeds essential addons', () {
    ProfileRuntime.initializeLegacy();

    expect(AppMigrationService.shouldSeedEssentialAddons(), isTrue);
  });

  test('app-created Admin profiles seed essential addons', () {
    for (final profileId in const <String>[
      ProfileBootstrap.migratedAdminId,
      ProfileBootstrap.freshAdminId,
    ]) {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 1),
      );

      expect(AppMigrationService.shouldSeedEssentialAddons(), isTrue);
    }
  });

  test('secondary and recovery profiles do not seed essential addons', () {
    for (final profileId in const <String>[
      'secondary-profile',
      ProfileBootstrap.recoveryAdminId,
    ]) {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 1),
      );

      expect(AppMigrationService.shouldSeedEssentialAddons(), isFalse);
    }
  });
}
