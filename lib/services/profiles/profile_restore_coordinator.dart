import 'dart:convert';
import 'dart:math';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/backup_restore_service.dart';
import '../../services/iptv_transfer_payload.dart';
import 'device_key_provider.dart';
import 'native_profile_projection.dart';
import 'portable_profile_package.dart';
import 'profile_authorization.dart';
import 'profile_data_generation.dart';
import 'profile_database_snapshot.dart';
import 'profile_lifecycle.dart';
import 'profile_portable_files.dart';
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

  const ProfileGraphRestoreReport({
    required this.profilesImported,
    required this.resourcesImported,
    required this.grantsImported,
    required this.bindingsImported,
    required this.pinResetsRequired,
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
      final values = _normalizePreferenceValues(section['values'] as Map);
      _validatePreferenceOverlay(values);
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
          setupComplete: record['setupComplete'] == true,
          disabled: record['disabled'] == true,
          wasPinProtected: record['wasPinProtected'] == true,
          preferences: values,
        ),
      );
    }

    await registry.beginProfileGraphRestore(
      operationId: operationId,
      stagedProfileIds: parsedProfiles.map((profile) => profile.id).toList(),
    );
    var published = false;
    try {
      for (final profile in parsedProfiles) {
        await registry.createProfile(
          id: profile.id,
          name: profile.name,
          avatarKey: profile.avatarKey,
          role: profile.role,
          policy: profile.policy,
          setupComplete: profile.setupComplete,
          disabled: profile.disabled,
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
        await _restoreDatabaseSection(
          package,
          package.profiles.singleWhere(
            (record) =>
                record['backupId'] ==
                profileIds.entries
                    .singleWhere((entry) => entry.value == profile.id)
                    .key,
          ),
          ProfileScope(
            profileId: profile.id,
            dataGeneration: 1,
            sessionEpoch: 0,
          ),
        );
        await _restoreFilesSection(
          package,
          package.profiles.singleWhere(
            (record) =>
                record['backupId'] ==
                profileIds.entries
                    .singleWhere((entry) => entry.value == profile.id)
                    .key,
          ),
          ProfileScope(
            profileId: profile.id,
            dataGeneration: 1,
            sessionEpoch: 0,
          ),
        );
        if (profile.wasPinProtected) {
          await registry.setPinRecord(
            profileId: profile.id,
            hash: null,
            salt: null,
            paramsJson: null,
            resetRequired: true,
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        }
      }

      var grantCount = 0;
      var bindingCount = 0;
      final stagedResources = <StagedGraphResource>[];
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
        final resourceId = _newId('resource');
        final secret = _normalizeSecret(
          type,
          Map<String, dynamic>.from(secretRecord),
        );
        if (secret.isEmpty) {
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
            grants: parsedGrants,
            bindings: parsedBindings,
          ),
        );
      }
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
      await registry.publishProfileGraphRestore(
        operationId: operationId,
        stagedProfileIds: parsedProfiles.map((profile) => profile.id).toList(),
        resources: stagedResources,
      );
      published = true;
      await registry.markRestoreCleaned(operationId);
      return ProfileGraphRestoreReport(
        profilesImported: parsedProfiles.length,
        resourcesImported: stagedResources.length,
        grantsImported: grantCount,
        bindingsImported: bindingCount,
        pinResetsRequired: parsedProfiles
            .where((profile) => profile.wasPinProtected)
            .length,
      );
    } catch (_) {
      if (!published) {
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

  Future<ProfileRestoreReport> restore({
    required PortableProfilePackage package,
    required String destinationProfileId,
    required ProfileAuthorizationContext authorization,
    bool replacePreferences = false,
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
    final sectionId = package.profiles.single['preferencesSection'];
    final section = package.sections[sectionId];
    if (section is! Map || section['values'] is! Map) {
      throw const FormatException('Profile preference section is missing');
    }
    final values = _normalizePreferenceValues(section['values'] as Map);
    _validatePreferenceOverlay(values);

    final operationId = _newId('restore');
    final current = ProfileRuntime.capture();
    final restoringActive = current.profileId == destinationProfileId;
    var published = false;
    ProfileScope? candidate;
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
      await _restoreDatabaseSection(
        package,
        package.profiles.single,
        stagingScope,
      );
      await _restoreFilesSection(
        package,
        package.profiles.single,
        stagingScope,
      );
      var imported = 0;
      var borrowedSkipped = 0;
      final stagedIptvProviders = <String, String>{};
      for (final record in package.resources) {
        if (record['owned'] != true || record['secretConfig'] is! Map) {
          borrowedSkipped++;
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
        final resourceId = _newId('resource');
        final secret = _normalizeSecret(
          type,
          Map<String, dynamic>.from(record['secretConfig'] as Map),
        );
        if (secret.isEmpty) continue;
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
        await registry.stageRestoreResource(
          operationId: operationId,
          backupId: record['backupId']! as String,
          resourceId: resourceId,
          type: type,
          label: (record['label'] as String? ?? type.name).trim(),
          ownerProfileId: destinationProfileId,
          publicConfig: _publicConfig(type, record),
          sealedSecretPayload: sealed,
          secretPayloadVersion: 1,
          permissions: permissions,
          bindingSlot: _bindingSlot(type, record['backupId']! as String),
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
      // one visible-state transaction.
      await authorization.validate(registry);
      final publishedProfile = await registry.publishDataGeneration(
        profileId: destinationProfileId,
        baseGeneration: staged.baseGeneration,
        stagedGeneration: staged.generation,
        operationId: operationId,
      );
      published = true;
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

      await registry.markRestoreCleaned(operationId);
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

  static void _validatePreferenceOverlay(Map<String, Object?> values) {
    for (final entry in values.entries) {
      if (entry.key.isEmpty ||
          entry.key.length > 256 ||
          _forbiddenPreference.hasMatch(entry.key)) {
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

  static Map<String, Object?> _normalizePreferenceValues(Map source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      if (entry.key is! String) {
        throw const FormatException('Preference key must be text');
      }
      final value = entry.value;
      if (value is List) {
        if (value.any((item) => item is! String)) {
          throw FormatException('Invalid string list preference ${entry.key}');
        }
        result[entry.key as String] = value.cast<String>().toList();
      } else {
        result[entry.key as String] = value;
      }
    }
    return result;
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
    return input..removeWhere((_, value) => value == null || value == '');
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

  static String _newId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return '$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  static final RegExp _forbiddenPreference = RegExp(
    r'(api.?key|password|access.?token|refresh.?token|credential|secret|'
    r'download_tree_uri|download_dir_path|custom_command|initial_setup)',
    caseSensitive: false,
  );
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
    required this.preferences,
  });
}
