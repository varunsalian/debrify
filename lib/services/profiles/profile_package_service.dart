import 'dart:convert';
import 'dart:io';

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

final class ProfileGraphPackageExport {
  const ProfileGraphPackageExport({
    required this.package,
    required this.profileBackupIdsByLocalId,
    required this.resourceBackupIdsByLocalId,
  });

  final PortableProfilePackage package;
  final Map<String, String> profileBackupIdsByLocalId;
  final Map<String, String> resourceBackupIdsByLocalId;
}

/// Additive hooks for the local archive exporter. When supplied, database
/// snapshots leave the package as file references instead of base64, and an
/// IPTV resource's imported M3U text leaves its secret record as an attachment
/// reference. Nothing else about the package changes; WebDAV and remote
/// callers never pass this.
final class ProfilePackageFileSinks {
  const ProfilePackageFileSinks({
    required this.databaseFile,
    required this.resourceContent,
    this.pruneRebuildableCaches = true,
  });

  /// Takes ownership of one finished snapshot file; returns the entry
  /// reference stored in the package record.
  final Future<String> Function(
    String profileBackupId,
    String databaseName,
    File snapshot, {
    required int bytes,
    required String sha256,
  })
  databaseFile;

  /// Stores one resource's imported M3U text; returns the reference record
  /// stored under `secretConfig.contentAttachment` in place of `content`.
  final Future<Map<String, Object?>> Function(
    String resourceBackupId,
    String content,
  )
  resourceContent;

  /// Drop rebuildable IPTV catalog/EPG caches from the snapshots. Debrify TV
  /// is never omitted on this path regardless of size.
  final bool pruneRebuildableCaches;

  /// Key that replaces `content` in an IPTV resource's secret record.
  static const String contentAttachmentKey = 'contentAttachment';

  /// Moves `secretConfig.content` into the attachment sink for resource
  /// types that carry imported playlist text. Other records are untouched.
  Future<void> externalizeContent(Map<String, dynamic> record) async {
    final secret = record['secretConfig'];
    if (secret is! Map) return;
    final content = secret['content'];
    if (content is! String || content.isEmpty) return;
    final backupId = record['backupId'];
    if (backupId is! String) return;
    final reference = await resourceContent(backupId, content);
    final replaced = Map<String, dynamic>.from(secret)
      ..remove('content')
      ..[contentAttachmentKey] = reference;
    record['secretConfig'] = replaced;
  }
}

class ProfilePackageService {
  final ProfileRegistry registry;
  final ConnectionResourceService resources;

  const ProfilePackageService({
    required this.registry,
    required this.resources,
  });

  /// Portable preference projection reused by recurring WebDAV hot sync.
  ///
  /// Backup restore deliberately retains explicit nulls so unsafe destination
  /// values can be cleared once. Recurring sync callers must drop those nulls
  /// and represent deletion only with tombstones.
  static Future<Map<String, Object?>> exportPortablePreferences(
    ProfileScope scope, {
    bool includeCredentialEngineSettings = true,
    bool dropNulls = false,
  }) async {
    final values = await _exportPreferences(
      scope,
      sanitized: false,
      includeCredentialEngineSettings: includeCredentialEngineSettings,
    );
    if (!dropNulls) return values;
    return <String, Object?>{
      for (final entry in values.entries)
        if (entry.value != null) entry.key: entry.value,
    };
  }

