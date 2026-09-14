import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import '../engine/local_engine_storage.dart';
import 'profile_authorization.dart';
import 'profile_data_generation.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_preferences.dart';
import 'profile_scope.dart';

class ProfileEngineAssignment {
  const ProfileEngineAssignment({
    required this.id,
    required this.displayName,
    required this.assignedToTarget,
    required this.availableFromManager,
    this.icon,
  });

  final String id;
  final String displayName;
  final String? icon;
  final bool assignedToTarget;
  final bool availableFromManager;
}

/// Copies explicitly selected torrent-engine definitions into another
/// profile. Definitions are copied, rather than shared by path, so a borrower
/// can never mutate or delete the managing profile's engine files.
///
/// Existing profiles are changed through a new data generation. A crash can
/// therefore expose either the old complete engine set or the new complete
/// set, never a partially rewritten `metadata.json` directory.
class ProfileEngineAssignmentService {
  const ProfileEngineAssignmentService(this.registry);

  static const int _maxEngineBytes = 4 * 1024 * 1024;
  static const int _maxTotalBytes = 64 * 1024 * 1024;

  final ProfileRegistry registry;

  Future<List<ProfileEngineAssignment>> listForTarget({
    required ProfileAuthorizationContext actor,
    String? targetProfileId,
  }) async {
    await _validateManagingAdmin(actor);
    final managerScope = ProfileRuntime.capture();
    final manager = await _readSnapshot(managerScope);

    _EngineSnapshot target = const _EngineSnapshot.empty();
    UserProfile? targetProfile;
    if (targetProfileId != null) {
      targetProfile = await registry.getProfile(targetProfileId);
      if (targetProfile == null || !targetProfile.isEnabled) {
        throw StateError('Destination profile is unavailable');
      }
      target = targetProfile.id == managerScope.profileId
          ? manager
          : await _readSnapshot(_scopeFor(targetProfile));
    }

    await _validateManagingAdmin(actor);
    if (targetProfile != null) {
      await _assertTargetUnchanged(targetProfile);
    }

    final ids = <String>{...manager.engines.keys, ...target.engines.keys};
    final assignments =
        <ProfileEngineAssignment>[
          for (final id in ids)
            ProfileEngineAssignment(
              id: id,
              displayName: (target.engines[id] ?? manager.engines[id])!
                  .metadata
                  .displayName,
              icon: (target.engines[id] ?? manager.engines[id])!.metadata.icon,
              assignedToTarget: target.engines.containsKey(id),
              availableFromManager: manager.engines.containsKey(id),
            ),
        ]..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    return assignments;
  }

  Future<void> apply({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required Set<String> selectedEngineIds,
  }) => ProfilePreferences.synchronizeExternalMutation(
    () => _apply(
      actor: actor,
      targetProfileId: targetProfileId,
      selectedEngineIds: selectedEngineIds,
    ),
    marksMutation: true,
  );

