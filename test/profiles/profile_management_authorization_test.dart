import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('picker can unlock its sole unpinned Admin for management', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-management-authorization-test-',
    );
    final registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    try {
      ProfileRuntime.debugReset();
      final admin = await registry.createProfile(
        name: 'Admin',
        role: UserProfileRole.admin,
      );
      await registry.commitBootstrap(
        activeProfileId: admin.id,
        migratedLegacyInstall: false,
      );
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: admin.id,
          dataGeneration: admin.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );
      ProfileLockController.instance.activate(admin, unlocked: false);

      await expectLater(
        (await ProfileAuthorizationContext.capture(
          registry,
        )).validate(registry),
        throwsStateError,
      );

      final unlocked =
          await ProfileAuthorizationContext.unlockActiveAdminForManagement(
            registry,
            expectedProfile: admin,
            pinVerified: false,
          );
      final authorization = await ProfileAuthorizationContext.capture(registry);

      expect(unlocked.id, admin.id);
      expect(ProfileLockController.instance.isUnlocked, isTrue);
      expect(
        (await authorization.validate(
          registry,
        )).allows(ProfileFeature.manageProfiles),
        isTrue,
      );
    } finally {
      ProfileLockController.instance.dispose();
      ProfileRuntime.debugReset();
      await registry.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
