import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../diagnostic_log.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_circle_merge.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_local_adapter.dart';
import 'webdav_sync_large_section_io.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_transport.dart';

enum WebDavSyncTrigger {
  launch,
  foreground,
  playbackStopped,
  background,
  periodic,
  manual,
  localChange,
  remoteChange,
}

enum WebDavSyncCycleDisposition {
  inactive,
  adoptionBlocked,
  clockPaused,
  seedRepairRequired,
  completed,
}

final class WebDavSyncCycleReport {
  const WebDavSyncCycleReport({
    required this.disposition,
    this.peerCount = 0,
    this.profilesApplied = 0,
    this.sectionsPushed = 0,
    this.deviceClockWarning = false,
    this.clockPauseReason,
    this.statusHint,
  });

  final WebDavSyncCycleDisposition disposition;
  final int peerCount;
  final int profilesApplied;
  final int sectionsPushed;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? clockPauseReason;
  final String? statusHint;
}

/// Bounded cache shared by successive production engine instances. Transport
/// credentials remain cycle-local, while authenticated immutable sections can
/// survive the runner's per-cycle client construction.
final class WebDavSyncSectionCache {
  static const int entryLimit = 32;
  static const int byteLimit = 4 * 1024 * 1024;

  final Map<String, _CachedSection> _entries = <String, _CachedSection>{};
  int _bytes = 0;

  int get entryCount => _entries.length;
  int get byteCount => _bytes;

  Object? take(String key) {
    final cached = _entries.remove(key);
    if (cached == null) return null;
    _entries[key] = cached;
    return cached.value;
  }

  void remove(String key) {
    final removed = _entries.remove(key);
    if (removed != null) _bytes -= removed.encodedBytes;
  }

  void put(String key, Object value, int encodedBytes) {
    remove(key);
    if (encodedBytes <= 0 || encodedBytes > byteLimit) return;
    while (_entries.isNotEmpty &&
        (_entries.length >= entryLimit || _bytes + encodedBytes > byteLimit)) {
      remove(_entries.keys.first);
    }
    _entries[key] = _CachedSection(value: value, encodedBytes: encodedBytes);
    _bytes += encodedBytes;
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

final class WebDavSyncCycleContext {
  const WebDavSyncCycleContext({
    required this.namespaceId,
    required this.deviceId,
    required this.markerPin,
    required this.root,
    required this.circleToLocalProfiles,
    required this.circleToLocalResources,
    this.wireProfileMap = const <String, String>{},
    this.wireResourceMap = const <String, String>{},
    this.active = false,
  });

  final String? namespaceId;
  final String? deviceId;
  final Uint8List? markerPin;
  final OpenedWebDavSyncRoot? root;
  final Map<String, String>? circleToLocalProfiles;
  final Map<String, String>? circleToLocalResources;

  /// Graph backup IDs -> circle IDs; these are wire identities, never local
  /// profile or resource IDs. M5 supplies them when graph activation lands.
  final Map<String, String> wireProfileMap;
  final Map<String, String> wireResourceMap;
  final bool active;

  bool get isComplete =>
      namespaceId != null &&
      deviceId != null &&
      markerPin != null &&
      markerPin!.isNotEmpty &&
      root != null &&
      circleToLocalProfiles != null &&
      circleToLocalResources != null;
}

typedef WebDavSyncTransportFactory =
    WebDavSyncTransport Function(WebDavSyncCycleContext context);

typedef WebDavSyncDiagnostic = void Function(String message, Object? error);

abstract interface class WebDavSyncCycleRunner {
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  });
}

/// Dormant until M5 supplies an active, root-authenticated context and both ID
/// maps. Merely constructing this engine never schedules work.
final class WebDavSyncEngine implements WebDavSyncCycleRunner {
  WebDavSyncEngine({
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncLocalAdapter localAdapter,
    required WebDavSyncTransportFactory transportFactory,
    WebDavSyncCodec? codec,
    WebDavSyncSectionCache? sectionCache,
    DateTime Function()? clock,
    WebDavSyncDiagnostic? diagnostic,
    this.readConcurrency = 4,
  }) : _stateRepository = stateRepository,
       _localAdapter = localAdapter,
       _transportFactory = transportFactory,
       _codec = codec ?? WebDavSyncCodec(),
       _sectionCache = sectionCache ?? WebDavSyncSectionCache(),
       _clock = clock ?? DateTime.now,
       _diagnostic = diagnostic ?? _ignoreDiagnostic,
       assert(readConcurrency >= 1 && readConcurrency <= 4);

  static const Duration staleManifestCutoff = Duration(days: 30);
  static const Duration tombstoneHorizon = Duration(days: 90);
  static const Duration unreferencedSectionRetention = Duration(days: 7);
  static const String _outboxStatusHint =
      'Circle changes are waiting for deletion history to be saved';
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncLocalAdapter _localAdapter;
  final WebDavSyncTransportFactory _transportFactory;
  final WebDavSyncCodec _codec;
  final WebDavSyncSectionCache _sectionCache;
  final DateTime Function() _clock;
  final WebDavSyncDiagnostic _diagnostic;
  final int readConcurrency;
  final Lock _cycleLock = Lock();
  @visibleForTesting
  int get debugSectionCacheEntries => _sectionCache.entryCount;

