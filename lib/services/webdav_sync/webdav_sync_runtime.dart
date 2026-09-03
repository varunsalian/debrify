import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../models/profiles/profile_policy.dart';
import '../diagnostic_log.dart' as app_diagnostics;
import '../main_page_bridge.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/device_key_provider.dart';
import '../profiles/profile_app_lifecycle_participant.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_bootstrap.dart';
import '../profiles/profile_database_adoption_gate.dart';
import '../profiles/profile_lifecycle.dart';
import '../profiles/profile_package_service.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_registry.dart';
import '../profiles/profile_restore_coordinator.dart';
import '../profiles/profile_runtime.dart';
import '../webdav_protocol_client.dart';
import '../../utils/platform_util.dart';
import 'webdav_sync_activation.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_adoption_operations.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_discovery.dart';
import 'webdav_sync_diagnostics.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_existing_root_connector.dart';
import 'webdav_sync_feature.dart';
import 'webdav_sync_first_join_resume.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_graph_tier.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_local_adapter.dart';
import 'webdav_sync_manifest_publisher.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_operation_coordinator.dart';
import 'webdav_sync_safety_backup.dart';
import 'webdav_sync_scheduler.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_tombstones.dart';
import 'webdav_sync_transport.dart';
import 'webdav_sync_ui_refresh.dart';

/// Runtime boundary for the engine's UI-agnostic post-commit apply callback.
/// Only the currently mounted, committed profile may publish live UI changes.
@visibleForTesting
void dispatchWebDavSyncAppliedKeysForActiveProfile(
  String localProfileId,
  Set<String> appliedKeys,
) {
  if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
    return;
  }
  if (ProfileRuntime.scope.value?.profileId != localProfileId) return;
  WebDavSyncUiRefresh.dispatch(appliedKeys);
}

@visibleForTesting
bool suppressWebDavSyncActiveProfileRetirement(WebDavSyncEngineState state) =>
    state.pendingActiveProfile != null &&
    state.pendingActiveProfile!.localProfileId ==
        state.pendingAdminSafetyProfile;

/// Executes the pre-round-4 deletion marker from local registry identity only.
/// A successful return means the marker can be cleared; no WebDAV context or
/// network cycle is needed after the gate has switched to a replacement.
@visibleForTesting
Future<bool> applyLegacyWebDavSyncActiveProfileDeletion({
  required ProfileRegistry registry,
  required WebDavSyncPendingActiveProfile pending,
  WebDavSyncDiagnostic? diagnostic,
}) async {
  if (!pending.isLegacyDeletion) {
    diagnostic?.call(
      'Dropped an invalid legacy WebDAV active-profile deletion marker',
      null,
    );
    return true;
  }
  final active = await registry.activeProfile();
  if (active?.id == pending.localProfileId) return false;
  RegistrySyncProfileProjection? projection;
  for (final candidate in await registry.readProfileSyncProjection()) {
    if (candidate.profile.id == pending.localProfileId) {
      projection = candidate;
      break;
    }
  }
  if (projection == null) {
    if (await registry.getProfile(pending.localProfileId) == null) return true;
    diagnostic?.call(
      'Dropped a legacy WebDAV active-profile deletion marker whose local '
      'identity could not be recovered',
      null,
    );
    return true;
  }
  final result = await registry.applySyncedRegistryDelta(
    SyncedRegistryDelta(
      deletes: <SyncedRegistryDeleteRecord>[
        SyncedRegistryDeleteRecord(
          record: WebDavSyncRegistryRecordId.profile(pending.localProfileId),
          expectedPriorUpdatedAtMs: projection.updatedAtMs,
        ),
      ],
    ),
  );
  return result == SyncedRegistryApplyResult.applied;
}

abstract interface class WebDavSyncActivationController {
  Future<void> inspectExisting(String bindingId);

  Future<WebDavSyncInitializationOutcome> initializeNew(String bindingId);

  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  });

  Future<WebDavSyncCycleReport> syncNow();
}

abstract interface class WebDavSyncManagementController {
  Future<WebDavSyncRuntimeStatus> status();

  Future<List<WebDavSyncDeviceSummary>> listDevices();

  Future<void> forgetDevice(String deviceId);
}

/// Lets the settings flow pause the old folder while an isolated replacement
/// is being verified, then resume whichever binding remains authoritative.
abstract interface class WebDavSyncReconfigurationController {
  void pauseForReconfiguration();

  Future<void> resumeAfterReconfiguration();
}

final class WebDavSyncRuntimeStatus {
  const WebDavSyncRuntimeStatus({
    required this.lastSuccessfulSyncMs,
    required this.peerCount,
    required this.adminPruneBlocked,
    required this.deviceClockWarning,
    required this.clockPauseReason,
    this.lastPushMs,
    this.lastRemoteChangeMs,
    this.pollState = WebDavSyncPollState.gated,
    this.localStateMissing = false,
    this.pruneBlockingProfiles = const <String>[],
    this.safetyCleanupBlocked = false,
    this.statusHint,
  });

  final int? lastSuccessfulSyncMs;
  final int peerCount;
  final bool adminPruneBlocked;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? clockPauseReason;
  final int? lastPushMs;
  final int? lastRemoteChangeMs;
  final WebDavSyncPollState pollState;
  final bool localStateMissing;
  final List<String> pruneBlockingProfiles;
  final bool safetyCleanupBlocked;
  final String? statusHint;
}