  Future<void> _apply({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required Set<String> selectedEngineIds,
  }) async {
    await _validateManagingAdmin(actor);
    final managerScope = ProfileRuntime.capture();
    final targetProfile = await registry.getProfile(targetProfileId);
    if (targetProfile == null || !targetProfile.isEnabled) {
      throw StateError('Destination profile is unavailable');
    }

    final manager = await _readSnapshot(managerScope);
    final target = targetProfile.id == managerScope.profileId
        ? manager
        : await _readSnapshot(_scopeFor(targetProfile));
    final desired = <String, _StoredEngine>{};
    for (final id in selectedEngineIds) {
      final engine = target.engines[id] ?? manager.engines[id];
      if (engine == null) {
        throw StateError('Selected torrent engine is no longer available');
      }
      desired[id] = engine;
    }

    if (setEquals(target.engines.keys.toSet(), desired.keys.toSet())) return;
    if (targetProfile.id == managerScope.profileId) {
      throw StateError(
        'The active profile must manage its engines from Torrent Engines',
      );
    }

    await _validateManagingAdmin(actor);
    await _assertTargetUnchanged(targetProfile);
    if (targetProfile.lifecycle == UserProfileLifecycle.staging) {
      // The profile is not picker-visible until its caller completes setup.
      // A failed setup deletes the whole staged profile and its generation.
      await _writeSnapshot(
        _scopeFor(targetProfile),
        desired,
        {
          ...target.deletedIds,
          ...target.engines.keys,
        }.difference(desired.keys.toSet()),
      );
      await _validateManagingAdmin(actor);
      await _assertTargetUnchanged(targetProfile);
      return;
    }

    final operationId = _newOperationId();
    StagedProfileGeneration? staged;
    var published = false;
    try {
      staged = await ProfileDataGenerationManager(registry).stage(
        operationId: operationId,
        profileId: targetProfile.id,
        preferenceOverlay: const <String, Object?>{},
      );
      final stagedScope = ProfileScope(
        profileId: targetProfile.id,
        dataGeneration: staged.generation,
        sessionEpoch: 0,
      );
      await _writeSnapshot(
        stagedScope,
        desired,
        {
          ...target.deletedIds,
          ...target.engines.keys,
        }.difference(desired.keys.toSet()),
      );
      staged = await ProfileDataGenerationManager(registry).finalize(staged);

      await _validateManagingAdmin(actor);
      await _assertTargetUnchanged(targetProfile);
      await registry.publishDataGeneration(
        profileId: targetProfile.id,
        baseGeneration: staged.baseGeneration,
        stagedGeneration: staged.generation,
        operationId: operationId,
      );
      published = true;
      ProfilePreferences.notifyWebDavSyncLocalChange(
        targetProfile.id,
        'engine_definitions_changed',
      );
      try {
        await registry.markRestoreCleaned(operationId);
      } catch (error) {
        // Publication is already authoritative. Bootstrap will remove the
        // published journal without rolling the visible generation back.
        debugPrint('Profile engine assignment cleanup deferred: $error');
      }
    } catch (_) {
      if (!published && staged != null) {
        await _cleanupUnpublished(operationId, staged);
      }
      rethrow;
    }
  }

  Future<UserProfile> _validateManagingAdmin(
    ProfileAuthorizationContext actor,
  ) async {
    final profile = await actor.validate(registry);
    if (!profile.isAdmin || !profile.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Torrent-engine assignment requires an Admin');
    }
    return profile;
  }

  Future<void> _assertTargetUnchanged(UserProfile expected) async {
    final current = await registry.getProfile(expected.id);
    if (current == null ||
        !current.isEnabled ||
        current.lifecycle != expected.lifecycle ||
        current.visibleDataGeneration != expected.visibleDataGeneration ||
        current.authorizationRevision != expected.authorizationRevision) {
      throw StateError('Destination profile changed during engine assignment');
    }
  }

  Future<void> _cleanupUnpublished(
    String operationId,
    StagedProfileGeneration staged,
  ) async {
    try {
      await ProfileDataGenerationManager.deleteGenerationData(
        staged.profileId,
        staged.generation,
      );
      final recoveries = await registry.recoverInterruptedRestores();
      final recovery = recoveries
          .where((item) => item.operationId == operationId)
          .firstOrNull;
      if (recovery != null) {
        await registry.completeInterruptedRestoreRecovery(recovery);
      }
    } catch (error) {
      // Keep the journal as durable cleanup authority for bootstrap.
      debugPrint('Profile engine assignment rollback deferred: $error');
    }
  }

  static ProfileScope _scopeFor(UserProfile profile) => ProfileScope(
    profileId: profile.id,
    dataGeneration: profile.visibleDataGeneration,
    sessionEpoch: 0,
  );

