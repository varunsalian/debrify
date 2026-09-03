import 'dart:convert';
import 'dart:math';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/backup_restore_service.dart';
import '../../services/iptv_transfer_payload.dart';
import '../../services/storage_service.dart';
import '../../utils/stremio_url.dart';
import 'connection_resource_service.dart';
import 'device_key_provider.dart';
import 'native_profile_projection.dart';
import 'portable_profile_package.dart';
import 'profile_authorization.dart';
import 'profile_avatar_ingest.dart';
import 'profile_avatar_mutation.dart';
import 'profile_data_generation.dart';
import 'profile_database_snapshot.dart';
import 'profile_lifecycle.dart';
import 'profile_pin_service.dart';
import 'profile_portable_files.dart';
import 'profile_preference_portability.dart';
import 'profile_preferences.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

class ProfileRestoreReport {
  final String destinationProfileId;
  final int publishedGeneration;
  final int preferencesApplied;
  final int resourcesImported;
  final int borrowedResourcesSkipped;
  final Map<String, dynamic> omissions;
  final RestoreReport? legacyFollowUp;

  const ProfileRestoreReport({
    required this.destinationProfileId,
    required this.publishedGeneration,
    required this.preferencesApplied,
    required this.resourcesImported,
    required this.borrowedResourcesSkipped,
    required this.omissions,
    this.legacyFollowUp,
  });
}

class ProfileGraphRestoreReport {
  final int profilesImported;
  final int resourcesImported;
  final int grantsImported;
  final int bindingsImported;
  final int pinResetsRequired;
  final List<String> importedProfileIds;

  const ProfileGraphRestoreReport({
    required this.profilesImported,
    required this.resourcesImported,
    required this.grantsImported,
    required this.bindingsImported,
    required this.pinResetsRequired,
    required this.importedProfileIds,
  });
}

/// Sole writer for profile-aware file and remote restores.
class ProfileRestoreCoordinator {
  final ProfileRegistry registry;
  final DeviceSecretCipher cipher;
  final List<ProfileLifecycleParticipant> lifecycleParticipants;

  const ProfileRestoreCoordinator({
    required this.registry,
    required this.cipher,
    this.lifecycleParticipants = const <ProfileLifecycleParticipant>[],
  });

  Future<ProfileGraphRestoreReport> restoreDeviceGraph({
    required PortableProfilePackage package,
    required ProfileAuthorizationContext authorization,
  }) async {
    final actor = await authorization.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('Comprehensive restore requires an Admin');
    }
    if (package.mode != 'deviceGraph' ||
        package.profiles.isEmpty ||
        package.profiles.length > PortableProfilePackage.maxProfiles) {
      throw const FormatException('Invalid device profile graph');
    }

    final restoreResourceIds = _allocateResourceIds(
      package.resources,
      include: (_) => true,
    );

    final operationId = _newId('graph-restore');
    final profileIds = <String, String>{};
    final parsedProfiles = <_ImportedProfile>[];
    for (final record in package.profiles) {
      final backupId = record['backupId'];
      final name = record['name'];
      final roleName = record['role'];
      final policySource = record['policy'];
      final sectionId = record['preferencesSection'];
      if (backupId is! String ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 80 ||
          roleName is! String ||
          policySource is! String ||
          sectionId is! String) {
        throw const FormatException('Invalid imported profile');
      }
      final matchingRole = UserProfileRole.values.where(
        (role) => role.name == roleName,
      );
      if (matchingRole.isEmpty) {
        throw FormatException('Unknown imported role $roleName');
      }
      final role = matchingRole.first;
      final section = package.sections[sectionId];
      if (section is! Map || section['values'] is! Map) {
        throw const FormatException('Imported profile settings are missing');
      }
      final values = _normalizePreferenceValues(
        section['values'] as Map,
        resourceIds: restoreResourceIds.bySourceId,
        includeCredentialEngineSettings: true,
        rejectDisallowedKeys:
            package.sourceVersion >= PortableProfilePackage.version,
      );
      _validatePreferenceOverlay(values, includeCredentialEngineSettings: true);
      StorageService.rearmGhostPurgeForImportedPlayback(values);
      final id = _newId('profile');
      if (profileIds.putIfAbsent(backupId, () => id) != id) {
        throw const FormatException('Duplicate imported profile ID');
      }
      parsedProfiles.add(
        _ImportedProfile(
          id: id,
          name: name.trim(),
          avatarKey: record['avatarKey'] as String?,
          role: role,
          policy: ProfilePolicy.decode(policySource, role),
          setupComplete: _optionalBool(record, 'setupComplete') ?? false,
          disabled: _optionalBool(record, 'disabled') ?? false,
          wasPinProtected: _optionalBool(record, 'wasPinProtected') ?? false,
          lockOnResume: _optionalBool(record, 'lockOnResume') ?? false,
          inactivityTimeoutMinutes: _optionalInactivityTimeout(record),
          preferences: values,
        ),
      );
    }