/// Production owner of WebDAV sync composition and trigger arming.
/// Construction alone does no network work; [initialize] recovers durable
/// adoption state, resumes an unfinished first sync, and arms Active bindings.
final class WebDavSyncRuntime
    with WidgetsBindingObserver
    implements
        WebDavSyncActivationController,
        WebDavSyncManagementController,
        WebDavSyncReconfigurationController,
        WebDavSyncRuntimeGate {
  WebDavSyncRuntime._() {
    _firstJoinAutoResume = WebDavSyncFirstJoinAutoResume(
      bindingStore: bindingStore,
      operations: _operations,
      connect: _connectExistingRoot,
      pauseCheck: () => _reconfigurationPaused,
      diagnostic: recordWebDavSyncDiagnostic,
    );
  }

  static final WebDavSyncRuntime instance = WebDavSyncRuntime._();

  final WebDavSyncBindingStore bindingStore = WebDavSyncBindingStore();
  late final WebDavSyncEngineStateStore stateStore = WebDavSyncEngineStateStore(
    bindingStore: bindingStore,
  );
  final WebDavSyncOperationCoordinator _operations =
      WebDavSyncOperationCoordinator();
  late final WebDavSyncFirstJoinAutoResume _firstJoinAutoResume;

  WebDavSyncScheduler? _scheduler;
  Timer? _maintenanceTimer;
  _ProductionCycleRunner? _cycleRunner;
  bool _initialized = false;
  Future<void>? _initializing;
  bool _reconfigurationPaused = false;
  bool _playbackActive = false;
  int _tvOsMemoryPressureUntilMs = 0;
  bool _startupRecoveryUnavailable = false;
  final Set<String> _missingStateNamespaces = <String>{};
  OpenedWebDavSyncRoot? _cachedRoot;
  String? _cachedRootRevision;
  List<int>? _cachedRootMarker;

  @override
  bool get playbackActive => _playbackActive;

  @override
  bool get playbackActiveOnTelevision =>
      _playbackActive && PlatformUtil.isTelevision;

  @override
  bool get tvOsLowMemory =>
      PlatformUtil.isTvOS &&
      DateTime.now().millisecondsSinceEpoch < _tvOsMemoryPressureUntilMs;

  @override
  void didHaveMemoryPressure() {
    if (!PlatformUtil.isTvOS) return;
    _clearCachedRoot();
    _tvOsMemoryPressureUntilMs = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
  }

  Future<void> initialize() {
    if (_initialized ||
        (!WebDavSyncFeature.enabled && !ProfileDatabaseAdoptionGate.isHeld)) {
      return Future<void>.value();
    }
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<void> started;
    started = _initializeOnce().whenComplete(() {
      if (identical(_initializing, started)) _initializing = null;
    });
    _initializing = started;
    return started;
  }

  Future<void> _initializeOnce() async {
    if (!ProfileRuntime.isProfileCommitted) {
      if (ProfileDatabaseAdoptionGate.isHeld) {
        // A rollback build must never strand a restart-durable barrier. There
        // cannot be a valid CircleAdoption outside committed profile mode, so
        // this is a stale gate rather than an operation that can be resumed.
        try {
          await ProfileDatabaseAdoptionGate.release();
        } catch (error) {
          debugPrint(
            'WebDAV sync stale database gate cleanup failed '
            '(${error.runtimeType})',
          );
        }
      }
      return;
    }
    final enableRuntime = WebDavSyncFeature.enabled;
    if (enableRuntime) {
      _cycleRunner = _ProductionCycleRunner(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        localAdapter: ProfileWebDavSyncLocalAdapter(ProfileBootstrap.registry),
        operations: _operations,
      );
      _scheduler = WebDavSyncScheduler(
        runner: _cycleRunner!,
        gate: this,
        localChangeObserver: recordWebDavSyncLocalChangeTrigger,
        localChangeDeferredObserver: recordWebDavSyncLocalChangeDeferred,
      );
      WidgetsBinding.instance.addObserver(this);
      MainPageBridge.addPlayerLaunchListener(_onPlaybackStarted);
      MainPageBridge.addContentPlaybackStopListener(_onPlaybackStopped);
    }
    try {
      await _recoverAdoptions();
      if (enableRuntime) {
        await _firstJoinAutoResume.resumeIfNeeded(
          reconfigurationPaused: _reconfigurationPaused,
        );
        await _armIfActive();
      }
      _initialized = true;
    } catch (error) {
      // Sync recovery is optional startup work. Persisted corruption or a
      // permanently failing adoption must not replace the whole application
      // with the dead-end startup failure screen, and must never strand DB
      // users behind the adoption gate.
      await _failOpenStartupRecovery(error);
      _initialized = true;
    }
  }

  Future<void> _failOpenStartupRecovery(Object error) async {
    debugPrint(
      'WebDAV sync startup recovery paused (${error.runtimeType}); '
      'the app will continue',
    );
    _disarmScheduler();
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _clearCachedRoot();

    var storeReadable = false;
    var statusPersisted = true;
    try {
      final snapshot = await bindingStore.load();
      storeReadable = true;
      for (final binding in snapshot.bindings.values.where(
        (candidate) =>
            candidate.circleId != null ||
            candidate.id == snapshot.activeBindingId ||
            candidate.id == snapshot.stagedBindingId,
      )) {
        try {
          await bindingStore.markError(
            binding.id,
            StateError(
              'WebDAV sync startup recovery could not finish; reconnect this folder',
            ),
          );
        } catch (_) {
          statusPersisted = false;
        }
      }
    } catch (_) {
      // A future/damaged binding-store schema cannot safely be rewritten by
      // this build. Leave its bytes intact for a newer build, but keep startup
      // and ordinary profile databases available.
      statusPersisted = false;
    }
    _startupRecoveryUnavailable =
        error is FormatException || !storeReadable || !statusPersisted;

    if (ProfileDatabaseAdoptionGate.isHeld) {
      try {
        await ProfileDatabaseAdoptionGate.release();
      } catch (releaseError) {
        debugPrint(
          'WebDAV sync database gate persistence cleanup failed '
          '(${releaseError.runtimeType})',
        );
      }
    }
  }

  Future<void> signalLaunch() async {
    await initialize();
    await _signalAutomatically(WebDavSyncTrigger.launch);
  }

  @override
  void pauseForReconfiguration() {
    _reconfigurationPaused = true;
    _clearCachedRoot();
    _disarmScheduler();
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
  }

  @override
  Future<void> resumeAfterReconfiguration() async {
    _reconfigurationPaused = false;
    await initialize();
    if (_scheduler != null) await _armIfActive();
  }

  @override
  Future<WebDavSyncCycleReport> syncNow() async {
    await initialize();
    final scheduler = _scheduler;
    if (scheduler == null) return _inactiveReport;
    final report = await scheduler.signal(WebDavSyncTrigger.manual);
    if (report.disposition == WebDavSyncCycleDisposition.completed ||
        report.disposition == WebDavSyncCycleDisposition.seedRepairRequired) {
      await _runSeedMaintenance(
        force:
            report.disposition == WebDavSyncCycleDisposition.seedRepairRequired,
      );
    }
    return report;
  }

  @override
  Future<WebDavSyncRuntimeStatus> status() async {
    await initialize();
    return _operations.run(() async {
      if (_startupRecoveryUnavailable) {
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
          localStateMissing: true,
        );
      }
      final stored = await bindingStore.load();
      final active = stored.activeBinding;
      if (active == null) {
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
        );
      }
      late final WebDavSyncEngineState state;
      try {
        state = await stateStore.load(active.namespaceId);
      } on WebDavSyncEngineStateMissingException {
        await _recordMissingState(active.namespaceId);
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
          localStateMissing: true,
        );
      }
      final ownDeviceId = stored.namespaceFor(active)?.deviceId;
      final peerCount = state.currentDeviceIds
          .where((deviceId) => deviceId != ownDeviceId)
          .length;
      final blockingIds = state.prunePendingProfileIds.toList()..sort();
      final blockingNames = <String>[];
      if (blockingIds.isNotEmpty) {
        try {
          final profiles = await ProfileBootstrap.registry.listProfiles(
            includeDisabled: true,
            includeStaging: true,
          );
          final namesById = <String, String>{
            for (final profile in profiles) profile.id: profile.name,
          };
          blockingNames.addAll(blockingIds.map((id) => namesById[id] ?? id));
        } catch (_) {
          blockingNames.addAll(blockingIds);
        }
      }
      return WebDavSyncRuntimeStatus(
        lastSuccessfulSyncMs: state.lastSuccessfulSyncMs,
        peerCount: peerCount,
        adminPruneBlocked: state.prunePendingProfileIds.isNotEmpty,
        deviceClockWarning: state.deviceClockWarning,
        clockPauseReason: state.lastClockPauseReason,
        lastPushMs: state.lastPushMs,
        lastRemoteChangeMs: state.lastRemoteChangeMs,
        pollState: peerCount == 0
            ? WebDavSyncPollState.gated
            : (_scheduler?.pollState ?? WebDavSyncPollState.gated),
        pruneBlockingProfiles: List<String>.unmodifiable(blockingNames),
        safetyCleanupBlocked: state.safetyProtectedProfileIds.isNotEmpty,
        statusHint: state.statusHint,
      );
    });
  }

  @override
  Future<List<WebDavSyncDeviceSummary>> listDevices() async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    return _operations.run(() async {
      await _captureManagingAdmin();
      return _graphTier().listDevices();
    });
  }

  @override
  Future<void> forgetDevice(String deviceId) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    await _operations.run(() async {
      final authorization = await _captureManagingAdmin();
      await _graphTier().forgetDevice(
        deviceId: deviceId,
        authorization: authorization,
      );
    });
  }

  @override
  Future<void> inspectExisting(String bindingId) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    await _operations.run(() async {
      var stored = await bindingStore.load();
      var binding = stored.bindings[bindingId];
      if (binding == null) {
        throw StateError('WebDAV sync binding is unavailable');
      }
      if (_missingStateNamespaces.contains(binding.namespaceId)) {
        await stateStore.initializeMissingForReconnect(binding.namespaceId);
        _missingStateNamespaces.remove(binding.namespaceId);
        if (binding.requiresStateReconnect) {
          binding = await bindingStore.setLifecycle(
            binding.id,
            WebDavSyncLifecycle.rootVerified,
          );
        }
        stored = await bindingStore.load();
        binding = stored.bindings[bindingId];
        if (binding == null) {
          throw StateError('WebDAV sync binding became unavailable');
        }
      }
      await WebDavSyncExistingRootDiscovery(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        diagnostic: recordWebDavSyncDiagnostic,
      ).discover(bindingId: bindingId);
    });
  }

  @override
  Future<WebDavSyncInitializationOutcome> initializeNew(
    String bindingId,
  ) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    return _operations.run(() async {
      final authorization = await _captureManagingAdmin();
      final components = _components();
      final outcome = await WebDavSyncNewRootInitializer(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        seedSource: components.seedSource,
      ).initialize(bindingId: bindingId, authorization: authorization);
      if (outcome is WebDavSyncInitialized) {
        _startupRecoveryUnavailable = false;
        await _armIfActive();
      }
      return outcome;
    });
  }

  @override
  Future<WebDavSyncBinding> connectExisting(
    String bindingId, {
    required bool replacementConfirmed,
  }) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    return _operations.run(() async {
      try {
        final result = await _connectExistingRoot(
          bindingId,
          replacementConfirmed: replacementConfirmed,
        );
        _startupRecoveryUnavailable = false;
        await _armIfActive();
        return result;
      } catch (error) {
        try {
          final stored = await bindingStore.load();
          final binding = stored.bindings[bindingId];
          if (binding?.lifecycle == WebDavSyncLifecycle.awaitingAdoption) {
            await bindingStore.markAwaitingAdoptionError(bindingId, error);
          }
        } catch (_) {
          // Error-status persistence must not replace the actionable failure
          // returned to the manual setup path.
        }
        rethrow;
      }
    });
  }

  Future<WebDavSyncBinding> _connectExistingRoot(
    String bindingId, {
    bool replacementConfirmed = true,
  }) async {
    final authorization = await _captureManagingAdmin();
    final components = _components();
    final connector = WebDavSyncExistingRootConnector(
      bindingStore: bindingStore,
      stateRepository: stateStore,
      discovery: WebDavSyncExistingRootDiscovery(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        diagnostic: recordWebDavSyncDiagnostic,
      ),
      adoption: _adoption(components),
      publisher: WebDavSyncOwnManifestPublisher(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        seedSource: components.seedSource,
      ),
      engine: _cycleRunner!,
    );
    return connector.connect(
      bindingId: bindingId,
      authorization: authorization,
      recaptureAuthorization: _captureManagingAdmin,
      replacementConfirmed: replacementConfirmed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    if (state == AppLifecycleState.resumed) {
      scheduler.resumeRemotePolling();
      unawaited(_handleForeground());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      scheduler.pauseRemotePolling();
      unawaited(_signalAutomatically(WebDavSyncTrigger.background));
    }
  }

  Future<void> _handleForeground() async {
    try {
      final outcome = await _firstJoinAutoResume.resumeIfNeeded(
        reconfigurationPaused: _reconfigurationPaused,
      );
      if (outcome == WebDavSyncFirstJoinAutoResumeOutcome.activated) {
        _startupRecoveryUnavailable = false;
        await _armIfActive();
      }
    } catch (_) {
      // The durable awaiting state remains available to a later foreground or
      // manual retry; ordinary foreground work must continue.
    }
    String? namespaceBefore;
    WebDavSyncPendingActiveProfile? pendingBefore;
    var retirementSuppressedBefore = false;
    try {
      final binding = (await bindingStore.load()).activeBinding;
      namespaceBefore = binding?.namespaceId;
      if (namespaceBefore != null) {
        final state = await stateStore.load(namespaceBefore);
        pendingBefore = state.pendingActiveProfile;
        retirementSuppressedBefore = suppressWebDavSyncActiveProfileRetirement(
          state,
        );
      }
    } catch (_) {
      // A malformed/unavailable binding must not interrupt foregrounding.
    }
    await _signalAutomatically(WebDavSyncTrigger.foreground);
    // A tombstone first observed by the cycle above is deliberately handled
    // on the next foreground. That boundary leaves a durable recovery point
    // between merge/apply and the user-visible replacement switch.
    if (_playbackActive || namespaceBefore == null || pendingBefore == null) {
      return;
    }
    // A foreground which restores another managing Admin clears the safety
    // hold during the cycle above. Retirement intentionally waits for the next
    // idle foreground, preserving a stable handoff boundary.
    if (retirementSuppressedBefore) return;
    final callback = MainPageBridge.retireProfileFromSync;
    if (callback == null) return;
    try {
      final stored = await bindingStore.load();
      final binding = stored.activeBinding;
      if (binding == null || binding.namespaceId != namespaceBefore) return;
      final state = await stateStore.load(binding.namespaceId);
      final pending = state.pendingActiveProfile;
      if (pending == null ||
          !_samePendingActiveProfile(pending, pendingBefore) ||
          suppressWebDavSyncActiveProfileRetirement(state) ||
          !await callback(
            pending.localProfileId,
            delete:
                pending.reason == WebDavSyncPendingActiveProfileReason.deleted,
            applyOutcome: () =>
                _applyPendingActiveProfile(binding.namespaceId, pending),
          )) {
        return;
      }
      await stateStore.update(
        binding.namespaceId,
        (current) =>
            current.pendingActiveProfile != null &&
                _samePendingActiveProfile(
                  current.pendingActiveProfile!,
                  pending,
                )
            ? current.copyWith(clearPendingActiveProfileDeletion: true)
            : current,
      );
    } catch (_) {
      // The durable marker remains for a later idle foreground.
    }
  }

  Future<void> _applyPendingActiveProfile(
    String namespaceId,
    WebDavSyncPendingActiveProfile pending,
  ) => serializeWebDavSyncPendingActiveProfileApply(
    operations: _operations,
    apply: () async {
      final current = await stateStore.load(namespaceId);
      final durable = current.pendingActiveProfile;
      if (durable == null ||
          !_samePendingActiveProfile(durable, pending) ||
          suppressWebDavSyncActiveProfileRetirement(current)) {
        return;
      }
      if (durable.isLegacyDeletion) {
        final resolved = await applyLegacyWebDavSyncActiveProfileDeletion(
          registry: ProfileBootstrap.registry,
          pending: durable,
          diagnostic: _pendingActiveProfileDiagnostic,
        );
        if (resolved) {
          await _clearPendingActiveProfile(namespaceId, durable);
        }
        return;
      }
      final leaf = durable.profileLeaf;
      final circleProfileId = durable.circleProfileId;
      if (leaf == null || circleProfileId == null) {
        _pendingActiveProfileDiagnostic(
          'Dropped a WebDAV active-profile marker whose stored outcome could '
          'not be recovered',
          null,
        );
        await _clearPendingActiveProfile(namespaceId, durable);
        return;
      }
      final currentWinner =
          current.circleProfilesBaseline?.profiles[circleProfileId];
      if (currentWinner != null &&
          _profileWinnerSupersedes(currentWinner, leaf)) {
        _pendingActiveProfileDiagnostic(
          'Dropped a stale WebDAV active-profile marker after a newer circle '
          'winner arrived',
          null,
        );
        await _clearPendingActiveProfile(namespaceId, durable);
        return;
      }
      final cycleRunner = _cycleRunner;
      final adapter = cycleRunner?.localAdapter;
      final WebDavSyncCircleLocalAdapter? circleAdapter =
          adapter is WebDavSyncCircleLocalAdapter
          ? adapter as WebDavSyncCircleLocalAdapter
          : null;
      final context = await _activeContext();
      if (circleAdapter == null ||
          context == null ||
          context.namespaceId != namespaceId ||
          !context.isComplete ||
          !current.hasAuthenticatedMaps) {
        _scheduler?.notifyLocalChange(
          ProfilePreferences.webDavSyncRegistryLogicalKey,
        );
        return;
      }
      final versions = WebDavSyncRegistryVersionSnapshot(
        enforce: true,
        updatedAtMsByRecord: durable.expectedPriorUpdatedAtMs == null
            ? const <String, int>{}
            : <String, int>{
                WebDavSyncRegistryRecordId.profile(
                  durable.localProfileId,
                ).storageKey: durable.expectedPriorUpdatedAtMs!,
              },
      );
      final session = await adapter!.beginCycle();
      final result = await circleAdapter.applyCircleState(
        session,
        WebDavSyncCircleApplyRequest(
          identityMaps: WebDavSyncIdentityMaps(
            circleToLocalProfiles: current.circleToLocalProfiles!,
            circleToLocalResources: current.circleToLocalResources!,
          ),
          circleId: context.root!.document.circleId,
          circleKey: context.root!.key,
          profiles: WebDavSyncProfilesDocument(
            profiles: <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
              circleProfileId: leaf,
            },
          ),
          resources: const WebDavSyncResourcesDocument(
            resources: <String, WebDavSyncResourceEntry>{},
            grants:
                <
                  String,
                  Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>
                >{},
            settings:
                <
                  String,
                  Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
                >{},
            bindings:
                <
                  String,
                  Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>
                >{},
          ),
          registryVersions: versions,
        ),
      );
      if (result == WebDavSyncCircleApplyResult.conflict) {
        _scheduler?.notifyConflictFollowUp();
        return;
      }
      await _clearPendingActiveProfile(namespaceId, durable);
    },
  );

  Future<void> _clearPendingActiveProfile(
    String namespaceId,
    WebDavSyncPendingActiveProfile pending,
  ) => stateStore.update(
    namespaceId,
    (current) =>
        current.pendingActiveProfile != null &&
            _samePendingActiveProfile(current.pendingActiveProfile!, pending)
        ? current.copyWith(clearPendingActiveProfileDeletion: true)
        : current,
  );

  static bool _profileWinnerSupersedes(
    WebDavSyncCircleLeaf<WebDavSyncProfileValue> current,
    WebDavSyncCircleLeaf<WebDavSyncProfileValue> stored,
  ) {
    final time = current.stamp.normalizedTimeMs.compareTo(
      stored.stamp.normalizedTimeMs,
    );
    if (time != 0) return time > 0;
    final origin = current.stamp.originDeviceId.compareTo(
      stored.stamp.originDeviceId,
    );
    if (origin != 0) return origin > 0;
    return semanticDigestOf(
          current.value?.toJson(),
        ).compareTo(semanticDigestOf(stored.value?.toJson())) >
        0;
  }

  static void _pendingActiveProfileDiagnostic(String message, Object? _) {
    debugPrint(message);
    app_diagnostics.DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'pending_active_profile_marker_dropped',
      level: app_diagnostics.DiagnosticLevel.warning,
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

  void _onPlaybackStarted() {
    _playbackActive = true;
  }

  void _onPlaybackStopped() {
    _playbackActive = false;
    final scheduler = _scheduler;
    if (scheduler != null) {
      unawaited(_signalAutomatically(WebDavSyncTrigger.playbackStopped));
    }
  }

  Future<void> _recoverAdoptions() async {
    final stored = await bindingStore.load();
    var recoveredJournal = false;
    final components = _components();
    final adoption = _adoption(components);
    for (final namespaceId
        in stored.bindings.values
            .where((binding) => binding.circleId != null)
            .map((binding) => binding.namespaceId)
            .toSet()) {
      late final WebDavSyncEngineState state;
      try {
        state = await stateStore.load(namespaceId);
      } on WebDavSyncEngineStateMissingException {
        await _recordMissingState(namespaceId, snapshot: stored);
        continue;
      }
      if (state.adoption == null) continue;
      recoveredJournal = true;
      await adoption.recover(namespaceId);
    }
    if (ProfileDatabaseAdoptionGate.isHeld && !recoveredJournal) {
      // The Caches-backed journal can be purged independently of the durable
      // UserDefaults gate on tvOS. The affected binding was marked as needing
      // an explicit reconnect above; release ordinary database opens so the
      // user can reach that recovery UI instead of boot-looping forever.
      await ProfileDatabaseAdoptionGate.release();
    }

    final seedRecovery = WebDavSyncSeedActivationRecovery(
      bindingStore: bindingStore,
      stateRepository: stateStore,
    );
    await seedRecovery.recover();

    // Crash window: lifecycle became Active after the verified first merge,
    // but the staged pointer was not yet promoted.
    final refreshed = await bindingStore.load();
    final staged = refreshed.stagedBinding;
    if (staged != null && staged.lifecycle == WebDavSyncLifecycle.active) {
      final state = await stateStore.load(staged.namespaceId);
      if (state.adoption != null ||
          !state.hasAuthenticatedMaps ||
          state.ownManifest == null) {
        throw StateError('WebDAV sync interrupted promotion is incomplete');
      }
      await bindingStore.promoteStaged(staged.id);
    }
    await seedRecovery.clearActiveCandidate();
  }

  Future<void> _armIfActive() async {
    if (_reconfigurationPaused) {
      _disarmScheduler();
      _maintenanceTimer?.cancel();
      _maintenanceTimer = null;
      return;
    }
    final stored = await bindingStore.load();
    final active = stored.activeBinding;
    if (active == null || active.lifecycle != WebDavSyncLifecycle.active) {
      _clearCachedRoot();
      _disarmScheduler();
      _maintenanceTimer?.cancel();
      _maintenanceTimer = null;
      return;
    }
    _cycleRunner!.retainBinding(active.id);
    _scheduler!.arm(
      _activeContext,
      remotePollContextProvider: _cycleRunner!.remotePollContext,
    );
    ProfilePreferences.webDavSyncLocalChangeSink = _onLocalProfileChange;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(WebDavSyncGraphTier.cadence, (_) {
      unawaited(_maintainSeed(force: false));
    });
  }

  void _onLocalProfileChange(String _, String logicalKey) {
    _scheduler?.notifyLocalChange(logicalKey);
  }

  void _disarmScheduler() {
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    _scheduler?.disarm();
  }

  Future<WebDavSyncCycleReport> _signalWithMaintenance(
    WebDavSyncTrigger trigger,
  ) async {
    final scheduler = _scheduler;
    if (scheduler == null) return _inactiveReport;
    final report = await scheduler.signal(trigger);
    if (report.disposition == WebDavSyncCycleDisposition.completed ||
        report.disposition == WebDavSyncCycleDisposition.seedRepairRequired) {
      await _maintainSeed(
        force:
            report.disposition == WebDavSyncCycleDisposition.seedRepairRequired,
      );
    }
    return report;
  }

  Future<void> _signalAutomatically(WebDavSyncTrigger trigger) async {
    try {
      await _signalWithMaintenance(trigger);
    } catch (_) {
      // Routine automatic sync is best effort. The settings status retains
      // errors recorded by the engine/discovery paths; launch, foreground,
      // background, and playback return never leak an async exception.
    }
  }

  Future<void> _maintainSeed({required bool force}) async {
    if (playbackActiveOnTelevision || tvOsLowMemory) return;
    try {
      await _runSeedMaintenance(force: force);
    } on StateError {
      // A non-Admin/locked session pauses bootstrap maintenance only.
    } on WebDavException {
      // Routine LAN/offline failures remain settings status, never banners.
    } catch (_) {
      // Automatic maintenance must not surface failures during playback/home.
    }
  }

  Future<void> _runSeedMaintenance({required bool force}) =>
      _operations.run(() async {
        final authorization = await ProfileAuthorizationContext.capture(
          ProfileBootstrap.registry,
        );
        await _graphTier().maintain(authorization: authorization, force: force);
      });

  Future<WebDavSyncCycleContext?> _activeContext() async {
    final stored = await bindingStore.load();
    final binding = stored.activeBinding;
    final namespace = binding == null ? null : stored.namespaceFor(binding);
    final marker = namespace?.markerBytes;
    if (binding == null ||
        binding.lifecycle != WebDavSyncLifecycle.active ||
        namespace == null ||
        marker == null ||
        marker.isEmpty) {
      _clearCachedRoot();
      return null;
    }
    late final WebDavSyncEngineState state;
    try {
      state = await stateStore.load(namespace.id);
    } on WebDavSyncEngineStateMissingException {
      _clearCachedRoot();
      await _recordMissingState(namespace.id, snapshot: stored);
      return null;
    }
    if (state.adoption != null ||
        !state.hasAuthenticatedMaps ||
        state.ownManifest == null) {
      return null;
    }
    final rootRevision =
        '${binding.id}:${binding.updatedAt.microsecondsSinceEpoch}:'
        '${binding.sealedSecrets}';
    var root = _cachedRoot;
    if (root == null ||
        _cachedRootRevision != rootRevision ||
        !_sameByteLists(_cachedRootMarker, marker)) {
      final secrets = await bindingStore.readSecrets(binding);
      root = await WebDavSyncCodec().openRoot(
        marker,
        secrets.syncPassphrase,
        runInBackground: true,
      );
      _cachedRoot = root;
      _cachedRootRevision = rootRevision;
      _cachedRootMarker = List<int>.unmodifiable(marker);
    }
    if (root.document.circleId != binding.circleId) {
      _clearCachedRoot();
      return null;
    }
    return WebDavSyncCycleContext(
      namespaceId: namespace.id,
      deviceId: namespace.deviceId,
      markerPin: marker,
      root: root,
      circleToLocalProfiles: state.circleToLocalProfiles,
      circleToLocalResources: state.circleToLocalResources,
      wireProfileMap: state.ownManifest!.profileMap,
      wireResourceMap: state.ownManifest!.resourceMap,
      active: true,
    );
  }

  void _clearCachedRoot() {
    _cachedRoot = null;
    _cachedRootRevision = null;
    _cachedRootMarker = null;
    _cycleRunner?.clearSectionCache();
  }

  Future<void> _recordMissingState(
    String namespaceId, {
    WebDavSyncStoreSnapshot? snapshot,
  }) async {
    _missingStateNamespaces.add(namespaceId);
    final current = snapshot ?? await bindingStore.load();
    for (final binding in current.bindings.values.where(
      (candidate) => candidate.namespaceId == namespaceId,
    )) {
      if (binding.requiresStateReconnect) continue;
      await bindingStore.markError(
        binding.id,
        const WebDavSyncEngineStateMissingException(),
      );
    }
  }

  @visibleForTesting
  void debugResetInitialization() {
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    _scheduler?.dispose();
    _cycleRunner?.closeCycleTransports();
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _scheduler = null;
    _cycleRunner = null;
    WidgetsBinding.instance.removeObserver(this);
    MainPageBridge.removePlayerLaunchListener(_onPlaybackStarted);
    MainPageBridge.removeContentPlaybackStopListener(_onPlaybackStopped);
    _initialized = false;
    _initializing = null;
    _reconfigurationPaused = false;
    _playbackActive = false;
    _startupRecoveryUnavailable = false;
    _missingStateNamespaces.clear();
    _firstJoinAutoResume.reset();
    _clearCachedRoot();
  }

  _RuntimeComponents _components() {
    final registry = ProfileBootstrap.registry;
    final packageService = ProfilePackageService(
      registry: registry,
      resources: ConnectionResourceService(
        registry: registry,
        cipher: DeviceKeyProvider.cipher,
      ),
    );
    return _RuntimeComponents(
      packageService: packageService,
      seedSource: DefaultWebDavSyncSeedSource(
        graphBuilder: WebDavSyncGraphBuilder(packageService),
        stateRepository: stateStore,
        localAdapter: ProfileWebDavSyncLocalAdapter(registry),
      ),
    );
  }

  WebDavSyncCircleAdoption _adoption(_RuntimeComponents components) {
    final registry = ProfileBootstrap.registry;
    final participant = ProfileAppLifecycleParticipant();
    return WebDavSyncCircleAdoption(
      stateRepository: stateStore,
      safetyBackups: LocalWebDavSyncSafetyBackupStore(
        source: DefaultWebDavSyncSafetyBackupSource(components.packageService),
      ),
      operations: DefaultWebDavSyncAdoptionOperations(
        registry: registry,
        restoreCoordinator: ProfileRestoreCoordinator(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
          lifecycleParticipants: <ProfileLifecycleParticipant>[participant],
        ),
        lifecycleCoordinator: ProfileLifecycleCoordinator(
          registry: registry,
          participants: <ProfileLifecycleParticipant>[participant],
        ),
        // Consent + an authenticated sync passphrase authorize this one
        // transaction. A crash-resume must not strand the global DB gate on
        // the imported Admin's ordinary profile-unlock screen.
        unlockImportedAdmin: (_) async => true,
      ),
      diagnostic: recordWebDavSyncDiagnostic,
    );
  }

  WebDavSyncGraphTier _graphTier() {
    final components = _components();
    final discovery = WebDavSyncExistingRootDiscovery(
      bindingStore: bindingStore,
      stateRepository: stateStore,
      diagnostic: recordWebDavSyncDiagnostic,
    );
    return WebDavSyncGraphTier(
      bindingStore: bindingStore,
      stateRepository: stateStore,
      discovery: discovery,
      graphBuilder: WebDavSyncGraphBuilder(components.packageService),
      adoption: _adoption(components),
      publisher: WebDavSyncOwnManifestPublisher(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        seedSource: components.seedSource,
      ),
      cycleRunner: _cycleRunner!,
      contextProvider: _activeContext,
    );
  }

  void _requireAvailable() {
    if (_scheduler == null || _cycleRunner == null) {
      throw StateError('WebDAV sync requires committed profiles');
    }
  }

  void _requireInteractiveWorkAllowed() {
    if (playbackActiveOnTelevision) {
      throw StateError('Stop playback before using WebDAV Sync');
    }
    if (tvOsLowMemory) {
      throw StateError(
        'Apple TV recently reported low memory. Wait a few minutes and try again',
      );
    }
  }

  static const WebDavSyncCycleReport _inactiveReport = WebDavSyncCycleReport(
    disposition: WebDavSyncCycleDisposition.inactive,
  );

  static Future<ProfileAuthorizationContext> _captureManagingAdmin() async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final profile = await authorization.validate(registry);
    if (!profile.isAdmin ||
        !profile.allows(ProfileFeature.manageProfiles) ||
        !profile.allows(ProfileFeature.backupRestore)) {
      throw StateError('WebDAV sync requires an active managing Admin');
    }
    return authorization;
  }
}

