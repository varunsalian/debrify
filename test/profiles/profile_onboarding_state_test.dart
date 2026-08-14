import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_reset_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late UserProfile admin;

  ProfileScope scope(UserProfile profile, int epoch) => ProfileScope(
    profileId: profile.id,
    dataGeneration: profile.visibleDataGeneration,
    sessionEpoch: epoch,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-onboarding-state-test-',
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
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: true,
    );
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: true,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(scope(admin, 1));
    ProfileBootstrap.debugInstallRegistry(registry);
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'registry completion is authoritative when compatibility key is absent',
    () async {
      expect(await StorageService.isInitialSetupComplete(), isTrue);
      final raw = await SharedPreferences.getInstance();
      expect(
        raw.containsKey('p.${admin.id}.g.1.initial_setup_complete_v1'),
        isFalse,
      );
    },
  );

  test(
    'an explicit compatibility value is reconciled once then removed',
    () async {
      final preferences = await ProfilePreferences.instance();
      await preferences.setBool('initial_setup_complete_v1', false);

      expect(await StorageService.isInitialSetupComplete(), isFalse);
      expect((await registry.getProfile(admin.id))?.setupComplete, isFalse);
      final raw = await SharedPreferences.getInstance();
      expect(
        raw.containsKey('p.${admin.id}.g.1.initial_setup_complete_v1'),
        isFalse,
      );
    },
  );

  test(
    'finishing onboarding updates the registry without recreating the old key',
    () async {
      await StorageService.setInitialSetupComplete(false);
      expect((await registry.getProfile(admin.id))?.setupComplete, isFalse);

      await StorageService.setInitialSetupComplete(true);

      expect((await registry.getProfile(admin.id))?.setupComplete, isTrue);
      expect(await StorageService.isInitialSetupComplete(), isTrue);
      final raw = await SharedPreferences.getInstance();
      expect(raw.get('p.${admin.id}.g.1.initial_setup_complete_v1'), isNull);
    },
  );

  test('Admin-created profile is ready without running onboarding', () async {
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final staged = await ProfileCreationService(registry).createStaged(
      actor: authorization,
      name: 'Member',
      role: UserProfileRole.member,
      policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
      copyDefaultsFromActive: false,
    );
    final member = await registry.completeProfileSetup(
      staged.id,
      actingProfileId: authorization.profileId,
      actingAuthorizationRevision: authorization.authorizationRevision,
      actingSessionEpoch: authorization.sessionEpoch,
    );
    await registry.setActiveProfile(member.id);
    ProfileRuntime.publish(scope(member, 2));

    expect(await StorageService.isInitialSetupComplete(), isTrue);
    expect((await registry.getProfile(member.id))?.setupComplete, isTrue);
  });

  test('profile reset atomically makes onboarding incomplete', () async {
    await ProfileResetService(registry: registry).resetActiveProfile();

    final reset = (await registry.getProfile(admin.id))!;
    expect(reset.visibleDataGeneration, 2);
    expect(reset.setupComplete, isFalse);
    expect(await StorageService.isInitialSetupComplete(), isFalse);
    final raw = await SharedPreferences.getInstance();
    expect(raw.get('p.${admin.id}.g.2.initial_setup_complete_v1'), isNull);
  });

  test('stale session cannot change onboarding completion', () async {
    final stale = await ProfileAuthorizationContext.capture(registry);
    ProfileRuntime.publish(scope(admin, 2));

    await expectLater(
      registry.setActiveProfileSetupComplete(
        profileId: stale.profileId,
        setupComplete: false,
        actingAuthorizationRevision: stale.authorizationRevision,
        actingSessionEpoch: stale.sessionEpoch,
      ),
      throwsStateError,
    );
    expect((await registry.getProfile(admin.id))?.setupComplete, isTrue);
  });
}
