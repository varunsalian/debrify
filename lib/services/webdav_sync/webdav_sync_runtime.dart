import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/profiles/profile_policy.dart';
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
import '../profiles/profile_restore_coordinator.dart';
import '../profiles/profile_runtime.dart';
import '../webdav_protocol_client.dart';
import '../../utils/platform_util.dart';
import 'webdav_sync_activation.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_adoption_operations.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_discovery.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_existing_root_connector.dart';
import 'webdav_sync_feature.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_graph_tier.dart';
import 'webdav_sync_local_adapter.dart';
import 'webdav_sync_manifest_publisher.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_operation_coordinator.dart';
import 'webdav_sync_safety_backup.dart';
import 'webdav_sync_scheduler.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_transport.dart';

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

  Future<WebDavSyncGraphTierReport> checkGraph({
    bool force = false,
    bool runBootstrapMaintenance = true,
  });

  Future<void> applyGraph(String semanticDigest);

  Future<void> declineGraph(String semanticDigest);

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
    required this.pendingGraphDigest,
    required this.adminPruneBlocked,
    required this.deviceClockWarning,
    required this.clockPauseReason,
    this.lastPushMs,
    this.lastRemoteChangeMs,
    this.pollState = WebDavSyncPollState.gated,
    this.localStateMissing = false,
    this.pruneBlockingProfiles = const <String>[],
    this.safetyCleanupBlocked = false,
  });

  final int? lastSuccessfulSyncMs;
  final int peerCount;
  final String? pendingGraphDigest;
  final bool adminPruneBlocked;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? clockPauseReason;
  final int? lastPushMs;
  final int? lastRemoteChangeMs;
  final WebDavSyncPollState pollState;
  final bool localStateMissing;
  final List<String> pruneBlockingProfiles;
  final bool safetyCleanupBlocked;
}