final class _RuntimeComponents {
  const _RuntimeComponents({
    required this.packageService,
    required this.seedSource,
  });

  final ProfilePackageService packageService;
  final DefaultWebDavSyncSeedSource seedSource;
}

final class WebDavSyncAuthenticationFailureTracker {
  static const int failureThreshold = 3;

  final Map<String, int> _consecutiveFailures = <String, int>{};

  bool recordFailure(String bindingId) {
    final count = (_consecutiveFailures[bindingId] ?? 0) + 1;
    _consecutiveFailures[bindingId] = count;
    return count >= failureThreshold;
  }

  void recordSuccess(String bindingId) {
    _consecutiveFailures.remove(bindingId);
  }
}

typedef WebDavSyncHttpClientFactory = http.Client Function();

final class WebDavSyncHttpClientBorrow {
  const WebDavSyncHttpClientBorrow({
    required this.client,
    required this.generation,
  });

  final http.Client client;
  final int generation;
}

/// Owns the one reusable protocol client for the currently armed binding.
/// Per-cycle transports borrow it and therefore cannot close it themselves.
final class WebDavSyncBindingHttpClientOwner {
  WebDavSyncBindingHttpClientOwner({WebDavSyncHttpClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final WebDavSyncHttpClientFactory _clientFactory;
  String? _bindingId;
  http.Client? _client;
  int _generation = 0;

  int get generation => _generation;

  WebDavSyncHttpClientBorrow borrow(String bindingId) {
    retainBinding(bindingId);
    final client = _client ??= _clientFactory();
    return WebDavSyncHttpClientBorrow(
      client: _WebDavSyncGenerationClient(
        owner: this,
        delegate: client,
        generation: _generation,
      ),
      generation: _generation,
    );
  }

  WebDavSyncHttpClientBorrow? borrowIfGeneration(
    String bindingId,
    int generation,
  ) {
    if (generation != _generation) return null;
    return borrow(bindingId);
  }

  void retainBinding(String bindingId) {
    if (_bindingId == bindingId) return;
    final previous = _client;
    _client = null;
    _bindingId = bindingId;
    _generation++;
    previous?.close();
  }

  bool isGenerationCurrent(int generation) => generation == _generation;

  bool _owns(http.Client client, int generation) =>
      generation == _generation && identical(client, _client);

  void close({int? ifGeneration}) {
    if (ifGeneration != null && ifGeneration != _generation) return;
    final previous = _client;
    _client = null;
    _bindingId = null;
    _generation++;
    previous?.close();
  }

  @visibleForTesting
  bool get debugHasClient => _client != null;
}

final class _WebDavSyncGenerationClient extends http.BaseClient {
  _WebDavSyncGenerationClient({
    required WebDavSyncBindingHttpClientOwner owner,
    required http.Client delegate,
    required int generation,
  }) : _owner = owner,
       _delegate = delegate,
       _generation = generation;

  final WebDavSyncBindingHttpClientOwner _owner;
  final http.Client _delegate;
  final int _generation;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_owner._owns(_delegate, _generation)) {
      throw http.ClientException(
        'WebDAV sync HTTP client generation is stale',
        request.url,
      );
    }
    return _delegate.send(request);
  }