  static Future<_EngineSnapshot> _readSnapshot(ProfileScope scope) async {
    final root = await AppStorage.documents();
    final directory = Directory(
      p.join(scope.storageDirectory(root, 'documents').path, 'engines'),
    );
    final metadataFile = File(p.join(directory.path, 'metadata.json'));
    if (!await metadataFile.exists()) return const _EngineSnapshot.empty();
    if (await metadataFile.length() > _maxEngineBytes) {
      throw const FormatException('Torrent-engine metadata is too large');
    }

    final metadataSource = await metadataFile.readAsString();
    final decoded = jsonDecode(metadataSource);
    if (decoded is! Map || decoded['engines'] is! Map) {
      throw const FormatException('Invalid torrent-engine metadata');
    }
    final records = decoded['engines'] as Map;
    final engines = <String, _StoredEngine>{};
    var total = 0;
    for (final entry in records.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid torrent-engine record');
      }
      final id = entry.key as String;
      if (id.isEmpty || id.length > 256) {
        throw const FormatException('Invalid torrent-engine ID');
      }
      final metadata = ImportedEngineMetadata.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (metadata.id != id || !_safeYamlFileName(metadata.fileName)) {
        throw const FormatException('Unsafe torrent-engine metadata');
      }
      final file = File(p.join(directory.path, metadata.fileName));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Torrent-engine definition is missing');
      }
      final length = await file.length();
      total += length;
      if (length > _maxEngineBytes || total > _maxTotalBytes) {
        throw const FormatException('Torrent-engine definitions are too large');
      }
      engines[id] = _StoredEngine(metadata, await file.readAsBytes());
    }
    if (!await metadataFile.exists() ||
        await metadataFile.readAsString() != metadataSource) {
      throw StateError('Torrent-engine metadata changed while being read');
    }
    for (final engine in engines.values) {
      final file = File(p.join(directory.path, engine.metadata.fileName));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !listEquals(await file.readAsBytes(), engine.bytes)) {
        throw StateError('Torrent-engine definition changed while being read');
      }
    }
    return _EngineSnapshot(
      engines,
      Set<String>.from(decoded['deletedEngineIds'] as List? ?? []),
    );
  }

  static Future<void> _writeSnapshot(
    ProfileScope scope,
    Map<String, _StoredEngine> engines,
    Set<String> deletedIds,
  ) async {
    final root = await AppStorage.documents();
    final directory = Directory(
      p.join(scope.storageDirectory(root, 'documents').path, 'engines'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);

    final metadata = <String, Object?>{};
    for (final entry in engines.entries) {
      final fileName = await _safeAssignedFileName(entry.key);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(entry.value.bytes, flush: true);
      final source = entry.value.metadata;
      metadata[entry.key] = ImportedEngineMetadata(
        id: entry.key,
        fileName: fileName,
        displayName: source.displayName,
        importedAt: source.importedAt,
        icon: source.icon,
      ).toJson();
    }
    await File(p.join(directory.path, 'metadata.json')).writeAsString(
      jsonEncode(<String, Object?>{
        'version': '1.0',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'engines': metadata,
        'deletedEngineIds': deletedIds.toList()..sort(),
      }),
      flush: true,
    );
  }

  static bool _safeYamlFileName(String value) {
    final extension = p.extension(value).toLowerCase();
    return value.isNotEmpty &&
        value == p.basename(value) &&
        (extension == '.yaml' || extension == '.yml');
  }

  static Future<String> _safeAssignedFileName(String engineId) async {
    final digest = await Sha256().hash(utf8.encode(engineId));
    final encoded = base64UrlEncode(digest.bytes).replaceAll('=', '');
    return 'assigned-$encoded.yaml';
  }

  static String _newOperationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return 'engine-assignment-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

class _EngineSnapshot {
  const _EngineSnapshot(this.engines, this.deletedIds);
  const _EngineSnapshot.empty()
    : engines = const <String, _StoredEngine>{},
      deletedIds = const {};

  final Map<String, _StoredEngine> engines;
  final Set<String> deletedIds;
}

class _StoredEngine {
  const _StoredEngine(this.metadata, this.bytes);

  final ImportedEngineMetadata metadata;
  final List<int> bytes;
}
