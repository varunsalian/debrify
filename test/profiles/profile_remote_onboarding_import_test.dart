import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_restore_coordinator.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  final router = RemoteCommandRouter();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-remote-onboarding-test-',
    );
    final documents = await Directory(
      p.join(temporaryDirectory.path, 'documents'),
    ).create(recursive: true);
    final support = await Directory(
      p.join(temporaryDirectory.path, 'support'),
    ).create(recursive: true);
    final cache = await Directory(
      p.join(temporaryDirectory.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    registry = await ProfileRegistry.open(
      path: p.join(support.path, 'profiles.db'),
    );
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(registry);
    router.debugOnboardingLifecycleParticipants = const [];
  });

  tearDown(() async {
    router.debugOnboardingLifecycleParticipants = null;
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'full-profile setup activates imported Admin and preserves setup profile',
    () async {
      final scaffold = await registry.createProfile(
        id: ProfileBootstrap.freshAdminId,
        name: 'Admin',
        role: UserProfileRole.admin,
        setupComplete: false,
      );
      final importedAdmin = await registry.createProfile(
        name: 'Living room',
        role: UserProfileRole.admin,
        setupComplete: true,
      );
      final importedMember = await registry.createProfile(
        name: 'Guest',
        role: UserProfileRole.member,
        setupComplete: true,
      );
      await registry.commitBootstrap(
        activeProfileId: scaffold.id,
        migratedLegacyInstall: false,
      );
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: scaffold.id,
          dataGeneration: scaffold.visibleDataGeneration,
          sessionEpoch: 1,
        ),
      );
      final scaffoldScope = ProfileRuntime.capture();
      final preferences = await SharedPreferences.getInstance();
      final preferenceKey = '${scaffoldScope.preferencePrefix}service.apiKey';
      await preferences.setString(preferenceKey, 'configured-during-setup');
      final privateDirectory = scaffoldScope.generationDirectory(
        await AppStorage.documents(),
      );
      await privateDirectory.create(recursive: true);
      final privateFile = File(p.join(privateDirectory.path, 'engine.json'));
      await privateFile.writeAsString('configured-during-setup');

      await router.debugActivateImportedAdminForOnboarding(
        ProfileGraphRestoreReport(
          profilesImported: 2,
          resourcesImported: 0,
          grantsImported: 0,
          bindingsImported: 0,
          pinResetsRequired: 0,
          importedProfileIds: <String>[importedAdmin.id, importedMember.id],
        ),
      );

      expect(ProfileRuntime.capture().profileId, importedAdmin.id);
      expect((await registry.activeProfile())?.id, importedAdmin.id);
      expect(await registry.getProfile(scaffold.id), isNotNull);
      expect(preferences.getString(preferenceKey), 'configured-during-setup');
      expect(await privateFile.readAsString(), 'configured-during-setup');
      expect(await registry.getProfile(importedMember.id), isNotNull);
    },
  );
}