  @visibleForTesting
  int get debugSectionCacheBytes => _sectionCache.byteCount;

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) => _cycleLock.synchronized(
    () => _runInstrumentedCycle(
      context,
      allowPreActivation: allowPreActivation,
      trigger: trigger,
    ),
  );

  Future<WebDavSyncCycleReport> _runInstrumentedCycle(
    WebDavSyncCycleContext? context, {
    required bool allowPreActivation,
    required WebDavSyncTrigger? trigger,
  }) async {
    final instrumentation = _CycleInstrumentation(trigger);
    try {
      final report = await _runCycle(
        context,
        allowPreActivation: allowPreActivation,
        trigger: trigger,
        instrumentation: instrumentation,
      );
      instrumentation.disposition = report.disposition.name;
      return report;
    } catch (_) {
      instrumentation.disposition = 'failed';
      rethrow;
    } finally {
      instrumentation.record();
    }
  }

  Future<WebDavSyncCycleReport> _runCycle(
    WebDavSyncCycleContext? context, {
    required bool allowPreActivation,
    required WebDavSyncTrigger? trigger,
    required _CycleInstrumentation instrumentation,
  }) async {
    var circlePublicationAllowed = true;
    if (_localAdapter is WebDavSyncRegistryTombstoneOutboxDrainer) {
      try {
        circlePublicationAllowed =
            await (_localAdapter as WebDavSyncRegistryTombstoneOutboxDrainer)
                .drainRegistryTombstoneOutbox();
        if (!circlePublicationAllowed) {
          _diagnostic(
            'Deferred WebDAV circle publication until the registry tombstone '
            'outbox drains',
            null,
          );
        }
      } catch (error) {
        circlePublicationAllowed = false;
        _diagnostic('Deferred WebDAV registry tombstone outbox drain', error);
      }
    }
    if (context == null ||
        !context.isComplete ||
        (!context.active && !allowPreActivation)) {
      return WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
        statusHint: circlePublicationAllowed ? null : _outboxStatusHint,
      );
    }
    final namespaceId = context.namespaceId!;
    final deviceId = context.deviceId!;
    final root = context.root!;
    final markerPin = context.markerPin!;
    var identityMaps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: context.circleToLocalProfiles!,
      circleToLocalResources: context.circleToLocalResources!,
    );
    if (root.document.circleId.isEmpty) {
      throw StateError('WebDAV sync root context is invalid');
    }

    var state = await _stateRepository.load(namespaceId);
    if (!circlePublicationAllowed) {
      state = await _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(statusHint: _outboxStatusHint),
      );
    } else if (state.statusHint == _outboxStatusHint) {
      state = await _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(clearStatusHint: true),
      );
    }
    if (state.blocksAllPushes) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.adoptionBlocked,
      );
    }
    final persistedManifest = state.ownManifest;
    if (persistedManifest != null &&
        (persistedManifest.circleId != root.document.circleId ||
            persistedManifest.deviceId != deviceId)) {
      throw StateError('WebDAV sync local manifest identity is invalid');
    }
    if (context.active && !allowPreActivation && state.ownManifest == null) {
      throw StateError('Active WebDAV sync requires a verified local manifest');
    }
    _validatePersistedMaps(state, identityMaps);
    state = await _persistMapsIfNeeded(namespaceId, state, identityMaps);
    state = await _promotePendingLocalTombstones(
      namespaceId,
      state,
      identityMaps,
    );

    WebDavSyncLocalSession? session;
    final circleAdapter = _localAdapter is WebDavSyncCircleLocalAdapter
        ? _localAdapter as WebDavSyncCircleLocalAdapter
        : null;
    final pendingCircle = state.pendingCircleApply;
    if (pendingCircle != null) {
      if (circleAdapter == null) {
        throw StateError('WebDAV sync circle apply adapter is unavailable');
      }
      session ??= await _localAdapter.beginCycle();
      final pendingInventory = _mapCircleInventory(
        await circleAdapter.readCircleInventory(session),
        identityMaps,
      );
      final pendingDeferredCircleId =
          WebDavSyncCircleMerge.selectAdminSafetyDeferral(
            profiles: pendingCircle.profiles,
            localManagingAdminCircleProfileIds:
                pendingInventory.managingAdminCircleProfileIds,
          );
      final pendingDeferredLocalId = pendingDeferredCircleId == null
          ? null
          : identityMaps.circleToLocalProfiles[pendingDeferredCircleId];
      final pendingAdminHint = pendingDeferredLocalId == null
          ? null
          : _adminSafetyStatusHint(
              pendingInventory.localProfileNames[pendingDeferredLocalId] ??
                  pendingDeferredCircleId!,
            );
      state = await _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(
          pendingAdminSafetyProfile: pendingDeferredLocalId,
          clearPendingAdminSafetyProfile: pendingDeferredLocalId == null,
          statusHint: circlePublicationAllowed
              ? pendingAdminHint
              : _outboxStatusHint,
          clearStatusHint: circlePublicationAllowed && pendingAdminHint == null,
        ),
      );
      if (pendingAdminHint != null) _diagnostic(pendingAdminHint, null);
      try {
        WebDavSyncCircleMerge.validateApplicableState(
          profiles: pendingCircle.profiles,
          resources: pendingCircle.resources,
          localCircleProfileIds: pendingInventory.circleProfileIds,
          localCircleResourceIds: pendingInventory.circleResourceIds,
          localCircleGrantIds: pendingInventory.circleGrantIds,
          localManagingAdminCircleProfileIds:
              pendingInventory.managingAdminCircleProfileIds,
        );
      } on WebDavSyncDeterministicCircleValidationException catch (error) {
        state = await _stateRepository.update(
          namespaceId,
          (current) => current.copyWith(
            clearPendingCircleApply: true,
            clearPendingActiveProfileDeletion: true,
            clearPendingAdminSafetyProfile: true,
            clearStatusHint: circlePublicationAllowed,
          ),
        );
        _diagnostic(
          'Quarantined an invalid pending WebDAV circle target',
          error,
        );
      }
      if (state.pendingCircleApply != null) {
        final phaseStarted = instrumentation.startPhase();
        try {
          final deferredLocalId = state.pendingActiveProfileDeletion;
          final deferredCircleId = deferredLocalId == null
              ? null
              : identityMaps.localToCircleProfiles[deferredLocalId];
          await circleAdapter.applyCircleState(
            session,
            WebDavSyncCircleApplyRequest(
              identityMaps: identityMaps,
              circleId: root.document.circleId,
              circleKey: root.key,
              profiles: pendingCircle.profiles,
              resources: pendingCircle.resources,
              deferredActiveCircleProfileId: deferredCircleId,
              deferredAdminCircleProfileId: pendingDeferredCircleId,
            ),
            replayingPending: true,
          );
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(
              circleProfilesBaseline: pendingCircle.profiles,
              circleResourcesBaseline: pendingCircle.resources,
              clearPendingCircleApply: true,
            ),
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
        }
      }
    }
    final pendingProfiles = state.profiles.entries
        .where((entry) => entry.value.pendingApply != null)
        .toList(growable: false);
    if (pendingProfiles.isNotEmpty) {
      final phaseStarted = instrumentation.startPhase();
      try {
        session = await _localAdapter.beginCycle();
        for (final entry in pendingProfiles) {
          final pending = entry.value.pendingApply!;
          if (context.circleToLocalProfiles![entry.key] !=
              pending.localProfileId) {
            throw StateError('WebDAV sync pending apply mapping changed');
          }
          await _localAdapter.applyProfile(
            session,
            pending.localProfileId,
            pending.values,
            replayingPending: true,
          );
          await _stateRepository.update(namespaceId, (current) {
            final profiles = Map<String, WebDavSyncProfileEngineState>.from(
              current.profiles,
            );
            final profile =
                profiles[entry.key] ?? const WebDavSyncProfileEngineState();
            profiles[entry.key] = profile.copyWith(
              baseline: pending.target,
              clearPendingApply: true,
            );
            return current.copyWith(
              profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                profiles,
              ),
            );
          });
        }
        state = await _stateRepository.load(namespaceId);
      } finally {
        instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
      }
    }

    final transport = _transportFactory(context);
    try {
      late final WebDavBytesResult rootRead;
      var phaseStarted = instrumentation.startPhase();
      try {
        rootRead = await _readRequiredRoot(transport, instrumentation);
      } finally {
        instrumentation.finishPhase(_CyclePhase.root, phaseStarted);
      }
      if (!_bytesEqual(markerPin, rootRead.bytes)) {
        throw const WebDavSyncRootChangedException();
      }
      late final WebDavSyncPeerListing listing;
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted();
        listing = await transport.listDeviceIds();
      } finally {
        instrumentation.finishPhase(_CyclePhase.list, phaseStarted);
      }
      instrumentation.peerCount = listing.deviceIds
          .where((listedDeviceId) => listedDeviceId != deviceId)
          .length;
      final localNowMs = _clock().toUtc().millisecondsSinceEpoch;
      final clockDecision = WebDavSyncClockPolicy.observe(
        prior: state.clock,
        localNowMs: localNowMs,
        serverDate: rootRead.metadata.serverDate ?? listing.metadata.serverDate,
      );
      state = await _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(
          clock: clockDecision.state,
          deviceClockWarning: clockDecision.deviceClockWarning,
          lastClockPauseReason: clockDecision.pauseReason,
          clearClockPauseReason: clockDecision.pauseReason == null,
        ),
      );
      if (!clockDecision.mayPublish) {
        return WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.clockPaused,
          peerCount: listing.deviceIds.length,
          deviceClockWarning: clockDecision.deviceClockWarning,
          clockPauseReason: clockDecision.pauseReason,
        );
      }
      // A missing manifest inside an existing own-device directory is safe to
      // repair from the persisted references below. If the directory itself
      // disappeared, those referenced content-addressed sections disappeared
      // with it; publishing only a replacement manifest would create a
      // permanently broken seed. Ask the graph tier to rebuild every section.
      if (state.ownManifest != null && !listing.deviceIds.contains(deviceId)) {
        return WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.seedRepairRequired,
          peerCount: listing.deviceIds.length,
          deviceClockWarning: clockDecision.deviceClockWarning,
        );
      }
      final serverNowMs = clockDecision.serverNowMs!;
      final manifestReads = await _readManifests(
        transport: transport,
        context: context,
        deviceIds: listing.deviceIds,
        state: state,
        serverNowMs: serverNowMs,
        instrumentation: instrumentation,
      );
      final manifests = <String, WebDavSyncManifest>{
        for (final entry in manifestReads.entries)
          entry.key: entry.value.manifest,
      };
      final verifiedOwnManifest = manifests[deviceId];
      if (verifiedOwnManifest != null &&
          (state.ownManifest == null ||
              verifiedOwnManifest.updatedAtMs >=
                  state.ownManifest!.updatedAtMs)) {
        state = await _stateRepository.update(
          namespaceId,
          (current) => current.copyWith(ownManifest: verifiedOwnManifest),
        );
      }
      final peerHighWater = Map<String, int>.from(state.peerManifestHighWater);
      for (final entry in manifests.entries) {
        final prior = peerHighWater[entry.key] ?? 0;
        if (entry.value.updatedAtMs > prior) {
          peerHighWater[entry.key] = entry.value.updatedAtMs;
        }
      }
      state = await _stateRepository.update(
        namespaceId,
        (current) => current.copyWith(
          peerManifestHighWater: boundedPeerManifestHighWater(
            peerHighWater,
            currentDeviceIds: listing.deviceIds,
          ),
          peerManifestValidators:
              Map<String, WebDavSyncManifestValidator>.unmodifiable(
                <String, WebDavSyncManifestValidator>{
                  for (final entry in manifestReads.entries)
                    if (entry.key != deviceId && entry.value.validator != null)
                      entry.key: entry.value.validator!,
                },
              ),
          currentDeviceIds: Set<String>.unmodifiable(manifests.keys),
        ),
      );

      session ??= await _localAdapter.beginCycle();
      _CircleCycleResult? circleResult;
      if (circleAdapter != null && circlePublicationAllowed) {
        final peerCircle = await _readCirclePeerData(
          transport: transport,
          root: root,
          manifests: manifests,
          instrumentation: instrumentation,
        );
        final remoteProfiles = WebDavSyncCircleMerge.mergeProfiles(
          peerCircle.profiles,
        );
        final remoteResources = WebDavSyncCircleMerge.mergeResources(
          peerCircle.resources,
        );
        final inventory = await circleAdapter.readCircleInventory(session);
        final plan = WebDavSyncGraphIdentityPlanner.ensureIncludingCircleIds(
          localProfileIds: inventory.localProfileIds,
          localResourceIds: inventory.localResourceIds,
          liveCircleProfileIds: remoteProfiles.profiles.entries
              .where((entry) => entry.value.value != null)
              .map((entry) => entry.key),
          liveCircleResourceIds: remoteResources.resources.entries
              .where((entry) => entry.value.metadata.value != null)
              .map((entry) => entry.key),
          currentCircleToLocalProfiles: state.circleToLocalProfiles,
          currentCircleToLocalResources: state.circleToLocalResources,
        );
        identityMaps = plan.maps;
        final circleInventory = _mapCircleInventory(inventory, identityMaps);
        if (!_mapEquals(
              state.circleToLocalProfiles!,
              identityMaps.circleToLocalProfiles,
            ) ||
            !_mapEquals(
              state.circleToLocalResources!,
              identityMaps.circleToLocalResources,
            )) {
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(
              circleToLocalProfiles: identityMaps.circleToLocalProfiles,
              circleToLocalResources: identityMaps.circleToLocalResources,
            ),
          );
        }
        final phaseStarted = instrumentation.startPhase();
        try {
          final built = await circleAdapter.buildCircleState(
            session,
            WebDavSyncCircleBuildRequest(
              identityMaps: identityMaps,
              deviceId: deviceId,
              circleId: root.document.circleId,
              circleKey: root.key,
              localNowMs: localNowMs,
              clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
              serverNowMs: serverNowMs,
              previousProfiles: state.circleProfilesBaseline,
              previousResources: state.circleResourcesBaseline,
              suppressedLocalProfileIds: <String>{
                if (state.pendingActiveProfileDeletion != null)
                  state.pendingActiveProfileDeletion!,
                if (state.pendingAdminSafetyProfile != null)
                  state.pendingAdminSafetyProfile!,
              },
            ),
          );
          final mergedProfiles = WebDavSyncCircleMerge.mergeProfiles(
            <WebDavSyncProfilesDocument>[
              built.profiles,
              ...peerCircle.profiles,
            ],
          );
          final mergedResourceWinners = WebDavSyncCircleMerge.mergeResources(
            <WebDavSyncResourcesDocument>[
              built.resources,
              ...peerCircle.resources,
            ],
          );
          final mergedResources =
              WebDavSyncCircleMerge.deriveApplicableResources(
                profiles: mergedProfiles,
                resources: mergedResourceWinners,
                localCircleProfileIds: circleInventory.circleProfileIds,
                localCircleResourceIds: circleInventory.circleResourceIds,
                localCircleGrantIds: circleInventory.circleGrantIds,
              );
          final deferredAdminCircleId =
              WebDavSyncCircleMerge.selectAdminSafetyDeferral(
                profiles: mergedProfiles,
                localManagingAdminCircleProfileIds:
                    circleInventory.managingAdminCircleProfileIds,
              );
          final deferredAdminLocalId = deferredAdminCircleId == null
              ? null
              : identityMaps.circleToLocalProfiles[deferredAdminCircleId];
          final adminHint = deferredAdminLocalId == null
              ? null
              : _adminSafetyStatusHint(
                  circleInventory.localProfileNames[deferredAdminLocalId] ??
                      deferredAdminCircleId!,
                );
          WebDavSyncCircleMerge.validateApplicableState(
            profiles: mergedProfiles,
            resources: mergedResources,
            localCircleProfileIds: circleInventory.circleProfileIds,
            localCircleResourceIds: circleInventory.circleResourceIds,
            localCircleGrantIds: circleInventory.circleGrantIds,
            localManagingAdminCircleProfileIds:
                circleInventory.managingAdminCircleProfileIds,
          );
          final activeCircleId =
              identityMaps.localToCircleProfiles[session.scope.profileId];
          final deferActive =
              activeCircleId != null &&
                  mergedProfiles.profiles[activeCircleId]?.value == null
              ? session.scope.profileId
              : null;
          final cancelDeferredActive =
              state.pendingActiveProfileDeletion == session.scope.profileId &&
              activeCircleId != null &&
              mergedProfiles.profiles[activeCircleId]?.value != null;
          final pending = WebDavSyncPendingCircleApply(
            profiles: mergedProfiles,
            resources: mergedResources,
          );
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(
              pendingCircleApply: pending,
              pendingActiveProfileDeletion: deferActive,
              clearPendingActiveProfileDeletion: cancelDeferredActive,
              pendingAdminSafetyProfile: deferredAdminLocalId,
              clearPendingAdminSafetyProfile: deferredAdminLocalId == null,
              statusHint: adminHint,
              clearStatusHint: adminHint == null,
            ),
          );
          if (adminHint != null) _diagnostic(adminHint, null);
          await circleAdapter.applyCircleState(
            session,
            WebDavSyncCircleApplyRequest(
              identityMaps: identityMaps,
              circleId: root.document.circleId,
              circleKey: root.key,
              profiles: mergedProfiles,
              resources: mergedResources,
              deferredActiveCircleProfileId: deferActive == null
                  ? null
                  : activeCircleId,
              deferredAdminCircleProfileId: deferredAdminCircleId,
            ),
          );
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(
              circleProfilesBaseline: mergedProfiles,
              circleResourcesBaseline: mergedResources,
              clearPendingCircleApply: true,
            ),
          );
          circleResult = _CircleCycleResult(
            profiles: mergedProfiles,
            resources: mergedResources,
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
        }
      }
      final profileResults = <String, _ProfileCycleResult>{};
      var profilesApplied = 0;
      for (final mapping in identityMaps.circleToLocalProfiles.entries) {
        final circleProfileId = mapping.key;
        final localProfileId = mapping.value;
        // Circle mappings and nullable leaves are retained indefinitely, but
        // a retired profile has no local preference generation to feed the
        // per-profile hot tier after its deferred physical deletion lands.
        if (circleResult != null &&
            circleResult.profiles.profiles[circleProfileId]?.value == null) {
          continue;
        }
        final peerData = await _readProfilePeerData(
          transport: transport,
          root: root,
          manifests: manifests,
          circleProfileId: circleProfileId,
          serverNowMs: serverNowMs,
          instrumentation: instrumentation,
        );
        final phaseStarted = instrumentation.startPhase();
        try {
          final localSnapshot = await _localAdapter.readProfile(
            session,
            localProfileId,
          );
          final profileState =
              state.profiles[circleProfileId] ??
              const WebDavSyncProfileEngineState();
          final built = WebDavSyncHotMerge.build(
            WebDavSyncBuildInput(
              circleProfileId: circleProfileId,
              deviceId: deviceId,
              rawPreferences: localSnapshot.rawPreferences,
              portablePreferences: localSnapshot.portablePreferences,
              identityMaps: identityMaps,
              localNowMs: localNowMs,
              clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
              serverNowMs: serverNowMs,
              previous: profileState.baseline,
            ),
          );
          final normalizedLocalTombstones = _normalizeLocalTombstones(
            profileState.tombstones,
            clockDecision,
            identityMaps,
            currentRecordKeys: built.document.watchState.records.keys.toSet(),
          );
          final localTombstoneDocument = WebDavSyncTombstoneDocument(
            circleProfileId: circleProfileId,
            items: normalizedLocalTombstones,
          );
          identityMaps.assertContainsNoLocalIds(
            localTombstoneDocument.toJson(),
          );
          final lastSuccess = state.lastSuccessfulSyncMs;
          final dormantSince =
              lastSuccess != null &&
                  serverNowMs - lastSuccess >= tombstoneHorizon.inMilliseconds
              ? lastSuccess
              : null;
          final merged = WebDavSyncHotMerge.clampForPublication(
            WebDavSyncHotMerge.merge(
              local: built.document,
              peers: peerData.hotDocuments,
              tombstoneDocuments: <WebDavSyncTombstoneDocument>[
                localTombstoneDocument,
                ...peerData.tombstoneDocuments,
              ],
              nowMs: serverNowMs,
              tombstoneHorizon: tombstoneHorizon,
              dormantSinceMs: dormantSince,
            ),
            serverNowMs: serverNowMs,
          );
          final values = WebDavSyncHotMerge.materializePreferences(
            document: merged.document,
            identityMaps: identityMaps,
            localRichRecords: built.localRichRecords,
            localPortableRecords: built.document.watchState.records,
            protectedPreferenceKeys: built.protectedPreferenceKeys,
          );
          final pending = WebDavSyncPendingApply(
            localProfileId: localProfileId,
            values: values,
            target: merged.document,
          );
          await _localAdapter.applyProfile(
            session,
            localProfileId,
            values,
            expectedMutationToken: localSnapshot.mutationToken,
            beforeWrite: () => _stateRepository.update(namespaceId, (current) {
              final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                current.profiles,
              );
              final currentProfile =
                  profiles[circleProfileId] ??
                  const WebDavSyncProfileEngineState();
              profiles[circleProfileId] = currentProfile.copyWith(
                pendingApply: pending,
              );
              return current.copyWith(
                profiles:
                    Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                      profiles,
                    ),
              );
            }),
          );
          await _stateRepository.update(namespaceId, (current) {
            final profiles = Map<String, WebDavSyncProfileEngineState>.from(
              current.profiles,
            );
            final currentProfile =
                profiles[circleProfileId] ??
                const WebDavSyncProfileEngineState();
            profiles[circleProfileId] = currentProfile.copyWith(
              baseline: merged.document,
              clearPendingApply: true,
            );
            return current.copyWith(
              profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                profiles,
              ),
            );
          });
          profilesApplied++;
          profileResults[circleProfileId] = _ProfileCycleResult(
            document: merged.document,
            tombstones: merged.tombstones,
            originalLocalTombstones: profileState.tombstones,
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
        }
      }

      state = await _stateRepository.load(namespaceId);
      if (state.blocksAllPushes) {
        return WebDavSyncCycleReport(
          disposition: WebDavSyncCycleDisposition.adoptionBlocked,
          peerCount: manifests.length,
          profilesApplied: profilesApplied,
          deviceClockWarning: clockDecision.deviceClockWarning,
        );
      }
      final push = await _pushChanged(
        transport: transport,
        context: context,
        session: session,
        root: root,
        identityMaps: identityMaps,
        state: state,
        profiles: profileResults,
        circle: circleResult,
        serverNowMs: serverNowMs,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        repairManifest: verifiedOwnManifest == null,
        instrumentation: instrumentation,
      );
      state = await _stateRepository.update(namespaceId, (current) {
        final profiles = Map<String, WebDavSyncProfileEngineState>.from(
          current.profiles,
        );
        for (final entry in push.publishedProfiles.entries) {
          final currentProfile =
              profiles[entry.key] ?? const WebDavSyncProfileEngineState();
          final cycleResult = profileResults[entry.key]!;
          profiles[entry.key] = currentProfile.copyWith(
            tombstones: _mergePublishedTombstones(
              current: currentProfile.tombstones,
              originalLocal: cycleResult.originalLocalTombstones,
              published: entry.value.tombstones,
            ),
            lastPushedHotDigest: entry.value.hotDigest,
            lastPushedTombstoneDigest: entry.value.tombstoneDigest,
          );
        }
        return current.copyWith(
          profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
            profiles,
          ),
          ownManifest: push.manifest ?? current.ownManifest,
          lastPushedProfilesDigest:
              push.publishedProfilesDigest ?? current.lastPushedProfilesDigest,
          lastPushedResourcesDigest:
              push.publishedResourcesDigest ??
              current.lastPushedResourcesDigest,
          lastSuccessfulSyncMs: serverNowMs,
          lastPushMs: push.sectionsPushed > 0
              ? serverNowMs
              : current.lastPushMs,
          lastRemoteChangeMs: trigger == WebDavSyncTrigger.remoteChange
              ? serverNowMs
              : current.lastRemoteChangeMs,
        );
      });
      await _collectUnreferencedOwnSections(
        transport: transport,
        session: session,
        deviceId: deviceId,
        manifest: state.ownManifest,
        serverNowMs: serverNowMs,
        instrumentation: instrumentation,
      );
      return WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.completed,
        peerCount: manifests.length,
        profilesApplied: profilesApplied,
        sectionsPushed: push.sectionsPushed,
        deviceClockWarning: clockDecision.deviceClockWarning,
        statusHint: state.statusHint,
      );
    } finally {
      transport.close();
    }
  }

  Future<void> _collectUnreferencedOwnSections({
    required WebDavSyncTransport transport,
    required WebDavSyncLocalSession session,
    required String deviceId,
    required WebDavSyncManifest? manifest,
    required int serverNowMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    final gcTransport = transport is WebDavSyncSectionGcTransport
        ? transport as WebDavSyncSectionGcTransport
        : null;
    if (gcTransport == null || manifest == null) return;
    final referenced = manifest.sections
        .map((section) => section.contentHash)
        .toSet();
    final cutoff = serverNowMs - unreferencedSectionRetention.inMilliseconds;
    session.validate();
    late final List<WebDavSyncStoredSection> stored;
    var phaseStarted = instrumentation.startPhase();
    try {
      instrumentation.requestStarted();
      stored = await gcTransport.listOwnSections(deviceId);
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.authentication) rethrow;
      _diagnostic('Deferred WebDAV sync section cleanup', error);
      return;
    } finally {
      instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
    }
    for (final section in stored) {
      if (referenced.contains(section.contentHash) ||
          section.lastModifiedMs > cutoff) {
        continue;
      }
      session.validate();
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted();
        await gcTransport.deleteOwnSection(deviceId, section.contentHash);
      } on WebDavException catch (error) {
        if (error.kind == WebDavErrorKind.authentication) rethrow;
        _diagnostic('Deferred one WebDAV sync section deletion', error);
      } finally {
        instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
      }
    }
  }

  static Future<WebDavBytesResult> _readRequiredRoot(
    WebDavSyncTransport transport,
    _CycleInstrumentation instrumentation,
  ) async {
    instrumentation.requestStarted();
    try {
      final result = await transport.readRootMarker();
      instrumentation.received(result.bytes.length);
      return result;
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.notFound) {
        throw const WebDavSyncRootMissingException();
      }
      rethrow;
    }
  }

  Future<Map<String, _ManifestRead>> _readManifests({
    required WebDavSyncTransport transport,
    required WebDavSyncCycleContext context,
    required List<String> deviceIds,
    required WebDavSyncEngineState state,
    required int serverNowMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    if (deviceIds.length > WebDavSyncLimits.maxPeers) {
      throw StateError('WebDAV sync peer count exceeds its limit');
    }
    final sortedDeviceIds = List<String>.from(deviceIds)..sort();
    final phaseStarted = instrumentation.startPhase();
    late final List<_ManifestRead?> reads;
    try {
      reads = await _mapConcurrentOrdered<String, _ManifestRead?>(
        sortedDeviceIds,
        limit: readConcurrency,
        operation: (deviceId) async {
          try {
            instrumentation.requestStarted();
            final read = await transport.readManifest(deviceId);
            instrumentation.received(read.bytes.length);
            final payload = await _codec.openDocument(
              key: context.root!.key,
              encoded: read.bytes,
              circleId: context.root!.document.circleId,
              deviceId: deviceId,
              logicalName: 'manifest',
              schemaVersion: WebDavSyncManifest.schemaVersion,
              maxBytes: WebDavSyncLimits.maxManifestBytes,
            );
            final manifest = WebDavSyncManifest.fromJson(payload);
            if (manifest.deviceId != deviceId ||
                manifest.circleId != context.root!.document.circleId) {
              throw const FormatException(
                'WebDAV sync manifest identity mismatch',
              );
            }
            if (!WebDavSyncClockPolicy.acceptsRemoteTimestamp(
              timestampMs: manifest.updatedAtMs,
              serverNowMs: serverNowMs,
            )) {
              _diagnostic('Ignored a future-dated WebDAV sync manifest', null);
              return null;
            }
            final highWater = state.peerManifestHighWater[deviceId];
            if (highWater != null && manifest.updatedAtMs < highWater) {
              _diagnostic('Ignored a regressed WebDAV sync manifest', null);
              return null;
            }
            return _ManifestRead(
              manifest: manifest,
              validator: WebDavSyncManifestValidator.fromMetadata(
                read.metadata,
              ),
            );
          } on WebDavException catch (error) {
            if (error.kind != WebDavErrorKind.notFound) rethrow;
            _diagnostic('Ignored a removed WebDAV sync peer', error);
            return null;
          } on Exception catch (error) {
            _diagnostic('Ignored an invalid WebDAV sync peer manifest', error);
            return null;
          }
        },
      );
    } finally {
      instrumentation.finishPhase(_CyclePhase.manifests, phaseStarted);
    }
    return <String, _ManifestRead>{
      for (var index = 0; index < sortedDeviceIds.length; index++)
        if (reads[index] != null) sortedDeviceIds[index]: reads[index]!,
    };
  }

  Future<_PeerProfileData> _readProfilePeerData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required Map<String, WebDavSyncManifest> manifests,
    required String circleProfileId,
    required int serverNowMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    final entries = manifests.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final phaseStarted = instrumentation.startPhase();
    late final List<_PeerProfileData> peers;
    try {
      peers =
          await _mapConcurrentOrdered<
            MapEntry<String, WebDavSyncManifest>,
            _PeerProfileData
          >(
            entries,
            limit: readConcurrency,
            operation: (entry) => _readOnePeerProfileData(
              transport: transport,
              root: root,
              deviceId: entry.key,
              manifest: entry.value,
              circleProfileId: circleProfileId,
              serverNowMs: serverNowMs,
              instrumentation: instrumentation,
            ),
          );
    } finally {
      instrumentation.finishPhase(_CyclePhase.sections, phaseStarted);
    }
    return _PeerProfileData(
      hotDocuments: List<WebDavSyncHotDocument>.unmodifiable(
        peers.expand((peer) => peer.hotDocuments),
      ),
      tombstoneDocuments: List<WebDavSyncTombstoneDocument>.unmodifiable(
        peers.expand((peer) => peer.tombstoneDocuments),
      ),
    );
  }

  Future<_PeerCircleData> _readCirclePeerData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required Map<String, WebDavSyncManifest> manifests,
    required _CycleInstrumentation instrumentation,
  }) async {
    final entries = manifests.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final phaseStarted = instrumentation.startPhase();
    late final List<_PeerCircleData> peers;
    try {
      peers = await _mapConcurrentOrdered(
        entries,
        limit: readConcurrency,
        operation: (entry) => _readOneCirclePeer(
          transport: transport,
          root: root,
          deviceId: entry.key,
          manifest: entry.value,
          instrumentation: instrumentation,
        ),
      );
    } finally {
      instrumentation.finishPhase(_CyclePhase.sections, phaseStarted);
    }
    return _PeerCircleData(
      profiles: List<WebDavSyncProfilesDocument>.unmodifiable(
        peers.expand((peer) => peer.profiles),
      ),
      resources: List<WebDavSyncResourcesDocument>.unmodifiable(
        peers.expand((peer) => peer.resources),
      ),
    );
  }

  Future<_PeerCircleData> _readOneCirclePeer({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required WebDavSyncManifest manifest,
    required _CycleInstrumentation instrumentation,
  }) async {
    WebDavSyncProfilesDocument? profiles;
    WebDavSyncResourcesDocument? resources;
    final profilesRef = manifest.section('profiles');
    if (profilesRef != null &&
        profilesRef.size > WebDavSyncLimits.maxHotDocumentBytes) {
      throw const FormatException('WebDAV sync profiles exceed size limit');
    }
    if (profilesRef != null &&
        profilesRef.schemaVersion == WebDavSyncProfilesDocument.schemaVersion) {
      try {
        final payload = await _readCircleSectionPayload(
          transport: transport,
          root: root,
          deviceId: deviceId,
          reference: profilesRef,
          maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
          instrumentation: instrumentation,
        );
        profiles = WebDavSyncProfilesDocument.fromJson(payload);
        if (profiles.semanticDigest != profilesRef.semanticDigest) {
          throw const FormatException(
            'WebDAV sync profiles section digest mismatch',
          );
        }
        _requireCircleStampBounds(
          _profileStamps(profiles),
          profilesRef.updatedAtMs,
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync profiles section', error);
      } on Exception catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync profiles section', error);
      }
    }
    final resourcesRef = manifest.section('resources');
    if (resourcesRef != null &&
        resourcesRef.size > WebDavSyncLimits.maxGraphDocumentBytes) {
      throw const FormatException('WebDAV sync resources exceed size limit');
    }
    if (resourcesRef != null &&
        resourcesRef.schemaVersion ==
            WebDavSyncResourcesDocument.schemaVersion) {
      try {
        final payload = await _readCircleSectionPayload(
          transport: transport,
          root: root,
          deviceId: deviceId,
          reference: resourcesRef,
          maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
          instrumentation: instrumentation,
        );
        resources = WebDavSyncResourcesDocument.fromJson(payload);
        if (resources.semanticDigest != resourcesRef.semanticDigest) {
          throw const FormatException(
            'WebDAV sync resources section digest mismatch',
          );
        }
        _requireCircleStampBounds(
          _resourceStamps(resources),
          resourcesRef.updatedAtMs,
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync resources section', error);
      } on Exception catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync resources section', error);
      }
    }
    return _PeerCircleData(
      profiles: profiles == null
          ? const <WebDavSyncProfilesDocument>[]
          : <WebDavSyncProfilesDocument>[profiles],
      resources: resources == null
          ? const <WebDavSyncResourcesDocument>[]
          : <WebDavSyncResourcesDocument>[resources],
    );
  }

  Future<Object?> _readCircleSectionPayload({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required WebDavSyncSectionReference reference,
    required int maxBytes,
    required _CycleInstrumentation instrumentation,
  }) async {
    final cacheKey = _sectionCacheKey(
      root.document.circleId,
      deviceId,
      reference,
      reference.name,
    );
    final cached = _cached(cacheKey);
    if (cached != null) return cached;
    instrumentation.requestStarted();
    final encoded = maxBytes == WebDavSyncLimits.maxGraphDocumentBytes
        ? await WebDavSyncLargeSectionIo(codec: _codec).readVerified(
            transport: transport,
            deviceId: deviceId,
            reference: reference,
            maxBytes: maxBytes,
          )
        : (await transport.readSection(
            deviceId,
            reference,
            maxBytes: maxBytes,
          )).bytes;
    instrumentation.received(encoded.length);
    if (encoded.length != reference.size ||
        contentHashOf(encoded) != reference.contentHash) {
      throw const FormatException('WebDAV sync section content mismatch');
    }
    final payload = await _codec.openDocument(
      key: root.key,
      encoded: encoded,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: reference.name,
      schemaVersion: reference.schemaVersion,
      maxBytes: maxBytes,
      runInBackground: maxBytes == WebDavSyncLimits.maxGraphDocumentBytes,
    );
    _cache(cacheKey, payload as Object, reference.size);
    return payload;
  }

  static Iterable<WebDavSyncStamp> _profileStamps(
    WebDavSyncProfilesDocument document,
  ) => document.profiles.values.map((entry) => entry.stamp);

  static Iterable<WebDavSyncStamp> _resourceStamps(
    WebDavSyncResourcesDocument document,
  ) sync* {
    for (final entry in document.resources.values) {
      yield entry.metadata.stamp;
      if (entry.secretConfig != null) yield entry.secretConfig!.stamp;
    }
    for (final values in document.grants.values) {
      yield* values.values.map((entry) => entry.stamp);
    }
    for (final values in document.settings.values) {
      yield* values.values.map((entry) => entry.stamp);
    }
    for (final values in document.bindings.values) {
      yield* values.values.map((entry) => entry.stamp);
    }
  }

  static void _requireCircleStampBounds(
    Iterable<WebDavSyncStamp> stamps,
    int publishedAtMs,
  ) {
    if (stamps.any((stamp) => stamp.normalizedTimeMs > publishedAtMs)) {
      throw const FormatException(
        'WebDAV sync circle section contains a future publication stamp',
      );
    }
  }

  Future<_PeerProfileData> _readOnePeerProfileData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required WebDavSyncManifest manifest,
    required String circleProfileId,
    required int serverNowMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    WebDavSyncHotDocument? hot;
    WebDavSyncTombstoneDocument? tombstone;
    final stale =
        serverNowMs - manifest.updatedAtMs > staleManifestCutoff.inMilliseconds;
    final hotRef = manifest.section('hot/$circleProfileId');
    if (!stale &&
        hotRef != null &&
        (hotRef.schemaVersion == 1 ||
            hotRef.schemaVersion == WebDavSyncHotDocument.schemaVersion) &&
        hotRef.size <= WebDavSyncLimits.maxHotDocumentBytes) {
      try {
        hot = await _readHotSection(
          transport,
          root,
          deviceId,
          hotRef,
          circleProfileId,
          instrumentation,
        );
        if (hotRef.schemaVersion == 1) {
          _diagnostic('Read a legacy WebDAV sync hot section', null);
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync hot section', error);
      } on Exception catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync hot section', error);
      }
    }
    final tombstoneRef = manifest.section('tombstones/$circleProfileId');
    // Tombstones deliberately ignore manifest heartbeat age.
    if (tombstoneRef != null &&
        tombstoneRef.schemaVersion ==
            WebDavSyncTombstoneDocument.schemaVersion &&
        tombstoneRef.size <= WebDavSyncLimits.maxTombstoneDocumentBytes) {
      try {
        tombstone = await _readTombstoneSection(
          transport,
          root,
          deviceId,
          tombstoneRef,
          circleProfileId,
          instrumentation,
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync tombstone section', error);
      } on Exception catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync tombstone section', error);
      }
    }
    return _PeerProfileData(
      hotDocuments: hot == null
          ? const <WebDavSyncHotDocument>[]
          : <WebDavSyncHotDocument>[hot],
      tombstoneDocuments: tombstone == null
          ? const <WebDavSyncTombstoneDocument>[]
          : <WebDavSyncTombstoneDocument>[tombstone],
    );
  }

  Future<WebDavSyncHotDocument> _readHotSection(
    WebDavSyncTransport transport,
    OpenedWebDavSyncRoot root,
    String deviceId,
    WebDavSyncSectionReference reference,
    String circleProfileId,
    _CycleInstrumentation instrumentation,
  ) async {
    final cacheKey = _sectionCacheKey(
      root.document.circleId,
      deviceId,
      reference,
      'hot',
    );
    final cached = _cached(cacheKey);
    if (cached is WebDavSyncHotDocument &&
        cached.circleProfileId == circleProfileId) {
      _requireHotPublicationBounds(cached, reference.updatedAtMs);
      return cached;
    }
    _removeCached(cacheKey);
    final payload = await _readAndOpenSection(
      transport: transport,
      root: root,
      deviceId: deviceId,
      reference: reference,
      maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
      instrumentation: instrumentation,
    );
    if (payload is! Map || payload['version'] != reference.schemaVersion) {
      throw const FormatException('WebDAV sync hot schema claim mismatch');
    }
    final document = WebDavSyncHotDocument.fromJson(payload);
    if (document.circleProfileId != circleProfileId ||
        semanticDigestOf(payload) != reference.semanticDigest) {
      throw const FormatException('WebDAV sync hot section digest mismatch');
    }
    _requireHotPublicationBounds(document, reference.updatedAtMs);
    _cache(cacheKey, document, reference.size);
    return document;
  }

  Future<WebDavSyncTombstoneDocument> _readTombstoneSection(
    WebDavSyncTransport transport,
    OpenedWebDavSyncRoot root,
    String deviceId,
    WebDavSyncSectionReference reference,
    String circleProfileId,
    _CycleInstrumentation instrumentation,
  ) async {
    final cacheKey = _sectionCacheKey(
      root.document.circleId,
      deviceId,
      reference,
      'tombstones',
    );
    final cached = _cached(cacheKey);
    if (cached is WebDavSyncTombstoneDocument &&
        cached.circleProfileId == circleProfileId &&
        cached.semanticDigest == reference.semanticDigest) {
      _requireTombstonePublicationBounds(cached, reference.updatedAtMs);
      return cached;
    }
    _removeCached(cacheKey);
    final payload = await _readAndOpenSection(
      transport: transport,
      root: root,
      deviceId: deviceId,
      reference: reference,
      maxBytes: WebDavSyncLimits.maxTombstoneDocumentBytes,
      instrumentation: instrumentation,
    );
    final document = WebDavSyncTombstoneDocument.fromJson(payload);
    if (document.circleProfileId != circleProfileId ||
        document.semanticDigest != reference.semanticDigest) {
      throw const FormatException(
        'WebDAV sync tombstone section digest mismatch',
      );
    }
    _requireTombstonePublicationBounds(document, reference.updatedAtMs);
    _cache(cacheKey, document, reference.size);
    return document;
  }

  Future<Object?> _readAndOpenSection({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required WebDavSyncSectionReference reference,
    required int maxBytes,
    required _CycleInstrumentation instrumentation,
  }) async {
    instrumentation.requestStarted();
    final read = await transport.readSection(
      deviceId,
      reference,
      maxBytes: maxBytes,
    );
    instrumentation.received(read.bytes.length);
    if (read.bytes.length != reference.size ||
        contentHashOf(read.bytes) != reference.contentHash) {
      throw const FormatException('WebDAV sync section content mismatch');
    }
    return _codec.openDocument(
      key: root.key,
      encoded: read.bytes,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: reference.name,
      schemaVersion: reference.schemaVersion,
      maxBytes: maxBytes,
    );
  }

  Future<_PushResult> _pushChanged({
    required WebDavSyncTransport transport,
    required WebDavSyncCycleContext context,
    required WebDavSyncLocalSession session,
    required OpenedWebDavSyncRoot root,
    required WebDavSyncIdentityMaps identityMaps,
    required WebDavSyncEngineState state,
    required Map<String, _ProfileCycleResult> profiles,
    required _CircleCycleResult? circle,
    required int serverNowMs,
    required int clockOffsetMs,
    required bool repairManifest,
    required _CycleInstrumentation instrumentation,
  }) async {
    final deviceId = context.deviceId!;
    final changed = <_SealedSection>[];
    final published = <String, _PublishedProfile>{};
    final profilesDigest = circle?.profiles.semanticDigest;
    final resourcesDigest = circle?.resources.semanticDigest;
    final pushProfiles =
        circle != null &&
        (state.lastPushedProfilesDigest != profilesDigest ||
            state.ownManifest?.section('profiles') == null);
    final pushResources =
        circle != null &&
        (state.lastPushedResourcesDigest != resourcesDigest ||
            state.ownManifest?.section('resources') == null);
    if (pushProfiles) {
      final phaseStarted = instrumentation.startPhase();
      try {
        changed.add(
          await _sealSection(
            root: root,
            deviceId: deviceId,
            name: 'profiles',
            schemaVersion: WebDavSyncProfilesDocument.schemaVersion,
            payload: circle.profiles.toJson(),
            semanticDigest: profilesDigest!,
            updatedAtMs: serverNowMs,
            maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
          ),
        );
      } finally {
        instrumentation.finishPhase(_CyclePhase.seal, phaseStarted);
      }
    }
    for (final entry in profiles.entries) {
      final profileState =
          state.profiles[entry.key] ?? const WebDavSyncProfileEngineState();
      final hotDigest = entry.value.document.semanticDigest;
      final publishedTombstones = <String, WebDavSyncTombstone>{
        for (final tombstone in entry.value.tombstones.entries)
          tombstone.key: tombstone.value.copyWith(
            firstPublishedAtMs:
                tombstone.value.firstPublishedAtMs ?? serverNowMs,
            rawLocalTime: false,
          ),
      };
      final tombstoneDocument = WebDavSyncTombstoneDocument(
        circleProfileId: entry.key,
        items: Map<String, WebDavSyncTombstone>.unmodifiable(
          publishedTombstones,
        ),
      );
      final tombstoneDigest = tombstoneDocument.semanticDigest;
      if (profileState.lastPushedHotDigest != hotDigest) {
        final phaseStarted = instrumentation.startPhase();
        try {
          changed.add(
            await _sealSection(
              root: root,
              deviceId: deviceId,
              name: 'hot/${entry.key}',
              schemaVersion: WebDavSyncHotDocument.schemaVersion,
              payload: entry.value.document.toJson(),
              semanticDigest: hotDigest,
              updatedAtMs: serverNowMs,
              maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
            ),
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.seal, phaseStarted);
        }
      }
      if (profileState.lastPushedTombstoneDigest != tombstoneDigest) {
        final phaseStarted = instrumentation.startPhase();
        try {
          changed.add(
            await _sealSection(
              root: root,
              deviceId: deviceId,
              name: 'tombstones/${entry.key}',
              schemaVersion: WebDavSyncTombstoneDocument.schemaVersion,
              payload: tombstoneDocument.toJson(),
              semanticDigest: tombstoneDigest,
              updatedAtMs: serverNowMs,
              maxBytes: WebDavSyncLimits.maxTombstoneDocumentBytes,
            ),
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.seal, phaseStarted);
        }
      }
      published[entry.key] = _PublishedProfile(
        hotDigest: hotDigest,
        tombstoneDigest: tombstoneDigest,
        tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(
          publishedTombstones,
        ),
      );
    }
    final dropsLegacyGraph =
        state.ownManifest?.section(WebDavSyncGraphKind.graph.logicalName) !=
        null;
    if (changed.isEmpty &&
        !pushResources &&
        !repairManifest &&
        !dropsLegacyGraph) {
      return _PushResult(
        sectionsPushed: 0,
        publishedProfiles: const <String, _PublishedProfile>{},
      );
    }

    session.validate();
    var phaseStarted = instrumentation.startPhase();
    try {
      instrumentation.requestStarted();
      await transport.ensureOwnLayout(deviceId);
    } finally {
      instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
    }
    for (final section in changed) {
      session.validate();
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted(bytesUp: section.bytes.length);
        await transport.writeSection(
          deviceId,
          section.reference.contentHash,
          section.bytes,
          maxBytes: _maxBytesFor(section.reference.name),
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.preconditionFailed) rethrow;
      } finally {
        instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
      }
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted();
        final readBack = await transport.readSection(
          deviceId,
          section.reference,
          maxBytes: _maxBytesFor(section.reference.name),
        );
        instrumentation.received(readBack.bytes.length);
        if (!_bytesEqual(readBack.bytes, section.bytes)) {
          throw StateError('WebDAV sync section read-back verification failed');
        }
      } finally {
        instrumentation.finishPhase(_CyclePhase.readBack, phaseStarted);
      }
    }

    WebDavSyncSectionReference? resourceReference;
    if (pushResources) {
      session.validate();
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted();
        resourceReference = await WebDavSyncLargeSectionIo(codec: _codec)
            .sealWriteVerify(
              transport: transport,
              key: root.key,
              circleId: root.document.circleId,
              deviceId: deviceId,
              logicalName: 'resources',
              schemaVersion: WebDavSyncResourcesDocument.schemaVersion,
              payload: circle.resources.toJson(),
              semanticDigest: resourcesDigest!,
              updatedAtMs: serverNowMs,
              maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
            );
      } finally {
        instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
      }
    }

    final sections = <String, WebDavSyncSectionReference>{
      for (final section
          in state.ownManifest?.sections ??
              const <WebDavSyncSectionReference>[])
        if (section.name != WebDavSyncGraphKind.graph.logicalName)
          section.name: section,
      for (final section in changed) section.reference.name: section.reference,
      if (resourceReference != null) resourceReference.name: resourceReference,
    };
    if (sections.isEmpty) {
      throw StateError('WebDAV sync refuses to publish an empty manifest');
    }
    final priorManifest = state.ownManifest;
    final manifest = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: serverNowMs,
      clockOffsetMs: clockOffsetMs,
      graphSchemaClaim: WebDavSyncGraphBuilder.schemaVersion,
      profileMap: context.wireProfileMap.isNotEmpty
          ? context.wireProfileMap
          : (priorManifest?.profileMap ?? const <String, String>{}),
      resourceMap: context.wireResourceMap.isNotEmpty
          ? context.wireResourceMap
          : (priorManifest?.resourceMap ?? const <String, String>{}),
      sections: List<WebDavSyncSectionReference>.unmodifiable(
        sections.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      ),
    );
    identityMaps.assertContainsNoLocalIds(manifest.toJson());
    late final Uint8List manifestBytes;
    phaseStarted = instrumentation.startPhase();
    try {
      manifestBytes = await _codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        payload: manifest.toJson(),
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
    } finally {
      instrumentation.finishPhase(_CyclePhase.seal, phaseStarted);
    }
    // Sections are immutable litter until the manifest points at them. The
    // pinned marker and captured profile scope must both still be current at
    // this final commit.
    late final WebDavBytesResult commitRoot;
    phaseStarted = instrumentation.startPhase();
    try {
      commitRoot = await _readRequiredRoot(transport, instrumentation);
    } finally {
      instrumentation.finishPhase(_CyclePhase.root, phaseStarted);
    }
    if (!_bytesEqual(context.markerPin!, commitRoot.bytes)) {
      throw const WebDavSyncRootChangedException();
    }
    session.validate();
    phaseStarted = instrumentation.startPhase();
    try {
      instrumentation.requestStarted(bytesUp: manifestBytes.length);
      await transport.writeManifest(deviceId, manifestBytes);
    } finally {
      instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
    }
    late final Object? opened;
    phaseStarted = instrumentation.startPhase();
    try {
      instrumentation.requestStarted();
      final manifestReadBack = await transport.readManifest(deviceId);
      instrumentation.received(manifestReadBack.bytes.length);
      if (!_bytesEqual(manifestReadBack.bytes, manifestBytes)) {
        throw StateError('WebDAV sync manifest read-back verification failed');
      }
      opened = await _codec.openDocument(
        key: root.key,
        encoded: manifestReadBack.bytes,
        circleId: root.document.circleId,
        deviceId: deviceId,
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
    } finally {
      instrumentation.finishPhase(_CyclePhase.readBack, phaseStarted);
    }
    final verifiedManifest = WebDavSyncManifest.fromJson(opened);
    return _PushResult(
      sectionsPushed: changed.length + (resourceReference == null ? 0 : 1),
      manifest: verifiedManifest,
      publishedProfiles: Map<String, _PublishedProfile>.unmodifiable(published),
      publishedProfilesDigest: profilesDigest,
      publishedResourcesDigest: resourcesDigest,
    );
  }

  Future<_SealedSection> _sealSection({
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    required String name,
    required int schemaVersion,
    required Object payload,
    required String semanticDigest,
    required int updatedAtMs,
    required int maxBytes,
  }) async {
    final bytes = await _codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: name,
      schemaVersion: schemaVersion,
      payload: payload,
      maxBytes: maxBytes,
      runInBackground: maxBytes == WebDavSyncLimits.maxGraphDocumentBytes,
    );
    return _SealedSection(
      bytes: bytes,
      reference: WebDavSyncSectionReference(
        name: name,
        contentHash: contentHashOf(bytes),
        semanticDigest: semanticDigest,
        updatedAtMs: updatedAtMs,
        schemaVersion: schemaVersion,
        size: bytes.length,
      ),
    );
  }

  Future<WebDavSyncEngineState> _persistMapsIfNeeded(
    String namespaceId,
    WebDavSyncEngineState state,
    WebDavSyncIdentityMaps maps,
  ) {
    if (state.circleToLocalProfiles != null &&
        state.circleToLocalResources != null) {
      return Future<WebDavSyncEngineState>.value(state);
    }
    return _stateRepository.update(
      namespaceId,
      (current) => current.copyWith(
        circleToLocalProfiles: maps.circleToLocalProfiles,
        circleToLocalResources: maps.circleToLocalResources,
      ),
    );
  }

  Future<WebDavSyncEngineState> _promotePendingLocalTombstones(
    String namespaceId,
    WebDavSyncEngineState state,
    WebDavSyncIdentityMaps maps,
  ) {
    if (state.pendingLocalProfiles.isEmpty) {
      return Future<WebDavSyncEngineState>.value(state);
    }
    return _stateRepository.update(namespaceId, (current) {
      final pending = Map<String, WebDavSyncProfileEngineState>.from(
        current.pendingLocalProfiles,
      );
      final profiles = Map<String, WebDavSyncProfileEngineState>.from(
        current.profiles,
      );
      var changed = false;
      for (final mapping in maps.circleToLocalProfiles.entries) {
        final local = pending.remove(mapping.value);
        if (local == null) continue;
        changed = true;
        final profile =
            profiles[mapping.key] ?? const WebDavSyncProfileEngineState();
        final tombstones = Map<String, WebDavSyncTombstone>.from(
          profile.tombstones,
        );
        for (final entry in local.tombstones.entries) {
          final existing = tombstones[entry.key];
          if (existing == null || _tombstoneIsNewer(entry.value, existing)) {
            tombstones[entry.key] = entry.value;
          }
        }
        profiles[mapping.key] = profile.copyWith(
          tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(tombstones),
        );
      }
      if (!changed) return current;
      return current.copyWith(
        profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
          profiles,
        ),
        pendingLocalProfiles:
            Map<String, WebDavSyncProfileEngineState>.unmodifiable(pending),
      );
    });
  }

  static bool _tombstoneIsNewer(
    WebDavSyncTombstone left,
    WebDavSyncTombstone right,
  ) =>
      left.stamp.normalizedTimeMs > right.stamp.normalizedTimeMs ||
      left.stamp.normalizedTimeMs == right.stamp.normalizedTimeMs &&
          left.stamp.originDeviceId.compareTo(right.stamp.originDeviceId) > 0;

  static void _validatePersistedMaps(
    WebDavSyncEngineState state,
    WebDavSyncIdentityMaps maps,
  ) {
    final profiles = state.circleToLocalProfiles;
    final resources = state.circleToLocalResources;
    if (profiles != null && !_mapEquals(profiles, maps.circleToLocalProfiles) ||
        resources != null &&
            !_mapEquals(resources, maps.circleToLocalResources)) {
      throw StateError('WebDAV sync authenticated identity maps changed');
    }
  }

  static Map<String, WebDavSyncTombstone> _normalizeLocalTombstones(
    Map<String, WebDavSyncTombstone> source,
    WebDavSyncClockDecision clock,
    WebDavSyncIdentityMaps identityMaps, {
    required Set<String> currentRecordKeys,
  }) {
    final result = <String, WebDavSyncTombstone>{};
    for (final entry in source.entries) {
      final wireKey = WebDavSyncRecordKey.projectLocalTombstoneKey(
        entry.key,
        identityMaps,
      );
      if (wireKey == null) continue;
      if (entry.value.rawLocalTime && currentRecordKeys.contains(wireKey)) {
        continue;
      }
      final normalized =
          (entry.value.rawLocalTime
                  ? entry.value.copyWith(
                      stamp: WebDavSyncStamp(
                        normalizedTimeMs: clock.normalizeLocalTimestamp(
                          entry.value.stamp.normalizedTimeMs,
                        ),
                        originDeviceId: entry.value.stamp.originDeviceId,
                      ),
                      rawLocalTime: false,
                    )
                  : entry.value)
              .copyWithKey(wireKey);
      final prior = result[wireKey];
      if (prior == null || _compareTombstoneStamp(normalized, prior) > 0) {
        result[wireKey] = normalized;
      }
    }
    return Map<String, WebDavSyncTombstone>.unmodifiable(result);
  }

  static int _compareTombstoneStamp(
    WebDavSyncTombstone left,
    WebDavSyncTombstone right,
  ) {
    final time = left.stamp.normalizedTimeMs.compareTo(
      right.stamp.normalizedTimeMs,
    );
    if (time != 0) return time;
    return left.stamp.originDeviceId.compareTo(right.stamp.originDeviceId);
  }

  static Map<String, WebDavSyncTombstone> _mergePublishedTombstones({
    required Map<String, WebDavSyncTombstone> current,
    required Map<String, WebDavSyncTombstone> originalLocal,
    required Map<String, WebDavSyncTombstone> published,
  }) {
    final result = Map<String, WebDavSyncTombstone>.from(published);
    for (final entry in current.entries) {
      final original = originalLocal[entry.key];
      final changedDuringCycle =
          original == null ||
          entry.value.stamp.normalizedTimeMs !=
              original.stamp.normalizedTimeMs ||
          entry.value.rawLocalTime != original.rawLocalTime;
      if (changedDuringCycle) result[entry.key] = entry.value;
    }
    return Map<String, WebDavSyncTombstone>.unmodifiable(result);
  }

  Object? _cached(String key) {
    return _sectionCache.take(key);
  }

  void _removeCached(String key) => _sectionCache.remove(key);

  void _cache(String key, Object value, int encodedBytes) =>
      _sectionCache.put(key, value, encodedBytes);

  static String _sectionCacheKey(
    String circleId,
    String deviceId,
    WebDavSyncSectionReference reference,
    String kind,
  ) =>
      '$circleId:$deviceId:${reference.name}:${reference.schemaVersion}:'
      '${reference.contentHash}:${reference.size}:${reference.updatedAtMs}:$kind';

  static int _maxBytesFor(String name) {
    if (name == 'resources') return WebDavSyncLimits.maxGraphDocumentBytes;
    if (name.startsWith('tombstones/')) {
      return WebDavSyncLimits.maxTombstoneDocumentBytes;
    }
    return WebDavSyncLimits.maxHotDocumentBytes;
  }

  static void _requireHotPublicationBounds(
    WebDavSyncHotDocument document,
    int publishedAtMs,
  ) {
    final stamps = <WebDavSyncStamp>[
      ...document.scalars.entries.values.map((entry) => entry.stamp),
      document.watchState.stamp,
      ...document.watchState.records.values.map((entry) => entry.stamp),
      ...document.watchState.orders.values.map((entry) => entry.stamp),
    ];
    if (stamps.any((stamp) => stamp.normalizedTimeMs > publishedAtMs)) {
      throw const FormatException(
        'WebDAV sync hot section contains a future publication stamp',
      );
    }
  }

  static void _requireTombstonePublicationBounds(
    WebDavSyncTombstoneDocument document,
    int publishedAtMs,
  ) {
    if (document.items.values.any(
      (item) =>
          item.stamp.normalizedTimeMs > publishedAtMs ||
          item.firstPublishedAtMs! > publishedAtMs,
    )) {
      throw const FormatException(
        'WebDAV sync tombstone section contains a future publication stamp',
      );
    }
  }

  static bool _mapEquals(Map<String, String> left, Map<String, String> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);

  static _MappedCircleInventory _mapCircleInventory(
    WebDavSyncCircleInventory inventory,
    WebDavSyncIdentityMaps maps,
  ) {
    final profileIds = inventory.localProfileIds
        .map((id) => maps.localToCircleProfiles[id])
        .whereType<String>()
        .toSet();
    final resourceIds = inventory.localResourceIds
        .map((id) => maps.localToCircleResources[id])
        .whereType<String>()
        .toSet();
    final managingAdminIds = inventory.managingAdminLocalProfileIds
        .map((id) => maps.localToCircleProfiles[id])
        .whereType<String>()
        .toSet();
    final grantIds = <WebDavSyncCircleGrantId>{};
    for (final grant in inventory.localGrantIds) {
      final profileId = maps.localToCircleProfiles[grant.circleProfileId];
      final resourceId = maps.localToCircleResources[grant.circleResourceId];
      if (profileId != null && resourceId != null) {
        grantIds.add((
          circleProfileId: profileId,
          circleResourceId: resourceId,
        ));
      }
    }
    return _MappedCircleInventory(
      circleProfileIds: Set<String>.unmodifiable(profileIds),
      circleResourceIds: Set<String>.unmodifiable(resourceIds),
      circleGrantIds: Set<WebDavSyncCircleGrantId>.unmodifiable(grantIds),
      managingAdminCircleProfileIds: Set<String>.unmodifiable(managingAdminIds),
      localProfileNames: inventory.localProfileNames,
    );
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < left.length ? left[index] : 0) ^
          (index < right.length ? right[index] : 0);
    }
    return difference == 0;
  }

  static void _ignoreDiagnostic(String _, Object? __) {}

  static String _adminSafetyStatusHint(String profile) =>
      'sync kept $profile as Admin on this device';
}

