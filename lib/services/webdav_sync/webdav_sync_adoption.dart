import 'dart:math';

import 'package:synchronized/synchronized.dart';

import '../profiles/portable_profile_package.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_restore_coordinator.dart';
import 'webdav_sync_adoption_models.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_safety_backup.dart';

final class WebDavSyncAdoptionRequest {
  const WebDavSyncAdoptionRequest({
    required this.namespaceId,
    required this.mode,
    required this.package,
    required this.graphSemanticDigest,
    required this.profileMap,
    required this.resourceMap,
    required this.passphrase,
    required this.authorization,
    required this.replacementConfirmed,
    this.completeOnboarding = false,
  });

  final String namespaceId;
  final WebDavSyncAdoptionMode mode;
  final PortableProfilePackage package;
  final String graphSemanticDigest;
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;
  final String passphrase;
  final ProfileAuthorizationContext authorization;
  final bool replacementConfirmed;
  final bool completeOnboarding;
}

abstract interface class WebDavSyncAdoptionOperations {
  Future<Set<String>> listProfileIds();

  Future<String> activeProfileId();

  Future<ProfileGraphRestoreReport> restoreGraph({
    required PortableProfilePackage package,
    required ProfileAuthorizationContext authorization,
  });

  Future<String> selectTargetAdmin(Set<String> importedProfileIds);

  Future<void> copyDatabases({
    required String oldProfileId,
    required String newProfileId,
  });

  Future<void> remapDatabases({
    required String newProfileId,
    required Map<String, String> oldToNewResources,
  });

  Future<void> carryLocalState({
    required String oldProfileId,
    required String newProfileId,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  });

  /// Checks the complete refresh carry before any pair is copied. This is a
  /// transaction-wide check because profile-scoped preferences coexist in one
  /// tvOS UserDefaults database until the predecessor graph is pruned.
  Future<void> preflightLocalStateCarry({
    required Map<String, String> oldToNewProfiles,
    required Map<String, String> oldToNewResources,
    required Set<String> unmappedOldResourceIds,
  });

  /// [beforeCommit] runs after the prior profile's handles have drained but
  /// before the target becomes authoritative. [beforeTargetInitialize] runs
  /// after publication and before target profile services initialize.
  Future<bool> handoff({
    required String targetProfileId,
    required bool completeOnboarding,
    required Future<void> Function() beforeCommit,
    required Future<void> Function() beforeTargetInitialize,
  });

  Future<void> pruneProfile(String profileId);

  Future<void> quarantineProfile(String profileId);

  Future<void> rollbackProfilesNotIn(Set<String> retainedProfileIds);

  /// Removes only the imported profiles named by a durable post-restore
  /// journal. This must not infer or delete unrelated profiles created after
  /// the pre-restore snapshot.
  Future<void> rollbackImportedProfiles(Set<String> importedProfileIds);

  Future<void> holdDatabaseGate();

  Future<void> releaseDatabaseGate();
}

typedef WebDavSyncAdoptionIdFactory = String Function();
typedef WebDavSyncAdoptionDiagnostic =
    void Function(String message, Object? error);

abstract interface class WebDavSyncAdoptionRunner {
  Future<WebDavSyncAdoptionRecord> adopt(WebDavSyncAdoptionRequest request);

  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId);

  /// Retries predecessor cleanup left quarantined by a completed adoption.
  /// Each ID remains a graph-publication blocker until its deletion succeeds.
  Future<Set<String>> retryPendingPrunes(String namespaceId);
}