    await registry.beginProfileGraphRestore(
      operationId: operationId,
      stagedProfileIds: parsedProfiles.map((profile) => profile.id).toList(),
    );
    var published = false;
    var publicationUncertain = false;
    var pinResetsRequired = 0;
    final avatarStages = <ProfilePortableAvatarStage>[];
    final avatarMutationProfiles = <String>{};
    try {
      for (final profile in parsedProfiles) {
        await registry.createProfile(
          id: profile.id,
          name: profile.name,
          avatarKey: profile.avatarKey,
          role: profile.role,
          policy: profile.policy,
          setupComplete: profile.setupComplete,
          // Keep the hidden staging row enabled just long enough to install a
          // carried PIN through the registry's normal credential boundary.
          // The requested disabled state is applied below before publication.
          disabled: false,
          lockOnResume: profile.lockOnResume,
          inactivityTimeoutMinutes: profile.inactivityTimeoutMinutes,
          lifecycle: UserProfileLifecycle.staging,
          actingProfileId: authorization.profileId,
          actingAuthorizationRevision: authorization.authorizationRevision,
          actingSessionEpoch: authorization.sessionEpoch,
        );
        final preferences = await ProfilePreferences.forCapturedScope(
          ProfileScope(
            profileId: profile.id,
            dataGeneration: 1,
            sessionEpoch: 0,
          ),
          CapturedProfilePreferenceAccess.restore,
        );
        for (final entry in profile.preferences.entries) {
          if (!await _writePreference(preferences, entry.key, entry.value)) {
            throw StateError('Could not stage imported profile settings');
          }
        }
        final sourceBackupId = profileIds.entries
            .singleWhere((entry) => entry.value == profile.id)
            .key;
        final sourceRecord = package.profiles.singleWhere(
          (record) => record['backupId'] == sourceBackupId,
        );
        final stagingScope = ProfileScope(
          profileId: profile.id,
          dataGeneration: 1,
          sessionEpoch: 0,
        );
        final databasesRestored = await _restoreDatabaseSection(
          package,
          sourceRecord,
          stagingScope,
        );
        if (databasesRestored > 0) {
          await ProfileDatabaseSnapshot.remapResourceReferences(
            stagingScope,
            restoreResourceIds.bySourceId,
          );
        }
        await _restoreFilesSection(package, sourceRecord, stagingScope);
        final avatarStage = await ProfilePortableFiles.stageAvatar(
          scope: stagingScope,
          record: sourceRecord['avatarFile'],
          expectedAvatarKey: profile.avatarKey,
          operationId: operationId,
        );
        if (avatarStage != null) avatarStages.add(avatarStage);
        if (profile.wasPinProtected) {
          // A carried PIN record restores the working PIN (and its recovery
          // code); anything missing or malformed falls back to the old
          // contract — locked until an Admin assigns a new PIN — rather
          // than failing the restore or importing a bogus credential.
          final carried = _parseCarriedPinRecord(sourceRecord['pinRecord']);
          if (carried == null) pinResetsRequired++;
          await registry.setPinRecord(
            profileId: profile.id,
            hash: carried?.hash,
            salt: carried?.salt,
            paramsJson: carried?.paramsJson,
            recoveryHash: carried?.recoveryHash,
            recoverySalt: carried?.recoverySalt,
            recoveryParamsJson: carried?.recoveryParamsJson,
            resetRequired: carried == null,
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        }
        if (profile.disabled) {
          await registry.disableProfile(
            profile.id,
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        }
      }

      var grantCount = 0;
      var bindingCount = 0;
      final stagedResources = <StagedGraphResource>[];
      final importedAddonIdentitiesByProfile = <String, Set<String>>{};
      for (final record in package.resources) {
        final backupId = record['backupId'];
        final ownerBackupId = record['ownerProfileBackupId'];
        final typeName = record['type'];
        final secretRecord = record['secretConfig'];
        if (backupId is! String ||
            ownerBackupId is! String ||
            typeName is! String ||
            secretRecord is! Map) {
          throw const FormatException('Invalid imported resource');
        }
        final ownerId = profileIds[ownerBackupId];
        final matchingType = ConnectionResourceType.values.where(
          (type) => type.name == typeName,
        );
        if (ownerId == null || matchingType.isEmpty) {
          throw const FormatException('Imported resource reference is invalid');
        }
        final type = matchingType.first;
        final disabled = _optionalBool(record, 'disabled') ?? false;
        final resourceId = restoreResourceIds.byBackupId[backupId];
        if (resourceId == null) {
          throw const FormatException('Imported resource ID is missing');
        }
        final secret = _remapJsonMap(
          _normalizeSecret(type, Map<String, dynamic>.from(secretRecord)),
          restoreResourceIds.bySourceId,
        );
        if (_hasNoUsableSecret(secret)) {
          throw const FormatException('Imported resource secret is empty');
        }
        final publicConfig = _publicConfig(type, record);
        final sealed = await cipher.seal(
          utf8.encode(jsonEncode(secret)),
          associatedData: utf8.encode(
            'debrify-resource|id=$resourceId|type=${type.name}|'
            'owner=$ownerId|public=1|secret=1',
          ),
        );
        final parsedGrants = <StagedGraphGrant>[];
        final grantedProfiles = <String>{};
        final rawGrants = record['grants'];
        if (rawGrants is! List) {
          throw const FormatException('Imported resource grants are missing');
        }
        for (final rawGrant in rawGrants) {
          if (rawGrant is! Map ||
              rawGrant['profileBackupId'] is! String ||
              rawGrant['permissions'] is! num) {
            throw const FormatException('Invalid imported resource grant');
          }
          final targetId = profileIds[rawGrant['profileBackupId'] as String];
          final target = parsedProfiles.where(
            (profile) => profile.id == targetId,
          );
          if (targetId == null || target.isEmpty) {
            throw const FormatException('Imported grant target is missing');
          }
          if (!grantedProfiles.add(targetId)) {
            throw const FormatException('Duplicate imported resource grant');
          }
          parsedGrants.add(
            StagedGraphGrant(
              profileId: targetId,
              permissions: _effectivePermissions(
                target.first.role,
                (rawGrant['permissions'] as num).toInt(),
              ),
            ),
          );
        }
        if (!parsedGrants.any((grant) => grant.profileId == ownerId)) {
          final owner = parsedProfiles.singleWhere(
            (profile) => profile.id == ownerId,
          );
          parsedGrants.add(
            StagedGraphGrant(
              profileId: ownerId,
              permissions: _effectivePermissions(owner.role, null),
            ),
          );
          grantedProfiles.add(ownerId);
        }
        final addonIdentity = type == ConnectionResourceType.stremioAddon
            ? _stremioManifestIdentity(secret)
            : null;
        if (addonIdentity != null) {
          for (final grant in parsedGrants) {
            importedAddonIdentitiesByProfile
                .putIfAbsent(grant.profileId, () => <String>{})
                .add(addonIdentity);
          }
        }
        final parsedBindings = <StagedGraphBinding>[];
        final bindingSlots = <String>{};
        final rawBindings = record['bindings'];
        if (rawBindings is! List) {
          throw const FormatException('Imported resource bindings are missing');
        }
        for (final rawBinding in rawBindings) {
          if (rawBinding is! Map ||
              rawBinding['profileBackupId'] is! String ||
              rawBinding['slot'] is! String) {
            throw const FormatException('Invalid imported resource binding');
          }
          final targetId = profileIds[rawBinding['profileBackupId'] as String];
          final slot = (rawBinding['slot'] as String).trim();
          if (targetId == null || slot.isEmpty || slot.length > 160) {
            throw const FormatException('Invalid imported binding reference');
          }
          if (!bindingSlots.add('$targetId\u0000$slot')) {
            throw const FormatException('Duplicate imported binding');
          }
          parsedBindings.add(
            StagedGraphBinding(profileId: targetId, slot: slot),
          );
        }
        final parsedSettings = <StagedGraphSettings>[];
        final settingsProfiles = <String>{};
        final rawSettings = record['profileSettings'];
        if (rawSettings != null && rawSettings is! List) {
          throw const FormatException('Invalid imported resource settings');
        }
        for (final rawSetting in (rawSettings as List?) ?? const <Object?>[]) {
          if (rawSetting is! Map ||
              rawSetting['profileBackupId'] is! String ||
              rawSetting['enabled'] is! bool ||
              rawSetting['values'] is! Map) {
            throw const FormatException('Invalid imported resource settings');
          }
          final targetId = profileIds[rawSetting['profileBackupId'] as String];
          if (targetId == null ||
              !grantedProfiles.contains(targetId) ||
              !settingsProfiles.add(targetId)) {
            throw const FormatException(
              'Imported resource settings reference is invalid',
            );
          }
          parsedSettings.add(
            StagedGraphSettings(
              profileId: targetId,
              enabled: rawSetting['enabled'] as bool,
              values: _normalizeResourceSettings(
                rawSetting['values'] as Map,
                restoreResourceIds.bySourceId,
              ),
            ),
          );
        }
        grantCount += parsedGrants.length;
        bindingCount += parsedBindings.length;
        stagedResources.add(
          StagedGraphResource(
            id: resourceId,
            type: type,
            label: (record['label'] as String? ?? type.name).trim(),
            ownerProfileId: ownerId,
            publicConfig: publicConfig,
            sealedSecretPayload: sealed,
            secretPayloadVersion: 1,
            enabled: !disabled,
            grants: parsedGrants,
            bindings: parsedBindings,
            settings: parsedSettings,
          ),
        );
      }
      final redundantDefaultAddonGrants = await _redundantDefaultAddonGrants(
        authorization: authorization,
        importedIdentitiesByProfile: importedAddonIdentitiesByProfile,
      );
      final generationManager = ProfileDataGenerationManager(registry);
      for (final profile in parsedProfiles) {
        await generationManager.finalizeGraphProfile(
          operationId: operationId,
          profileId: profile.id,
        );
      }
      await registry.verifyProfileGraphRestore(operationId);
      await authorization.validate(registry);
      for (final profile in parsedProfiles) {
        await generationManager.verifyGraphProfile(
          operationId: operationId,
          profileId: profile.id,
        );
      }
      await ProfileAvatarMutation.runExclusiveMany(
        parsedProfiles.map((profile) => profile.id),
        () async {
          for (final stage in avatarStages) {
            await ProfileAvatarMutation.begin(
              stage.profileId,
              stage.avatar.format(),
            );
            avatarMutationProfiles.add(stage.profileId);
            await stage.install();
          }
          try {
            await registry.publishProfileGraphRestore(
              operationId: operationId,
              stagedProfileIds: parsedProfiles
                  .map((profile) => profile.id)
                  .toList(),
              resources: stagedResources,
              redundantDefaultAddonGrants: redundantDefaultAddonGrants,
            );
          } catch (error, stackTrace) {
            bool committed;
            try {
              committed = await registry.profileGraphRestorePublished(
                operationId,
              );
            } catch (_) {
              publicationUncertain = true;
              Error.throwWithStackTrace(error, stackTrace);
            }
            if (!committed) Error.throwWithStackTrace(error, stackTrace);
            try {
              // The journal proves the SQLite transaction, but tvOS may still
              // have failed before publishing that projection to Keychain.
              // Require a successful retry before finalizing live avatar bytes.
              await registry.checkpointTvOsRecovery();
            } catch (_) {
              publicationUncertain = true;
              Error.throwWithStackTrace(error, stackTrace);
            }
          }
          published = true;
          for (final stage in avatarStages) {
            try {
              await stage.finish();
              await ProfileAvatarMutation.complete(stage.profileId);
            } catch (_) {
              // Registry publication is already durable. Retain this profile's
              // intent and report success; bootstrap finishes the idempotent
              // prune/staging cleanup instead of inviting a duplicate restore.
            }
          }
        },
      );
      try {
        await registry.markRestoreCleaned(operationId);
      } catch (_) {
        // Publication is already authoritative. A retained `published` journal
        // is harmless and bootstrap removes it idempotently.
      }
      return ProfileGraphRestoreReport(
        profilesImported: parsedProfiles.length,
        resourcesImported: stagedResources.length,
        grantsImported: grantCount,
        bindingsImported: bindingCount,
        pinResetsRequired: pinResetsRequired,
        importedProfileIds: List<String>.unmodifiable(
          parsedProfiles.map((profile) => profile.id),
        ),
      );
    } catch (_) {
      if (!published && !publicationUncertain) {
        for (final stage in avatarStages) {
          try {
            await stage.rollback();
          } catch (_) {
            // The graph journal still owns the whole staging profile and
            // startup will delete its complete private tree.
          }
        }
        var cleanupComplete = true;
        for (final profile in parsedProfiles) {
          try {
            // Keep the journal and staging row authoritative until physical
            // cleanup has completed. A crash at either boundary is therefore
            // restart-safe and idempotent.
            await ProfileDataGenerationManager.deleteAllProfileData(profile.id);
            await registry.deleteProfile(profile.id);
          } catch (_) {
            // Startup consumes the graph journal and finishes cleanup.
            cleanupComplete = false;
          }
        }
        if (cleanupComplete) {
          for (final profileId in avatarMutationProfiles) {
            try {
              await ProfileAvatarMutation.complete(profileId);
            } catch (_) {
              // Retaining the intent is safe; bootstrap sees no profile and
              // removes the remaining private tree.
            }
          }
          try {
            await registry.markRestoreCleaned(operationId);
          } catch (_) {
            // Preserve the journal if cleanup could not be proven complete.
          }
        }
      }
      rethrow;
    }
  }

  /// Restores one package into its authorizing profile.
  ///
  /// [completeOnboarding] is reserved for the first-run restore entry point;
  /// it makes setup completion part of the generation publication transaction.
  Future<ProfileRestoreReport> restore({
    required PortableProfilePackage package,
    required String destinationProfileId,
    required ProfileAuthorizationContext authorization,
    bool replacePreferences = false,
    bool completeOnboarding = false,
  }) async {
    final actor = await authorization.validate(registry);
    if (actor.id != destinationProfileId) {
      throw StateError('Restore destination must match local authorization');
    }
    if (!actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('Profile is not allowed to restore backups');
    }
    if (package.profiles.length != 1) {
      throw StateError('Single-profile restore requires exactly one profile');
    }
    final profileRecord = package.profiles.single;
    final restoreResourceIds = _allocateResourceIds(
      package.resources,
      include: (record) => _importsSingleProfileResource(
        record,
        sourceVersion: package.sourceVersion,
      ),
    );
    final sectionId = profileRecord['preferencesSection'];
    final section = package.sections[sectionId];
    if (section is! Map || section['values'] is! Map) {
      throw const FormatException('Profile preference section is missing');
    }
    final values = _normalizePreferenceValues(
      section['values'] as Map,
      resourceIds: restoreResourceIds.bySourceId,
      includeCredentialEngineSettings: package.mode != 'sanitizedSettings',
      rejectDisallowedKeys:
          package.sourceVersion >= PortableProfilePackage.version,
    );
    _validatePreferenceOverlay(
      values,
      includeCredentialEngineSettings: package.mode != 'sanitizedSettings',
    );
    final importedSetupComplete = _optionalBool(profileRecord, 'setupComplete');
    final importedLockOnResume = _optionalBool(profileRecord, 'lockOnResume');
    final updateInactivityTimeout = profileRecord.containsKey(
      'inactivityTimeoutMinutes',
    );
    final importedInactivityTimeout = _optionalInactivityTimeout(profileRecord);
    // Merge-mode restore keeps destination keys the package omits, so imported
    // playback must re-arm the purge or its ghosts are stranded behind an
    // already-satisfied generation marker.
    StorageService.rearmGhostPurgeForImportedPlayback(values);

    final operationId = _newId('restore');
    final current = ProfileRuntime.capture();
    final restoringActive = current.profileId == destinationProfileId;
    var published = false;
    var publicationUncertain = false;
    ProfileScope? candidate;
    ProfilePortableAvatarStage? avatarStage;
    var avatarStageApplies = false;
    if (restoringActive) {
      for (final participant in lifecycleParticipants) {
        await participant.prepareDeactivate(current);
      }
    }

    try {
      final generationManager = ProfileDataGenerationManager(registry);
      var staged = await generationManager.stage(
        operationId: operationId,
        profileId: destinationProfileId,
        preferenceOverlay: values,
        replacePreferences: replacePreferences,
      );
      final stagingScope = ProfileScope(
        profileId: destinationProfileId,
        dataGeneration: staged.generation,
        sessionEpoch: 0,
      );
      final databasesRestored = await _restoreDatabaseSection(
        package,
        profileRecord,
        stagingScope,
      );
      if (databasesRestored > 0) {
        await ProfileDatabaseSnapshot.remapResourceReferences(
          stagingScope,
          restoreResourceIds.bySourceId,
        );
      }
      await _restoreFilesSection(package, profileRecord, stagingScope);
      final importedAvatarKey = profileRecord['avatarKey'];
      final importedAvatar = importedAvatarKey is String
          ? ProfileAvatar.tryParse(importedAvatarKey)
          : null;
      final currentAvatar = ProfileAvatar.tryParse(actor.avatarKey);
      avatarStageApplies =
          importedAvatar?.kind == ProfileAvatarKind.image &&
          currentAvatar?.kind == ProfileAvatarKind.image &&
          importedAvatar!.id == currentAvatar!.id;
      // A single-profile restore does not replace profile identity. Only stage
      // avatar bytes when they repair the exact file key already owned by the
      // destination; otherwise there is no live avatar mutation to recover.
      if (avatarStageApplies) {
        avatarStage = await ProfilePortableFiles.stageAvatar(
          scope: stagingScope,
          record: profileRecord['avatarFile'],
          expectedAvatarKey: importedAvatarKey as String,
          operationId: operationId,
        );
        avatarStageApplies = avatarStage != null;
      }
      var imported = 0;
      var borrowedSkipped = 0;
      final stagedIptvProviders = <String, String>{};
      for (final record in package.resources) {
        if (record['owned'] != true || record['secretConfig'] is! Map) {
          borrowedSkipped++;
          continue;
        }
        // Version 3 single-profile restore deliberately skipped degenerate
        // owned resources. Keep that compatibility without weakening v4:
        // current authenticated packages treat an empty resource as corrupt.
        if (!_importsSingleProfileResource(
          record,
          sourceVersion: package.sourceVersion,
        )) {
          continue;
        }
        if (!actor.allows(ProfileFeature.manageConnections)) {
          throw StateError('Destination cannot own imported connections');
        }
        final typeName = record['type'];
        final matching = ConnectionResourceType.values.where(
          (value) => value.name == typeName,
        );
        if (matching.isEmpty) {
          throw FormatException('Unknown resource type $typeName');
        }
        final type = matching.first;
        final backupId = record['backupId'];
        if (backupId is! String) {
          throw const FormatException('Invalid imported resource ID');
        }
        final resourceId = restoreResourceIds.byBackupId[backupId];
        if (resourceId == null) {
          throw const FormatException('Imported resource ID is missing');
        }
        final secret = _remapJsonMap(
          _normalizeSecret(
            type,
            Map<String, dynamic>.from(record['secretConfig'] as Map),
          ),
          restoreResourceIds.bySourceId,
        );
        if (_hasNoUsableSecret(secret)) {
          throw const FormatException('Imported resource secret is empty');
        }
        if (type == ConnectionResourceType.iptvM3u ||
            type == ConnectionResourceType.iptvXtream) {
          stagedIptvProviders[IptvTransferPayload.providerFingerprintFromJson(
                secret,
              )] =
              resourceId;
          final legacyProviderId = secret['id'];
          if (legacyProviderId is String && legacyProviderId.isNotEmpty) {
            stagedIptvProviders[legacyProviderId] = resourceId;
          }
        }
        final aad = utf8.encode(
          'debrify-resource|id=$resourceId|type=${type.name}|'
          'owner=$destinationProfileId|public=1|secret=1',
        );
        final sealed = await cipher.seal(
          utf8.encode(jsonEncode(secret)),
          associatedData: aad,
        );
        final permissions = _effectivePermissions(
          actor.role,
          (record['permissions'] as num?)?.toInt(),
        );
        final localSettings = _singleResourceSettings(
          record['profileSettings'],
          restoreResourceIds.bySourceId,
        );
        await registry.stageRestoreResource(
          operationId: operationId,
          backupId: backupId,
          resourceId: resourceId,
          type: type,
          label: (record['label'] as String? ?? type.name).trim(),
          ownerProfileId: destinationProfileId,
          publicConfig: _publicConfig(type, record),
          sealedSecretPayload: sealed,
          secretPayloadVersion: 1,
          permissions: permissions,
          bindingSlot: _bindingSlot(type, backupId),
          profileEnabled: localSettings?.enabled,
          profileSettings: localSettings?.values,
          resourceEnabled: !(_optionalBool(record, 'disabled') ?? false),
        );
        imported++;
      }

      RestoreReport? followUp;
      final legacy = package.sections['legacyFollowUp'];
      if (legacy is Map) {
        followUp = await ProfileRuntime.withCapturedScope(
          stagingScope,
          () => IptvTransferPayload.withProviderIdOverrides(
            stagedIptvProviders,
            () => BackupRestoreService.applyBackup(
              Map<String, dynamic>.from(legacy),
              selection: const BackupSelection(
                realDebrid: false,
                torbox: false,
                premiumize: false,
                allDebrid: false,
                pikpak: false,
                trakt: false,
                simkl: false,
                searchEngines: false,
                addons: false,
                webDav: false,
                indexerManagers: false,
                iptvPlaylists: false,
                iptvFavorites: true,
                iptvLists: true,
                streamBadges: true,
                // Tracking prefs are profile-scoped plain prefs like the IPTV
                // favorites above — they ride the legacy follow-up, not the
                // staged-resource path, or a profile import silently resets
                // them to Smart/all/seeded defaults.
                trackingPreferences: true,
              ),
              refreshEngineRuntime: false,
            ),
          ),
        );
        if (followUp!.hasAnyFailure) {
          throw StateError('Legacy backup restore was incomplete');
        }
      }
      _verifyLegacyInventory(
        package: package,
        resourcesImported: imported,
        borrowedResourcesSkipped: borrowedSkipped,
        followUp: followUp,
      );

      staged = await generationManager.finalize(staged);

      if (restoringActive) {
        candidate = ProfileScope(
          profileId: destinationProfileId,
          dataGeneration: staged.generation,
          sessionEpoch: ProfileRuntime.nextEpoch,
        );
      }

      // Revalidate the captured role/policy/revision immediately before the
      // one visible-state transaction. The shared avatar queue stays held from
      // live-file installation through registry publication and pruning.
      await authorization.validate(registry);
      late final UserProfile publishedProfile;
      await ProfileAvatarMutation.runExclusive(destinationProfileId, () async {
        // Authorization must be revalidated after waiting in the avatar queue.
        // Any writer ahead of us increments the profile revision, preventing a
        // stale actor key from pruning its newly published file.
        await authorization.validate(registry);
        final mutationStarted = currentAvatar != null;
        if (mutationStarted) {
          await ProfileAvatarMutation.begin(
            destinationProfileId,
            actor.avatarKey!,
          );
        }
        try {
          if (avatarStageApplies) await avatarStage!.install();
          try {
            publishedProfile = await registry.publishDataGeneration(
              profileId: destinationProfileId,
              baseGeneration: staged.baseGeneration,
              stagedGeneration: staged.generation,
              operationId: operationId,
              // Publishing a new active generation changes the session epoch
              // and remounts AppInitializer immediately. An onboarding caller
              // must make completion visible in this same transaction so that
              // remounted initializer cannot observe `false` and push a second
              // onboarding route while restore follow-up work is still running.
              profileSetupComplete: completeOnboarding
                  ? true
                  : importedSetupComplete,
              profileLockOnResume: importedLockOnResume,
              updateInactivityTimeout: updateInactivityTimeout,
              profileInactivityTimeoutMinutes: importedInactivityTimeout,
            );
          } catch (error, stackTrace) {
            bool committed;
            try {
              committed = await registry.dataGenerationPublished(
                operationId: operationId,
                profileId: destinationProfileId,
                generation: staged.generation,
              );
            } catch (_) {
              publicationUncertain = true;
              Error.throwWithStackTrace(error, stackTrace);
            }
            if (!committed) Error.throwWithStackTrace(error, stackTrace);
            try {
              await registry.checkpointTvOsRecovery();
            } catch (_) {
              publicationUncertain = true;
              Error.throwWithStackTrace(error, stackTrace);
            }
            publishedProfile = (await registry.getProfile(
              destinationProfileId,
            ))!;
          }
          published = true;
          var cleanupComplete = true;
          try {
            if (avatarStageApplies) {
              await avatarStage!.finish();
            } else {
              await avatarStage?.rollback();
            }
          } catch (_) {
            cleanupComplete = false;
          }
          if (mutationStarted) {
            try {
              await ProfileAvatarIngest.commit(
                profileId: destinationProfileId,
                avatarKey: actor.avatarKey,
              );
            } catch (_) {
              cleanupComplete = false;
            }
            if (cleanupComplete) {
              try {
                await ProfileAvatarMutation.complete(destinationProfileId);
              } catch (_) {
                // A retained intent is safe and is cleared by bootstrap.
              }
            }
          }
        } catch (error, stackTrace) {
          if (!published && !publicationUncertain) {
            await avatarStage?.rollback();
            final currentProfile = await registry.getProfile(
              destinationProfileId,
            );
            if (mutationStarted) {
              await ProfileAvatarIngest.commit(
                profileId: destinationProfileId,
                avatarKey: currentProfile?.avatarKey,
              );
              await ProfileAvatarMutation.complete(destinationProfileId);
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      });
      if (restoringActive) {
        ProfileRuntime.publish(candidate!);
        // Global caches/controllers may only warm after registry and runtime
        // publish the candidate. A post-commit failure rolls forward below.
        for (final participant in lifecycleParticipants) {
          await participant.initializeCandidate(candidate);
        }
        await NativeProfileProjection.publish(candidate);
        for (final participant in lifecycleParticipants) {
          await participant.didActivate(candidate);
        }
      }

      try {
        await registry.markRestoreCleaned(operationId);
      } catch (_) {
        // A published restore is successful even if cleanup's recovery
        // checkpoint fails; its published journal is safe to replay.
      }
      final omissions = Map<String, dynamic>.from(package.omissions);
      if (legacy is Map) {
        final postScope = restoringActive
            ? candidate!
            : ProfileScope(
                profileId: destinationProfileId,
                dataGeneration: staged.generation,
                sessionEpoch: 0,
              );
        try {
          final networkReport = await ProfileRuntime.withCapturedScope(
            postScope,
            () => BackupRestoreService.applyBackup(
              Map<String, dynamic>.from(legacy),
              selection: const BackupSelection(
                realDebrid: false,
                torbox: false,
                premiumize: false,
                allDebrid: false,
                pikpak: false,
                trakt: false,
                simkl: false,
                searchEngines: true,
                addons: false,
                webDav: false,
                indexerManagers: false,
                iptvPlaylists: false,
                iptvFavorites: false,
                iptvLists: false,
                streamBadges: false,
              ),
              refreshEngineRuntime: restoringActive,
            ),
          );
          followUp ??= RestoreReport();
          followUp
            ..searchEnginesImported = networkReport.searchEnginesImported
            ..searchEnginesAlreadyPresent =
                networkReport.searchEnginesAlreadyPresent
            ..searchEnginesFailed = networkReport.searchEnginesFailed
            ..errors.addAll(networkReport.errors);
          if (networkReport.searchEnginesFailed > 0) {
            omissions['searchEngines'] = networkReport.searchEnginesFailed;
          }
        } catch (_) {
          final expected = _legacyInventoryCount(
            package,
            'searchEngineRecords',
          );
          if (expected > 0) omissions['searchEngines'] = expected;
        }
      }
      return ProfileRestoreReport(
        destinationProfileId: destinationProfileId,
        publishedGeneration: publishedProfile.visibleDataGeneration,
        preferencesApplied: values.length,
        resourcesImported: imported,
        borrowedResourcesSkipped: borrowedSkipped,
        omissions: omissions,
        legacyFollowUp: followUp,
      );
    } catch (_) {
      if (restoringActive) {
        final rollbackScope = published && candidate != null
            ? candidate
            : current;
        if (published && candidate != null) ProfileRuntime.publish(candidate);
        for (final participant in lifecycleParticipants.reversed) {
          try {
            await participant.rollback(rollbackScope);
          } catch (_) {
            // Preserve the original error. A published generation rolls
            // forward; an unpublished one restores the prior scope.
          }
        }
      }
      rethrow;
    }
  }

  static void _validatePreferenceOverlay(
    Map<String, Object?> values, {
    required bool includeCredentialEngineSettings,
  }) {
    for (final entry in values.entries) {
      if (entry.key.isEmpty ||
          entry.key.length > 256 ||
          !ProfilePreferencePortability.allowsKey(
            entry.key,
            includeCredentialEngineSettings: includeCredentialEngineSettings,
          )) {
        throw FormatException('Forbidden restored preference ${entry.key}');
      }
      final value = entry.value;
      if (value is! bool &&
          value is! num &&
          value is! String &&
          value is! List<String> &&
          value != null) {
        throw FormatException('Unsupported restored preference ${entry.key}');
      }
    }
  }

  static void _verifyLegacyInventory({
    required PortableProfilePackage package,
    required int resourcesImported,
    required int borrowedResourcesSkipped,
    required RestoreReport? followUp,
  }) {
    final raw = package.sections['legacyInventory'];
    if (raw == null) return;
    if (raw is! Map || raw['schemaVersion'] != 1) {
      throw const FormatException('Legacy restore inventory is malformed');
    }
    int count(String field) {
      final value = raw[field];
      if (value is! int || value < 0) {
        throw FormatException('Legacy restore inventory $field is malformed');
      }
      return value;
    }

    if (resourcesImported != count('resourceRecords') ||
        borrowedResourcesSkipped != 0) {
      throw StateError('Legacy resource inventory was not fully restored');
    }
    final report = followUp;
    final expectedFavorites = count('iptvFavoriteRecords');
    final expectedLists = count('iptvListRecords');
    final expectedListChannels = count('iptvListChannelRecords');
    if ((report == null &&
            expectedFavorites + expectedLists + expectedListChannels > 0) ||
        (report != null &&
            (report.iptvFavoritesImported +
                        report.iptvFavoritesAlreadyPresent !=
                    expectedFavorites ||
                report.iptvListsCreated + report.iptvListsMerged !=
                    expectedLists ||
                report.iptvListChannelsImported +
                        report.iptvListChannelsAlreadyPresent !=
                    expectedListChannels))) {
      throw StateError(
        'Legacy dependent-data inventory was not fully restored',
      );
    }
  }

  static int _legacyInventoryCount(
    PortableProfilePackage package,
    String field,
  ) {
    final raw = package.sections['legacyInventory'];
    if (raw is! Map) return 0;
    final value = raw[field];
    return value is int && value >= 0 ? value : 0;
  }

  static Future<int> _restoreDatabaseSection(
    PortableProfilePackage package,
    Map<String, dynamic> profileRecord,
    ProfileScope destination,
  ) async {
    final sectionId = profileRecord['databasesSection'];
    if (sectionId == null) return 0;
    if (sectionId is! String) {
      throw const FormatException('Invalid database section reference');
    }
    final section = package.sections[sectionId];
    if (section is! Map || section['values'] is! Map) {
      throw const FormatException('Database section is missing');
    }
    return ProfileDatabaseSnapshot.restore(
      destination,
      Map<Object?, Object?>.from(section['values'] as Map),
    );
  }

  static Future<int> _restoreFilesSection(
    PortableProfilePackage package,
    Map<String, dynamic> profileRecord,
    ProfileScope destination,
  ) async {
    final sectionId = profileRecord['filesSection'];
    if (sectionId == null) return 0;
    if (sectionId is! String) {
      throw const FormatException('Invalid portable files section reference');
    }
    final section = package.sections[sectionId];
    if (section is! Map || section['values'] is! Map) {
      throw const FormatException('Portable files section is missing');
    }
    return ProfilePortableFiles.restore(
      destination,
      Map<Object?, Object?>.from(section['values'] as Map),
    );
  }

  static Map<String, Object?> _normalizePreferenceValues(
    Map source, {
    Map<String, String> resourceIds = const <String, String>{},
    required bool includeCredentialEngineSettings,
    required bool rejectDisallowedKeys,
  }) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      if (entry.key is! String) {
        throw const FormatException('Preference key must be text');
      }
      final key = entry.key as String;
      if (!ProfilePreferencePortability.allowsKey(
        key,
        includeCredentialEngineSettings: includeCredentialEngineSettings,
      )) {
        // v3 used a narrower export filter, so authentic legacy packages may
        // contain cache, superseded resource, or device-local preferences
        // that v4 no longer permits. Drop those values exactly as a current
        // exporter would; an unexpected key in v4 remains a hard failure.
        if (rejectDisallowedKeys) {
          throw FormatException('Forbidden restored preference $key');
        }
        continue;
      }
      Object? value = entry.value;
      if (value is List) {
        if (value.any((item) => item is! String)) {
          throw FormatException('Invalid string list preference $key');
        }
        value = value.cast<String>().toList();
      }
      final prepared = ProfilePreferencePortability.prepareValue(
        key,
        value,
        includeCredentialEngineSettings: includeCredentialEngineSettings,
      );
      if (!prepared.include) continue;
      result[key] = _remapPreferenceValue(prepared.value, resourceIds);
    }
    return result;
  }

  static Object? _remapPreferenceValue(
    Object? value,
    Map<String, String> resourceIds,
  ) {
    if (resourceIds.isEmpty) return value;
    if (value is List<String>) {
      return value
          .map((item) => resourceIds[item] ?? item)
          .toList(growable: false);
    }
    if (value is! String) return value;
    final direct = resourceIds[value];
    if (direct != null) return direct;
    if (!resourceIds.keys.any(value.contains)) return value;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map || decoded is List) {
        return jsonEncode(_remapJsonValue(decoded, resourceIds));
      }
    } on FormatException {
      // Not a JSON-backed preference; exact-string replacement above was the
      // only safe interpretation.
    }
    return value;
  }

