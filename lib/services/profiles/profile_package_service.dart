import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profiles/profile_policy.dart';
import 'connection_resource_service.dart';
import 'profile_authorization.dart';
import 'profile_database_snapshot.dart';
import 'profile_portable_files.dart';
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
  }) async {
    final profile = await context.validate(registry);
    if (profile.id != scope.profileId) {
      throw StateError('Export scope does not match authorization');
    }
    if (!profile.allows(ProfileFeature.backupRestore)) {
      throw StateError('Profile is not allowed to export backups');
    }
    final preferences = await _exportPreferences(scope, sanitized: sanitized);
    final databaseExport = sanitized
        ? null
        : await ProfileDatabaseSnapshot.export(scope);
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
      final granted = await registry.listGrantedResources(profile.id);
      for (var index = 0; index < granted.length; index++) {
        final resource = granted[index];
        final grant = await registry.getGrant(profile.id, resource.id);
        if (grant == null) continue;
        if (resource.ownerProfileId != profile.id) {
          borrowedResourcesOmitted++;
          continue;
        }
        final record = <String, dynamic>{
          'backupId': 'resource-$index',
          'type': resource.type.name,
          'label': resource.label,
          'owned': true,
          'publicConfig': resource.publicConfig,
          'permissions': grant.permissions,
        };
        if (includeSecrets) {
          record['secretConfig'] = await resources.revealSecret(
            context: context,
            resourceId: resource.id,
            feature: ProfileFeature.backupRestore,
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
          if (!sanitized) 'wasPinProtected': profile.hasPin,
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
        'downloadsAndRecordings': true,
        'activeJobsAndSchedules': true,
        'devicePathsAndGrants': true,
        'remoteIdentityAndPeers': true,
        'pinsAndLockout': true,
        'cachesAndTransientEpg': true,
        if (borrowedResourcesOmitted > 0)
          'borrowedConnections': borrowedResourcesOmitted,
        if (databaseExport != null && databaseExport.skipped.isNotEmpty)
          'libraryDatabasesTooLarge': databaseExport.skipped.join(', '),
      },
    );
    await context.validate(registry);
    return package;
  }

  Future<PortableProfilePackage> exportAllProfiles({
    required ProfileAuthorizationContext context,
    required bool includeSecrets,
  }) async {
    final actor = await context.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('Comprehensive backup requires an Admin');
    }
    if (!includeSecrets) {
      throw StateError('Comprehensive backups must be passphrase encrypted');
    }
    final profiles = await registry.listProfiles(includeDisabled: true);
    final profileBackupIds = <String, String>{};
    final profileRecords = <Map<String, dynamic>>[];
    final sections = <String, dynamic>{};
    final skippedDatabases = <String>[];
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      final backupId = 'profile-$index';
      final sectionId = '$backupId-preferences';
      profileBackupIds[profile.id] = backupId;
      profileRecords.add(<String, dynamic>{
        'backupId': backupId,
        'name': profile.name,
        'avatarKey': profile.avatarKey,
        'role': profile.role.name,
        'policy': profile.policy.encode(),
        'wasPinProtected': profile.hasPin || profile.pinResetRequired,
        'setupComplete': profile.setupComplete,
        'disabled': !profile.isEnabled,
        'preferencesSection': sectionId,
      });
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: 0,
      );
      sections[sectionId] = await PortableProfilePackage.buildSection(
        await _exportPreferences(scope, sanitized: false),
      );
      final databaseExport = await ProfileDatabaseSnapshot.export(scope);
      skippedDatabases.addAll(
        databaseExport.skipped.map((entry) => '${profile.name}: $entry'),
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
    final resourceRecords = <Map<String, dynamic>>[];
    final allResources = await registry.listAllResources();
    for (var index = 0; index < allResources.length; index++) {
      final resource = allResources[index];
      final ownerBackupId = profileBackupIds[resource.ownerProfileId];
      if (ownerBackupId == null) continue;
      final backupId = 'resource-$index';
      resourceRecords.add(<String, dynamic>{
        'backupId': backupId,
        'type': resource.type.name,
        'label': resource.label,
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
        'devicePathsAndOsGrants': true,
        'remoteIdentityAndPeers': true,
        'pinHashesAndLockout': true,
        'deviceKeysAndExecutables': true,
        'cachesAndTransientEpg': true,
        if (skippedDatabases.isNotEmpty)
          'libraryDatabasesTooLarge': skippedDatabases.join(', '),
      },
    );
    await context.validate(registry);
    return package;
  }

  static Future<Map<String, Object?>> _exportPreferences(
    ProfileScope scope, {
    required bool sanitized,
  }) async {
    final raw = await SharedPreferences.getInstance();
    final preferences = <String, Object?>{};
    for (final physical in raw.getKeys()) {
      if (!physical.startsWith(scope.preferencePrefix)) continue;
      final logical = physical.substring(scope.preferencePrefix.length);
      final value = raw.get(physical);
      if (sanitized
          ? !SanitizedProfilePreferences.allowsEntry(logical, value)
          : _excludedPreference(logical)) {
        continue;
      }
      if (value is bool ||
          value is num ||
          value is String ||
          value is List<String>) {
        preferences[logical] = value;
      }
    }
    return preferences;
  }

  static bool _excludedPreference(String key) =>
      _credentialPattern.hasMatch(key) ||
      key.startsWith('remote_') ||
      key.contains('download_tree_uri') ||
      key.contains('download_dir_path') ||
      key.contains('external_player_custom') ||
      key.contains('custom_command') ||
      key == 'initial_setup_complete_v1';

  static final RegExp _credentialPattern = RegExp(
    r'(api.?key|password|access.?token|refresh.?token|credential|secret|url)',
    caseSensitive: false,
  );
}
