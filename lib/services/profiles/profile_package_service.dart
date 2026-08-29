import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profiles/profile_policy.dart';
import 'connection_resource_service.dart';
import 'profile_authorization.dart';
import 'profile_database_snapshot.dart';
import 'profile_portable_files.dart';
import 'profile_preference_portability.dart';
import 'profile_registry.dart';
import 'profile_scope.dart';
import 'portable_profile_package.dart';
import 'sanitized_profile_preferences.dart';

class ProfilePackageService {
  final ProfileRegistry registry;
  final ConnectionResourceService resources;

  const ProfilePackageService({
    required this.registry,
    required this.resources,
  });

  Future<PortableProfilePackage> exportProfile({
    required ProfileAuthorizationContext context,
    required ProfileScope scope,
    required bool includeSecrets,
    required bool sanitized,
    bool compactDatabaseSnapshots = false,
  }) async {
    final profile = await context.validate(registry);
    if (profile.id != scope.profileId) {
      throw StateError('Export scope does not match authorization');
    }
    if (!profile.allows(ProfileFeature.backupRestore)) {
      throw StateError('Profile is not allowed to export backups');
    }
    final preferences = await _exportPreferences(
      scope,
      sanitized: sanitized,
      includeCredentialEngineSettings: includeSecrets,
    );
    final pinRecord = sanitized ? null : await _exportPinRecord(profile.id);
    final databaseExport = sanitized
        ? null
        : await ProfileDatabaseSnapshot.export(
            scope,
            compact: compactDatabaseSnapshots,
          );
    final databaseSnapshots = databaseExport?.attachments ?? const {};
    final portableFiles = sanitized
        ? const <String, Object?>{}
        : await ProfilePortableFiles.export(scope);
    final portableAvatar = sanitized
        ? null
        : await ProfilePortableFiles.exportAvatar(scope, profile.avatarKey);

    final exportedResources = <Map<String, dynamic>>[];
    var borrowedResourcesOmitted = 0;
    if (!sanitized) {
      final granted = await registry.listGrantedResourcesIncludingDisabled(
        profile.id,
      );
      for (var index = 0; index < granted.length; index++) {
        final resource = granted[index];
        if (resource.ownerProfileId != profile.id) {
          borrowedResourcesOmitted++;
          continue;
        }
        // Borrowed resources are never included in a single-profile package,
        // so a concurrent borrower revoke is irrelevant. Owned resources are
        // different: losing their owner grant means the graph changed and the
        // backup must restart rather than silently claim completeness.
        final grant = await registry.getGrant(profile.id, resource.id);
        if (grant == null) {
          throw StateError('Connection grant changed during backup');
        }
        final record = <String, dynamic>{
          'backupId': 'resource-$index',
          'sourceResourceId': resource.id,
          'type': resource.type.name,
          'label': resource.label,
          'owned': true,
          'disabled': !resource.enabled,
          'publicConfig': resource.publicConfig,
          'permissions': grant.permissions,
        };
        final localSettings = await registry.getProfileResourceSettings(
          profile.id,
          resource.id,
        );
        if (localSettings != null) {
          record['profileSettings'] = <String, dynamic>{
            'enabled': localSettings.enabled,
            'values': localSettings.settings,
          };
        }
        if (includeSecrets) {
          record['secretConfig'] = await resources
              .revealOwnedSecretForProfileBackup(
                context: context,
                resourceId: resource.id,
              );
        }
        exportedResources.add(record);
      }
    }

    final package = PortableProfilePackage(
      mode: sanitized ? 'sanitizedSettings' : 'singleProfile',
      createdAt: DateTime.now().toUtc(),
      profiles: <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'profile-0',
          if (!sanitized) 'name': profile.name,
          if (!sanitized) 'avatarKey': profile.avatarKey,
          if (!sanitized) 'role': profile.role.name,
          if (!sanitized) 'policy': profile.policy.encode(),
          if (!sanitized)
            'wasPinProtected': profile.hasPin || profile.pinResetRequired,
          if (!sanitized) 'setupComplete': profile.setupComplete,
          if (!sanitized) 'lockOnResume': profile.lockOnResume,
          if (!sanitized)
            'inactivityTimeoutMinutes': profile.inactivityTimeoutMinutes,
          if (pinRecord != null) 'pinRecord': pinRecord,
          if (portableAvatar != null) 'avatarFile': portableAvatar,
          'preferencesSection': 'profile-0-preferences',
          if (databaseSnapshots.isNotEmpty)
            'databasesSection': 'profile-0-databases',
          if (portableFiles.isNotEmpty) 'filesSection': 'profile-0-files',
        },
      ],
      resources: exportedResources,
      sections: <String, dynamic>{
        'profile-0-preferences': await PortableProfilePackage.buildSection(
          preferences,
        ),
        if (databaseSnapshots.isNotEmpty)
          'profile-0-databases': await PortableProfilePackage.buildSection(
            databaseSnapshots,
          ),
        if (portableFiles.isNotEmpty)
          'profile-0-files': await PortableProfilePackage.buildSection(
            portableFiles,
          ),
      },
      omissions: <String, dynamic>{
        'downloadAndRecordingBinaries': true,
        'activeJobsAndSchedules': true,
        'deviceWidePreferencesAndRuntimeState': true,
        'devicePathsOsGrantsAndImportedFonts': true,
        'remoteIdentityAndPeers': true,
        'destinationNameAvatarRolePolicyPinAndEnabledState': true,
        'pinAttemptCountersAndLockout': true,
        'deviceKeysExecutablesCommandsAndCustomSchemes': true,
        'localFilesystemBindingsAndResolvedPlaybackSources': true,
        'transientPreferenceAndFileCaches': true,
        if (borrowedResourcesOmitted > 0)
          'borrowedConnections': borrowedResourcesOmitted,
        if (databaseExport != null && databaseExport.compacted.isNotEmpty)
          'rebuildableDatabaseCachesOmitted': databaseExport.compacted.join(
            ', ',
          ),
      },
    );
    await context.validate(registry);
    return package;
  }

  /// [compactDatabaseSnapshots] removes only rebuildable caches while retaining
  /// every durable library row. It is used when a remote graph would otherwise
  /// exceed the transport budget.
  Future<PortableProfilePackage> exportAllProfiles({
    required ProfileAuthorizationContext context,
    required bool includeSecrets,
    bool compactDatabaseSnapshots = false,
  }) async {
    final actor = await context.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('Comprehensive backup requires an Admin');
    }
    if (!includeSecrets) {
      throw StateError('Comprehensive backups must include connection secrets');
    }
    final profiles = await registry.listProfiles(includeDisabled: true);
    final profileBackupIds = <String, String>{};
    final profileRecords = <Map<String, dynamic>>[];
    final sections = <String, dynamic>{};
    final compactedDatabases = <String>[];
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      final backupId = 'profile-$index';
      final sectionId = '$backupId-preferences';
      profileBackupIds[profile.id] = backupId;
      final pinRecord = await _exportPinRecord(
        profile.id,
        includeDisabled: true,
      );
      profileRecords.add(<String, dynamic>{
        'backupId': backupId,
        'name': profile.name,
        'avatarKey': profile.avatarKey,
        'role': profile.role.name,
        'policy': profile.policy.encode(),
        'wasPinProtected': profile.hasPin || profile.pinResetRequired,
        if (pinRecord != null) 'pinRecord': pinRecord,
        'setupComplete': profile.setupComplete,
        'disabled': !profile.isEnabled,
        'lockOnResume': profile.lockOnResume,
        'inactivityTimeoutMinutes': profile.inactivityTimeoutMinutes,
        'preferencesSection': sectionId,
      });
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: 0,
      );
      sections[sectionId] = await PortableProfilePackage.buildSection(
        await _exportPreferences(
          scope,
          sanitized: false,
          includeCredentialEngineSettings: true,
        ),
      );
      final databaseExport = await ProfileDatabaseSnapshot.export(
        scope,
        compact: compactDatabaseSnapshots,
      );
      compactedDatabases.addAll(
        databaseExport.compacted.map((entry) => '${profile.name}: $entry'),
      );
      if (databaseExport.attachments.isNotEmpty) {
        final databaseSectionId = '$backupId-databases';
        profileRecords.last['databasesSection'] = databaseSectionId;
        sections[databaseSectionId] = await PortableProfilePackage.buildSection(
          databaseExport.attachments,
        );
      }
      final portableFiles = await ProfilePortableFiles.export(scope);
      if (portableFiles.isNotEmpty) {
        final filesSectionId = '$backupId-files';
        profileRecords.last['filesSection'] = filesSectionId;
        sections[filesSectionId] = await PortableProfilePackage.buildSection(
          portableFiles,
        );
      }
      final portableAvatar = await ProfilePortableFiles.exportAvatar(
        scope,
        profile.avatarKey,
      );
      if (portableAvatar != null) {
        profileRecords.last['avatarFile'] = portableAvatar;
      }
    }

    final grants = await registry.listAllResourceGrants();
    final bindings = await registry.listAllResourceBindings();
    final profileSettings = await registry.listAllResourceSettings();
    final resourceRecords = <Map<String, dynamic>>[];
    final allResources = await registry.listAllResourcesIncludingDisabled();
    for (var index = 0; index < allResources.length; index++) {
      final resource = allResources[index];
      final ownerBackupId = profileBackupIds[resource.ownerProfileId];
      if (ownerBackupId == null) continue;
      final backupId = 'resource-$index';
      resourceRecords.add(<String, dynamic>{
        'backupId': backupId,
        'sourceResourceId': resource.id,
        'type': resource.type.name,
        'label': resource.label,
        'disabled': !resource.enabled,
        'ownerProfileBackupId': ownerBackupId,
        'publicConfig': resource.publicConfig,
        'secretConfig': await resources.revealSecretForDeviceBackup(
          context: context,
          resourceId: resource.id,
        ),
        'grants': <Map<String, dynamic>>[
          for (final grant in grants)
            if (grant['resource_id'] == resource.id &&
                profileBackupIds[grant['profile_id']] != null)
              <String, dynamic>{
                'profileBackupId': profileBackupIds[grant['profile_id']]!,
                'permissions': grant['permissions'],
              },
        ],
        'bindings': <Map<String, dynamic>>[
          for (final binding in bindings)
            if (binding['resource_id'] == resource.id &&
                profileBackupIds[binding['profile_id']] != null)
              <String, dynamic>{
                'profileBackupId': profileBackupIds[binding['profile_id']]!,
                'slot': binding['slot'],
              },
        ],
        'profileSettings': <Map<String, dynamic>>[
          for (final settings in profileSettings)
            if (settings['resource_id'] == resource.id &&
                profileBackupIds[settings['profile_id']] != null)
              <String, dynamic>{
                'profileBackupId': profileBackupIds[settings['profile_id']]!,
                'enabled': settings['enabled'] == 1,
                'values': Map<String, dynamic>.from(
                  jsonDecode(settings['settings_json']! as String) as Map,
                ),
              },
        ],
      });
    }
    final package = PortableProfilePackage(
      mode: 'deviceGraph',
      createdAt: DateTime.now().toUtc(),
      profiles: profileRecords,
      resources: resourceRecords,
      sections: sections,
      omissions: <String, dynamic>{
        'downloadAndRecordingBinaries': true,
        'activeJobsAndSchedules': true,
        'deviceWidePreferencesAndRuntimeState': true,
        'devicePathsAndOsGrants': true,
        'remoteIdentityAndPeers': true,
        'pinAttemptCountersAndLockout': true,
        'deviceKeysExecutablesCommandsAndCustomSchemes': true,
        'localFilesystemBindingsAndResolvedPlaybackSources': true,
        'transientPreferenceAndFileCaches': true,
        if (compactedDatabases.isNotEmpty)
          'rebuildableDatabaseCachesOmitted': compactedDatabases.join(', '),
      },
    );
    await context.validate(registry);
    return package;
  }

  /// PIN hashes travel with the profile (product call 2026-08-17: restored
  /// profiles keep their PINs instead of arriving locked behind an Admin
  /// reset). Only ever hashes — the clear PIN does not exist anywhere — and
  /// only in non-sanitized packages, which are passphrase-encrypted by
  /// construction. The reset flag deliberately does NOT travel: a backup
  /// predating a lockdown must not undo it, and one taken during it carries
  /// no hash at all.
  Future<Map<String, Object?>?> _exportPinRecord(
    String profileId, {
    bool includeDisabled = false,
  }) async {
    final record = await registry.getPinRecord(
      profileId,
      includeDisabled: includeDisabled,
    );
    if (record == null || !record.hasPin || record.resetRequired) return null;
    try {
      return <String, Object?>{
        'hash': base64Encode(record.hash!),
        'salt': base64Encode(record.salt!),
        'params': jsonDecode(record.paramsJson!),
        if (record.hasRecoveryCode) ...<String, Object?>{
          'recoveryHash': base64Encode(record.recoveryHash!),
          'recoverySalt': base64Encode(record.recoverySalt!),
          'recoveryParams': jsonDecode(record.recoveryParamsJson!),
        },
      };
    } on FormatException {
      // Locally corrupt params — the same state verify() survives by
      // degrading to admin reset. The PIN just doesn't travel; the backup
      // itself must never fail over it.
      return null;
    }
  }

  static Future<Map<String, Object?>> _exportPreferences(
    ProfileScope scope, {
    required bool sanitized,
    required bool includeCredentialEngineSettings,
  }) async {
    final raw = await SharedPreferences.getInstance();
    final preferences = <String, Object?>{};
    for (final physical in raw.getKeys()) {
      if (!physical.startsWith(scope.preferencePrefix)) continue;
      final logical = physical.substring(scope.preferencePrefix.length);
      final value = raw.get(physical);
      if (sanitized
          ? !SanitizedProfilePreferences.allowsEntry(logical, value)
          : !ProfilePreferencePortability.allowsKey(
              logical,
              includeCredentialEngineSettings: includeCredentialEngineSettings,
            )) {
        continue;
      }
      final prepared = sanitized
          ? (include: true, value: value)
          : ProfilePreferencePortability.prepareValue(
              logical,
              value,
              includeCredentialEngineSettings: includeCredentialEngineSettings,
            );
      final portable = prepared.value;
      if (prepared.include &&
          (portable == null ||
              portable is bool ||
              portable is num ||
              portable is String ||
              portable is List<String>)) {
        preferences[logical] = portable;
      }
    }
    return preferences;
  }
}