  static Object? _remapJsonValue(
    Object? value,
    Map<String, String> resourceIds,
  ) {
    if (value is String) return resourceIds[value] ?? value;
    if (value is List) {
      return value
          .map((item) => _remapJsonValue(item, resourceIds))
          .toList(growable: false);
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('JSON key must be text');
        }
        result[resourceIds[key] ?? key] = _remapJsonValue(
          entry.value,
          resourceIds,
        );
      }
      return result;
    }
    return value;
  }

  static Map<String, dynamic> _remapJsonMap(
    Map<String, dynamic> value,
    Map<String, String> resourceIds,
  ) => Map<String, dynamic>.from(_remapJsonValue(value, resourceIds)! as Map);

  static Map<String, dynamic> _normalizeResourceSettings(
    Map source,
    Map<String, String> resourceIds,
  ) {
    late final Map<String, dynamic> normalized;
    try {
      normalized = Map<String, dynamic>.from(
        _remapJsonValue(source, resourceIds)! as Map,
      );
      if (utf8.encode(jsonEncode(normalized)).length > 64 * 1024) {
        throw const FormatException('Imported resource settings are too large');
      }
    } on JsonUnsupportedObjectError {
      throw const FormatException('Invalid imported resource settings');
    }
    return normalized;
  }

  static ({bool enabled, Map<String, dynamic> values})? _singleResourceSettings(
    Object? raw,
    Map<String, String> resourceIds,
  ) {
    if (raw == null) return null;
    if (raw is! Map || raw['enabled'] is! bool || raw['values'] is! Map) {
      throw const FormatException('Invalid imported resource settings');
    }
    return (
      enabled: raw['enabled'] as bool,
      values: _normalizeResourceSettings(raw['values'] as Map, resourceIds),
    );
  }

  static ({Map<String, String> byBackupId, Map<String, String> bySourceId})
  _allocateResourceIds(
    List<Map<String, dynamic>> records, {
    required bool Function(Map<String, dynamic>) include,
  }) {
    final byBackupId = <String, String>{};
    final bySourceId = <String, String>{};
    for (final record in records.where(include)) {
      final backupId = record['backupId'];
      if (backupId is! String || backupId.isEmpty) {
        throw const FormatException('Invalid imported resource ID');
      }
      final destinationId = _newId('resource');
      if (byBackupId.putIfAbsent(backupId, () => destinationId) !=
          destinationId) {
        throw const FormatException('Duplicate imported resource ID');
      }
      final sourceId = record['sourceResourceId'];
      if (sourceId == null) continue; // Version-3 packages predating ID remap.
      if (sourceId is! String ||
          !ProfileScope.isValidProfileId(sourceId) ||
          bySourceId.putIfAbsent(sourceId, () => destinationId) !=
              destinationId) {
        throw const FormatException('Invalid source resource ID');
      }
    }
    return (byBackupId: byBackupId, bySourceId: bySourceId);
  }

  static bool? _optionalBool(Map<String, dynamic> record, String key) {
    if (!record.containsKey(key)) return null;
    final value = record[key];
    if (value is! bool) throw FormatException('Invalid imported $key');
    return value;
  }

  static int? _optionalInactivityTimeout(Map<String, dynamic> record) {
    if (!record.containsKey('inactivityTimeoutMinutes') ||
        record['inactivityTimeoutMinutes'] == null) {
      return null;
    }
    final value = record['inactivityTimeoutMinutes'];
    if (value is! int || !const <int>{5, 15, 30, 60}.contains(value)) {
      throw const FormatException('Invalid imported auto-lock interval');
    }
    return value;
  }

  static Future<bool> _writePreference(
    ProfilePreferences preferences,
    String key,
    Object? value,
  ) => switch (value) {
    bool value => preferences.setBool(key, value),
    int value => preferences.setInt(key, value),
    double value => preferences.setDouble(key, value),
    String value => preferences.setString(key, value),
    List<String> value => preferences.setStringList(key, value),
    null => preferences.remove(key),
    _ => throw FormatException('Unsupported imported preference $key'),
  };

  static Map<String, dynamic> _normalizeSecret(
    ConnectionResourceType type,
    Map<String, dynamic> input,
  ) {
    if (type == ConnectionResourceType.trakt) {
      return <String, dynamic>{
        'accessToken': input['accessToken'] ?? input['access_token'],
        'refreshToken': input['refreshToken'] ?? input['refresh_token'],
        'expiryMs': input['expiryMs'] ?? input['expiry_ms'],
        'username': input['username'],
      }..removeWhere((_, value) => value == null || value == '');
    }
    if (type == ConnectionResourceType.simkl) {
      return <String, dynamic>{
        'accessToken': input['accessToken'] ?? input['access_token'],
        'username': input['username'],
      }..removeWhere((_, value) => value == null || value == '');
    }
    // Nulls only, unlike the two shapes above. Those build a fixed record out
    // of genuinely optional fields, where an empty token means "absent". This
    // branch passes a provider's own record through, and there a structurally
    // required field can legitimately be empty — an Xtream provider stores
    // `url: ''` because its endpoint is `serverUrl`. Dropping it left the
    // sealed record missing a key its reader casts non-null, which threw for
    // the whole collection rather than the one entry.
    return input..removeWhere((_, value) => value == null);
  }

  /// Imported profiles are staged through the ordinary profile-creation API,
  /// which deliberately shares existing device resources by default. Keep
  /// that useful fallback for receiver-only addons, but remove an inherited
  /// default grant when the imported graph gives the same profile the exact
  /// same configured addon. Matching uses the full normalized manifest URL,
  /// including configuration/query data; names and manifest IDs are not
  /// unique enough to revoke a grant safely.
  Future<List<GraphRestoreDefaultGrantPrune>> _redundantDefaultAddonGrants({
    required ProfileAuthorizationContext authorization,
    required Map<String, Set<String>> importedIdentitiesByProfile,
  }) async {
    if (importedIdentitiesByProfile.isEmpty) {
      return const <GraphRestoreDefaultGrantPrune>[];
    }
    final defaultBorrowersByResource = <String, Set<String>>{};
    for (final grant in await registry.listAllResourceGrants()) {
      final profileId = grant['profile_id'];
      final resourceId = grant['resource_id'];
      if (profileId is! String ||
          resourceId is! String ||
          !importedIdentitiesByProfile.containsKey(profileId) ||
          !_isDefaultSeedGrant(grant['grant_origin_json'])) {
        continue;
      }
      defaultBorrowersByResource
          .putIfAbsent(resourceId, () => <String>{})
          .add(profileId);
    }
    if (defaultBorrowersByResource.isEmpty) {
      return const <GraphRestoreDefaultGrantPrune>[];
    }

    final service = ConnectionResourceService(
      registry: registry,
      cipher: cipher,
    );
    final result = <GraphRestoreDefaultGrantPrune>[];
    for (final resource in await registry.listAllResourcesIncludingDisabled()) {
      final borrowers = defaultBorrowersByResource[resource.id];
      if (borrowers == null ||
          resource.type != ConnectionResourceType.stremioAddon) {
        continue;
      }
      Map<String, dynamic> secret;
      try {
        secret = await service.revealSecretForDeviceBackup(
          context: authorization,
          resourceId: resource.id,
        );
      } catch (_) {
        // A malformed local addon must not make an otherwise valid restore
        // impossible. Revalidate separately so an authority change is never
        // mistaken for a harmless unreadable resource.
        await authorization.validate(registry);
        continue;
      }
      final identity = _stremioManifestIdentity(secret);
      if (identity == null) continue;
      for (final profileId in borrowers) {
        if (importedIdentitiesByProfile[profileId]!.contains(identity)) {
          result.add(
            GraphRestoreDefaultGrantPrune(
              profileId: profileId,
              resourceId: resource.id,
              expectedResourceAuthorizationRevision:
                  resource.authorizationRevision,
            ),
          );
        }
      }
    }
    await authorization.validate(registry);
    return result;
  }

  static String? _stremioManifestIdentity(Map<String, dynamic> secret) {
    final raw = secret['manifest_url'] ?? secret['manifestUrl'];
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final normalized = normalizeStremioManifestUri(raw);
      if (!normalized.hasScheme || !normalized.hasAuthority) return null;
      return normalized.toString();
    } on FormatException {
      return null;
    }
  }

  static bool _isDefaultSeedGrant(Object? encoded) {
    if (encoded is! String) return false;
    try {
      final value = jsonDecode(encoded);
      return value is Map && value['origin'] == 'defaultSeed';
    } on FormatException {
      return false;
    }
  }

  /// Whether [secret] carries nothing worth sealing.
  ///
  /// Deliberately not `Map.isEmpty`: the empty-value strip that used to make
  /// that test work is exactly what erased required fields. Testing the values
  /// keeps the "don't mint a resource from an empty record" rule without
  /// mutating the record to get it.
  static bool _hasNoUsableSecret(Map<String, dynamic> secret) =>
      secret.values.every((value) => value == null || value == '');

  static bool _importsSingleProfileResource(
    Map<String, dynamic> record, {
    required int sourceVersion,
  }) {
    if (record['owned'] != true || record['secretConfig'] is! Map) {
      return false;
    }
    if (sourceVersion >= PortableProfilePackage.version) return true;
    final typeName = record['type'];
    final matching = ConnectionResourceType.values.where(
      (value) => value.name == typeName,
    );
    // Preserve the existing explicit error for unknown resource types.
    if (matching.isEmpty) return true;
    final normalized = _normalizeSecret(
      matching.first,
      Map<String, dynamic>.from(record['secretConfig'] as Map),
    );
    return !_hasNoUsableSecret(normalized);
  }

  static Map<String, dynamic> _publicConfig(
    ConnectionResourceType type,
    Map<String, dynamic> record,
  ) {
    final raw = record['publicConfig'];
    final supplied = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final label = (record['label'] as String? ?? type.name).trim();
    final allowed = switch (type) {
      ConnectionResourceType.realDebrid ||
      ConnectionResourceType.torbox ||
      ConnectionResourceType.premiumize ||
      ConnectionResourceType.pikpak ||
      ConnectionResourceType.allDebrid => const <String>{
        'region',
        'accountLabel',
      },
      ConnectionResourceType.webDav => const <String>{'accountLabel'},
      ConnectionResourceType.trakt ||
      ConnectionResourceType.simkl ||
      ConnectionResourceType.mdblist ||
      ConnectionResourceType.reddit => const <String>{
        'accountLabel',
        'username',
      },
      ConnectionResourceType.iptvM3u ||
      ConnectionResourceType.iptvXtream ||
      ConnectionResourceType.xmltv => const <String>{
        'playlistName',
        'providerKind',
      },
      ConnectionResourceType.stremioAddon => const <String>{
        'addonName',
        'contentKinds',
      },
      ConnectionResourceType.jackett ||
      ConnectionResourceType.prowlarr => const <String>{'managerName'},
    };
    final result = <String, dynamic>{'schemaVersion': 1};
    for (final entry in supplied.entries) {
      if (allowed.contains(entry.key)) result[entry.key] = entry.value;
    }
    switch (type) {
      case ConnectionResourceType.iptvM3u:
      case ConnectionResourceType.iptvXtream:
      case ConnectionResourceType.xmltv:
        result.putIfAbsent('playlistName', () => label);
        result.putIfAbsent(
          'providerKind',
          () => type == ConnectionResourceType.iptvXtream ? 'xtream' : 'm3u',
        );
      case ConnectionResourceType.stremioAddon:
        result.putIfAbsent('addonName', () => label);
        result.putIfAbsent('contentKinds', () => const <String>[]);
      case ConnectionResourceType.jackett:
      case ConnectionResourceType.prowlarr:
        result.putIfAbsent('managerName', () => label);
      default:
        result.putIfAbsent('accountLabel', () => label);
    }
    return result;
  }

  static int _effectivePermissions(UserProfileRole role, int? requested) {
    final allowedMask = ResourcePermission.values.fold<int>(
      0,
      (mask, permission) => mask | permission.bit,
    );
    var permissions = requested ?? allowedMask;
    permissions &= allowedMask;
    if (role == UserProfileRole.child) {
      for (final denied in const <ResourcePermission>{
        ResourcePermission.writeRemote,
        ResourcePermission.manage,
        ResourcePermission.revealSecret,
        ResourcePermission.share,
      }) {
        permissions &= ~denied.bit;
      }
    }
    return permissions;
  }

  static String _bindingSlot(ConnectionResourceType type, String backupId) =>
      type.singletonCredentialBindingSlot ?? 'import.${type.name}.$backupId';

  /// Bounded parse of a carried PIN record. Mirrors the verifier's own
  /// sanity checks (32-byte hash, 8-64 byte salt, KDF params inside the safe
  /// envelope); the recovery trio is all-or-none. Returns null on ANY
  /// deviation — the caller falls back to admin-reset, never fails the
  /// restore.
  static ({
    List<int> hash,
    List<int> salt,
    String paramsJson,
    List<int>? recoveryHash,
    List<int>? recoverySalt,
    String? recoveryParamsJson,
  })?
  _parseCarriedPinRecord(Object? raw) {
    if (raw is! Map) return null;
    List<int>? decode(Object? value, int min, int max) {
      if (value is! String) return null;
      try {
        final bytes = base64Decode(value);
        if (bytes.length < min || bytes.length > max) return null;
        return bytes;
      } on FormatException {
        return null;
      }
    }

    String? boundedParams(Object? value) {
      if (value is! Map) return null;
      try {
        PinKdfParams.fromJson(Map<String, dynamic>.from(value));
      } catch (_) {
        return null;
      }
      return jsonEncode(value);
    }

    final hash = decode(raw['hash'], 32, 32);
    final salt = decode(raw['salt'], 8, 64);
    final paramsJson = boundedParams(raw['params']);
    if (hash == null || salt == null || paramsJson == null) return null;

    final hasRecovery =
        raw.containsKey('recoveryHash') ||
        raw.containsKey('recoverySalt') ||
        raw.containsKey('recoveryParams');
    List<int>? recoveryHash;
    List<int>? recoverySalt;
    String? recoveryParamsJson;
    if (hasRecovery) {
      recoveryHash = decode(raw['recoveryHash'], 32, 32);
      recoverySalt = decode(raw['recoverySalt'], 8, 64);
      recoveryParamsJson = boundedParams(raw['recoveryParams']);
      if (recoveryHash == null ||
          recoverySalt == null ||
          recoveryParamsJson == null) {
        // A broken recovery trio degrades to PIN-only rather than dropping
        // the whole carried credential.
        recoveryHash = null;
        recoverySalt = null;
        recoveryParamsJson = null;
      }
    }
    return (
      hash: hash,
      salt: salt,
      paramsJson: paramsJson,
      recoveryHash: recoveryHash,
      recoverySalt: recoverySalt,
      recoveryParamsJson: recoveryParamsJson,
    );
  }

  static String _newId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return '$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

class _ImportedProfile {
  final String id;
  final String name;
  final String? avatarKey;
  final UserProfileRole role;
  final ProfilePolicy policy;
  final bool setupComplete;
  final bool disabled;
  final bool wasPinProtected;
  final bool lockOnResume;
  final int? inactivityTimeoutMinutes;
  final Map<String, Object?> preferences;

  const _ImportedProfile({
    required this.id,
    required this.name,
    required this.avatarKey,
    required this.role,
    required this.policy,
    required this.setupComplete,
    required this.disabled,
    required this.wasPinProtected,
    required this.lockOnResume,
    required this.inactivityTimeoutMinutes,
    required this.preferences,
  });
}