  @override
  void close() {
    // The binding owner alone closes the underlying shared client.
  }
}

final class _ProductionCycleRunner
    implements WebDavSyncCycleRunner, WebDavSyncCycleTransportOwner {
  _ProductionCycleRunner({
    required this.bindingStore,
    required this.stateRepository,
    required this.localAdapter,
    required this.operations,
    WebDavSyncBindingHttpClientOwner? httpClientOwner,
  }) : _httpClientOwner = httpClientOwner ?? WebDavSyncBindingHttpClientOwner();

  final WebDavSyncBindingStore bindingStore;
  final WebDavSyncEngineStateRepository stateRepository;
  final WebDavSyncLocalAdapter localAdapter;
  final WebDavSyncOperationCoordinator operations;
  final WebDavSyncBindingHttpClientOwner _httpClientOwner;
  final WebDavSyncAuthenticationFailureTracker _authenticationFailures =
      WebDavSyncAuthenticationFailureTracker();
  final WebDavSyncSectionCache _sectionCache = WebDavSyncSectionCache();

  void clearSectionCache() => _sectionCache.clear();

  void retainBinding(String bindingId) =>
      _httpClientOwner.retainBinding(bindingId);

  @override
  void closeCycleTransports() => _httpClientOwner.close();

  Future<WebDavSyncRemotePollContext?> remotePollContext() async {
    final clientGeneration = _httpClientOwner.generation;
    final stored = await bindingStore.load();
    final binding = stored.activeBinding;
    if (binding == null || binding.lifecycle != WebDavSyncLifecycle.active) {
      return null;
    }
    final namespace = stored.namespaceFor(binding);
    if (namespace == null) return null;
    final state = await stateRepository.load(namespace.id);
    if (state.blocksAllPushes) return null;
    final peerDeviceIds =
        state.currentDeviceIds
            .where((deviceId) => deviceId != namespace.deviceId)
            .toList()
          ..sort();
    if (peerDeviceIds.isEmpty) return null;
    final secrets = await bindingStore.readSecrets(binding);
    final borrow = _httpClientOwner.borrowIfGeneration(
      binding.id,
      clientGeneration,
    );
    if (borrow == null) return null;
    return WebDavSyncRemotePollContext(
      transport: ProtocolWebDavSyncTransport(
        location: binding.location,
        credentials: WebDavCredentials(
          username: secrets.username,
          password: secrets.password,
        ),
        client: borrow.client,
      ),
      peerDeviceIds: List<String>.unmodifiable(peerDeviceIds),
      validators: state.peerManifestValidators,
      clientGeneration: borrow.generation,
      isClientGenerationCurrent: _httpClientOwner.isGenerationCurrent,
    );
  }

  @override
  Future<WebDavSyncCycleReport> runCycle(
    WebDavSyncCycleContext? context, {
    bool allowPreActivation = false,
    WebDavSyncTrigger? trigger,
  }) => operations.run(
    () => _runCycle(
      context,
      allowPreActivation: allowPreActivation,
      trigger: trigger,
    ),
  );

  Future<WebDavSyncCycleReport> _runCycle(
    WebDavSyncCycleContext? context, {
    required bool allowPreActivation,
    required WebDavSyncTrigger? trigger,
  }) async {
    final clientGeneration = _httpClientOwner.generation;
    if (context == null || context.namespaceId == null) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    if (!context.active && !allowPreActivation) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final stored = await bindingStore.load();
    final preActivation = !context.active && allowPreActivation;
    final binding = stored.bindingForCycle(
      namespaceId: context.namespaceId!,
      preActivation: preActivation,
    );
    final namespace = binding == null ? null : stored.namespaceFor(binding);
    if (binding == null ||
        namespace == null ||
        binding.circleId != context.root?.document.circleId ||
        namespace.deviceId != context.deviceId ||
        !_sameBytes(namespace.markerBytes, context.markerPin)) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final secrets = await bindingStore.readSecrets(binding);
    final borrow = _httpClientOwner.borrowIfGeneration(
      binding.id,
      clientGeneration,
    );
    if (borrow == null) {
      return const WebDavSyncCycleReport(
        disposition: WebDavSyncCycleDisposition.inactive,
      );
    }
    final engine = WebDavSyncEngine(
      stateRepository: stateRepository,
      localAdapter: localAdapter,
      sectionCache: _sectionCache,
      transportFactory: (_) => ProtocolWebDavSyncTransport(
        location: binding.location,
        credentials: WebDavCredentials(
          username: secrets.username,
          password: secrets.password,
        ),
        client: borrow.client,
      ),
      diagnostic: recordWebDavSyncDiagnostic,
      appliedKeysCallback: dispatchWebDavSyncAppliedKeysForActiveProfile,
    );
    try {
      final report = await engine.runCycle(
        context,
        allowPreActivation: allowPreActivation,
        trigger: trigger,
      );
      _authenticationFailures.recordSuccess(binding.id);
      return report;
    } on WebDavSyncSetupException catch (error) {
      _authenticationFailures.recordSuccess(binding.id);
      await bindingStore.markError(binding.id, error);
      rethrow;
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.authentication &&
          _authenticationFailures.recordFailure(binding.id)) {
        await bindingStore.markError(binding.id, error);
      } else if (error.kind != WebDavErrorKind.authentication) {
        _authenticationFailures.recordSuccess(binding.id);
      }
      rethrow;
    } catch (_) {
      _authenticationFailures.recordSuccess(binding.id);
      rethrow;
    }
  }

  static bool _sameBytes(List<int>? left, List<int>? right) {
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

bool _sameByteLists(List<int>? left, List<int>? right) {
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
