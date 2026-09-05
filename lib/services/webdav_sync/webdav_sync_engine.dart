import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../../models/profiles/user_profile.dart';
import '../diagnostic_log.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/profile_lock_controller.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_circle_merge.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_diagnostics.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_local_adapter.dart';
import 'webdav_sync_large_section_io.dart';
import 'webdav_sync_library_models.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_tombstones.dart';
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
  capacityBlocked,
  clockPaused,
  seedRepairRequired,
  completed,
}

enum WebDavSyncTvManualStage { reading, merging, applying, publishing }

enum WebDavSyncTvManualDisposition {
  completed,
  cancelled,
  inactive,
  firstJoinPending,
  cycleRunning,
  televisionPlayback,
  tvOsLowMemory,
  clockPaused,
  conflict,
}

final class WebDavSyncTvCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

typedef WebDavSyncTvStageCallback =
    void Function(WebDavSyncTvManualStage stage);

final class WebDavSyncTvManualReport {
  const WebDavSyncTvManualReport({
    required this.disposition,
    this.peerCount = 0,
    this.sectionsPushed = 0,
    this.syncedAtMs,
  });

  final WebDavSyncTvManualDisposition disposition;
  final int peerCount;
  final int sectionsPushed;
  final int? syncedAtMs;
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
    this.localChangeFollowUp = false,
    this.localPublicationConfirmed = false,
    this.localProfilesSuppressed = false,
  });

  final WebDavSyncCycleDisposition disposition;
  final int peerCount;
  final int profilesApplied;
  final int sectionsPushed;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? clockPauseReason;
  final String? statusHint;
  final bool localChangeFollowUp;

  /// Publication proof, independent of informational remote-merge warnings.
  /// Profile receipts must additionally check [localProfilesSuppressed].
  /// False when publication was blocked or needs a fresh snapshot.
  final bool localPublicationConfirmed;

  /// Profile records were withheld from the snapshot by a local safety hold.
  /// Other families may still have been published successfully.
  final bool localProfilesSuppressed;
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
    this.authorityContentHash,
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
  final String? authorityContentHash;
  bool matchesAuthority(List<int> bytes) =>
      (authorityContentHash ?? webDavSyncAuthorityHash(markerPin!)) ==
      webDavSyncAuthorityHash(bytes);
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

/// Best-effort post-commit observer. The engine reports logical preference
/// keys only and remains independent of their process or UI consumers.
typedef WebDavSyncAppliedKeysCallback =
    void Function(String localProfileId, Set<String> appliedKeys);

abstract interface class WebDavSyncCycleRunner {
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  });
}

abstract interface class WebDavSyncTvManualRunner {
  Future<WebDavSyncTvManualReport> runTvSync(
    WebDavSyncCycleContext? context, {
    required WebDavSyncTvCancellationToken cancellationToken,
    WebDavSyncTvStageCallback? onStage,
  });
}

/// Optional lifecycle owned by cycle runners that retain transport resources
/// between scheduler signals.
abstract interface class WebDavSyncCycleTransportOwner {
  void closeCycleTransports();
}