final class _MappedCircleInventory {
  const _MappedCircleInventory({
    required this.circleProfileIds,
    required this.circleResourceIds,
    required this.circleGrantIds,
    required this.managingAdminCircleProfileIds,
    required this.localProfileNames,
  });

  final Set<String> circleProfileIds;
  final Set<String> circleResourceIds;
  final Set<WebDavSyncCircleGrantId> circleGrantIds;
  final Set<String> managingAdminCircleProfileIds;
  final Map<String, String> localProfileNames;
}

final class _ManifestRead {
  const _ManifestRead({required this.manifest, required this.validator});

  final WebDavSyncManifest manifest;
  final WebDavSyncManifestValidator? validator;
}

final class _PeerProfileData {
  const _PeerProfileData({
    required this.hotDocuments,
    required this.tombstoneDocuments,
  });

  final List<WebDavSyncHotDocument> hotDocuments;
  final List<WebDavSyncTombstoneDocument> tombstoneDocuments;
}

Future<List<R>> _mapConcurrentOrdered<T, R>(
  List<T> input, {
  required int limit,
  required Future<R> Function(T value) operation,
}) async {
  if (input.isEmpty) return <R>[];
  final results = List<R?>.filled(input.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < input.length) {
      final index = nextIndex++;
      results[index] = await operation(input[index]);
    }
  }

  final workerCount = input.length < limit ? input.length : limit;
  await Future.wait<void>(
    List<Future<void>>.generate(workerCount, (_) => worker()),
  );
  return List<R>.generate(input.length, (index) => results[index] as R);
}