  Future<PortableProfilePackage> exportProfile({
    required ProfileAuthorizationContext context,
    required ProfileScope scope,
    required bool includeSecrets,
    required bool sanitized,
    bool compactDatabaseSnapshots = false,
    ProfilePackageFileSinks? fileSinks,
  }) async {
    if (fileSinks != null && (sanitized || !includeSecrets)) {
      throw ArgumentError('File-backed export requires a full profile export');
    }
    if (fileSinks != null && compactDatabaseSnapshots) {
      throw ArgumentError('File-backed export never compacts Debrify TV');
    }
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
            fileSink: fileSinks == null
                ? null
                : (name, snapshot, {required bytes, required sha256}) =>
                      fileSinks.databaseFile(
                        'profile-0',
                        name,
                        snapshot,
                        bytes: bytes,
                        sha256: sha256,
                      ),
            pruneRebuildableCaches:
                fileSinks != null && fileSinks.pruneRebuildableCaches,
          );
    final databaseSnapshots = databaseExport?.attachments ?? const {};
    final rebuildableCachesCompacted = databaseExport?.compacted
        .where((name) => name != ProfileDatabaseSnapshot.debrifyTvDatabaseName)
        .toList(growable: false);
    final debrifyTvOmission = databaseExport?.debrifyTvOmission;
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
          if (fileSinks != null) await fileSinks.externalizeContent(record);
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
          if (!sanitized)
            'createdAtMs': profile.createdAt.millisecondsSinceEpoch,
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
        if (rebuildableCachesCompacted?.isNotEmpty == true)
          'rebuildableDatabaseCachesOmitted': rebuildableCachesCompacted!.join(
            ', ',
          ),
        if (debrifyTvOmission?.isEmpty == false)
          DebrifyTvBackupOmission.key: debrifyTvOmission!.toJson(),
      },
    );
    await context.validate(registry);
    return package;
  }

  /// [compactDatabaseSnapshots] removes rebuildable IPTV catalog caches and
  /// omits Debrify TV channels together with their saved hash pools. Manual
  /// backup callers obtain explicit consent; WebDAV Sync also accepts these
  /// two named omissions when the automatic size fallback needs them and
  /// discloses that limitation on its setup page.
  Future<PortableProfilePackage> exportAllProfiles({
    required ProfileAuthorizationContext context,
    required bool includeSecrets,
    bool compactDatabaseSnapshots = false,
    bool includeDatabases = true,
    bool includePreferences = true,
    ProfilePackageFileSinks? fileSinks,
  }) async {
    if (fileSinks != null && compactDatabaseSnapshots) {
      throw ArgumentError('File-backed export never compacts Debrify TV');
    }
    return (await _exportAllProfiles(
      context: context,
      includeSecrets: includeSecrets,
      compactDatabaseSnapshots: compactDatabaseSnapshots,
      includeDatabases: includeDatabases,
      includePreferences: includePreferences,
      fileSinks: fileSinks,
    )).package;
  }

  /// Full graph export plus the local-to-backup identity correlation needed by
  /// WebDAV Sync. The optional projection rewrites resource IDs inside SQLite
  /// snapshots before they leave the device.
  Future<ProfileGraphPackageExport> exportAllProfilesForSync({
    required ProfileAuthorizationContext context,
    required Map<String, String> profileIdProjection,
    required Map<String, String> resourceIdProjection,
    required bool includeDatabases,
    required bool includePreferences,
  }) => _exportAllProfiles(
    context: context,
    includeSecrets: true,
    compactDatabaseSnapshots: false,
    includeDatabases: includeDatabases,
    includePreferences: includePreferences,
    profileIdProjection: profileIdProjection,
    resourceIdProjection: resourceIdProjection,
  );

  Future<ProfileGraphPackageExport> _exportAllProfiles({
    required ProfileAuthorizationContext context,
    required bool includeSecrets,
    required bool compactDatabaseSnapshots,
    required bool includeDatabases,
    required bool includePreferences,
    Map<String, String> profileIdProjection = const <String, String>{},
    Map<String, String> resourceIdProjection = const <String, String>{},
    ProfilePackageFileSinks? fileSinks,
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
    final profiles = (await registry.listProfiles(
      includeDisabled: true,
    )).toList(growable: false);
    _sortByProjectedIdentity(
      profiles,
      localId: (profile) => profile.id,
      projection: profileIdProjection,
      label: 'profile',
    );
    final profileBackupIds = <String, String>{};
    final profileRecords = <Map<String, dynamic>>[];
    final sections = <String, dynamic>{};
    final resourceBackupIds = <String, String>{};
    final compactedDatabases = <String>[];
    var debrifyTvOmission = const DebrifyTvBackupOmission.none();
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      final backupId = 'profile-$index';
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
        'createdAtMs': profile.createdAt.millisecondsSinceEpoch,
        'disabled': !profile.isEnabled,
        'lockOnResume': profile.lockOnResume,
        'inactivityTimeoutMinutes': profile.inactivityTimeoutMinutes,
        if (includePreferences) 'preferencesSection': '$backupId-preferences',
      });
      final scope = ProfileScope(
        profileId: profile.id,
        dataGeneration: profile.visibleDataGeneration,
        sessionEpoch: 0,
      );
      if (includePreferences) {
        sections['$backupId-preferences'] =
            await PortableProfilePackage.buildSection(
              await _exportPreferences(
                scope,
                sanitized: false,
                includeCredentialEngineSettings: true,
              ),
            );
      }
      if (includeDatabases) {
        final databaseExport = await ProfileDatabaseSnapshot.export(
          scope,
          compact: compactDatabaseSnapshots,
          resourceIdProjection: resourceIdProjection,
          fileSink: fileSinks == null
              ? null
              : (name, snapshot, {required bytes, required sha256}) =>
                    fileSinks.databaseFile(
                      backupId,
                      name,
                      snapshot,
                      bytes: bytes,
                      sha256: sha256,
                    ),
          pruneRebuildableCaches:
              fileSinks != null && fileSinks.pruneRebuildableCaches,
        );
        compactedDatabases.addAll(
          databaseExport.compacted
              .where(
                (entry) =>
                    entry != ProfileDatabaseSnapshot.debrifyTvDatabaseName,
              )
              .map((entry) => '${profile.name}: $entry'),
        );
        debrifyTvOmission += databaseExport.debrifyTvOmission;
        if (databaseExport.attachments.isNotEmpty) {
          final databaseSectionId = '$backupId-databases';
          profileRecords.last['databasesSection'] = databaseSectionId;
          sections[databaseSectionId] =
              await PortableProfilePackage.buildSection(
                databaseExport.attachments,
              );
        }
      }
      final portableFiles = await ProfilePortableFiles.export(scope);
      if (portableFiles.isNotEmpty) {
        final orderedPortableFiles = Map<String, Object?>.fromEntries(
          portableFiles.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)),
        );
        final filesSectionId = '$backupId-files';
        profileRecords.last['filesSection'] = filesSectionId;
        sections[filesSectionId] = await PortableProfilePackage.buildSection(
          orderedPortableFiles,
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
    final allResources = (await registry.listAllResourcesIncludingDisabled())
        .toList(growable: false);
    _sortByProjectedIdentity(
      allResources,
      localId: (resource) => resource.id,
      projection: resourceIdProjection,
      label: 'resource',
    );
    for (var index = 0; index < allResources.length; index++) {
      final resource = allResources[index];
      final ownerBackupId = profileBackupIds[resource.ownerProfileId];
      if (ownerBackupId == null) continue;
      final backupId = 'resource-$index';
      resourceBackupIds[resource.id] = backupId;
      final resourceGrants = <Map<String, dynamic>>[
        for (final grant in grants)
          if (grant['resource_id'] == resource.id &&
              profileBackupIds[grant['profile_id']] != null)
            <String, dynamic>{
              'profileBackupId': profileBackupIds[grant['profile_id']]!,
              'permissions': grant['permissions'],
            },
      ]..sort(_compareProfileReferences);
      final resourceBindings = <Map<String, dynamic>>[
        for (final binding in bindings)
          if (binding['resource_id'] == resource.id &&
              profileBackupIds[binding['profile_id']] != null)
            <String, dynamic>{
              'profileBackupId': profileBackupIds[binding['profile_id']]!,
              'slot': binding['slot'],
            },
      ]..sort(_compareProfileReferences);
      final resourceSettings = <Map<String, dynamic>>[
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
      ]..sort(_compareProfileReferences);
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
        'grants': resourceGrants,
        'bindings': resourceBindings,
        'profileSettings': resourceSettings,
      });
      if (fileSinks != null) {
        await fileSinks.externalizeContent(resourceRecords.last);
      }
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
        if (!debrifyTvOmission.isEmpty)
          DebrifyTvBackupOmission.key: debrifyTvOmission.toJson(),
      },
    );
    await context.validate(registry);
    return ProfileGraphPackageExport(
      package: package,
      profileBackupIdsByLocalId: Map<String, String>.unmodifiable(
        profileBackupIds,
      ),
      resourceBackupIdsByLocalId: Map<String, String>.unmodifiable(
        resourceBackupIds,
      ),
    );
  }

  static void _sortByProjectedIdentity<T>(
    List<T> values, {
    required String Function(T value) localId,
    required Map<String, String> projection,
    required String label,
  }) {
    if (projection.isEmpty && values.isEmpty) return;
    if (projection.length != values.length ||
        values.any((value) => !projection.containsKey(localId(value)))) {
      if (projection.isNotEmpty) {
        throw StateError(
          'WebDAV sync $label identity projection is incomplete',
        );
      }
      return;
    }
    values.sort(
      (left, right) =>
          projection[localId(left)]!.compareTo(projection[localId(right)]!),
    );
  }

  static int _compareProfileReferences(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final byProfile = (left['profileBackupId'] as String).compareTo(
      right['profileBackupId'] as String,
    );
    if (byProfile != 0) return byProfile;
    return (left['slot'] as String? ?? '').compareTo(
      right['slot'] as String? ?? '',
    );
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
    final physicalKeys =
        raw
            .getKeys()
            .where((key) => key.startsWith(scope.preferencePrefix))
            .toList()
          ..sort();
    for (final physical in physicalKeys) {
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