/// Production owner of WebDAV sync composition and trigger arming.
/// Construction alone does no network work; [initialize] only resumes a
/// durable local adoption and arms an already-Active binding.
final class WebDavSyncRuntime
    with WidgetsBindingObserver
    implements
        WebDavSyncActivationController,
        WebDavSyncManagementController,
        WebDavSyncReconfigurationController,
        WebDavSyncRuntimeGate {
  WebDavSyncRuntime._();

  static final WebDavSyncRuntime instance = WebDavSyncRuntime._();

  final WebDavSyncBindingStore bindingStore = WebDavSyncBindingStore();
  late final WebDavSyncEngineStateStore stateStore = WebDavSyncEngineStateStore(
    bindingStore: bindingStore,
  );
  final WebDavSyncOperationCoordinator _operations =
      WebDavSyncOperationCoordinator();

  WebDavSyncScheduler? _scheduler;
  Timer? _graphTimer;
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
      _scheduler = WebDavSyncScheduler(runner: _cycleRunner!, gate: this);
      WidgetsBinding.instance.addObserver(this);
      MainPageBridge.addPlayerLaunchListener(_onPlaybackStarted);
      MainPageBridge.addContentPlaybackStopListener(_onPlaybackStopped);
    }
    try {
      await _recoverAdoptions();
      if (enableRuntime) await _armIfActive();
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
    _graphTimer?.cancel();
    _graphTimer = null;
    _clearCachedRoot();
    MainPageBridge.setWebDavGraphChangePending(false);

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
    _graphTimer?.cancel();
    _graphTimer = null;
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
      // Manual sync must stay interactive: scan immediately for profile and
      // connection changes, but do not rebuild every profile database merely
      // because the user changed a hot preference. Structural repair branches
      // inside the graph tier still publish a complete seed when required.
      await checkGraph(force: true, runBootstrapMaintenance: false);
    }
    return report;
  }

  @override
  Future<WebDavSyncRuntimeStatus> status() async {
    await initialize();
    return _operations.run(() async {
      if (_startupRecoveryUnavailable) {
        MainPageBridge.setWebDavGraphChangePending(false);
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          pendingGraphDigest: null,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
          localStateMissing: true,
        );
      }
      final stored = await bindingStore.load();
      final active = stored.activeBinding;
      if (active == null) {
        MainPageBridge.setWebDavGraphChangePending(false);
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          pendingGraphDigest: null,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
        );
      }
      late final WebDavSyncEngineState state;
      try {
        state = await stateStore.load(active.namespaceId);
      } on WebDavSyncEngineStateMissingException {
        MainPageBridge.setWebDavGraphChangePending(false);
        await _recordMissingState(active.namespaceId);
        return const WebDavSyncRuntimeStatus(
          lastSuccessfulSyncMs: null,
          peerCount: 0,
          pendingGraphDigest: null,
          adminPruneBlocked: false,
          deviceClockWarning: false,
          clockPauseReason: null,
          localStateMissing: true,
        );
      }
      MainPageBridge.setWebDavGraphChangePending(
        state.pendingGraphDigest != null,
      );
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
        pendingGraphDigest: state.pendingGraphDigest,
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
      );
    });
  }

  @override
  Future<WebDavSyncGraphTierReport> checkGraph({
    bool force = false,
    bool runBootstrapMaintenance = true,
  }) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    final report = await _operations.run(() async {
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      return _graphTier().maintain(
        authorization: authorization,
        force: force,
        runBootstrapMaintenance: runBootstrapMaintenance,
      );
    });
    await _refreshGraphBadge();
    return report;
  }

  @override
  Future<void> applyGraph(String semanticDigest) async {
    await initialize();
    _requireInteractiveWorkAllowed();
    _requireAvailable();
    await _operations.run(() async {
      final authorization = await _captureManagingAdmin();
      await _graphTier().applyRemote(
        expectedDigest: semanticDigest,
        authorization: authorization,
        recaptureAuthorization: _captureManagingAdmin,
      );
    });
    await _refreshGraphBadge();
  }

  @override
  Future<void> declineGraph(String semanticDigest) async {
    await initialize();
    _requireAvailable();
    await _operations.run(() async {
      await _captureManagingAdmin();
      await _graphTier().decline(semanticDigest);
    });
    await _refreshGraphBadge();
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
      final authorization = await _captureManagingAdmin();
      final components = _components();
      final adoption = _adoption(components);
      final connector = WebDavSyncExistingRootConnector(
        bindingStore: bindingStore,
        stateRepository: stateStore,
        discovery: WebDavSyncExistingRootDiscovery(
          bindingStore: bindingStore,
          stateRepository: stateStore,
        ),
        adoption: adoption,
        publisher: WebDavSyncOwnManifestPublisher(
          bindingStore: bindingStore,
          stateRepository: stateStore,
          seedSource: components.seedSource,
        ),
        engine: _cycleRunner!,
      );
      final active = await connector.connect(
        bindingId: bindingId,
        authorization: authorization,
        recaptureAuthorization: _captureManagingAdmin,
        replacementConfirmed: replacementConfirmed,
      );
      _startupRecoveryUnavailable = false;
      await _armIfActive();
      return active;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    if (state == AppLifecycleState.resumed) {
      scheduler.resumeRemotePolling();
      unawaited(_signalAutomatically(WebDavSyncTrigger.foreground));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      scheduler.pauseRemotePolling();
      unawaited(_signalAutomatically(WebDavSyncTrigger.background));
    }
  }

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
      _graphTimer?.cancel();
      _graphTimer = null;
      return;
    }
    final stored = await bindingStore.load();
    final active = stored.activeBinding;
    if (active == null || active.lifecycle != WebDavSyncLifecycle.active) {
      _clearCachedRoot();
      _disarmScheduler();
      _graphTimer?.cancel();
      _graphTimer = null;
      return;
    }
    _scheduler!.arm(
      _activeContext,
      remotePollContextProvider: _cycleRunner!.remotePollContext,
    );
    ProfilePreferences.webDavSyncLocalChangeSink = _onLocalProfileChange;
    _graphTimer?.cancel();
    _graphTimer = Timer.periodic(WebDavSyncGraphTier.cadence, (_) {
      unawaited(_maintainGraph(force: false));
    });
  }

  void _onLocalProfileChange(String _, String logicalKey) {
    _scheduler?.notifyLocalChange(logicalKey);
  }

  void _disarmScheduler() {
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    _scheduler?.disarm();
  }

  Future<WebDavSyncCycleReport> _signalWithGraph(
    WebDavSyncTrigger trigger,
  ) async {
    final scheduler = _scheduler;
    if (scheduler == null) return _inactiveReport;
    final report = await scheduler.signal(trigger);
    if (report.disposition == WebDavSyncCycleDisposition.completed ||
        report.disposition == WebDavSyncCycleDisposition.seedRepairRequired) {
      await _maintainGraph(
        force:
            report.disposition == WebDavSyncCycleDisposition.seedRepairRequired,
      );
    }
    return report;
  }

  Future<void> _signalAutomatically(WebDavSyncTrigger trigger) async {
    try {
      await _signalWithGraph(trigger);
    } catch (_) {
      // Routine automatic sync is best effort. The settings status retains
      // errors recorded by the engine/discovery paths; launch, foreground,
      // background, and playback return never leak an async exception.
    }
  }

  Future<void> _maintainGraph({required bool force}) async {
    if (playbackActiveOnTelevision || tvOsLowMemory) return;
    try {
      await checkGraph(force: force);
    } on StateError {
      // A non-Admin/locked session or a profile switch pauses only the graph
      // tier. Hot sync and application startup continue normally.
    } on WebDavException {
      // Routine LAN/offline failures remain settings status, never banners.
    } catch (_) {
      // Corrupt/replaced roots are persisted by discovery for the settings
      // card; automatic triggers must not surface them during playback/home.
    }
  }

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

  Future<void> _refreshGraphBadge() async {
    try {
      final active = (await bindingStore.load()).activeBinding;
      if (active == null) {
        MainPageBridge.setWebDavGraphChangePending(false);
        return;
      }
      final state = await stateStore.load(active.namespaceId);
      MainPageBridge.setWebDavGraphChangePending(
        state.pendingGraphDigest != null,
      );
    } on WebDavSyncEngineStateMissingException {
      MainPageBridge.setWebDavGraphChangePending(false);
    }
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
    _graphTimer?.cancel();
    _graphTimer = null;
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
    );
  }

  WebDavSyncGraphTier _graphTier() {
    final components = _components();
    final discovery = WebDavSyncExistingRootDiscovery(
      bindingStore: bindingStore,
      stateRepository: stateStore,
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

final class _ProductionCycleRunner implements WebDavSyncCycleRunner {
  _ProductionCycleRunner({
    required this.bindingStore,
    required this.stateRepository,
    required this.localAdapter,
    required this.operations,
  });

  final WebDavSyncBindingStore bindingStore;
  final WebDavSyncEngineStateRepository stateRepository;
  final WebDavSyncLocalAdapter localAdapter;
  final WebDavSyncOperationCoordinator operations;
  final WebDavSyncAuthenticationFailureTracker _authenticationFailures =
      WebDavSyncAuthenticationFailureTracker();
  final WebDavSyncSectionCache _sectionCache = WebDavSyncSectionCache();

  void clearSectionCache() => _sectionCache.clear();

  Future<WebDavSyncRemotePollContext?> remotePollContext() async {
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
    return WebDavSyncRemotePollContext(
      transport: ProtocolWebDavSyncTransport(
        location: binding.location,
        credentials: WebDavCredentials(
          username: secrets.username,
          password: secrets.password,
        ),
      ),
      peerDeviceIds: List<String>.unmodifiable(peerDeviceIds),
      validators: state.peerManifestValidators,
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
      ),
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