final class _CachedSection {
  const _CachedSection({required this.value, required this.encodedBytes});

  final Object value;
  final int encodedBytes;
}

final class _ProfileCycleResult {
  const _ProfileCycleResult({
    required this.document,
    required this.tombstones,
    required this.originalLocalTombstones,
  });

  final WebDavSyncHotDocument document;
  final Map<String, WebDavSyncTombstone> tombstones;
  final Map<String, WebDavSyncTombstone> originalLocalTombstones;
}

final class _CircleCycleResult {
  const _CircleCycleResult({required this.profiles, required this.resources});

  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
}

final class _PeerCircleData {
  const _PeerCircleData({required this.profiles, required this.resources});

  final List<WebDavSyncProfilesDocument> profiles;
  final List<WebDavSyncResourcesDocument> resources;
}

final class _SealedSection {
  const _SealedSection({required this.bytes, required this.reference});

  final Uint8List bytes;
  final WebDavSyncSectionReference reference;
}

final class _PublishedProfile {
  const _PublishedProfile({
    required this.hotDigest,
    required this.tombstoneDigest,
    required this.tombstones,
  });

  final String hotDigest;
  final String tombstoneDigest;
  final Map<String, WebDavSyncTombstone> tombstones;
}

final class _PushResult {
  const _PushResult({
    required this.sectionsPushed,
    required this.publishedProfiles,
    this.manifest,
    this.publishedProfilesDigest,
    this.publishedResourcesDigest,
  });

