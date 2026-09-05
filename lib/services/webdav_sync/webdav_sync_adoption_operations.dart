import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_cleanup_ledger.dart';
import '../profiles/profile_data_generation.dart';
import '../profiles/profile_database_snapshot.dart';
import '../profiles/profile_database_adoption_gate.dart';
import '../profiles/profile_lifecycle.dart';
import '../profiles/profile_preference_budget.dart';
import '../profiles/portable_profile_package.dart';
import '../profiles/profile_registry.dart';
import '../profiles/profile_restore_coordinator.dart';
import '../profiles/profile_scope.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_models.dart';

typedef WebDavSyncImportedAdminUnlock =
    Future<bool> Function(UserProfile target);

/// Production implementation of the destructive tail. It deliberately uses
/// the same lifecycle and deletion APIs as the profile UI so database drains,
/// authorization revision changes, and filesystem cleanup retain one source
/// of truth.
final class DefaultWebDavSyncAdoptionOperations
    implements WebDavSyncAdoptionOperations {
  const DefaultWebDavSyncAdoptionOperations({
    required this.registry,
    required this.restoreCoordinator,
    required this.lifecycleCoordinator,
    this.unlockImportedAdmin,
  });

  final ProfileRegistry registry;
  final ProfileRestoreCoordinator restoreCoordinator;
  final ProfileLifecycleCoordinator lifecycleCoordinator;
  final WebDavSyncImportedAdminUnlock? unlockImportedAdmin;

  @override
  Future<Set<String>> listProfileIds() async => (await registry.listProfiles(
    includeDisabled: true,
  )).map((profile) => profile.id).toSet();

  @override
  Future<String> activeProfileId() async =>
      await registry.getActiveProfileId() ??
      (throw StateError('Active profile is unavailable'));

  @override
  Future<ProfileGraphRestoreReport> restoreGraph({
    required PortableProfilePackage package,
    required ProfileAuthorizationContext authorization,
  }) => restoreCoordinator.restoreDeviceGraph(
    package: package,
    authorization: authorization,
  );

  @override
  Future<String> selectTargetAdmin(Set<String> importedProfileIds) async {
    final candidates = <UserProfile>[];
    for (final id in importedProfileIds) {
      final profile = await registry.getProfile(id);
      if (profile != null &&
          profile.isEnabled &&
          profile.isAdmin &&
          profile.allows(ProfileFeature.manageProfiles) &&
          profile.allows(ProfileFeature.backupRestore) &&
          !profile.pinResetRequired) {
        candidates.add(profile);
      }
    }
    candidates.sort((left, right) {
      final byPin = (left.hasPin ? 1 : 0).compareTo(right.hasPin ? 1 : 0);
      return byPin != 0 ? byPin : left.id.compareTo(right.id);
    });
    if (candidates.isEmpty) {
      throw StateError('The imported graph has no usable Admin profile');
    }
    return candidates.first.id;
  }

  @override
  Future<void> copyDatabases({
    required String oldProfileId,
    required String newProfileId,
  }) async {
    final oldScope = await _scope(oldProfileId);
    final newScope = await _scope(newProfileId);
    final documents = await AppStorage.documents();
    for (final name in ProfileDatabaseSnapshot.databaseNames.toList()..sort()) {
      final source = oldScope.fileIn(documents, 'documents', name);
      if (!await source.exists()) continue;
      final destination = newScope.fileIn(documents, 'documents', name);
      await _copyDatabaseAtomically(source, destination, name);
    }
  }

  @override
  Future<void> remapDatabases({
    required String newProfileId,
    required Map<String, String> oldToNewResources,
  }) async {
    await ProfileDatabaseSnapshot.remapResourceReferences(
      await _scope(newProfileId),
      oldToNewResources,
    );
  }

  @override
  Future<void> carryLocalState({
    required String oldProfileId,
    required String newProfileId,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  }) async {
    final oldScope = await _scope(oldProfileId);
    final newScope = await _scope(newProfileId);
    await _carryPreferences(
      oldScope,
      newScope,
      oldToNewResources,
      unmappedOldResourceIds,
    );
    await _carryFiles(oldScope, newScope);
  }

  @override
  Future<void> preflightLocalStateCarry({
    required Map<String, String> oldToNewProfiles,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  }) async {
    if (!ProfilePreferenceBudget.enforced || oldToNewProfiles.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final plannedTargets = prefs.getKeys().toSet();
    var projectedBytes = ProfilePreferenceBudget.measure(prefs);
    final pairs = oldToNewProfiles.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final pair in pairs) {
      final source = await _scope(pair.key);
      final destination = await _scope(pair.value);
      final sourceKeys =
          prefs
              .getKeys()
              .where((key) => key.startsWith(source.preferencePrefix))
              .toList()
            ..sort();
      for (final physical in sourceKeys) {
        final logical = physical.substring(source.preferencePrefix.length);
        final target = destination.preferenceKey(logical);
        if (!plannedTargets.add(target)) continue;
        final value = _projectPreference(
          prefs.get(physical),
          oldToNewResources,
          unmappedOldResourceIds,
        );
        if (identical(value, _dropped) || value == null) continue;
        projectedBytes += ProfilePreferenceBudget.entryFootprint(target, value);
        if (projectedBytes > ProfilePreferenceBudget.emergencyLimitBytes) {
          throw StateError(
            'Apple TV preference storage is too full to refresh this sync '
            'circle safely ($projectedBytes > '
            '${ProfilePreferenceBudget.emergencyLimitBytes} bytes)',
          );
        }
      }
    }
  }

  @override
  Future<bool> handoff({
    required String targetProfileId,
    required bool completeOnboarding,
    required Future<void> Function() beforeCommit,
    required Future<void> Function() beforeTargetInitialize,
  }) async {
    // A resumed handoff can already own authority from its earlier durable
    // activation. Failures while draining that target are still post-handoff.
    var authorityCommitted =
        await registry.getActiveProfileId() == targetProfileId;
    try {
      return await lifecycleCoordinator.switchTo(
        targetProfileId,
        unlock: unlockImportedAdmin,
        completeOnboarding: completeOnboarding,
        afterDeactivateBeforeCommit: beforeCommit,
        afterAuthorityCommitted: () => authorityCommitted = true,
        afterCommitBeforeInitialize: beforeTargetInitialize,
      );
    } catch (error, stackTrace) {
      if (!authorityCommitted || error is WebDavSyncPostHandoffException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        WebDavSyncPostHandoffException(error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> pruneProfile(String profileId) async {
    final profile = await registry.getProfile(profileId);
    if (profile == null) {
      await ProfileCleanupLedger.resume(registry);
      return;
    }
    var actor = await _captureManagingAdmin();
    await registry.revokeGrantsOnOwnedResources(
      ownerProfileId: profileId,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    actor = await _captureManagingAdmin();
    await ProfileCleanupLedger.scheduleProfile(profileId);
    await registry.deleteProfileWithDisposition(
      id: profileId,
      deleteOwnedResources: true,
      detachPublicArtifacts: true,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
    await ProfileDataGenerationManager.deleteAllProfileData(profileId);
    await ProfileCleanupLedger.completeProfile(profileId);
  }

  @override
  Future<void> quarantineProfile(String profileId) async {
    final profile = await registry.getProfile(profileId);
    if (profile == null || !profile.isEnabled) return;
    final actor = await _captureManagingAdmin();
    await registry.disableProfile(
      profileId,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );
  }

  @override
  Future<void> rollbackProfilesNotIn(Set<String> retainedProfileIds) async {
    final current = await listProfileIds();
    final imported = current.difference(retainedProfileIds).toList()..sort();
    for (final profileId in imported) {
      await pruneProfile(profileId);
    }
  }

  @override
  Future<void> rollbackImportedProfiles(Set<String> importedProfileIds) async {
    final imported = importedProfileIds.toList()..sort();
    for (final profileId in imported) {
      if (await registry.getProfile(profileId) == null) continue;
      await pruneProfile(profileId);
    }
  }

  @override
  Future<void> holdDatabaseGate() => ProfileDatabaseAdoptionGate.hold();

  @override
  Future<void> releaseDatabaseGate() => ProfileDatabaseAdoptionGate.release();

  Future<ProfileAuthorizationContext> _captureManagingAdmin() async {
    final context = await ProfileAuthorizationContext.capture(registry);
    final actor = await context.validate(registry);
    if (!actor.isAdmin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('WebDAV sync adoption requires an active Admin');
    }
    return context;
  }

  Future<ProfileScope> _scope(String profileId) async {
    final profile = await registry.getProfile(profileId);
    if (profile == null) {
      throw StateError('WebDAV sync adoption profile is unavailable');
    }
    return ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: 0,
    );
  }

  static Future<void> _copyDatabaseAtomically(
    File source,
    File destination,
    String name,
  ) async {
    final sourceDb = await openDatabase(source.path, singleInstance: false);
    try {
      await sourceDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await _requireIntegrity(sourceDb, name);
    } finally {
      await sourceDb.close();
    }
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.webdav-adoption.tmp');
    if (await temporary.exists()) await temporary.delete();
    Object? operationFailure;
    try {
      await source.copy(temporary.path);
      final handle = await temporary.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      final copied = await openDatabase(temporary.path, singleInstance: false);
      try {
        await _requireIntegrity(copied, name);
      } finally {
        await copied.close();
      }
      await _removeDatabaseFamily(destination);
      await temporary.rename(destination.path);
    } catch (error) {
      operationFailure = error;
      rethrow;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
        await _removeSidecars(temporary);
      } catch (_) {
        if (operationFailure == null) rethrow;
      }
    }
  }

  static Future<void> _requireIntegrity(Database db, String name) async {
    final rows = await db.rawQuery('PRAGMA integrity_check');
    if (rows.length != 1 || rows.single.values.singleOrNull != 'ok') {
      throw StateError('$name failed adoption integrity check');
    }
  }

  static Future<void> _removeDatabaseFamily(File file) async {
    if (await file.exists()) await file.delete();
    await _removeSidecars(file);
  }

  static Future<void> _removeSidecars(File file) async {
    for (final suffix in const <String>['-wal', '-shm', '-journal']) {
      final sidecar = File('${file.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  static Future<void> _carryPreferences(
    ProfileScope source,
    ProfileScope destination,
    Map<String, String> resourceMap,
    Set<String> droppedResources,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final targetKeys = prefs
        .getKeys()
        .where((key) => key.startsWith(destination.preferencePrefix))
        .toSet();
    final sourceKeys =
        prefs
            .getKeys()
            .where((key) => key.startsWith(source.preferencePrefix))
            .toList()
          ..sort();
    for (final physical in sourceKeys) {
      final logical = physical.substring(source.preferencePrefix.length);
      final target = destination.preferenceKey(logical);
      if (targetKeys.contains(target)) continue;
      final value = _projectPreference(
        prefs.get(physical),
        resourceMap,
        droppedResources,
      );
      if (identical(value, _dropped)) continue;
      await _writePreference(prefs, target, value);
      targetKeys.add(target);
    }
  }

  static Object? _projectPreference(
    Object? value,
    Map<String, String> resourceMap,
    Set<String> droppedResources,
  ) {
    if (value is List<String>) {
      return <String>[
        for (final item in value)
          if (!droppedResources.contains(item)) resourceMap[item] ?? item,
      ];
    }
    if (value is! String) return value;
    if (droppedResources.contains(value)) return _dropped;
    final direct = resourceMap[value];
    if (direct != null) return direct;
    if (!resourceMap.keys.any(value.contains) &&
        !droppedResources.any(value.contains)) {
      return value;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map || decoded is List) {
        final projected = _projectJson(decoded, resourceMap, droppedResources);
        return identical(projected, _dropped)
            ? _dropped
            : jsonEncode(projected);
      }
    } on FormatException {
      // Non-JSON values are remapped only by exact identity above.
    }
    return value;
  }

  static Object? _projectJson(
    Object? value,
    Map<String, String> resourceMap,
    Set<String> droppedResources,
  ) {
    if (value is String) {
      if (droppedResources.contains(value)) return _dropped;
      return resourceMap[value] ?? value;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final item in value) {
        final projected = _projectJson(item, resourceMap, droppedResources);
        if (!identical(projected, _dropped)) result.add(projected);
      }
      return result;
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('Preference JSON key must be text');
        }
        if (droppedResources.contains(key)) continue;
        final projected = _projectJson(
          entry.value,
          resourceMap,
          droppedResources,
        );
        if (!identical(projected, _dropped)) {
          result[resourceMap[key] ?? key] = projected;
        }
      }
      return result;
    }
    return value;
  }

  static Future<void> _writePreference(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (ProfilePreferenceBudget.enforced && value != null) {
      final replaced = prefs.containsKey(key)
          ? ProfilePreferenceBudget.entryFootprint(key, prefs.get(key))
          : 0;
      final projected =
          ProfilePreferenceBudget.measure(prefs) -
          replaced +
          ProfilePreferenceBudget.entryFootprint(key, value);
      if (projected > ProfilePreferenceBudget.emergencyLimitBytes) {
        throw StateError(
          'Apple TV preference storage changed during sync-circle refresh',
        );
      }
    }
    final written = switch (value) {
      bool value => await prefs.setBool(key, value),
      int value => await prefs.setInt(key, value),
      double value => await prefs.setDouble(key, value),
      String value => await prefs.setString(key, value),
      List<String> value => await prefs.setStringList(key, value),
      null => await prefs.remove(key),
      _ => throw FormatException('Unsupported carried preference $key'),
    };
    if (!written) throw StateError('Could not carry a profile preference');
  }

  static Future<void> _carryFiles(
    ProfileScope source,
    ProfileScope destination,
  ) async {
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    for (final root in roots) {
      if (!seen.add(p.normalize(root.absolute.path))) continue;
      final sourceRoot = source.generationDirectory(root);
      if (!await sourceRoot.exists()) continue;
      final destinationRoot = destination.generationDirectory(root);
      await for (final entity in sourceRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) {
          throw StateError('Profile state contains a symlink');
        }
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: sourceRoot.path);
        if (_excludedCarryFile(relative)) continue;
        final target = File(p.join(destinationRoot.path, relative));
        if (await target.exists()) continue;
        await target.parent.create(recursive: true);
        final temporary = File('${target.path}.webdav-carry.tmp');
        if (await temporary.exists()) await temporary.delete();
        Object? operationFailure;
        try {
          final beforeLength = await entity.length();
          final beforeHash = await _hashFile(entity);
          await entity.copy(temporary.path);
          final handle = await temporary.open(mode: FileMode.append);
          try {
            await handle.flush();
          } finally {
            await handle.close();
          }
          if (await entity.length() != beforeLength ||
              await temporary.length() != beforeLength ||
              await _hashFile(entity) != beforeHash ||
              await _hashFile(temporary) != beforeHash) {
            throw StateError('Profile file changed during adoption carry');
          }
          if (await target.exists()) continue;
          await temporary.rename(target.path);
        } catch (error) {
          operationFailure = error;
          rethrow;
        } finally {
          try {
            if (await temporary.exists()) await temporary.delete();
          } catch (_) {
            if (operationFailure == null) rethrow;
          }
        }
      }
    }
  }

  static bool _excludedCarryFile(String relative) {
    final normalized = relative.replaceAll(r'\', '/').toLowerCase();
    final name = p.posix.basename(normalized);
    return name.endsWith('.db') ||
        name.endsWith('-wal') ||
        name.endsWith('-shm') ||
        name.endsWith('-journal') ||
        name.endsWith('.tmp') ||
        name.endsWith('.temp') ||
        name.contains('.restore.tmp') ||
        name.contains('.webdav-adoption.') ||
        name.contains('.webdav-carry.');
  }

  static Future<String> _hashFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

const Object _dropped = Object();