/// Dormant until M5 supplies an active, root-authenticated context and both ID
/// maps. Merely constructing this engine never schedules work.
final class WebDavSyncEngine
    implements WebDavSyncCycleRunner, WebDavSyncTvManualRunner {
  WebDavSyncEngine({
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncLocalAdapter localAdapter,
    required WebDavSyncTransportFactory transportFactory,
    WebDavSyncCodec? codec,
    WebDavSyncSectionCache? sectionCache,
    DateTime Function()? clock,
    WebDavSyncDiagnostic? diagnostic,
    WebDavSyncAppliedKeysCallback? appliedKeysCallback,
    this.readConcurrency = 4,
  }) : _stateRepository = stateRepository,
       _localAdapter = localAdapter,
       _transportFactory = transportFactory,
       _codec = codec ?? WebDavSyncCodec(),
       _sectionCache = sectionCache ?? WebDavSyncSectionCache(),
       _clock = clock ?? DateTime.now,
       _diagnostic = diagnostic ?? _ignoreDiagnostic,
       _appliedKeysCallback = appliedKeysCallback ?? _ignoreAppliedKeys,
       assert(readConcurrency >= 1 && readConcurrency <= 4);

  static const Duration staleManifestCutoff = Duration(days: 30);
  static const Duration tombstoneHorizon = Duration(days: 90);
  static const Duration unreferencedSectionRetention = Duration(days: 7);
  static const String _outboxStatusHint =
      'Circle changes are waiting for deletion history to be saved';
  static const String _ambientCapacityStatusHint =
      'Sync paused because saved IPTV and playback activity exceeds 20,000 '
      'items. Remove older history or lists, then press Sync now.';
  static const String _adminSafetyDiagnostic =
      'Deferred a WebDAV sync admin change for local safety';
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncLocalAdapter _localAdapter;
  final WebDavSyncTransportFactory _transportFactory;
  final WebDavSyncCodec _codec;
  final WebDavSyncSectionCache _sectionCache;
  final DateTime Function() _clock;
  final WebDavSyncDiagnostic _diagnostic;
  final WebDavSyncAppliedKeysCallback _appliedKeysCallback;
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

  @override
  Future<WebDavSyncTvManualReport> runTvSync(
    WebDavSyncCycleContext? context, {
    required WebDavSyncTvCancellationToken cancellationToken,
    WebDavSyncTvStageCallback? onStage,
  }) {
    if (_cycleLock.locked) {
      return Future<WebDavSyncTvManualReport>.value(
        const WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cycleRunning,
        ),
      );
    }
    return _cycleLock.synchronized(
      () => _runTvSync(
        context,
        cancellationToken: cancellationToken,
        onStage: onStage,
      ),
    );
  }

  Future<WebDavSyncTvManualReport> _runTvSync(
    WebDavSyncCycleContext? context, {
    required WebDavSyncTvCancellationToken cancellationToken,
    required WebDavSyncTvStageCallback? onStage,
  }) async {
    if (cancellationToken.isCancelled) {
      return const WebDavSyncTvManualReport(
        disposition: WebDavSyncTvManualDisposition.cancelled,
      );
    }
    if (context == null || !context.isComplete || !context.active) {
      return const WebDavSyncTvManualReport(
        disposition: WebDavSyncTvManualDisposition.inactive,
      );
    }
    final tvAdapter = _localAdapter is WebDavSyncTvLibraryLocalAdapter
        ? _localAdapter as WebDavSyncTvLibraryLocalAdapter
        : null;
    if (tvAdapter == null) {
      throw StateError('WebDAV sync Debrify TV adapter is unavailable');
    }
    final namespaceId = context.namespaceId!;
    final deviceId = context.deviceId!;
    final root = context.root!;
    var state = await _stateRepository.load(namespaceId);
    if (state.blocksAllPushes || state.ownManifest == null) {
      return const WebDavSyncTvManualReport(
        disposition: WebDavSyncTvManualDisposition.firstJoinPending,
      );
    }
    final identityMaps = WebDavSyncIdentityMaps(
      circleToLocalProfiles: context.circleToLocalProfiles!,
      circleToLocalResources: context.circleToLocalResources!,
    );
    _validatePersistedMaps(state, identityMaps);
    final persistedManifest = state.ownManifest!;
    if (persistedManifest.circleId != root.document.circleId ||
        persistedManifest.deviceId != deviceId) {
      throw StateError('WebDAV sync local manifest identity is invalid');
    }

    final instrumentation = _CycleInstrumentation(WebDavSyncTrigger.manual);
    final appliedKeysByLocalProfile = <String, Set<String>>{};
    final transport = _transportFactory(context);
    var peerCount = 0;
    try {
      _reportTvStage(onStage, WebDavSyncTvManualStage.reading);
      final rootRead = await _readRequiredRoot(transport, instrumentation);
      if (!context.matchesAuthority(rootRead.bytes)) {
        throw const WebDavSyncRootChangedException();
      }
      instrumentation.requestStarted();
      final listing = await transport.listDeviceIds();
      peerCount = listing.deviceIds
          .where((listedDeviceId) => listedDeviceId != deviceId)
          .length;
      instrumentation.peerCount = peerCount;
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
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.clockPaused,
          peerCount: peerCount,
        );
      }
      if (!listing.deviceIds.contains(deviceId)) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.inactive,
          peerCount: peerCount,
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
          verifiedOwnManifest.updatedAtMs >= state.ownManifest!.updatedAtMs) {
        state = await _stateRepository.update(
          namespaceId,
          (current) => current.copyWith(ownManifest: verifiedOwnManifest),
        );
      }
      final ownManifest = state.ownManifest!;
      final session = await _localAdapter.beginCycle();
      final localProfileId = session.scope.profileId;
      final circleProfileId =
          identityMaps.localToCircleProfiles[localProfileId];
      if (circleProfileId == null) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.inactive,
          peerCount: peerCount,
        );
      }
      final local = await tvAdapter.readTvLibrary(
        session,
        localProfileId,
        WebDavSyncLibraryBuildRequest(
          circleProfileId: circleProfileId,
          identityMaps: identityMaps,
          clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
          serverNowMs: serverNowMs,
        ),
      );
      final peerData = await _readTvLibraryPeerData(
        transport: transport,
        root: root,
        ownDeviceId: deviceId,
        ownManifest: ownManifest,
        manifests: manifests,
        circleProfileId: circleProfileId,
        lastMergedPeerSections: state.lastMergedPeerSections,
        serverNowMs: serverNowMs,
        instrumentation: instrumentation,
      );
      if (cancellationToken.isCancelled) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cancelled,
          peerCount: peerCount,
        );
      }

      _reportTvStage(onStage, WebDavSyncTvManualStage.merging);
      final merged = WebDavSyncLibraryMerge.merge(
        circleProfileId: circleProfileId,
        documents: <WebDavSyncLibraryDocument>[
          if (peerData.ownBaseline != null) peerData.ownBaseline!,
          local.document,
          ...peerData.peerDocuments,
        ],
      ).onlyTvRecords();
      final target = await _finalizeLibraryTargetOffMain(identityMaps, merged);
      if (cancellationToken.isCancelled) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cancelled,
          peerCount: peerCount,
        );
      }

      _reportTvStage(onStage, WebDavSyncTvManualStage.applying);
      final outcome = await tvAdapter.applyTvLibrary(
        session,
        localProfileId,
        WebDavSyncLibraryApplyRequest(
          circleProfileId: circleProfileId,
          identityMaps: identityMaps,
          document: target,
          observedRevisions: local.revisions,
          hiddenGroupNamesByWireKey: const <String, String>{},
        ),
      );
      if (outcome.result == WebDavSyncLibraryApplyResult.conflict) {
        _diagnostic(
          'Deferred manual Debrify TV sync after a concurrent local change',
          null,
        );
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.conflict,
          peerCount: peerCount,
        );
      }
      _recordAppliedKeys(
        appliedKeysByLocalProfile,
        localProfileId,
        outcome.appliedNamespaces,
      );
      if (cancellationToken.isCancelled) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cancelled,
          peerCount: peerCount,
        );
      }

      _reportTvStage(onStage, WebDavSyncTvManualStage.publishing);
      final pushed = await _pushTvLibrary(
        transport: transport,
        context: context,
        session: session,
        root: root,
        identityMaps: identityMaps,
        manifest: ownManifest,
        circleProfileId: circleProfileId,
        document: target,
        serverNowMs: serverNowMs,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        instrumentation: instrumentation,
      );
      if (cancellationToken.isCancelled) {
        return WebDavSyncTvManualReport(
          disposition: WebDavSyncTvManualDisposition.cancelled,
          peerCount: peerCount,
          sectionsPushed: pushed.sectionsPushed,
        );
      }
      await _stateRepository.update(namespaceId, (current) {
        final currentDevices = <String>{
          ...current.currentDeviceIds,
          ...manifests.keys,
        };
        final consumed = _ConsumedPeerSections()
          ..addAll(peerData.peerReferences);
        return current.copyWith(
          ownManifest: pushed.manifest,
          lastMergedPeerSections: consumed.mergeInto(
            current.lastMergedPeerSections,
            currentDeviceIds: currentDevices,
          ),
        );
      });
      await tvAdapter.completeTvLibrarySync(
        session,
        localProfileId,
        expectedPendingRevision: local.tvPendingRevision,
        syncedAtMs: serverNowMs,
      );
      instrumentation.disposition = 'tvCompleted';
      return WebDavSyncTvManualReport(
        disposition: WebDavSyncTvManualDisposition.completed,
        peerCount: peerCount,
        sectionsPushed: pushed.sectionsPushed,
        syncedAtMs: serverNowMs,
      );
    } catch (_) {
      instrumentation.disposition = 'tvFailed';
      rethrow;
    } finally {
      transport.close();
      _publishAppliedKeys(appliedKeysByLocalProfile);
      instrumentation.record();
    }
  }

  void _reportTvStage(
    WebDavSyncTvStageCallback? callback,
    WebDavSyncTvManualStage stage,
  ) {
    try {
      callback?.call(stage);
    } catch (error) {
      _diagnostic('Ignored a failed Debrify TV progress callback', error);
    }
  }

  Future<WebDavSyncCycleReport> _runInstrumentedCycle(
    WebDavSyncCycleContext? context, {
    required bool allowPreActivation,
    required WebDavSyncTrigger? trigger,
  }) async {
    final instrumentation = _CycleInstrumentation(trigger);
    final appliedKeysByLocalProfile = <String, Set<String>>{};
    try {
      final report = await _runCycle(
        context,
        allowPreActivation: allowPreActivation,
        trigger: trigger,
        instrumentation: instrumentation,
        appliedKeysByLocalProfile: appliedKeysByLocalProfile,
      );
      instrumentation.disposition = report.disposition.name;
      return report;
    } catch (error) {
      instrumentation.disposition = 'failed';
      if (error is WebDavException) {
        instrumentation.connectionFailure = webDavConnectionFailureFields(
          error,
        );
      }
      // Only the shape of the failure, never its message, URI, or body: a
      // failed cycle event carried nothing before, which left a real field
      // failure unexplainable from the log.
      instrumentation.failureKind = _CycleInstrumentation.describeFailure(
        error,
      );
      rethrow;
    } finally {
      _publishAppliedKeys(appliedKeysByLocalProfile);
      instrumentation.record();
    }
  }

  Future<WebDavSyncCycleReport> _runCycle(
    WebDavSyncCycleContext? context, {
    required bool allowPreActivation,
    required WebDavSyncTrigger? trigger,
    required _CycleInstrumentation instrumentation,
    required Map<String, Set<String>> appliedKeysByLocalProfile,
  }) async {
    var circlePublicationAllowed = true;
    var localChangeFollowUp = false;
    var circleConflict = false;
    final libraryConflictProfiles = <String>{};
    final consumedPeerSections = _ConsumedPeerSections();
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
    final libraryAdapter = _localAdapter is WebDavSyncLibraryLocalAdapter
        ? _localAdapter as WebDavSyncLibraryLocalAdapter
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
      final pendingApplicableResources =
          WebDavSyncCircleMerge.deriveApplicableResources(
            profiles: pendingCircle.profiles,
            resources: pendingCircle.resources,
            localCircleProfileIds: pendingInventory.circleProfileIds,
            localCircleResourceIds: pendingInventory.circleResourceIds,
            localCircleGrantIds: pendingInventory.circleGrantIds,
            onDeferred: (message) => _diagnostic(message, null),
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
      state = await _clearEligiblePendingActiveProfile(
        namespaceId: namespaceId,
        state: state,
        profiles: pendingCircle.profiles,
        identityMaps: identityMaps,
      );
      final pendingActiveCircleId =
          identityMaps.localToCircleProfiles[session.scope.profileId];
      final pendingActiveWinner = pendingActiveCircleId == null
          ? null
          : pendingCircle.profiles.profiles[pendingActiveCircleId];
      final pendingActiveReason = pendingActiveWinner == null
          ? null
          : _activeProfileDeferralReason(pendingActiveWinner.value);
      final pendingDeferredActive = pendingActiveReason == null
          ? null
          : WebDavSyncPendingActiveProfile(
              localProfileId: session.scope.profileId,
              circleProfileId: pendingActiveCircleId,
              reason: pendingActiveReason,
              profileLeaf: pendingActiveWinner,
              expectedPriorUpdatedAtMs: pendingCircle.registryVersions
                  .expectedUpdatedAtMs(
                    WebDavSyncRegistryRecordId.profile(
                      session.scope.profileId,
                    ).storageKey,
                  ),
            );
      final pendingAdminHint = pendingDeferredLocalId == null
          ? null
          : pendingDeferredActive?.localProfileId == pendingDeferredLocalId
          ? _activeAdminSafetyStatusHint(
              pendingInventory.localProfileNames[pendingDeferredLocalId] ??
                  pendingDeferredCircleId!,
            )
          : _adminSafetyStatusHint(
              pendingInventory.localProfileNames[pendingDeferredLocalId] ??
                  pendingDeferredCircleId!,
            );
      try {
        WebDavSyncCircleMerge.validateApplicableState(
          profiles: pendingCircle.profiles,
          resources: pendingApplicableResources,
          localCircleProfileIds: pendingInventory.circleProfileIds,
          localCircleResourceIds: pendingInventory.circleResourceIds,
          localCircleGrantIds: pendingInventory.circleGrantIds,
          localManagingAdminCircleProfileIds:
              pendingInventory.managingAdminCircleProfileIds,
        );
      } on WebDavSyncDeterministicCircleValidationException catch (error) {
        state = await _stateRepository.update(
          namespaceId,
          (current) => current.copyWith(clearPendingCircleApply: true),
        );
        _diagnostic(
          'Quarantined an invalid pending WebDAV circle target',
          error,
        );
      }
      if (state.pendingCircleApply != null) {
        final phaseStarted = instrumentation.startPhase();
        try {
          final applyResult = await circleAdapter.applyCircleState(
            session,
            WebDavSyncCircleApplyRequest(
              identityMaps: identityMaps,
              circleId: root.document.circleId,
              circleKey: root.key,
              profiles: pendingCircle.profiles,
              resources: pendingApplicableResources,
              registryVersions: pendingCircle.registryVersions,
              deferredActiveCircleProfileId:
                  pendingActiveCircleId == null || pendingDeferredActive == null
                  ? null
                  : pendingActiveCircleId,
              deferredAdminCircleProfileId: pendingDeferredCircleId,
            ),
            replayingPending: true,
          );
          if (applyResult == WebDavSyncCircleApplyResult.conflict) {
            localChangeFollowUp = true;
            circleConflict = true;
            state = await _stateRepository.update(
              namespaceId,
              (current) => current.copyWith(clearPendingCircleApply: true),
            );
            _diagnostic(
              'Deferred WebDAV circle apply after a concurrent local '
              'registry change',
              null,
            );
          } else {
            state = await _stateRepository.update(
              namespaceId,
              (current) => current.copyWith(
                circleProfilesBaseline: pendingCircle.profiles,
                circleResourcesBaseline: pendingCircle.resources,
                clearPendingCircleApply: true,
                pendingActiveProfile: pendingDeferredActive,
                clearPendingActiveProfileDeletion:
                    pendingDeferredActive == null,
                pendingAdminSafetyProfile: pendingDeferredLocalId,
                clearPendingAdminSafetyProfile: pendingDeferredLocalId == null,
                statusHint: circlePublicationAllowed
                    ? pendingAdminHint
                    : _outboxStatusHint,
                clearStatusHint:
                    circlePublicationAllowed && pendingAdminHint == null,
              ),
            );
            if (pendingAdminHint != null) {
              _diagnostic(_adminSafetyDiagnostic, null);
            }
          }
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
        }
      }
    }
    final transport = _transportFactory(context);
    try {
      final rootPhaseStarted = instrumentation.startPhase();
      final rootFuture = _readRequiredRoot(transport, instrumentation);
      final listPhaseStarted = instrumentation.startPhase();
      instrumentation.requestStarted();
      final listingFuture =
          _captureListing(
            Future<WebDavSyncPeerListing>.sync(transport.listDeviceIds),
          ).whenComplete(
            () =>
                instrumentation.finishPhase(_CyclePhase.list, listPhaseStarted),
          );
      late final WebDavBytesResult rootRead;
      try {
        try {
          rootRead = await rootFuture;
        } finally {
          instrumentation.finishPhase(_CyclePhase.root, rootPhaseStarted);
        }
      } catch (error, stackTrace) {
        await listingFuture;
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!context.matchesAuthority(rootRead.bytes)) {
        await listingFuture;
        throw const WebDavSyncRootChangedException();
      }
      final listing = (await listingFuture).unwrap();
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
      final pendingProfiles = state.profiles.entries
          .where((entry) => entry.value.pendingApply != null)
          .toList(growable: false);
      if (pendingProfiles.isNotEmpty) {
        final replayStarted = instrumentation.startPhase();
        try {
          session ??= await _localAdapter.beginCycle();
          for (final entry in pendingProfiles) {
            final pending = entry.value.pendingApply!;
            if (identityMaps.circleToLocalProfiles[entry.key] !=
                pending.localProfileId) {
              throw StateError('WebDAV sync pending apply mapping changed');
            }
            WebDavSyncHotDocument? replayedTarget;
            var replayedAppliedKeys = const <String>{};
            for (var attempt = 0; attempt < 2; attempt++) {
              final fresh = await _localAdapter.readProfile(
                session,
                pending.localProfileId,
              );
              final currentProfile =
                  state.profiles[entry.key] ??
                  const WebDavSyncProfileEngineState();
              final built = WebDavSyncHotMerge.build(
                WebDavSyncBuildInput(
                  circleProfileId: entry.key,
                  deviceId: deviceId,
                  rawPreferences: fresh.rawPreferences,
                  portablePreferences: fresh.portablePreferences,
                  identityMaps: identityMaps,
                  localNowMs: localNowMs,
                  clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
                  serverNowMs: serverNowMs,
                  previous: currentProfile.baseline,
                ),
              );
              final localTombstones = _normalizeLocalTombstones(
                currentProfile.tombstones,
                clockDecision,
                identityMaps,
                currentRecordKeys: built.document.watchState.records.keys
                    .toSet(),
              );
              final lastSuccess = state.lastSuccessfulSyncMs;
              final dormantSince =
                  lastSuccess != null &&
                      serverNowMs - lastSuccess >=
                          tombstoneHorizon.inMilliseconds
                  ? lastSuccess
                  : null;
              final replayed = WebDavSyncHotMerge.clampForPublication(
                WebDavSyncHotMerge.merge(
                  local: built.document,
                  peers: <WebDavSyncHotDocument>[pending.target],
                  tombstoneDocuments: <WebDavSyncTombstoneDocument>[
                    WebDavSyncTombstoneDocument(
                      circleProfileId: entry.key,
                      items: localTombstones,
                    ),
                  ],
                  nowMs: serverNowMs,
                  tombstoneHorizon: tombstoneHorizon,
                  dormantSinceMs: dormantSince,
                ),
                serverNowMs: serverNowMs,
              );
              final values = WebDavSyncHotMerge.materializePreferences(
                document: replayed.document,
                identityMaps: identityMaps,
                localRichRecords: built.localRichRecords,
                localPortableRecords: built.document.watchState.records,
                protectedPreferenceKeys: built.protectedPreferenceKeys,
              );
              try {
                replayedAppliedKeys = await _localAdapter.applyProfile(
                  session,
                  pending.localProfileId,
                  values,
                  expectedMutationToken: fresh.mutationToken,
                  replayingPending: true,
                );
                replayedTarget = replayed.document;
                break;
              } on ProfilePreferenceMutationConflict {
                if (attempt != 0) rethrow;
                state = await _stateRepository.load(namespaceId);
              }
            }
            await _stateRepository.update(namespaceId, (current) {
              final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                current.profiles,
              );
              final profile =
                  profiles[entry.key] ?? const WebDavSyncProfileEngineState();
              profiles[entry.key] = profile.copyWith(
                baseline: replayedTarget!,
                clearPendingApply: true,
              );
              return current.copyWith(
                profiles:
                    Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                      profiles,
                    ),
              );
            });
            _recordAppliedKeys(
              appliedKeysByLocalProfile,
              pending.localProfileId,
              replayedAppliedKeys,
            );
          }
          state = await _stateRepository.load(namespaceId);
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, replayStarted);
        }
      }
      final pendingLibraries = state.profiles.entries
          .where((entry) => entry.value.pendingLibraryApply != null)
          .toList(growable: false);
      if (pendingLibraries.isNotEmpty) {
        if (libraryAdapter == null) {
          throw StateError('WebDAV sync library apply adapter is unavailable');
        }
        final replayStarted = instrumentation.startPhase();
        try {
          session ??= await _localAdapter.beginCycle();
          for (final entry in pendingLibraries) {
            final pending = entry.value.pendingLibraryApply!;
            if (identityMaps.circleToLocalProfiles[entry.key] !=
                pending.localProfileId) {
              throw StateError('WebDAV sync pending library mapping changed');
            }
            final fresh = await libraryAdapter.readLibrary(
              session,
              pending.localProfileId,
              WebDavSyncLibraryBuildRequest(
                circleProfileId: entry.key,
                identityMaps: identityMaps,
                clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
                serverNowMs: serverNowMs,
              ),
            );
            final replayed = WebDavSyncLibraryMerge.merge(
              circleProfileId: entry.key,
              documents: _ambientLibraryDocuments(<WebDavSyncLibraryDocument>[
                if (entry.value.libraryBaseline != null)
                  entry.value.libraryBaseline!,
                fresh.document,
                pending.target,
              ]),
            );
            if (!_ambientLibraryFits(replayed)) {
              return _persistAmbientCapacityBlock(
                namespaceId: namespaceId,
                peerCount: listing.deviceIds.length,
                deviceClockWarning: clockDecision.deviceClockWarning,
              );
            }
            final outcome = await libraryAdapter.applyLibrary(
              session,
              pending.localProfileId,
              WebDavSyncLibraryApplyRequest(
                circleProfileId: entry.key,
                identityMaps: identityMaps,
                document: replayed,
                observedRevisions: fresh.revisions,
                hiddenGroupNamesByWireKey: fresh.hiddenGroupNamesByWireKey,
              ),
              replayingPending: true,
            );
            if (outcome.result == WebDavSyncLibraryApplyResult.conflict) {
              localChangeFollowUp = true;
              libraryConflictProfiles.add(entry.key);
              await _stateRepository.update(namespaceId, (current) {
                final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                  current.profiles,
                );
                final profile = profiles[entry.key];
                if (profile != null) {
                  profiles[entry.key] = profile.copyWith(
                    clearPendingLibraryApply: true,
                  );
                }
                return current.copyWith(
                  profiles:
                      Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                        profiles,
                      ),
                );
              });
              continue;
            }
            await _stateRepository.update(namespaceId, (current) {
              final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                current.profiles,
              );
              final profile =
                  profiles[entry.key] ?? const WebDavSyncProfileEngineState();
              profiles[entry.key] = profile.copyWith(
                libraryBaseline: replayed,
                clearPendingLibraryApply: true,
              );
              return current.copyWith(
                profiles:
                    Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                      profiles,
                    ),
              );
            });
            _recordAppliedKeys(
              appliedKeysByLocalProfile,
              pending.localProfileId,
              outcome.appliedNamespaces,
            );
          }
          state = await _stateRepository.load(namespaceId);
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, replayStarted);
        }
      }
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
      var localProfilesSuppressed = false;
      circlePublication:
      if (circleAdapter != null &&
          circlePublicationAllowed &&
          !circleConflict) {
        final peerCircle = await _readCirclePeerData(
          transport: transport,
          root: root,
          namespaceId: namespaceId,
          ownDeviceId: deviceId,
          manifests: manifests,
          lastMergedPeerSections: state.lastMergedPeerSections,
          hasProfilesBaseline: state.circleProfilesBaseline != null,
          hasResourcesBaseline: state.circleResourcesBaseline != null,
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
          final suppressedLocalProfileIds = <String>{
            if (state.pendingActiveProfile != null)
              state.pendingActiveProfile!.localProfileId,
            if (state.pendingAdminSafetyProfile != null)
              state.pendingAdminSafetyProfile!,
          };
          localProfilesSuppressed = suppressedLocalProfileIds.isNotEmpty;
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
              suppressedLocalProfileIds: suppressedLocalProfileIds,
            ),
          );
          if (built.registryOutboxRowCount != 0) {
            circlePublicationAllowed = false;
            state = await _stateRepository.update(
              namespaceId,
              (current) => current.copyWith(statusHint: _outboxStatusHint),
            );
            _diagnostic(
              'Deferred WebDAV circle publication because the registry '
              'snapshot has pending tombstones',
              null,
            );
            break circlePublication;
          }
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
                onDeferred: (message) => _diagnostic(message, null),
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
          final activeWinner = activeCircleId == null
              ? null
              : mergedProfiles.profiles[activeCircleId];
          final activeDeferralReason = activeWinner == null
              ? null
              : _activeProfileDeferralReason(activeWinner.value);
          final deferActive = activeDeferralReason == null
              ? null
              : WebDavSyncPendingActiveProfile(
                  localProfileId: session.scope.profileId,
                  circleProfileId: activeCircleId,
                  reason: activeDeferralReason,
                  profileLeaf: activeWinner,
                  expectedPriorUpdatedAtMs: built.registryVersions
                      .expectedUpdatedAtMs(
                        WebDavSyncRegistryRecordId.profile(
                          session.scope.profileId,
                        ).storageKey,
                      ),
                );
          state = await _clearEligiblePendingActiveProfile(
            namespaceId: namespaceId,
            state: state,
            profiles: mergedProfiles,
            identityMaps: identityMaps,
          );
          final effectiveAdminHint =
              deferredAdminLocalId != null &&
                  (deferActive?.localProfileId ??
                          state.pendingActiveProfile?.localProfileId) ==
                      deferredAdminLocalId
              ? _activeAdminSafetyStatusHint(
                  circleInventory.localProfileNames[deferredAdminLocalId] ??
                      deferredAdminCircleId!,
                )
              : adminHint;
          final pending = WebDavSyncPendingCircleApply(
            profiles: mergedProfiles,
            resources: mergedResourceWinners,
            registryVersions: built.registryVersions,
          );
          state = await _stateRepository.update(
            namespaceId,
            (current) => current.copyWith(pendingCircleApply: pending),
          );
          final applyResult = await circleAdapter.applyCircleState(
            session,
            WebDavSyncCircleApplyRequest(
              identityMaps: identityMaps,
              circleId: root.document.circleId,
              circleKey: root.key,
              profiles: mergedProfiles,
              resources: mergedResources,
              registryVersions: built.registryVersions,
              deferredActiveCircleProfileId: deferActive == null
                  ? null
                  : activeCircleId,
              deferredAdminCircleProfileId: deferredAdminCircleId,
            ),
          );
          if (applyResult == WebDavSyncCircleApplyResult.conflict) {
            localChangeFollowUp = true;
            circleConflict = true;
            state = await _stateRepository.update(
              namespaceId,
              (current) => current.copyWith(clearPendingCircleApply: true),
            );
            _diagnostic(
              'Deferred WebDAV circle apply after a concurrent local '
              'registry change',
              null,
            );
          } else {
            state = await _stateRepository.update(
              namespaceId,
              (current) => current.copyWith(
                circleProfilesBaseline: mergedProfiles,
                circleResourcesBaseline: mergedResourceWinners,
                clearPendingCircleApply: true,
                pendingActiveProfile: deferActive,
                clearPendingActiveProfileDeletion: deferActive == null,
                pendingAdminSafetyProfile: deferredAdminLocalId,
                clearPendingAdminSafetyProfile: deferredAdminLocalId == null,
                statusHint: effectiveAdminHint,
                clearStatusHint: effectiveAdminHint == null,
              ),
            );
            if (effectiveAdminHint != null) {
              _diagnostic(_adminSafetyDiagnostic, null);
            }
            circleResult = _CircleCycleResult(
              profiles: mergedProfiles,
              resources: mergedResourceWinners,
            );
            consumedPeerSections.addAll(peerCircle.readReferences);
          }
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
        }
      }
      final profileResults = <String, _ProfileCycleResult>{};
      var profilesApplied = 0;
      // Refresh the visible profile before spending time on other profiles.
      // Preserve the existing order among all remaining mappings.
      final activeProfileId = session.scope.profileId;
      final profileMappings = identityMaps.circleToLocalProfiles.entries;
      final orderedProfiles = [
        ...profileMappings.where((entry) => entry.value == activeProfileId),
        ...profileMappings.where((entry) => entry.value != activeProfileId),
      ];
      for (final mapping in orderedProfiles) {
        final circleProfileId = mapping.key;
        final localProfileId = mapping.value;
        // Circle mappings and nullable leaves are retained indefinitely, but
        // a retired profile has no local preference generation to feed the
        // per-profile hot tier after its deferred physical deletion lands.
        if (circleResult != null &&
            circleResult.profiles.profiles[circleProfileId]?.value == null) {
          continue;
        }
        final profileState =
            state.profiles[circleProfileId] ??
            const WebDavSyncProfileEngineState();
        final peerData = await _readProfilePeerData(
          transport: transport,
          root: root,
          namespaceId: namespaceId,
          ownDeviceId: deviceId,
          manifests: manifests,
          circleProfileId: circleProfileId,
          serverNowMs: serverNowMs,
          profileState: profileState,
          lastMergedPeerSections: state.lastMergedPeerSections,
          instrumentation: instrumentation,
        );
        final phaseStarted = instrumentation.startPhase();
        try {
          late final WebDavSyncLocalProfileSnapshot localSnapshot;
          try {
            localSnapshot = await _localAdapter.readProfile(
              session,
              localProfileId,
            );
          } on WebDavSyncMappedProfileUnavailable catch (error) {
            _diagnostic(
              'Skipped an unavailable mapped WebDAV sync profile',
              error,
            );
            continue;
          }
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
          final appliedKeys = await _localAdapter.applyProfile(
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
          consumedPeerSections.addAll(peerData.hotAndTombstoneReferences);
          _recordAppliedKeys(
            appliedKeysByLocalProfile,
            localProfileId,
            appliedKeys,
          );
          WebDavSyncLibraryDocument? mergedLibrary;
          if (libraryAdapter != null &&
              !libraryConflictProfiles.contains(circleProfileId)) {
            final localLibrary = await libraryAdapter.readLibrary(
              session,
              localProfileId,
              WebDavSyncLibraryBuildRequest(
                circleProfileId: circleProfileId,
                identityMaps: identityMaps,
                clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
                serverNowMs: serverNowMs,
              ),
            );
            final mergedLibraryTarget = WebDavSyncLibraryMerge.merge(
              circleProfileId: circleProfileId,
              documents: _ambientLibraryDocuments(<WebDavSyncLibraryDocument>[
                if (profileState.libraryBaseline != null)
                  profileState.libraryBaseline!,
                localLibrary.document,
                ...peerData.libraryDocuments,
              ]),
            );
            if (!_ambientLibraryFits(mergedLibraryTarget)) {
              return _persistAmbientCapacityBlock(
                namespaceId: namespaceId,
                peerCount: manifests.length,
                deviceClockWarning: clockDecision.deviceClockWarning,
              );
            }
            // The merge itself is sub-100 ms at the 60k-leaf field scale. Its
            // canonical digest and full identity scan are larger traversals,
            // so keep those off the UI isolate and retain the digest on the
            // returned immutable document for cache/publish comparisons.
            final libraryTarget = await _finalizeLibraryTargetOffMain(
              identityMaps,
              mergedLibraryTarget,
            );
            final pendingLibrary = WebDavSyncPendingLibraryApply(
              localProfileId: localProfileId,
              target: libraryTarget,
              observedRevisions: localLibrary.revisions,
            );
            final outcome = await libraryAdapter.applyLibrary(
              session,
              localProfileId,
              WebDavSyncLibraryApplyRequest(
                circleProfileId: circleProfileId,
                identityMaps: identityMaps,
                document: libraryTarget,
                observedRevisions: localLibrary.revisions,
                hiddenGroupNamesByWireKey:
                    localLibrary.hiddenGroupNamesByWireKey,
              ),
              beforeWrite: () => _stateRepository.update(namespaceId, (
                current,
              ) {
                final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                  current.profiles,
                );
                final currentProfile =
                    profiles[circleProfileId] ??
                    const WebDavSyncProfileEngineState();
                profiles[circleProfileId] = currentProfile.copyWith(
                  pendingLibraryApply: pendingLibrary,
                );
                return current.copyWith(
                  profiles:
                      Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                        profiles,
                      ),
                );
              }),
            );
            if (outcome.result == WebDavSyncLibraryApplyResult.conflict) {
              localChangeFollowUp = true;
              libraryConflictProfiles.add(circleProfileId);
              await _stateRepository.update(namespaceId, (current) {
                final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                  current.profiles,
                );
                final currentProfile = profiles[circleProfileId];
                if (currentProfile != null) {
                  profiles[circleProfileId] = currentProfile.copyWith(
                    clearPendingLibraryApply: true,
                  );
                }
                return current.copyWith(
                  profiles:
                      Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                        profiles,
                      ),
                );
              });
              _diagnostic(
                'Deferred WebDAV library apply after a concurrent local '
                'database change',
                null,
              );
            } else {
              mergedLibrary = libraryTarget;
              await _stateRepository.update(namespaceId, (current) {
                final profiles = Map<String, WebDavSyncProfileEngineState>.from(
                  current.profiles,
                );
                final currentProfile =
                    profiles[circleProfileId] ??
                    const WebDavSyncProfileEngineState();
                profiles[circleProfileId] = currentProfile.copyWith(
                  libraryBaseline: libraryTarget,
                  clearPendingLibraryApply: true,
                );
                return current.copyWith(
                  profiles:
                      Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                        profiles,
                      ),
                );
              });
              consumedPeerSections.addAll(peerData.libraryReferences);
              _recordAppliedKeys(
                appliedKeysByLocalProfile,
                localProfileId,
                outcome.appliedNamespaces,
              );
            }
          }
          profilesApplied++;
          profileResults[circleProfileId] = _ProfileCycleResult(
            document: merged.document,
            library: mergedLibrary,
            tombstones: merged.tombstones,
            originalLocalTombstones: profileState.tombstones,
          );
        } finally {
          instrumentation.finishPhase(_CyclePhase.mergeApply, phaseStarted);
          // The incoming profile batch is durable. Let Home observe it before
          // other profiles, outbound uploads, or remote cleanup finish.
          _publishAppliedKeys(
            appliedKeysByLocalProfile,
            localProfileId: localProfileId,
          );
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
      // A missing flag denotes a pre-compression journal. Only an active
      // binding may perform the one-shot rewrite; the flag itself is committed
      // below with the completed cycle, never with a pre-activation seed.
      final forceCompressionMigration =
          context.active && !state.sealedCompressionMigrated;
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
        forceCompressionMigration: forceCompressionMigration,
        instrumentation: instrumentation,
      );
      await _collectUnreferencedOwnSections(
        transport: transport,
        session: session,
        deviceId: deviceId,
        manifest: push.manifest ?? state.ownManifest,
        serverNowMs: serverNowMs,
        instrumentation: instrumentation,
      );
      final cycleConflicted =
          circleConflict || libraryConflictProfiles.isNotEmpty;
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
            lastPushedLibraryDigest: entry.value.libraryDigest,
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
          // Reference advancement is vetoed per tier, never globally: a
          // circle-tier conflict must not doom every peer hot/library
          // section to be re-downloaded forever (a perpetual circle
          // follow-up once held 5MB re-reads and 15s of processing on
          // every cycle). Library references for conflicted profiles were
          // never consumed, so no further filter is needed for them.
          lastMergedPeerSections: consumedPeerSections.mergeInto(
            current.lastMergedPeerSections,
            currentDeviceIds: manifests.keys,
            excludeSectionNames: circleConflict
                ? const <String>{'profiles', 'resources'}
                : const <String>{},
          ),
          sealedCompressionMigrated:
              current.sealedCompressionMigrated ||
              (forceCompressionMigration &&
                  push.sectionsPushed > 0 &&
                  !cycleConflicted),
          clearStatusHint: current.statusHint == _ambientCapacityStatusHint,
        );
      });
      return WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.completed,
        peerCount: manifests.length,
        profilesApplied: profilesApplied,
        sectionsPushed: push.sectionsPushed,
        deviceClockWarning: clockDecision.deviceClockWarning,
        statusHint: state.statusHint,
        localChangeFollowUp: localChangeFollowUp,
        localProfilesSuppressed: localProfilesSuppressed,
        localPublicationConfirmed:
            circlePublicationAllowed &&
            !cycleConflicted &&
            !localChangeFollowUp,
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
          var stage = WebDavSyncManifestReadStage.read;
          try {
            instrumentation.requestStarted();
            final read = await transport.readManifest(deviceId);
            instrumentation.received(read.bytes.length);
            stage = WebDavSyncManifestReadStage.decode;
            final payload = await _codec.openDocument(
              key: context.root!.key,
              encoded: read.bytes,
              circleId: context.root!.document.circleId,
              deviceId: deviceId,
              logicalName: 'manifest',
              schemaVersion: WebDavSyncManifest.schemaVersion,
              maxBytes: WebDavSyncLimits.maxManifestBytes,
            );
            stage = WebDavSyncManifestReadStage.parse;
            final manifest = WebDavSyncManifest.fromJson(payload);
            stage = WebDavSyncManifestReadStage.identity;
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
            stage = WebDavSyncManifestReadStage.metadata;
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
            _diagnostic(
              'Ignored an invalid WebDAV sync peer manifest',
              WebDavSyncManifestFailure(stage, error),
            );
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
    required String namespaceId,
    required String ownDeviceId,
    required Map<String, WebDavSyncManifest> manifests,
    required String circleProfileId,
    required int serverNowMs,
    required WebDavSyncProfileEngineState profileState,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
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
              namespaceId: namespaceId,
              ownDeviceId: ownDeviceId,
              deviceId: entry.key,
              manifest: entry.value,
              circleProfileId: circleProfileId,
              serverNowMs: serverNowMs,
              profileState: profileState,
              lastMergedPeerSections: lastMergedPeerSections,
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
      libraryDocuments: List<WebDavSyncLibraryDocument>.unmodifiable(
        peers.expand((peer) => peer.libraryDocuments),
      ),
      hotAndTombstoneReferences: List<_PeerSectionReference>.unmodifiable(
        peers.expand((peer) => peer.hotAndTombstoneReferences),
      ),
      libraryReferences: List<_PeerSectionReference>.unmodifiable(
        peers.expand((peer) => peer.libraryReferences),
      ),
    );
  }

  Future<_TvLibraryPeerData> _readTvLibraryPeerData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String ownDeviceId,
    required WebDavSyncManifest ownManifest,
    required Map<String, WebDavSyncManifest> manifests,
    required String circleProfileId,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
    required int serverNowMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    Future<_TvLibraryRead> readOne(
      String deviceId,
      WebDavSyncManifest manifest, {
      required bool own,
      required bool hasBaseline,
    }) async {
      final tvReference = manifest.section('tv-library/$circleProfileId');
      final fallback = !own && tvReference == null;
      final reference =
          tvReference ??
          (fallback ? manifest.section('library/$circleProfileId') : null);
      if (reference == null ||
          reference.schemaVersion != WebDavSyncLibraryDocument.schemaVersion) {
        return const _TvLibraryRead();
      }
      if (reference.size > WebDavSyncLibraryDocument.maxEncodedBytes) {
        _diagnostic('Ignored an oversized Debrify TV library section', null);
        return const _TvLibraryRead();
      }
      if (!own &&
          !fallback &&
          _shouldSkipMergedPeerSection(
            deviceId: deviceId,
            ownDeviceId: ownDeviceId,
            reference: reference,
            hasBaseline: hasBaseline,
            lastMergedPeerSections: lastMergedPeerSections,
            instrumentation: instrumentation,
          )) {
        return const _TvLibraryRead();
      }
      try {
        final raw = await _readLibrarySection(
          transport,
          root,
          deviceId,
          reference,
          circleProfileId,
          instrumentation,
        );
        if (!fallback &&
            raw.records.keys.any(
              (key) => !WebDavSyncLibraryKinds.isTvWireKey(key),
            )) {
          _diagnostic(
            'Ignored non-TV records in a Debrify TV library section',
            null,
          );
        }
        return _TvLibraryRead(
          document: raw.onlyTvRecords(),
          // Ambient owns library/P reference tracking. A mixed-version
          // fallback must neither consult nor advance that shared cursor.
          reference: own || fallback
              ? null
              : _PeerSectionReference(deviceId: deviceId, reference: reference),
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed Debrify TV library section', error);
      } on Exception catch (error) {
        _diagnostic('Ignored an invalid Debrify TV library section', error);
      }
      return const _TvLibraryRead();
    }

    final own = await readOne(
      ownDeviceId,
      ownManifest,
      own: true,
      hasBaseline: false,
    );
    final entries =
        manifests.entries
            .where((entry) => entry.key != ownDeviceId)
            .toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));
    final reads =
        await _mapConcurrentOrdered<
          MapEntry<String, WebDavSyncManifest>,
          _TvLibraryRead
        >(
          entries,
          limit: readConcurrency,
          operation: (entry) => readOne(
            entry.key,
            entry.value,
            own: false,
            hasBaseline: own.document != null,
          ),
        );
    return _TvLibraryPeerData(
      ownBaseline: own.document,
      peerDocuments: List<WebDavSyncLibraryDocument>.unmodifiable(
        reads
            .map((read) => read.document)
            .whereType<WebDavSyncLibraryDocument>(),
      ),
      peerReferences: List<_PeerSectionReference>.unmodifiable(
        reads.map((read) => read.reference).whereType<_PeerSectionReference>(),
      ),
    );
  }

  Future<_PeerCircleData> _readCirclePeerData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String namespaceId,
    required String ownDeviceId,
    required Map<String, WebDavSyncManifest> manifests,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
    required bool hasProfilesBaseline,
    required bool hasResourcesBaseline,
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
          namespaceId: namespaceId,
          ownDeviceId: ownDeviceId,
          deviceId: entry.key,
          manifest: entry.value,
          lastMergedPeerSections: lastMergedPeerSections,
          hasProfilesBaseline: hasProfilesBaseline,
          hasResourcesBaseline: hasResourcesBaseline,
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
      readReferences: List<_PeerSectionReference>.unmodifiable(
        peers.expand((peer) => peer.readReferences),
      ),
    );
  }

  Future<_PeerCircleData> _readOneCirclePeer({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String namespaceId,
    required String ownDeviceId,
    required String deviceId,
    required WebDavSyncManifest manifest,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
    required bool hasProfilesBaseline,
    required bool hasResourcesBaseline,
    required _CycleInstrumentation instrumentation,
  }) async {
    WebDavSyncProfilesDocument? profiles;
    WebDavSyncResourcesDocument? resources;
    final readReferences = <_PeerSectionReference>[];
    final profilesRef = manifest.section('profiles');
    if (profilesRef != null &&
        profilesRef.size > WebDavSyncLimits.maxHotDocumentBytes) {
      throw const FormatException('WebDAV sync profiles exceed size limit');
    }
    if (profilesRef != null &&
        profilesRef.schemaVersion == WebDavSyncProfilesDocument.schemaVersion &&
        !_shouldSkipMergedPeerSection(
          deviceId: deviceId,
          ownDeviceId: ownDeviceId,
          reference: profilesRef,
          hasBaseline: hasProfilesBaseline,
          lastMergedPeerSections: lastMergedPeerSections,
          instrumentation: instrumentation,
        )) {
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
        if (deviceId != ownDeviceId) {
          readReferences.add(
            _PeerSectionReference(deviceId: deviceId, reference: profilesRef),
          );
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync profiles section', error);
      } on Exception catch (error) {
        if (deviceId == ownDeviceId) {
          await _markOwnSectionDirty(namespaceId, profilesRef.name);
        }
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
            WebDavSyncResourcesDocument.schemaVersion &&
        !_shouldSkipMergedPeerSection(
          deviceId: deviceId,
          ownDeviceId: ownDeviceId,
          reference: resourcesRef,
          hasBaseline: hasResourcesBaseline,
          lastMergedPeerSections: lastMergedPeerSections,
          instrumentation: instrumentation,
        )) {
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
        if (deviceId != ownDeviceId) {
          readReferences.add(
            _PeerSectionReference(deviceId: deviceId, reference: resourcesRef),
          );
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync resources section', error);
      } on Exception catch (error) {
        if (deviceId == ownDeviceId) {
          await _markOwnSectionDirty(namespaceId, resourcesRef.name);
        }
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
      readReferences: List<_PeerSectionReference>.unmodifiable(readReferences),
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

  /// The section merges gated here are monotone record-level LWW merges
  /// against a durable baseline. Once a peer document was merged and that
  /// baseline was persisted, the baseline contains every record contributed
  /// by that document; the exact same reference therefore contributes nothing
  /// new and is equivalent to an absent merge input. This applies to hot data,
  /// retained tombstones, libraries, profiles, and resources. Bootstrap is
  /// intentionally not gated: it is an adoption/repair snapshot rather than a
  /// monotone merge against these engine baselines, so its readers continue to
  /// fetch and verify it.
  static bool _shouldSkipMergedPeerSection({
    required String deviceId,
    required String ownDeviceId,
    required WebDavSyncSectionReference reference,
    required bool hasBaseline,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
    required _CycleInstrumentation instrumentation,
  }) {
    if (deviceId == ownDeviceId || !hasBaseline) return false;
    final merged = lastMergedPeerSections[deviceId]?[reference.name];
    if (merged == null || !_sameSectionReference(merged, reference)) {
      return false;
    }
    instrumentation.sectionSkipped(reference.size);
    return true;
  }

  static bool _sameSectionReference(
    WebDavSyncSectionReference left,
    WebDavSyncSectionReference right,
  ) =>
      left.name == right.name &&
      left.contentHash == right.contentHash &&
      left.semanticDigest == right.semanticDigest &&
      left.updatedAtMs == right.updatedAtMs &&
      left.schemaVersion == right.schemaVersion &&
      left.size == right.size;

  Future<_PeerProfileData> _readOnePeerProfileData({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required String namespaceId,
    required String ownDeviceId,
    required String deviceId,
    required WebDavSyncManifest manifest,
    required String circleProfileId,
    required int serverNowMs,
    required WebDavSyncProfileEngineState profileState,
    required Map<String, Map<String, WebDavSyncSectionReference>>
    lastMergedPeerSections,
    required _CycleInstrumentation instrumentation,
  }) async {
    WebDavSyncHotDocument? hot;
    WebDavSyncTombstoneDocument? tombstone;
    WebDavSyncLibraryDocument? library;
    final hotAndTombstoneReferences = <_PeerSectionReference>[];
    final libraryReferences = <_PeerSectionReference>[];
    final stale =
        serverNowMs - manifest.updatedAtMs > staleManifestCutoff.inMilliseconds;
    final hotRef = manifest.section('hot/$circleProfileId');
    if (!stale &&
        hotRef != null &&
        (hotRef.schemaVersion == 1 ||
            hotRef.schemaVersion == WebDavSyncHotDocument.schemaVersion) &&
        hotRef.size <= WebDavSyncLimits.maxHotDocumentBytes &&
        !_shouldSkipMergedPeerSection(
          deviceId: deviceId,
          ownDeviceId: ownDeviceId,
          reference: hotRef,
          hasBaseline: profileState.baseline != null,
          lastMergedPeerSections: lastMergedPeerSections,
          instrumentation: instrumentation,
        )) {
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
        if (deviceId != ownDeviceId) {
          hotAndTombstoneReferences.add(
            _PeerSectionReference(deviceId: deviceId, reference: hotRef),
          );
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync hot section', error);
      } on Exception catch (error) {
        if (deviceId == ownDeviceId) {
          await _markOwnSectionDirty(namespaceId, hotRef.name);
        }
        _diagnostic('Ignored an invalid WebDAV sync hot section', error);
      }
    }
    final tombstoneRef = manifest.section('tombstones/$circleProfileId');
    // Tombstones deliberately ignore manifest heartbeat age.
    if (tombstoneRef != null &&
        tombstoneRef.schemaVersion ==
            WebDavSyncTombstoneDocument.schemaVersion &&
        tombstoneRef.size <= WebDavSyncLimits.maxTombstoneDocumentBytes &&
        !_shouldSkipMergedPeerSection(
          deviceId: deviceId,
          ownDeviceId: ownDeviceId,
          reference: tombstoneRef,
          hasBaseline: profileState.baseline != null,
          lastMergedPeerSections: lastMergedPeerSections,
          instrumentation: instrumentation,
        )) {
      try {
        tombstone = await _readTombstoneSection(
          transport,
          root,
          deviceId,
          tombstoneRef,
          circleProfileId,
          instrumentation,
        );
        if (deviceId != ownDeviceId) {
          hotAndTombstoneReferences.add(
            _PeerSectionReference(deviceId: deviceId, reference: tombstoneRef),
          );
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync tombstone section', error);
      } on Exception catch (error) {
        if (deviceId == ownDeviceId) {
          await _markOwnSectionDirty(namespaceId, tombstoneRef.name);
        }
        _diagnostic('Ignored an invalid WebDAV sync tombstone section', error);
      }
    }
    final libraryRef = manifest.section('library/$circleProfileId');
    // Durable library leaves deliberately ignore heartbeat age, like
    // tombstones: a stale device can still hold the only winning deletion.
    if (libraryRef != null &&
        libraryRef.schemaVersion == WebDavSyncLibraryDocument.schemaVersion &&
        libraryRef.size > WebDavSyncLibraryDocument.maxEncodedBytes) {
      if (deviceId == ownDeviceId) {
        await _markOwnSectionDirty(namespaceId, libraryRef.name);
      }
      _diagnostic('Ignored an oversized WebDAV sync library section', null);
    } else if (libraryRef != null &&
        libraryRef.schemaVersion == WebDavSyncLibraryDocument.schemaVersion &&
        libraryRef.size <= WebDavSyncLibraryDocument.maxEncodedBytes &&
        !_shouldSkipMergedPeerSection(
          deviceId: deviceId,
          ownDeviceId: ownDeviceId,
          reference: libraryRef,
          hasBaseline:
              profileState.baseline != null &&
              profileState.libraryBaseline != null,
          lastMergedPeerSections: lastMergedPeerSections,
          instrumentation: instrumentation,
        )) {
      try {
        library = await _readLibrarySection(
          transport,
          root,
          deviceId,
          libraryRef,
          circleProfileId,
          instrumentation,
        );
        if (deviceId != ownDeviceId) {
          libraryReferences.add(
            _PeerSectionReference(deviceId: deviceId, reference: libraryRef),
          );
        }
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync library section', error);
      } on Exception catch (error) {
        if (deviceId == ownDeviceId) {
          await _markOwnSectionDirty(namespaceId, libraryRef.name);
        }
        _diagnostic('Ignored an invalid WebDAV sync library section', error);
      }
    }
    return _PeerProfileData(
      hotDocuments: hot == null
          ? const <WebDavSyncHotDocument>[]
          : <WebDavSyncHotDocument>[hot],
      tombstoneDocuments: tombstone == null
          ? const <WebDavSyncTombstoneDocument>[]
          : <WebDavSyncTombstoneDocument>[tombstone],
      libraryDocuments: library == null
          ? const <WebDavSyncLibraryDocument>[]
          : <WebDavSyncLibraryDocument>[library],
      hotAndTombstoneReferences: List<_PeerSectionReference>.unmodifiable(
        hotAndTombstoneReferences,
      ),
      libraryReferences: List<_PeerSectionReference>.unmodifiable(
        libraryReferences,
      ),
    );
  }

  Future<WebDavSyncLibraryDocument> _readLibrarySection(
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
      'library',
    );
    final cached = _cached(cacheKey);
    if (cached is WebDavSyncLibraryDocument &&
        cached.circleProfileId == circleProfileId &&
        cached.semanticDigest == reference.semanticDigest) {
      _requireLibraryPublicationBounds(cached, reference.updatedAtMs);
      return cached;
    }
    _removeCached(cacheKey);
    instrumentation.requestStarted();
    final encoded = await WebDavSyncLargeSectionIo(codec: _codec).readVerified(
      transport: transport,
      deviceId: deviceId,
      reference: reference,
      maxBytes: WebDavSyncLibraryDocument.maxEncodedBytes,
    );
    instrumentation.received(encoded.length);
    final payload = await _codec.openDocument(
      key: root.key,
      encoded: encoded,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: reference.name,
      schemaVersion: reference.schemaVersion,
      payloadDecoder: decodeWebDavSyncLibraryDocument,
      maxBytes: WebDavSyncLibraryDocument.maxEncodedBytes,
      runInBackground: true,
    );
    if (payload is! WebDavSyncLibraryDocument) {
      throw const FormatException('Invalid WebDAV sync library document');
    }
    final document = payload;
    if (document.circleProfileId != circleProfileId ||
        document.semanticDigest != reference.semanticDigest) {
      throw const FormatException('WebDAV sync library section mismatch');
    }
    _requireLibraryPublicationBounds(document, reference.updatedAtMs);
    _cache(cacheKey, document, reference.size);
    return document;
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

  Future<void> _markOwnSectionDirty(String namespaceId, String sectionName) =>
      _stateRepository.update(namespaceId, (current) {
        if (sectionName == 'profiles') {
          return current.copyWith(clearLastPushedProfilesDigest: true);
        }
        if (sectionName == 'resources') {
          return current.copyWith(clearLastPushedResourcesDigest: true);
        }
        const hotPrefix = 'hot/';
        const tombstonePrefix = 'tombstones/';
        const libraryPrefix = 'library/';
        final isHot = sectionName.startsWith(hotPrefix);
        final isTombstone = sectionName.startsWith(tombstonePrefix);
        final isLibrary = sectionName.startsWith(libraryPrefix);
        if (!isHot && !isTombstone && !isLibrary) return current;
        final circleProfileId = sectionName.substring(
          isHot
              ? hotPrefix.length
              : isTombstone
              ? tombstonePrefix.length
              : libraryPrefix.length,
        );
        final profile = current.profiles[circleProfileId];
        if (profile == null) return current;
        return current.copyWith(
          profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
            <String, WebDavSyncProfileEngineState>{
              ...current.profiles,
              circleProfileId: profile.copyWith(
                clearLastPushedHotDigest: isHot,
                clearLastPushedTombstoneDigest: isTombstone,
                clearLastPushedLibraryDigest: isLibrary,
              ),
            },
          ),
        );
      });

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
    required bool forceCompressionMigration,
    required _CycleInstrumentation instrumentation,
  }) async {
    final deviceId = context.deviceId!;
    final changed = <_SealedSection>[];
    final librariesToPush = <String, WebDavSyncLibraryDocument>{};
    final published = <String, _PublishedProfile>{};
    final profilesDigest = circle?.profiles.semanticDigest;
    final resourcesDigest = circle?.resources.semanticDigest;
    final pushProfiles =
        circle != null &&
        (forceCompressionMigration ||
            state.lastPushedProfilesDigest != profilesDigest ||
            state.ownManifest?.section('profiles') == null);
    final pushResources =
        circle != null &&
        (forceCompressionMigration ||
            state.lastPushedResourcesDigest != resourcesDigest ||
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
      if (forceCompressionMigration ||
          profileState.lastPushedHotDigest != hotDigest) {
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
      if (forceCompressionMigration ||
          profileState.lastPushedTombstoneDigest != tombstoneDigest) {
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
      final library = entry.value.library;
      if (library != null &&
          (forceCompressionMigration ||
              profileState.lastPushedLibraryDigest != library.semanticDigest ||
              state.ownManifest?.section('library/${entry.key}') == null)) {
        librariesToPush[entry.key] = library;
      }
      published[entry.key] = _PublishedProfile(
        hotDigest: hotDigest,
        tombstoneDigest: tombstoneDigest,
        libraryDigest: entry.value.library?.semanticDigest,
        tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(
          publishedTombstones,
        ),
      );
    }
    final dropsLegacyGraph =
        state.ownManifest?.section(WebDavSyncGraphKind.graph.logicalName) !=
        null;
    if (changed.isEmpty &&
        librariesToPush.isEmpty &&
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
      WebDavResponseMetadata? metadata;
      WebDavException? writeFailure;
      StackTrace? writeFailureStackTrace;
      try {
        instrumentation.requestStarted(bytesUp: section.bytes.length);
        metadata = await transport.writeSection(
          deviceId,
          section.reference.contentHash,
          section.bytes,
          maxBytes: _maxBytesFor(section.reference.name),
        );
      } on WebDavException catch (error, stackTrace) {
        writeFailure = error;
        writeFailureStackTrace = stackTrace;
      } finally {
        instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
      }
      phaseStarted = instrumentation.startPhase();
      try {
        if (writeFailure != null || section.reference.name == 'profiles') {
          instrumentation.requestStarted();
          final readBack = await transport.readSection(
            deviceId,
            section.reference,
            maxBytes: _maxBytesFor(section.reference.name),
          );
          instrumentation.received(readBack.bytes.length);
          if (readBack.bytes.length != section.reference.size ||
              contentHashOf(readBack.bytes) != section.reference.contentHash ||
              !_bytesEqual(readBack.bytes, section.bytes)) {
            throw StateError(
              'WebDAV sync section read-back verification failed',
            );
          }
          if (writeFailure != null) {
            await _codec.openDocument(
              key: root.key,
              encoded: readBack.bytes,
              circleId: root.document.circleId,
              deviceId: deviceId,
              logicalName: section.reference.name,
              schemaVersion: section.reference.schemaVersion,
              maxBytes: _maxBytesFor(section.reference.name),
            );
          }
        } else if (metadata != null) {
          validateWebDavSyncSectionWriteMetadata(
            metadata,
            expectedBytes: section.bytes.length,
          );
        }
      } on Object {
        if (writeFailure != null) {
          Error.throwWithStackTrace(writeFailure, writeFailureStackTrace!);
        }
        rethrow;
      } finally {
        instrumentation.finishPhase(_CyclePhase.readBack, phaseStarted);
      }
    }

    final libraryReferences = <String, WebDavSyncSectionReference>{};
    for (final entry in librariesToPush.entries) {
      session.validate();
      phaseStarted = instrumentation.startPhase();
      try {
        instrumentation.requestStarted();
        final document = entry.value;
        final reference = await WebDavSyncLargeSectionIo(codec: _codec)
            .sealWriteVerify(
              transport: transport,
              key: root.key,
              circleId: root.document.circleId,
              deviceId: deviceId,
              logicalName: 'library/${entry.key}',
              schemaVersion: WebDavSyncLibraryDocument.schemaVersion,
              payload: document,
              payloadEncoder: encodeWebDavSyncLibraryDocument,
              semanticDigest: document.semanticDigest,
              updatedAtMs: serverNowMs,
              maxBytes: WebDavSyncLibraryDocument.maxEncodedBytes,
            );
        libraryReferences[reference.name] = reference;
      } finally {
        instrumentation.finishPhase(_CyclePhase.push, phaseStarted);
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
      ...libraryReferences,
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
    if (!context.matchesAuthority(commitRoot.bytes)) {
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
      sectionsPushed:
          changed.length +
          libraryReferences.length +
          (resourceReference == null ? 0 : 1),
      manifest: verifiedManifest,
      publishedProfiles: Map<String, _PublishedProfile>.unmodifiable(published),
      publishedProfilesDigest: profilesDigest,
      publishedResourcesDigest: resourcesDigest,
    );
  }

  Future<_TvLibraryPushResult> _pushTvLibrary({
    required WebDavSyncTransport transport,
    required WebDavSyncCycleContext context,
    required WebDavSyncLocalSession session,
    required OpenedWebDavSyncRoot root,
    required WebDavSyncIdentityMaps identityMaps,
    required WebDavSyncManifest manifest,
    required String circleProfileId,
    required WebDavSyncLibraryDocument document,
    required int serverNowMs,
    required int clockOffsetMs,
    required _CycleInstrumentation instrumentation,
  }) async {
    final logicalName = 'tv-library/$circleProfileId';
    final currentReference = manifest.section(logicalName);
    if (currentReference?.semanticDigest == document.semanticDigest) {
      return _TvLibraryPushResult(manifest: manifest, sectionsPushed: 0);
    }
    final deviceId = context.deviceId!;
    session.validate();
    instrumentation.requestStarted();
    await transport.ensureOwnLayout(deviceId);
    instrumentation.requestStarted();
    final reference = await WebDavSyncLargeSectionIo(codec: _codec)
        .sealWriteVerify(
          transport: transport,
          key: root.key,
          circleId: root.document.circleId,
          deviceId: deviceId,
          logicalName: logicalName,
          schemaVersion: WebDavSyncLibraryDocument.schemaVersion,
          payload: document,
          payloadEncoder: encodeWebDavSyncLibraryDocument,
          semanticDigest: document.semanticDigest,
          updatedAtMs: serverNowMs,
          maxBytes: WebDavSyncLibraryDocument.maxEncodedBytes,
        );
    final sections = <String, WebDavSyncSectionReference>{
      for (final section in manifest.sections) section.name: section,
      reference.name: reference,
    };
    final updated = WebDavSyncManifest(
      circleId: root.document.circleId,
      deviceId: deviceId,
      updatedAtMs: serverNowMs,
      clockOffsetMs: clockOffsetMs,
      graphSchemaClaim: manifest.graphSchemaClaim,
      profileMap: context.wireProfileMap.isNotEmpty
          ? context.wireProfileMap
          : manifest.profileMap,
      resourceMap: context.wireResourceMap.isNotEmpty
          ? context.wireResourceMap
          : manifest.resourceMap,
      sections: List<WebDavSyncSectionReference>.unmodifiable(
        sections.values.toList()..sort((left, right) {
          return left.name.compareTo(right.name);
        }),
      ),
    );
    identityMaps.assertContainsNoLocalIds(updated.toJson());
    final encodedManifest = await _codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      payload: updated.toJson(),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    final commitRoot = await _readRequiredRoot(transport, instrumentation);
    if (!context.matchesAuthority(commitRoot.bytes)) {
      throw const WebDavSyncRootChangedException();
    }
    session.validate();
    instrumentation.requestStarted(bytesUp: encodedManifest.length);
    await transport.writeManifest(deviceId, encodedManifest);
    instrumentation.requestStarted();
    final readBack = await transport.readManifest(deviceId);
    instrumentation.received(readBack.bytes.length);
    if (!_bytesEqual(readBack.bytes, encodedManifest)) {
      throw StateError('WebDAV sync manifest read-back verification failed');
    }
    final opened = await _codec.openDocument(
      key: root.key,
      encoded: readBack.bytes,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'manifest',
      schemaVersion: WebDavSyncManifest.schemaVersion,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    final verified = WebDavSyncManifest.fromJson(opened);
    _cache(
      _sectionCacheKey(root.document.circleId, deviceId, reference, 'library'),
      document,
      reference.size,
    );
    return _TvLibraryPushResult(manifest: verified, sectionsPushed: 1);
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

  Future<WebDavSyncEngineState> _clearEligiblePendingActiveProfile({
    required String namespaceId,
    required WebDavSyncEngineState state,
    required WebDavSyncProfilesDocument profiles,
    required WebDavSyncIdentityMaps identityMaps,
  }) {
    final pending = state.pendingActiveProfile;
    if (pending == null) {
      return Future<WebDavSyncEngineState>.value(state);
    }
    final circleProfileId =
        pending.circleProfileId ??
        identityMaps.localToCircleProfiles[pending.localProfileId];
    final winner = circleProfileId == null
        ? null
        : profiles.profiles[circleProfileId];
    if (winner == null || _activeProfileDeferralReason(winner.value) != null) {
      return Future<WebDavSyncEngineState>.value(state);
    }
    return _stateRepository.update(
      namespaceId,
      (current) =>
          current.pendingActiveProfile != null &&
              _samePendingActiveProfile(current.pendingActiveProfile!, pending)
          ? current.copyWith(clearPendingActiveProfileDeletion: true)
          : current,
    );
  }

  static bool _samePendingActiveProfile(
    WebDavSyncPendingActiveProfile left,
    WebDavSyncPendingActiveProfile right,
  ) =>
      left.localProfileId == right.localProfileId &&
      left.circleProfileId == right.circleProfileId &&
      left.reason == right.reason &&
      left.profileLeaf?.stamp.normalizedTimeMs ==
          right.profileLeaf?.stamp.normalizedTimeMs &&
      left.profileLeaf?.stamp.originDeviceId ==
          right.profileLeaf?.stamp.originDeviceId &&
      left.expectedPriorUpdatedAtMs == right.expectedPriorUpdatedAtMs &&
      semanticDigestOf(left.profileLeaf?.value?.toJson()) ==
          semanticDigestOf(right.profileLeaf?.value?.toJson());

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
    if (name.startsWith('library/') || name.startsWith('tv-library/')) {
      return WebDavSyncLibraryDocument.maxEncodedBytes;
    }
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

  static void _requireLibraryPublicationBounds(
    WebDavSyncLibraryDocument document,
    int publishedAtMs,
  ) {
    if (document.records.values.any(
      (leaf) => leaf.stamp.normalizedTimeMs > publishedAtMs,
    )) {
      throw const FormatException(
        'WebDAV sync library section contains a future publication stamp',
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

  static void _recordAppliedKeys(
    Map<String, Set<String>> appliedKeysByLocalProfile,
    String localProfileId,
    Set<String> appliedKeys,
  ) {
    if (appliedKeys.isEmpty) return;
    appliedKeysByLocalProfile
        .putIfAbsent(localProfileId, () => <String>{})
        .addAll(appliedKeys);
  }

  /// Runs the merged target's identity assertion and canonical digest in a
  /// worker isolate. This lives in its own method so the [Isolate.run]
  /// closure's enclosing context holds ONLY the two sendable parameters —
  /// written inline in the cycle, the captured context chain reaches the
  /// engine and its cycle lock, whose in-flight Future is unsendable.
  static Future<WebDavSyncLibraryDocument> _finalizeLibraryTargetOffMain(
    WebDavSyncIdentityMaps identityMaps,
    WebDavSyncLibraryDocument merged,
  ) {
    return Isolate.run(() {
      identityMaps.assertContainsNoLocalIds(merged.toJson());
      return merged.withComputedSemanticDigest();
    });
  }

  List<WebDavSyncLibraryDocument> _ambientLibraryDocuments(
    Iterable<WebDavSyncLibraryDocument> documents,
  ) {
    final source = documents.toList(growable: false);
    if (source.any(
      (document) =>
          document.records.keys.any(WebDavSyncLibraryKinds.isTvWireKey),
    )) {
      _diagnostic(
        'Ignored Debrify TV records in an ambient library section',
        null,
      );
    }
    return <WebDavSyncLibraryDocument>[
      for (final document in source) document.withoutTvRecords(),
    ];
  }

  bool _ambientLibraryFits(WebDavSyncLibraryDocument document) {
    // Deletions remain on the wire so offline peers cannot resurrect data.
    // Their retained keys must not consume the user's live-activity budget.
    if (document.records.values.where((leaf) => leaf.value != null).length <=
        WebDavSyncLibraryDocument.maxAmbientLeaves) {
      return true;
    }
    _diagnostic(
      'Refused WebDAV ambient library build above 20,000 records',
      null,
    );
    return false;
  }

  Future<WebDavSyncCycleReport> _persistAmbientCapacityBlock({
    required String namespaceId,
    required int peerCount,
    required bool deviceClockWarning,
  }) async {
    await _stateRepository.update(
      namespaceId,
      (current) => current.statusHint == _ambientCapacityStatusHint
          ? current
          : current.copyWith(statusHint: _ambientCapacityStatusHint),
    );
    return WebDavSyncCycleReport(
      disposition: WebDavSyncCycleDisposition.capacityBlocked,
      peerCount: peerCount,
      deviceClockWarning: deviceClockWarning,
      statusHint: _ambientCapacityStatusHint,
    );
  }

  void _publishAppliedKeys(
    Map<String, Set<String>> appliedKeysByLocalProfile, {
    String? localProfileId,
  }) {
    // Drain before dispatch so the cycle's final fallback cannot notify twice.
    final ready = <String, Set<String>>{};
    if (localProfileId == null) {
      ready.addAll(appliedKeysByLocalProfile);
      appliedKeysByLocalProfile.clear();
    } else {
      final keys = appliedKeysByLocalProfile.remove(localProfileId);
      if (keys != null) ready[localProfileId] = keys;
    }
    for (final entry in ready.entries) {
      try {
        _appliedKeysCallback(entry.key, Set<String>.unmodifiable(entry.value));
      } catch (error) {
        try {
          _diagnostic(
            'Ignored a failed post-commit WebDAV sync refresh callback',
            error,
          );
        } catch (_) {
          // Neither an optional observer nor diagnostics may change the
          // outcome of a preference batch which has already committed.
        }
      }
    }
  }

  static void _ignoreDiagnostic(String _, Object? __) {}

  static void _ignoreAppliedKeys(String _, Set<String> __) {}

  static WebDavSyncPendingActiveProfileReason? _activeProfileDeferralReason(
    WebDavSyncProfileValue? value,
  ) {
    if (value == null) return WebDavSyncPendingActiveProfileReason.deleted;
    if (!value.enabled ||
        value.lifecycle != UserProfileLifecycle.active ||
        value.pin.resetRequired) {
      return WebDavSyncPendingActiveProfileReason.disabled;
    }
    return null;
  }

  static String _adminSafetyStatusHint(String profile) =>
      'sync kept $profile as Admin on this device';

  static String _activeAdminSafetyStatusHint(String profile) =>
      'sync kept active $profile because it is this device\'s only '
      'managing Admin';
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

final class _ListingResult {
  const _ListingResult.value(this.value) : error = null, stackTrace = null;

  const _ListingResult.error(this.error, this.stackTrace) : value = null;

  final WebDavSyncPeerListing? value;
  final Object? error;
  final StackTrace? stackTrace;

  WebDavSyncPeerListing unwrap() {
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, stackTrace!);
    }
    return value!;
  }
}

Future<_ListingResult> _captureListing(
  Future<WebDavSyncPeerListing> listing,
) async {
  try {
    return _ListingResult.value(await listing);
  } catch (error, stackTrace) {
    return _ListingResult.error(error, stackTrace);
  }
}

final class _PeerProfileData {
  const _PeerProfileData({
    required this.hotDocuments,
    required this.tombstoneDocuments,
    required this.libraryDocuments,
    required this.hotAndTombstoneReferences,
    required this.libraryReferences,
  });

  final List<WebDavSyncHotDocument> hotDocuments;
  final List<WebDavSyncTombstoneDocument> tombstoneDocuments;
  final List<WebDavSyncLibraryDocument> libraryDocuments;
  final List<_PeerSectionReference> hotAndTombstoneReferences;
  final List<_PeerSectionReference> libraryReferences;
}

final class _TvLibraryRead {
  const _TvLibraryRead({this.document, this.reference});

  final WebDavSyncLibraryDocument? document;
  final _PeerSectionReference? reference;
}

final class _TvLibraryPeerData {
  const _TvLibraryPeerData({
    required this.ownBaseline,
    required this.peerDocuments,
    required this.peerReferences,
  });

  final WebDavSyncLibraryDocument? ownBaseline;
  final List<WebDavSyncLibraryDocument> peerDocuments;
  final List<_PeerSectionReference> peerReferences;
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
    required this.library,
    required this.tombstones,
    required this.originalLocalTombstones,
  });

  final WebDavSyncHotDocument document;
  final WebDavSyncLibraryDocument? library;
  final Map<String, WebDavSyncTombstone> tombstones;
  final Map<String, WebDavSyncTombstone> originalLocalTombstones;
}

final class _CircleCycleResult {
  const _CircleCycleResult({required this.profiles, required this.resources});

  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
}

final class _PeerCircleData {
  const _PeerCircleData({
    required this.profiles,
    required this.resources,
    required this.readReferences,
  });

  final List<WebDavSyncProfilesDocument> profiles;
  final List<WebDavSyncResourcesDocument> resources;
  final List<_PeerSectionReference> readReferences;
}

final class _PeerSectionReference {
  const _PeerSectionReference({
    required this.deviceId,
    required this.reference,
  });

  final String deviceId;
  final WebDavSyncSectionReference reference;
}

final class _ConsumedPeerSections {
  final Map<String, Map<String, WebDavSyncSectionReference>> _references =
      <String, Map<String, WebDavSyncSectionReference>>{};

  void addAll(Iterable<_PeerSectionReference> references) {
    for (final item in references) {
      (_references[item.deviceId] ??=
              <String, WebDavSyncSectionReference>{})[item.reference.name] =
          item.reference;
    }
  }

  Map<String, Map<String, WebDavSyncSectionReference>> mergeInto(
    Map<String, Map<String, WebDavSyncSectionReference>> current, {
    required Iterable<String> currentDeviceIds,
    Set<String> excludeSectionNames = const <String>{},
  }) {
    final currentDevices = currentDeviceIds.toSet();
    final merged = <String, Map<String, WebDavSyncSectionReference>>{
      for (final device in current.entries)
        if (currentDevices.contains(device.key))
          device.key: Map<String, WebDavSyncSectionReference>.from(
            device.value,
          ),
    };
    for (final device in _references.entries) {
      if (!currentDevices.contains(device.key)) continue;
      final target = merged[device.key] ??=
          <String, WebDavSyncSectionReference>{};
      for (final section in device.value.entries) {
        if (excludeSectionNames.contains(section.key)) continue;
        target[section.key] = section.value;
      }
    }
    if (merged.length > WebDavSyncLimits.maxPeers ||
        merged.values.any(
          (sections) =>
              sections.length > WebDavSyncLimits.maxSectionsPerManifest,
        )) {
      throw StateError('WebDAV sync merged section state exceeds its limit');
    }
    return Map<String, Map<String, WebDavSyncSectionReference>>.unmodifiable(
      <String, Map<String, WebDavSyncSectionReference>>{
        for (final device in merged.entries)
          device.key: Map<String, WebDavSyncSectionReference>.unmodifiable(
            device.value,
          ),
      },
    );
  }
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
    required this.libraryDigest,
    required this.tombstones,
  });

  final String hotDigest;
  final String tombstoneDigest;
  final String? libraryDigest;
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

final class _TvLibraryPushResult {
  const _TvLibraryPushResult({
    required this.manifest,
    required this.sectionsPushed,
  });

  final WebDavSyncManifest manifest;
  final int sectionsPushed;
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

/// The shape of a failed cycle, and nothing more.
///
/// A WebDAV error contributes its kind and HTTP status. Our own assertions
/// are fixed literals ("WebDAV sync … is invalid"), so a StateError whose
/// message is made of plain words keeps it; anything carrying an id, path,
/// or digit falls back to the bare type. Messages, URIs, and bodies of any
/// other error never reach the diagnostic store. Two consecutive launch
/// failures in the field were unexplainable with the type alone.
@visibleForTesting
String describeWebDavSyncCycleFailure(Object error) {
  if (error is WebDavException) {
    final status = error.statusCode;
    return 'WebDavException:${error.kind.name}'
        '${status == null ? '' : ':$status'}';
  }
  if (error is ResourceAuthorizationException) {
    final reason = switch (error.message) {
      'Profile session is locked' => 'profile_locked',
      'Profile authorization has changed' => 'profile_authority_changed',
      'Profile authorization session has ended' => 'profile_session_changed',
      'Resource is unavailable' => 'resource_unavailable',
      'Resource permission denied' => 'permission_denied',
      _ => 'other',
    };
    return 'ResourceAuthorizationException:$reason';
  }
  if (error is StateError &&
      _literalStateErrorMessage.hasMatch(error.message)) {
    return 'StateError:${error.message}';
  }
  return error.runtimeType.toString();
}

final RegExp _literalStateErrorMessage = RegExp(
  r'^(Active )?WebDAV sync [A-Za-z ,/-]+$',
);

final class _CycleInstrumentation {
  _CycleInstrumentation(this.trigger) : _stopwatch = Stopwatch()..start();

  final WebDavSyncTrigger? trigger;
  final Stopwatch _stopwatch;
  int peerCount = 0;
  int requestCount = 0;
  int bytesUp = 0;
  int bytesDown = 0;
  int sectionsSkipped = 0;
  int bytesSaved = 0;
  String disposition = 'failed';
  String? failureKind;
  Map<String, Object> connectionFailure = const {};
  int _rootUs = 0;
  int _listUs = 0;
  int _manifestsUs = 0;
  int _sectionsUs = 0;
  int _mergeApplyUs = 0;
  int _sealUs = 0;
  int _pushUs = 0;
  int _readBackUs = 0;

  int startPhase() => _stopwatch.elapsedMicroseconds;

  /// The failure's shape only. A WebDAV error contributes its kind and HTTP
  /// status; everything else contributes just its type. Messages, URIs, and
  /// bodies never reach the diagnostic store.
  static String describeFailure(Object error) =>
      describeWebDavSyncCycleFailure(error);

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

  void sectionSkipped(int byteCount) {
    sectionsSkipped++;
    bytesSaved += byteCount;
  }

  void record() {
    _stopwatch.stop();
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'cycle',
      fields: <String, Object?>{
        ...connectionFailure,
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
        'sectionsSkipped': sectionsSkipped,
        'bytesSaved': bytesSaved,
        'disposition': DiagnosticLabel(disposition),
        if (failureKind case final kind?) ...{
          'failureKind': DiagnosticLabel(kind),
          'profileLocked':
              ProfileLockController.instance.lockedProfileId.value != null,
        },
      },
    );
  }

  static int _milliseconds(int microseconds) =>
      Duration(microseconds: microseconds).inMilliseconds;
}