  final int sectionsPushed;
  final WebDavSyncManifest? manifest;
  final Map<String, _PublishedProfile> publishedProfiles;
  final String? publishedProfilesDigest;
  final String? publishedResourcesDigest;
}

enum _CyclePhase {
  root,
  list,
  manifests,
  sections,
  mergeApply,
  seal,
  push,
  readBack,
}

final class _CycleInstrumentation {
  _CycleInstrumentation(this.trigger) : _stopwatch = Stopwatch()..start();

  final WebDavSyncTrigger? trigger;
  final Stopwatch _stopwatch;
  int peerCount = 0;
  int requestCount = 0;
  int bytesUp = 0;
  int bytesDown = 0;
  String disposition = 'failed';
  int _rootUs = 0;
  int _listUs = 0;
  int _manifestsUs = 0;
  int _sectionsUs = 0;
  int _mergeApplyUs = 0;
  int _sealUs = 0;
  int _pushUs = 0;
  int _readBackUs = 0;

  int startPhase() => _stopwatch.elapsedMicroseconds;

  void finishPhase(_CyclePhase phase, int startedAtUs) {
    final elapsedUs = _stopwatch.elapsedMicroseconds - startedAtUs;
    switch (phase) {
      case _CyclePhase.root:
        _rootUs += elapsedUs;
        break;
      case _CyclePhase.list:
        _listUs += elapsedUs;
        break;
      case _CyclePhase.manifests:
        _manifestsUs += elapsedUs;
        break;
      case _CyclePhase.sections:
        _sectionsUs += elapsedUs;
        break;
      case _CyclePhase.mergeApply:
        _mergeApplyUs += elapsedUs;
        break;
      case _CyclePhase.seal:
        _sealUs += elapsedUs;
        break;
      case _CyclePhase.push:
        _pushUs += elapsedUs;
        break;
      case _CyclePhase.readBack:
        _readBackUs += elapsedUs;
        break;
    }
  }

  void requestStarted({int bytesUp = 0}) {
    requestCount++;
    this.bytesUp += bytesUp;
  }

  void received(int byteCount) => bytesDown += byteCount;

  void record() {
    _stopwatch.stop();
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'cycle',
      fields: <String, Object?>{
        'trigger': DiagnosticLabel(trigger?.name ?? 'internal'),
        'peerCount': peerCount,
        'rootMs': _milliseconds(_rootUs),
        'listMs': _milliseconds(_listUs),
        'manifestsMs': _milliseconds(_manifestsUs),
        'sectionsMs': _milliseconds(_sectionsUs),
        'mergeApplyMs': _milliseconds(_mergeApplyUs),
        'sealMs': _milliseconds(_sealUs),
        'pushMs': _milliseconds(_pushUs),
        'readBackMs': _milliseconds(_readBackUs),
        'totalMs': _stopwatch.elapsedMilliseconds,
        'requestCount': requestCount,
        'bytesUp': bytesUp,
        'bytesDown': bytesDown,
        'disposition': DiagnosticLabel(disposition),
      },
    );
  }

  static int _milliseconds(int microseconds) =>
      Duration(microseconds: microseconds).inMilliseconds;
}