/// Durable crash-ordered coordinator for both first join and later structure
/// refresh. Every side effect is followed by a persisted completion marker;
/// repeating a step after a process death is therefore intentional.
final class WebDavSyncCircleAdoption implements WebDavSyncAdoptionRunner {
  WebDavSyncCircleAdoption({
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncSafetyBackupStore safetyBackups,
    required WebDavSyncAdoptionOperations operations,
    WebDavSyncAdoptionIdFactory? adoptionIdFactory,
    WebDavSyncAdoptionDiagnostic? diagnostic,
  }) : _stateRepository = stateRepository,
       _safetyBackups = safetyBackups,
       _operations = operations,
       _adoptionIdFactory = adoptionIdFactory ?? _mintAdoptionId,
       _diagnostic = diagnostic ?? _ignoreDiagnostic;

  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncSafetyBackupStore _safetyBackups;
  final WebDavSyncAdoptionOperations _operations;
  final WebDavSyncAdoptionIdFactory _adoptionIdFactory;
  final WebDavSyncAdoptionDiagnostic _diagnostic;
  final Lock _lock = Lock();

  @override
  Future<WebDavSyncAdoptionRecord> adopt(
    WebDavSyncAdoptionRequest request,
  ) => _lock.synchronized(() async {
    if (!request.replacementConfirmed) {
      throw StateError(
        'Replacing local profiles requires explicit confirmation',
      );
    }
    final state = await _stateRepository.load(request.namespaceId);
    if (state.adoption != null) {
      throw StateError('A WebDAV sync adoption is already in progress');
    }
    _validateRequest(request);
    final preRestore = await _operations.listProfileIds();
    if (preRestore.isEmpty) {
      throw StateError('WebDAV sync adoption requires a local profile');
    }
    if (request.mode == WebDavSyncAdoptionMode.refresh) {
      final mapped = state.circleToLocalProfiles;
      if (mapped == null ||
          mapped.isEmpty ||
          !preRestore.containsAll(mapped.values)) {
        throw StateError('WebDAV sync refresh mappings are incomplete');
      }
    }
    final adoptionId = _adoptionIdFactory();
    final backup = await _safetyBackups.createVerified(
      adoptionId: adoptionId,
      passphrase: request.passphrase,
      authorization: request.authorization,
    );
    var record = WebDavSyncAdoptionRecord(
      adoptionId: adoptionId,
      mode: request.mode,
      phase: WebDavSyncAdoptionPhase.restoring,
      graphSemanticDigest: request.graphSemanticDigest,
      preRestoreProfileIds: Set<String>.unmodifiable(preRestore),
      backupPath: backup.path,
      backupSha256: backup.sha256Hex,
      backupVerified: true,
      completeOnboarding: request.completeOnboarding,
    );
    await _stateRepository.update(request.namespaceId, (current) {
      if (current.adoption != null) {
        throw StateError('A WebDAV sync adoption started concurrently');
      }
      return current.copyWith(adoption: record);
    });
    await _operations.holdDatabaseGate();
    try {
      final restored = await _operations.restoreGraph(
        package: request.package,
        authorization: request.authorization,
      );
      final newProfileMap = _mapRestoredProfiles(
        package: request.package,
        report: restored,
        wireMap: request.profileMap,
      );
      final newResourceMap = _mapRestoredResources(
        package: request.package,
        report: restored,
        wireMap: request.resourceMap,
      );
      final oldToNewProfiles = request.mode == WebDavSyncAdoptionMode.refresh
          ? _predecessors(state.circleToLocalProfiles!, newProfileMap)
          : const <String, String>{};
      final oldToNewResources = request.mode == WebDavSyncAdoptionMode.refresh
          ? _predecessors(
              state.circleToLocalResources ?? const <String, String>{},
              newResourceMap,
            )
          : const <String, String>{};
      final unmappedOldResources =
          request.mode == WebDavSyncAdoptionMode.refresh
          ? <String>{
              for (final entry
                  in (state.circleToLocalResources ?? const <String, String>{})
                      .entries)
                if (!newResourceMap.containsKey(entry.key)) entry.value,
            }
          : const <String>{};
      final targetAdmin = await _operations.selectTargetAdmin(
        newProfileMap.values.toSet(),
      );
      if (!newProfileMap.containsValue(targetAdmin)) {
        throw StateError('Imported Admin is outside the adopted graph');
      }
      await _operations.preflightLocalStateCarry(
        oldToNewProfiles: oldToNewProfiles,
        oldToNewResources: oldToNewResources,
        unmappedOldResourceIds: unmappedOldResources,
      );
      record = record.copyWith(
        phase: WebDavSyncAdoptionPhase.restored,
        circleProfileToNewLocal: newProfileMap,
        circleResourceToNewLocal: newResourceMap,
        oldToNewProfiles: oldToNewProfiles,
        oldToNewResources: oldToNewResources,
        unmappedOldResourceIds: Set<String>.unmodifiable(unmappedOldResources),
        targetAdminProfileId: targetAdmin,
      );
      await _replaceRecord(request.namespaceId, record);
    } catch (error, stackTrace) {
      try {
        final current = await _stateRepository.load(request.namespaceId);
        final journal = current.adoption;
        if (journal?.adoptionId == record.adoptionId &&
            journal?.phase == WebDavSyncAdoptionPhase.restoring) {
          await _rollbackRestoring(request.namespaceId, journal!);
        }
      } catch (cleanupError) {
        // Preserve the restoring journal and closed database gate whenever
        // cleanup itself cannot finish; startup recovery will retry it.
        _diagnostic(
          'WebDAV sync adoption rollback remains pending',
          cleanupError,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return _resumeTail(request.namespaceId, record);
  });

  /// Must run before the first ordinary sync cycle after startup. A crash in
  /// the restore publication window rolls back every post-snapshot profile.
  /// A prepared adoption that never reached handoff also rolls back only its
  /// journal-listed imports; handoff and later phases resume idempotently.
  @override
  Future<WebDavSyncAdoptionRecord?> recover(String namespaceId) =>
      _lock.synchronized(() async {
        final state = await _stateRepository.load(namespaceId);
        final record = state.adoption;
        if (record == null) return null;
        await _operations.holdDatabaseGate();
        if (record.phase == WebDavSyncAdoptionPhase.restoring) {
          await _rollbackRestoring(namespaceId, record);
          return null;
        }
        if (_canRollbackPrepared(record)) {
          await _rollbackPrepared(namespaceId, record);
          return null;
        }
        return _resumeTail(namespaceId, record);
      });

  @override
  Future<Set<String>> retryPendingPrunes(String namespaceId) =>
      _lock.synchronized(() async {
        var state = await _stateRepository.load(namespaceId);
        if (state.adoption != null) {
          throw StateError(
            'WebDAV sync adoption must finish before cleanup can retry',
          );
        }
        final existingProfiles = await _operations.listProfileIds();
        final removedProtected = state.safetyProtectedProfileIds.difference(
          existingProfiles,
        );
        if (removedProtected.isNotEmpty) {
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(
              prunePendingProfileIds: Set<String>.unmodifiable(
                current.prunePendingProfileIds.difference(removedProtected),
              ),
              safetyProtectedProfileIds: Set<String>.unmodifiable(
                current.safetyProtectedProfileIds.difference(removedProtected),
              ),
            ),
          );
        }
        final pending =
            state.prunePendingProfileIds
                .difference(state.safetyProtectedProfileIds)
                .toList()
              ..sort();
        for (final profileId in pending) {
          try {
            await _operations.pruneProfile(profileId);
          } catch (error) {
            try {
              await _operations.quarantineProfile(profileId);
            } catch (quarantineError) {
              _diagnostic(
                'WebDAV sync profile quarantine remains pending',
                quarantineError,
              );
            }
            _diagnostic('WebDAV sync profile prune is still pending', error);
            continue;
          }
          state = await _stateRepository.update(namespaceId, (current) {
            if (current.adoption != null) {
              throw StateError('WebDAV sync adoption started during cleanup');
            }
            return current.copyWith(
              prunePendingProfileIds: Set<String>.unmodifiable(
                current.prunePendingProfileIds.difference(<String>{profileId}),
              ),
            );
          });
        }
        return state.prunePendingProfileIds;
      });

  Future<void> _rollbackRestoring(
    String namespaceId,
    WebDavSyncAdoptionRecord record,
  ) async {
    await _operations.rollbackProfilesNotIn(record.preRestoreProfileIds);
    await _operations.releaseDatabaseGate();
    try {
      await _stateRepository.update(namespaceId, (current) {
        if (current.adoption?.adoptionId != record.adoptionId) {
          throw StateError('WebDAV sync adoption journal changed');
        }
        return current.copyWith(clearAdoption: true);
      });
    } catch (_) {
      // Re-close the process gate if the durable journal could not be cleared.
      // That keeps ordinary DB users out until a later recovery retries.
      await _operations.holdDatabaseGate();
      rethrow;
    }
  }

  Future<void> _rollbackPrepared(
    String namespaceId,
    WebDavSyncAdoptionRecord record,
  ) async {
    if (!_canRollbackPrepared(record)) {
      throw StateError('WebDAV sync adoption already reached handoff');
    }
    final activeProfileId = await _operations.activeProfileId();
    if (!record.preRestoreProfileIds.contains(activeProfileId)) {
      throw StateError('WebDAV sync adoption rollback crossed handoff');
    }
    final currentProfileIds = await _operations.listProfileIds();
    if (!currentProfileIds.containsAll(record.preRestoreProfileIds)) {
      throw StateError('WebDAV sync adoption predecessors are incomplete');
    }
    final importedProfileIds = record.circleProfileToNewLocal.values.toSet();
    if (importedProfileIds.isEmpty ||
        importedProfileIds.length != record.circleProfileToNewLocal.length ||
        importedProfileIds.any(record.preRestoreProfileIds.contains)) {
      throw StateError('WebDAV sync adoption rollback map is incomplete');
    }
    await _operations.rollbackImportedProfiles(importedProfileIds);
    await _operations.releaseDatabaseGate();
    try {
      await _stateRepository.update(namespaceId, (current) {
        if (current.adoption?.adoptionId != record.adoptionId) {
          throw StateError('WebDAV sync adoption journal changed');
        }
        return current.copyWith(clearAdoption: true);
      });
    } catch (_) {
      await _operations.holdDatabaseGate();
      rethrow;
    }
  }

  Future<WebDavSyncAdoptionRecord> _resumeTail(
    String namespaceId,
    WebDavSyncAdoptionRecord initial,
  ) async {
    var record = initial;
    var gateReleased = false;
    var authorityCommitted = false;
    try {
      if (record.phase == WebDavSyncAdoptionPhase.complete) {
        authorityCommitted = true;
        await _operations.releaseDatabaseGate();
        gateReleased = true;
        await _finalize(namespaceId, record);
        return record;
      }
      _requireRestoredRecord(record);
      final active = await _operations.activeProfileId();
      authorityCommitted = active == record.targetAdminProfileId;
      final deferredOldProfile = record.oldToNewProfiles.containsKey(active)
          ? active
          : _unfinishedSource(record);

      if (_before(record.phase, WebDavSyncAdoptionPhase.copyingDatabases)) {
        record = record.copyWith(
          phase: WebDavSyncAdoptionPhase.copyingDatabases,
        );
        await _replaceRecord(namespaceId, record);
      }
      for (final entry in record.oldToNewProfiles.entries) {
        if (entry.key == deferredOldProfile ||
            record.databaseCopiesComplete.contains(entry.key)) {
          continue;
        }
        await _operations.copyDatabases(
          oldProfileId: entry.key,
          newProfileId: entry.value,
        );
        record = record.copyWith(
          databaseCopiesComplete: <String>{
            ...record.databaseCopiesComplete,
            entry.key,
          },
        );
        await _replaceRecord(namespaceId, record);
      }

      if (_before(record.phase, WebDavSyncAdoptionPhase.remappingDatabases)) {
        record = record.copyWith(
          phase: WebDavSyncAdoptionPhase.remappingDatabases,
        );
        await _replaceRecord(namespaceId, record);
      }
      for (final entry in record.oldToNewProfiles.entries) {
        if (entry.key == deferredOldProfile ||
            record.databaseRemapsComplete.contains(entry.key)) {
          continue;
        }
        await _operations.remapDatabases(
          newProfileId: entry.value,
          oldToNewResources: record.oldToNewResources,
        );
        record = record.copyWith(
          databaseRemapsComplete: <String>{
            ...record.databaseRemapsComplete,
            entry.key,
          },
        );
        await _replaceRecord(namespaceId, record);
      }

      if (_before(record.phase, WebDavSyncAdoptionPhase.carryingLocalState)) {
        record = record.copyWith(
          phase: WebDavSyncAdoptionPhase.carryingLocalState,
        );
        await _replaceRecord(namespaceId, record);
      }
      for (final entry in record.oldToNewProfiles.entries) {
        if (entry.key == deferredOldProfile ||
            record.localCarryComplete.contains(entry.key)) {
          continue;
        }
        await _operations.carryLocalState(
          oldProfileId: entry.key,
          newProfileId: entry.value,
          oldToNewResources: record.oldToNewResources,
          unmappedOldResourceIds: record.unmappedOldResourceIds,
        );
        record = record.copyWith(
          localCarryComplete: <String>{...record.localCarryComplete, entry.key},
        );
        await _replaceRecord(namespaceId, record);
      }

      if (_before(record.phase, WebDavSyncAdoptionPhase.handingOff)) {
        record = record.copyWith(phase: WebDavSyncAdoptionPhase.handingOff);
        await _replaceRecord(namespaceId, record);
      }
      final deferred = deferredOldProfile == null
          ? null
          : MapEntry(
              deferredOldProfile,
              record.oldToNewProfiles[deferredOldProfile]!,
            );
      final switched = await _operations.handoff(
        targetProfileId: record.targetAdminProfileId!,
        completeOnboarding: record.completeOnboarding,
        beforeCommit: () async {
          if (deferred != null) {
            record = await _completePair(
              namespaceId: namespaceId,
              record: record,
              oldProfileId: deferred.key,
              newProfileId: deferred.value,
            );
          }
        },
        beforeTargetInitialize: () async {
          await _operations.releaseDatabaseGate();
          gateReleased = true;
        },
      );
      if (!switched) {
        throw StateError('Could not activate the imported Admin profile');
      }
      authorityCommitted = true;

      final backupRetained = await _safetyBackups.verifyRetained(
        WebDavSyncSafetyBackup(
          path: record.backupPath,
          sha256Hex: record.backupSha256,
        ),
      );
      record = record.copyWith(
        phase: WebDavSyncAdoptionPhase.pruning,
        safetyBackupRetained: backupRetained,
      );
      await _replaceRecord(namespaceId, record);
      final pruneSet = record.mode == WebDavSyncAdoptionMode.firstJoin
          ? record.preRestoreProfileIds
          : record.oldToNewProfiles.keys.toSet();
      for (final profileId in pruneSet) {
        if (record.prunedProfileIds.contains(profileId) ||
            record.prunePendingProfileIds.contains(profileId)) {
          continue;
        }
        if (record.mode == WebDavSyncAdoptionMode.refresh &&
            (!_pairComplete(record, profileId) ||
                !record.preRestoreProfileIds.contains(profileId))) {
          throw StateError('WebDAV sync refresh prune guard is incomplete');
        }
        if (!record.safetyBackupRetained) {
          await _operations.quarantineProfile(profileId);
          _diagnostic(
            'WebDAV sync retained the predecessor because its safety backup is unavailable',
            null,
          );
          record = record.copyWith(
            prunePendingProfileIds: <String>{
              ...record.prunePendingProfileIds,
              profileId,
            },
          );
        } else {
          try {
            await _operations.pruneProfile(profileId);
            record = record.copyWith(
              prunedProfileIds: <String>{...record.prunedProfileIds, profileId},
            );
          } catch (error) {
            await _operations.quarantineProfile(profileId);
            _diagnostic('WebDAV sync profile prune is pending', error);
            record = record.copyWith(
              prunePendingProfileIds: <String>{
                ...record.prunePendingProfileIds,
                profileId,
              },
            );
          }
        }
        await _replaceRecord(namespaceId, record);
      }
      record = record.copyWith(phase: WebDavSyncAdoptionPhase.complete);
      await _replaceRecord(namespaceId, record);
      await _finalize(namespaceId, record);
      return record;
    } catch (error, stackTrace) {
      if (_canRollbackPrepared(record)) {
        try {
          await _rollbackPrepared(namespaceId, record);
          gateReleased = true;
        } catch (rollbackError) {
          _diagnostic(
            'WebDAV sync pre-handoff rollback remains pending',
            rollbackError,
          );
        }
      }
      final surfaced =
          authorityCommitted && error is! WebDavSyncPostHandoffException
          ? WebDavSyncPostHandoffException(error)
          : error;
      Error.throwWithStackTrace(surfaced, stackTrace);
    } finally {
      if (!gateReleased) {
        try {
          await _operations.releaseDatabaseGate();
        } catch (error) {
          _diagnostic('WebDAV sync database gate release failed', error);
        }
      }
    }
  }

  Future<WebDavSyncAdoptionRecord> _completePair({
    required String namespaceId,
    required WebDavSyncAdoptionRecord record,
    required String oldProfileId,
    required String newProfileId,
  }) async {
    var current = record;
    if (!current.databaseCopiesComplete.contains(oldProfileId)) {
      await _operations.copyDatabases(
        oldProfileId: oldProfileId,
        newProfileId: newProfileId,
      );
      current = current.copyWith(
        databaseCopiesComplete: <String>{
          ...current.databaseCopiesComplete,
          oldProfileId,
        },
      );
      await _replaceRecord(namespaceId, current);
    }
    if (!current.databaseRemapsComplete.contains(oldProfileId)) {
      await _operations.remapDatabases(
        newProfileId: newProfileId,
        oldToNewResources: current.oldToNewResources,
      );
      current = current.copyWith(
        databaseRemapsComplete: <String>{
          ...current.databaseRemapsComplete,
          oldProfileId,
        },
      );
      await _replaceRecord(namespaceId, current);
    }
    if (!current.localCarryComplete.contains(oldProfileId)) {
      await _operations.carryLocalState(
        oldProfileId: oldProfileId,
        newProfileId: newProfileId,
        oldToNewResources: current.oldToNewResources,
        unmappedOldResourceIds: current.unmappedOldResourceIds,
      );
      current = current.copyWith(
        localCarryComplete: <String>{
          ...current.localCarryComplete,
          oldProfileId,
        },
      );
      await _replaceRecord(namespaceId, current);
    }
    return current;
  }

  Future<void> _finalize(String namespaceId, WebDavSyncAdoptionRecord record) =>
      _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(
          circleToLocalProfiles: record.circleProfileToNewLocal,
          circleToLocalResources: record.circleResourceToNewLocal,
          prunePendingProfileIds: <String>{
            ...current.prunePendingProfileIds,
            ...record.prunePendingProfileIds,
          },
          safetyProtectedProfileIds: record.safetyBackupRetained
              ? current.safetyProtectedProfileIds
              : <String>{
                  ...current.safetyProtectedProfileIds,
                  ...record.prunePendingProfileIds,
                },
          clearAdoption: true,
        ),
      );

  Future<void> _replaceRecord(
    String namespaceId,
    WebDavSyncAdoptionRecord record,
  ) => _stateRepository.update(namespaceId, (current) {
    if (current.adoption?.adoptionId != record.adoptionId) {
      throw StateError('WebDAV sync adoption journal changed');
    }
    return current.copyWith(adoption: record);
  });

  static Map<String, String> _mapRestoredProfiles({
    required PortableProfilePackage package,
    required ProfileGraphRestoreReport report,
    required Map<String, String> wireMap,
  }) {
    if (report.importedProfileIds.length != package.profiles.length) {
      throw StateError('WebDAV sync restore profile report is incomplete');
    }
    final result = <String, String>{};
    for (var index = 0; index < package.profiles.length; index++) {
      final backupId = package.profiles[index]['backupId'];
      final circleId = backupId is String ? wireMap[backupId] : null;
      if (circleId == null ||
          result.putIfAbsent(
                circleId,
                () => report.importedProfileIds[index],
              ) !=
              report.importedProfileIds[index]) {
        throw StateError('WebDAV sync restored profile map is incomplete');
      }
    }
    if (result.length != wireMap.length) {
      throw StateError('WebDAV sync restored profile map has omissions');
    }
    return Map<String, String>.unmodifiable(result);
  }

  static Map<String, String> _mapRestoredResources({
    required PortableProfilePackage package,
    required ProfileGraphRestoreReport report,
    required Map<String, String> wireMap,
  }) {
    final result = <String, String>{};
    for (final resource in package.resources) {
      final backupId = resource['backupId'];
      final circleId = backupId is String ? wireMap[backupId] : null;
      final localId = backupId is String
          ? report.importedResourceIdsByBackupId[backupId]
          : null;
      if (circleId == null ||
          localId == null ||
          result.putIfAbsent(circleId, () => localId) != localId) {
        throw StateError('WebDAV sync restored resource map is incomplete');
      }
    }
    if (result.length != wireMap.length ||
        result.length != report.importedResourceIdsByBackupId.length) {
      throw StateError('WebDAV sync restored resource map has omissions');
    }
    return Map<String, String>.unmodifiable(result);
  }

  static Map<String, String> _predecessors(
    Map<String, String> oldMap,
    Map<String, String> newMap,
  ) => Map<String, String>.unmodifiable(<String, String>{
    for (final entry in oldMap.entries)
      if (newMap[entry.key] case final newId?) entry.value: newId,
  });

  static String? _unfinishedSource(WebDavSyncAdoptionRecord record) {
    final unfinished = record.oldToNewProfiles.keys
        .where((id) => !_pairComplete(record, id))
        .toList(growable: false);
    return unfinished.length == 1 ? unfinished.single : null;
  }

  static bool _pairComplete(WebDavSyncAdoptionRecord record, String oldId) =>
      record.databaseCopiesComplete.contains(oldId) &&
      record.databaseRemapsComplete.contains(oldId) &&
      record.localCarryComplete.contains(oldId);

  static bool _before(
    WebDavSyncAdoptionPhase left,
    WebDavSyncAdoptionPhase right,
  ) => left.index < right.index;

  static bool _canRollbackPrepared(WebDavSyncAdoptionRecord record) {
    final phase = record.phase.index;
    return phase >= WebDavSyncAdoptionPhase.restored.index &&
        phase <= WebDavSyncAdoptionPhase.carryingLocalState.index;
  }

  static void _requireRestoredRecord(WebDavSyncAdoptionRecord record) {
    if (record.circleProfileToNewLocal.isEmpty ||
        record.targetAdminProfileId == null) {
      throw StateError('WebDAV sync adoption journal is incomplete');
    }
  }

  static void _validateRequest(WebDavSyncAdoptionRequest request) {
    if (request.completeOnboarding &&
        request.mode != WebDavSyncAdoptionMode.firstJoin) {
      throw ArgumentError(
        'Onboarding completion is only valid for a first join',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(request.graphSemanticDigest) ||
        request.package.mode != 'deviceGraph' ||
        request.package.profiles.isEmpty ||
        request.profileMap.length != request.package.profiles.length ||
        request.resourceMap.length != request.package.resources.length) {
      throw const FormatException('Invalid WebDAV sync adoption graph');
    }
  }

  static String _mintAdoptionId() {
    final random = Random.secure();
    final value = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'adoption-$value';
  }

  static void _ignoreDiagnostic(String message, Object? error) {}
}
