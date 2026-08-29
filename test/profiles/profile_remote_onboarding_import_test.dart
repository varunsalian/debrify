import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/app_migration_service.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
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
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (i) => i + 7),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    router.debugOnboardingLifecycleParticipants = const [];
  });

  tearDown(() async {
    router.debugOnboardingLifecycleParticipants = null;
    DeviceKeyProvider.debugReset();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'full-profile setup activates imported Admin and retires the setup profile',
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
      // An untouched setup profile is noise once an imported Admin owns the
      // device — it goes, so the user is not left picking "Admin" vs their
      // real profile at every launch.
      expect(await registry.getProfile(scaffold.id), isNull);
      expect(await registry.getProfile(importedMember.id), isNotNull);
    },
  );

  // The protection the old unconditional retention provided, now targeted:
  // someone may configure services before navigating back to import, and that
  // work must not be discarded silently.
  test('a setup profile that owns a connection survives the import', () async {
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
    await registry.insertResource(
      resource: ConnectionResource(
        id: 'configured-during-setup',
        type: ConnectionResourceType.realDebrid,
        label: 'Real-Debrid',
        ownerProfileId: scaffold.id,
        publicConfig: const <String, dynamic>{},
        authorizationRevision: 1,
        enabled: true,
      ),
      sealedSecretPayload: jsonEncode(<String, dynamic>{'sealed': true}),
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
  });

  // ProfileResetService sends an established profile back into onboarding
  // with its identity intact — including its PIN. A PIN proves the profile
  // was somebody's; its identity must never be silently deleted.
  test('a PIN-protected bootstrap profile survives the import', () async {
    final scaffold = await registry.createProfile(
      id: ProfileBootstrap.freshAdminId,
      name: 'Varun',
      role: UserProfileRole.admin,
      setupComplete: false,
    );
    final importedAdmin = await registry.createProfile(
      name: 'Living room',
      role: UserProfileRole.admin,
      setupComplete: true,
    );
    await registry.setPinRecord(
      profileId: scaffold.id,
      hash: List<int>.filled(32, 1),
      salt: List<int>.filled(16, 2),
      paramsJson: '{"algo":"test"}',
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

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
  });

  // A rename is the other identity marker reset preserves: the factory
  // scaffold is always created as ProfileBootstrap.freshAdminName, so any
  // other stored name was chosen by a person.
  test('a renamed bootstrap profile survives the import', () async {
    final scaffold = await registry.createProfile(
      id: ProfileBootstrap.freshAdminId,
      name: 'Varun',
      role: UserProfileRole.admin,
      setupComplete: false,
    );
    final importedAdmin = await registry.createProfile(
      name: 'Living room',
      role: UserProfileRole.admin,
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

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
  });

  // The reset-with-members trap: a local member created before the admin was
  // reset borrows the admin's seed addons via default grant seeding, and only
  // freshAdminId is ever re-seeded — deleting the seeds would strand that
  // member without addons permanently. An outside borrower vetoes retirement.
  test('a local member borrowing the seeds blocks the retirement', () async {
    final scaffold = await registry.createProfile(
      id: ProfileBootstrap.freshAdminId,
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: false,
    );
    final localMember = await registry.createProfile(
      name: 'Kid',
      role: UserProfileRole.member,
      setupComplete: true,
    );
    final importedAdmin = await registry.createProfile(
      name: 'Living room',
      role: UserProfileRole.admin,
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
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final seed = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Cinemeta',
      publicConfig: const <String, dynamic>{'addonName': 'Cinemeta'},
      secretConfig: const <String, dynamic>{
        'manifest_url': AppMigrationService.cinemetaManifestUrl,
      },
    );
    expect(await registry.getGrant(localMember.id, seed.id), isNotNull);

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        // The local member is NOT part of the import.
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
    // The member's borrowed grant is untouched — the veto fires BEFORE the
    // revocation, not after.
    expect(await registry.getGrant(localMember.id, seed.id), isNotNull);
  });

  // On an online first launch AppMigrationService seeds the essential addons
  // BEFORE onboarding starts, so the bootstrap profile owns stremioAddon
  // resources with zero user action. Those seeds must not veto the retirement
  // — or virtually every real device would keep the profile, since importing
  // from a phone implies being online.
  test('essential-addon seeds do not block the retirement', () async {
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
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final seeded = <ConnectionResource>[];
    for (final manifestUrl in const <String>[
      AppMigrationService.cinemetaManifestUrl,
      AppMigrationService.openSubtitlesManifestUrl,
      AppMigrationService.officialOpenSubtitlesManifestUrl,
      AppMigrationService.watchNextManifestUrl,
    ]) {
      seeded.add(
        await resources.create(
          // Each insert bumps the owner's authorization revision, so a
          // captured context is single-use.
          context: await ProfileAuthorizationContext.capture(registry),
          type: ConnectionResourceType.stremioAddon,
          label: 'Seeded addon',
          publicConfig: const <String, dynamic>{'addonName': 'Seeded addon'},
          secretConfig: <String, dynamic>{'manifest_url': manifestUrl},
        ),
      );
    }
    // The imported graph carries the sender's own copies of every essential —
    // the condition under which deleting the receiver's seeds loses nothing.
    await registry.setActiveProfile(importedAdmin.id);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: importedAdmin.id,
        dataGeneration: importedAdmin.visibleDataGeneration,
        sessionEpoch: 1,
      ),
    );
    for (final manifestUrl in const <String>[
      AppMigrationService.cinemetaManifestUrl,
      AppMigrationService.openSubtitlesManifestUrl,
      AppMigrationService.officialOpenSubtitlesManifestUrl,
      AppMigrationService.watchNextManifestUrl,
    ]) {
      await resources.create(
        context: await ProfileAuthorizationContext.capture(registry),
        type: ConnectionResourceType.stremioAddon,
        label: 'Imported addon',
        publicConfig: const <String, dynamic>{'addonName': 'Imported addon'},
        secretConfig: <String, dynamic>{'manifest_url': manifestUrl},
      );
    }
    await registry.setActiveProfile(scaffold.id);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: scaffold.id,
        dataGeneration: scaffold.visibleDataGeneration,
        sessionEpoch: 1,
      ),
    );

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNull);
    // The seeded rows go down with the profile they belonged to.
    for (final resource in seeded) {
      expect(await registry.getResource(resource.id), isNull);
    }
  });

  // A sender on an older build can predate one of the current essentials —
  // its graph then lacks that addon, only freshAdminId is ever re-seeded, and
  // the receiver's seed is the device's last copy. Deleting it would leave
  // the imported profiles without it forever, so missing coverage vetoes the
  // retirement BEFORE any grant is revoked.
  test('an import missing an essential addon blocks the retirement', () async {
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
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final seed = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Cinemeta',
      publicConfig: const <String, dynamic>{'addonName': 'Cinemeta'},
      secretConfig: const <String, dynamic>{
        'manifest_url': AppMigrationService.cinemetaManifestUrl,
      },
    );
    // The imported admin brings NO addons of its own.

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
    // The imported admin keeps BORROWING the device's only Cinemeta — the
    // veto fires before the revocation, so the grant survives.
    expect(await registry.getGrant(importedAdmin.id, seed.id), isNotNull);
  });

  // listAllResources() hides disabled rows while the delete-time owned count
  // does not — so reading only the enabled set classified this profile as
  // owning nothing but disposable seeds and then deleted the disabled
  // credential unseen. The veto must see every owned row.
  test('a DISABLED owned connection still blocks the retirement', () async {
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
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    // An enabled essential seed — on its own this would be disposable.
    await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Cinemeta',
      publicConfig: const <String, dynamic>{'addonName': 'Cinemeta'},
      secretConfig: const <String, dynamic>{
        'manifest_url': AppMigrationService.cinemetaManifestUrl,
      },
    );
    // A DISABLED debrid credential the user configured, invisible to
    // listAllResources but very much deleted by deleteOwnedResources.
    await registry.insertResource(
      resource: ConnectionResource(
        id: 'disabled-debrid',
        type: ConnectionResourceType.realDebrid,
        label: 'Real-Debrid',
        ownerProfileId: scaffold.id,
        publicConfig: const <String, dynamic>{},
        authorizationRevision: 1,
        enabled: false,
      ),
      sealedSecretPayload: jsonEncode(<String, dynamic>{'sealed': true}),
      secretPayloadVersion: 1,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
    );

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
    expect(await registry.getResource('disabled-debrid'), isNotNull);
  });

  // A profile returned to onboarding by ProfileResetService keeps its avatar
  // and policy. Those are customizations even when the name is still factory
  // and no PIN is set.
  test('a customized avatar blocks the retirement', () async {
    final scaffold = await registry.createProfile(
      id: ProfileBootstrap.freshAdminId,
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: false,
      avatarKey: 'preset:fox',
    );
    final importedAdmin = await registry.createProfile(
      name: 'Living room',
      role: UserProfileRole.admin,
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

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
  });

  // A user-added addon has a manifest URL outside the essential set: it is
  // real configuration and keeps the veto, even alongside genuine seeds.
  test('a user-added addon still blocks the retirement', () async {
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
    final resources = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      label: 'Cinemeta',
      publicConfig: const <String, dynamic>{'addonName': 'Cinemeta'},
      secretConfig: const <String, dynamic>{
        'manifest_url': AppMigrationService.cinemetaManifestUrl,
      },
    );
    final userAddon = await resources.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.stremioAddon,
      // Even a familiar name does not make it a seed: the URL decides.
      label: 'Cinemeta',
      publicConfig: const <String, dynamic>{'addonName': 'Cinemeta'},
      secretConfig: const <String, dynamic>{
        'manifest_url': 'https://my-private-addon.example/manifest.json',
      },
    );

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
    expect(await registry.getResource(userAddon.id), isNotNull);
  });

  // Search engines imported during local onboarding are YAMLs in the profile's
  // scoped documents tree — no connection resource, no owned artifact — so the
  // registry's disposition checks alone would happily delete them. Any private
  // file must veto the retirement.
  test('a setup profile with private generation files survives', () async {
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
    final privateDirectory = scaffoldScope.storageDirectory(
      await AppStorage.documents(),
      'documents',
    );
    await privateDirectory.create(recursive: true);
    final engineFile = File(p.join(privateDirectory.path, 'engine.yaml'));
    await engineFile.writeAsString('configured-during-setup');

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    // Hand-off still happens; only the deletion is vetoed.
    expect(ProfileRuntime.capture().profileId, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
    expect(await engineFile.readAsString(), 'configured-during-setup');
  });

  // switchTo can throw AFTER its registry commit (a participant warm failure),
  // in which case the imported Admin IS authoritative despite the throw. The
  // retirement must key off the registry's active profile, not the exception.
  test('a post-commit participant failure still retires the setup '
      'profile', () async {
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
    router.debugOnboardingLifecycleParticipants = <ProfileLifecycleParticipant>[
      _ThrowsAfterCommitParticipant(),
    ];

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        importedProfileIds: <String>[importedAdmin.id],
      ),
    );

    expect((await registry.activeProfile())?.id, importedAdmin.id);
    expect(await registry.getProfile(scaffold.id), isNull);
  });

  // No usable imported Admin means the hand-off never happens, and the setup
  // profile is the only way into the device. Deleting it would brick onboarding.
  test('a deferred hand-off keeps the setup profile active', () async {
    final scaffold = await registry.createProfile(
      id: ProfileBootstrap.freshAdminId,
      name: 'Admin',
      role: UserProfileRole.admin,
      setupComplete: false,
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

    await router.debugActivateImportedAdminForOnboarding(
      ProfileGraphRestoreReport(
        profilesImported: 1,
        resourcesImported: 0,
        grantsImported: 0,
        bindingsImported: 0,
        pinResetsRequired: 0,
        // Member only — nothing here can take authority.
        importedProfileIds: <String>[importedMember.id],
      ),
    );

    expect(ProfileRuntime.capture().profileId, scaffold.id);
    expect(await registry.getProfile(scaffold.id), isNotNull);
  });
}

/// Simulates ProfileAppLifecycleParticipant dying during candidate warming —
/// after the registry commit, so the target is already authoritative.
class _ThrowsAfterCommitParticipant implements ProfileLifecycleParticipant {
  @override
  Future<void> prepareDeactivate(ProfileScope current) async {}

  @override
  Future<void> initializeCandidate(ProfileScope candidate) async {
    throw StateError('warm failed after commit');
  }

  @override
  Future<void> didActivate(ProfileScope active) async {}

  @override
  Future<void> rollback(ProfileScope restored) async {}
}
