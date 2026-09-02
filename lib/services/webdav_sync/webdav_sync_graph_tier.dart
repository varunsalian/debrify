import 'dart:math';

import '../../models/profiles/profile_policy.dart';
import '../profiles/profile_authorization.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_adoption_models.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_discovery.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_existing_root_connector.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_large_section_io.dart';
import 'webdav_sync_manifest_publisher.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_transport.dart';

enum WebDavSyncGraphTierDisposition {
  unchanged,
  localPublished,
  remoteChange,
  remoteDeclined,
  adminRequired,
  updateRequired,
  skipped,
}

final class WebDavSyncGraphChange {
  const WebDavSyncGraphChange({
    required this.semanticDigest,
    required this.deviceId,
    required this.updatedAtMs,
  });

  final String semanticDigest;
  final String deviceId;
  final int updatedAtMs;
}

final class WebDavSyncGraphTierReport {
  const WebDavSyncGraphTierReport({required this.disposition, this.change});

  final WebDavSyncGraphTierDisposition disposition;
  final WebDavSyncGraphChange? change;
}

final class WebDavSyncDeviceSummary {
  const WebDavSyncDeviceSummary({
    required this.deviceId,
    required this.lastSeenMs,
    required this.isThisDevice,
  });

  final String deviceId;
  final int lastSeenMs;
  final bool isThisDevice;
}

typedef WebDavSyncGraphTransportFactory =
    WebDavSyncActivationTransport Function({
      required WebDavSyncBinding binding,
      required WebDavSyncSecrets secrets,
    });

/// Admin-only structure tier: discovers and prompts remote graph revisions,
/// publishes complete local revisions, and performs guarded device cleanup.
final class WebDavSyncGraphTier {
  WebDavSyncGraphTier({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncActiveGraphDiscoverer discovery,
    required WebDavSyncGraphBuilder graphBuilder,
    required WebDavSyncAdoptionRunner adoption,
    required WebDavSyncSeedPublisher publisher,
    required WebDavSyncCycleRunner cycleRunner,
    required Future<WebDavSyncCycleContext?> Function() contextProvider,
    WebDavSyncCodec? codec,
    WebDavSyncGraphTransportFactory? transportFactory,
    DateTime Function()? clock,
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository,
       _discovery = discovery,
       _graphBuilder = graphBuilder,
       _adoption = adoption,
       _publisher = publisher,
       _cycleRunner = cycleRunner,
       _contextProvider = contextProvider,
       _codec = codec ?? WebDavSyncCodec(),
       _transportFactory =
           transportFactory ??
           (({required binding, required secrets}) =>
               ProtocolWebDavSyncTransport(
                 location: binding.location,
                 credentials: WebDavCredentials(
                   username: secrets.username,
                   password: secrets.password,
                 ),
               )),
       _clock = clock ?? DateTime.now;

  static const Duration cadence = Duration(hours: 6);
  static const Duration bootstrapCadence = Duration(days: 1);

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncActiveGraphDiscoverer _discovery;
  final WebDavSyncGraphBuilder _graphBuilder;
  final WebDavSyncAdoptionRunner _adoption;
  final WebDavSyncSeedPublisher _publisher;
  final WebDavSyncCycleRunner _cycleRunner;
  final Future<WebDavSyncCycleContext?> Function() _contextProvider;
  final WebDavSyncCodec _codec;
  final WebDavSyncGraphTransportFactory _transportFactory;
  final DateTime Function() _clock;

  Future<WebDavSyncGraphTierReport> maintain({
    required ProfileAuthorizationContext authorization,
    bool force = false,
    bool runBootstrapMaintenance = true,
  }) async {
    if (!await _isManagingAdmin(authorization)) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.adminRequired,
      );
    }
    final active = await _activeBinding();
    var state = await _stateRepository.load(active.namespaceId);
    // Discovery persists the highest graph schema ever observed. Surface an
    // upgrade requirement on every settings read, including inside the
    // six-hour network cadence; otherwise the warning disappears after the
    // first scan even though this build still cannot interpret the graph.
    if (state.schemaRatchet > WebDavSyncGraphBuilder.schemaVersion) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.updateRequired,
      );
    }
    if (state.prunePendingProfileIds.isNotEmpty) {
      await _adoption.retryPendingPrunes(active.namespaceId);
      state = await _stateRepository.load(active.namespaceId);
      if (state.blocksGraphPushes) {
        return const WebDavSyncGraphTierReport(
          disposition: WebDavSyncGraphTierDisposition.skipped,
        );
      }
    }
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    final lastCheck = state.lastGraphCheckMs;
    final lastBootstrapCheck = state.lastBootstrapCheckMs;
    final graphDue =
        force ||
        lastCheck == null ||
        nowMs < lastCheck ||
        nowMs - lastCheck >= cadence.inMilliseconds;
    final bootstrapDue =
        runBootstrapMaintenance &&
        (force ||
            lastBootstrapCheck == null ||
            nowMs < lastBootstrapCheck ||
            nowMs - lastBootstrapCheck >= bootstrapCadence.inMilliseconds);
    if (!graphDue && !bootstrapDue) {
      final pending = state.pendingGraphDigest;
      return WebDavSyncGraphTierReport(
        disposition: pending == null
            ? WebDavSyncGraphTierDisposition.skipped
            : WebDavSyncGraphTierDisposition.remoteChange,
        change: pending == null
            ? null
            : WebDavSyncGraphChange(
                semanticDigest: pending,
                deviceId: 'peer',
                updatedAtMs: lastCheck,
              ),
      );
    }

    final scan = await _discovery.scanActive(bindingId: active.id);
    state = await _stateRepository.update(
      active.namespaceId,
      (current) => current.copyWith(lastGraphCheckMs: nowMs),
    );
    if (scan.requiresGraphUpgrade) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.updateRequired,
      );
    }

    // An unresolved adoption remains an explicit graph blocker. Pending
    // predecessor prunes were retried above before any network publication.
    if (state.blocksGraphPushes) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.skipped,
      );
    }
    final maps = _requireMaps(state);
    final registry = _graphBuilder.packageService.registry;
    final profiles = await registry.listProfiles(includeDisabled: true);
    final resources = await registry.listAllResourcesIncludingDisabled();
    final identitiesChanged =
        !_sameSet(
          profiles.map((profile) => profile.id),
          maps.localToCircleProfiles.keys,
        ) ||
        !_sameSet(
          resources.map((resource) => resource.id),
          maps.localToCircleResources.keys,
        );
    WebDavSyncPreparedGraph? local;
    final candidate = scan.latestGraph;
    if (candidate != null &&
        candidate.document.semanticDigest != state.appliedGraphDigest) {
      final change = _change(candidate);
      if (!state.declinedGraphDigests.contains(change.semanticDigest)) {
        var equivalentStructure = false;
        if (!identitiesChanged) {
          local = await _graphBuilder.build(
            kind: WebDavSyncGraphKind.graph,
            authorization: authorization,
            identityMaps: maps,
          );
          equivalentStructure =
              WebDavSyncGraphBuilder.structureDigest(
                candidate.document.package,
                profileMap: candidate.manifest.profileMap,
                resourceMap: candidate.manifest.resourceMap,
              ) ==
              WebDavSyncGraphBuilder.structureDigest(
                local.package,
                profileMap: local.profileMap,
                resourceMap: local.resourceMap,
              );
        }
        if (!equivalentStructure) {
          await _stateRepository.update(
            active.namespaceId,
            (current) =>
                current.copyWith(pendingGraphDigest: change.semanticDigest),
          );
          return WebDavSyncGraphTierReport(
            disposition: WebDavSyncGraphTierDisposition.remoteChange,
            change: change,
          );
        }
        // A legacy writer can give the same graph a different exact payload
        // digest through local row ordering or portable engine files. Clear a
        // stale prompt; the canonical local graph is published below.
        state = await _stateRepository.update(
          active.namespaceId,
          (current) => current.copyWith(clearPendingGraph: true),
        );
      }
    }

    if (!scan.manifests.containsKey(scan.namespace.deviceId)) {
      // The hot engine distinguishes a missing manifest from a missing whole
      // device directory. Discovery cannot safely prove that the persisted
      // section references still exist, so rebuild the complete authenticated
      // seed before advertising this device again.
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }

    if (identitiesChanged) {
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }
    final ownManifest = state.ownManifest;
    final ownGraph = ownManifest?.section(
      WebDavSyncGraphKind.graph.logicalName,
    );
    final ownIdentityMapsMatch =
        ownManifest != null &&
        _sameSet(
          ownManifest.profileMap.values,
          maps.circleToLocalProfiles.keys,
        ) &&
        _sameSet(
          ownManifest.resourceMap.values,
          maps.circleToLocalResources.keys,
        );
    if (ownGraph?.semanticDigest != state.appliedGraphDigest ||
        !ownIdentityMapsMatch) {
      // Adoption commits the local maps before this device republishes them.
      // If publication was interrupted, resume that non-destructive tail
      // instead of considering the locally-applied graph fully advertised.
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }
    local ??= await _graphBuilder.build(
      kind: WebDavSyncGraphKind.graph,
      authorization: authorization,
      identityMaps: maps,
    );
    if (local.semanticDigest != state.appliedGraphDigest) {
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }
    if (bootstrapDue) {
      final bootstrap = await _graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: maps,
      );
      final publishedBootstrap = state.ownManifest?.section(
        WebDavSyncGraphKind.bootstrap.logicalName,
      );
      final databaseDigest =
          bootstrap.bootstrapDatabaseDigest ??
          (throw StateError('WebDAV sync bootstrap digest is missing'));
      if (publishedBootstrap == null ||
          state.publishedBootstrapDatabaseDigest != databaseDigest) {
        await _publisher.publish(
          bindingId: active.id,
          authorization: authorization,
        );
        return const WebDavSyncGraphTierReport(
          disposition: WebDavSyncGraphTierDisposition.localPublished,
        );
      }
      await _stateRepository.update(
        active.namespaceId,
        (current) => current.copyWith(
          lastBootstrapCheckMs: nowMs,
          publishedBootstrapDatabaseDigest: databaseDigest,
        ),
      );
    }
    await _stateRepository.update(
      active.namespaceId,
      (current) => current.copyWith(clearPendingGraph: true),
    );
    return WebDavSyncGraphTierReport(
      disposition:
          candidate != null &&
              state.declinedGraphDigests.contains(
                candidate.document.semanticDigest,
              )
          ? WebDavSyncGraphTierDisposition.remoteDeclined
          : WebDavSyncGraphTierDisposition.unchanged,
    );
  }

  Future<void> applyRemote({
    required String expectedDigest,
    required ProfileAuthorizationContext authorization,
    required WebDavSyncAuthorizationRecapture recaptureAuthorization,
  }) async {
    if (!await _isManagingAdmin(authorization)) {
      throw StateError('WebDAV sync graph refresh requires an Admin');
    }
    final active = await _activeBinding();
    var state = await _stateRepository.load(active.namespaceId);
    if (state.prunePendingProfileIds.isNotEmpty) {
      await _adoption.retryPendingPrunes(active.namespaceId);
      state = await _stateRepository.load(active.namespaceId);
    }
    if (state.blocksGraphPushes) {
      throw StateError(
        'Finish the pending profile cleanup before applying sync changes',
      );
    }
    final scan = await _discovery.scanActive(bindingId: active.id);
    if (scan.requiresGraphUpgrade) {
      throw StateError(
        'Update Debrify before syncing profiles and connections',
      );
    }
    final graph = scan.latestGraph;
    if (graph == null || graph.document.semanticDigest != expectedDigest) {
      throw StateError('The pending WebDAV sync update changed; check again');
    }
    if (state.appliedGraphDigest != expectedDigest) {
      final secrets = await _bindingStore.readSecrets(active);
      await _adoption.adopt(
        WebDavSyncAdoptionRequest(
          namespaceId: active.namespaceId,
          mode: WebDavSyncAdoptionMode.refresh,
          package: graph.document.package,
          graphSemanticDigest: graph.document.semanticDigest,
          profileMap: graph.manifest.profileMap,
          resourceMap: graph.manifest.resourceMap,
          passphrase: secrets.syncPassphrase,
          authorization: authorization,
          replacementConfirmed: true,
        ),
      );
    }
    final refreshedAuthorization = await recaptureAuthorization();
    final published = await _publisher.publish(
      bindingId: active.id,
      authorization: refreshedAuthorization,
    );
    final refreshedState = await _stateRepository.load(active.namespaceId);
    final report = await _cycleRunner.runCycle(
      WebDavSyncCycleContext(
        namespaceId: scan.namespace.id,
        deviceId: scan.namespace.deviceId,
        markerPin: scan.markerBytes,
        root: scan.root,
        circleToLocalProfiles: refreshedState.circleToLocalProfiles,
        circleToLocalResources: refreshedState.circleToLocalResources,
        wireProfileMap: published.manifest.profileMap,
        wireResourceMap: published.manifest.resourceMap,
        active: true,
      ),
    );
    if (report.disposition != WebDavSyncCycleDisposition.completed) {
      throw StateError('WebDAV sync graph refresh could not finish its merge');
    }
    await _stateRepository.update(
      active.namespaceId,
      (current) => current.copyWith(clearPendingGraph: true),
    );
  }

  Future<void> decline(String semanticDigest) async {
    _requireDigest(semanticDigest);
    final active = await _activeBinding();
    await _stateRepository.update(active.namespaceId, (current) {
      return current.copyWith(
        declinedGraphDigests: boundedDeclinedGraphDigests(
          current.declinedGraphDigests,
          semanticDigest,
        ),
        clearPendingGraph: current.pendingGraphDigest == semanticDigest,
      );
    });
  }

  Future<List<WebDavSyncDeviceSummary>> listDevices() async {
    final active = await _activeBinding();
    final scan = await _discovery.scanActive(bindingId: active.id);
    return List<WebDavSyncDeviceSummary>.unmodifiable(
      scan.manifests.values
          .map(
            (manifest) => WebDavSyncDeviceSummary(
              deviceId: manifest.deviceId,
              lastSeenMs: manifest.updatedAtMs,
              isThisDevice: manifest.deviceId == scan.namespace.deviceId,
            ),
          )
          .toList()
        ..sort((left, right) {
          if (left.isThisDevice != right.isThisDevice) {
            return left.isThisDevice ? -1 : 1;
          }
          return right.lastSeenMs.compareTo(left.lastSeenMs);
        }),
    );
  }

  Future<void> forgetDevice({
    required String deviceId,
    required ProfileAuthorizationContext authorization,
  }) async {
    if (!await _isManagingAdmin(authorization)) {
      throw StateError('Forgetting a sync device requires an Admin');
    }
    final context = await _contextProvider();
    if (context == null || !context.active) {
      throw StateError('WebDAV sync is not Active');
    }
    if (deviceId == context.deviceId) {
      throw StateError('This device cannot forget its own active record');
    }
    // Pull and republish the complete tombstone union before any cross-device
    // deletion. The engine verifies its own section and manifest read-backs.
    final merge = await _cycleRunner.runCycle(context);
    if (merge.disposition != WebDavSyncCycleDisposition.completed) {
      throw StateError('Could not preserve sync deletions before forgetting');
    }

    final active = await _activeBinding();
    var scan = await _discovery.scanActive(bindingId: active.id);
    var target = scan.manifests[deviceId];
    var own = scan.manifests[scan.namespace.deviceId];
    if (target == null) {
      throw StateError('The selected sync device no longer exists');
    }
    final currentState = await _stateRepository.load(active.namespaceId);
    final latestGraph = scan.latestGraph;
    if (latestGraph?.manifest.deviceId == deviceId &&
        latestGraph!.document.semanticDigest !=
            currentState.appliedGraphDigest &&
        !currentState.declinedGraphDigests.contains(
          latestGraph.document.semanticDigest,
        )) {
      throw StateError(
        'Apply or decline this device\'s pending profile update before '
        'forgetting it',
      );
    }
    var bootstrap = own?.section(WebDavSyncGraphKind.bootstrap.logicalName);
    var graph = own?.section(WebDavSyncGraphKind.graph.logicalName);
    if (bootstrap == null || graph == null) {
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      scan = await _discovery.scanActive(bindingId: active.id);
      target = scan.manifests[deviceId];
      own = scan.manifests[scan.namespace.deviceId];
      if (target == null) {
        throw StateError('The selected sync device no longer exists');
      }
      bootstrap = own?.section(WebDavSyncGraphKind.bootstrap.logicalName);
      graph = own?.section(WebDavSyncGraphKind.graph.logicalName);
      if (own == null || bootstrap == null || graph == null) {
        throw StateError('Bootstrap continuity could not be published');
      }
    }
    final secrets = await _bindingStore.readSecrets(active);
    final transport = _transportFactory(binding: active, secrets: secrets);
    try {
      await _verifyGraph(
        transport: transport,
        scan: scan,
        manifest: own!,
        kind: WebDavSyncGraphKind.bootstrap,
        reference: bootstrap,
      );
      await _verifyGraph(
        transport: transport,
        scan: scan,
        manifest: own,
        kind: WebDavSyncGraphKind.graph,
        reference: graph,
      );
      final marker = await transport.readRootMarker();
      if (!_bytesEqual(scan.markerBytes, marker.bytes)) {
        throw const WebDavSyncRootChangedException();
      }
      final currentTargetBytes = await transport.readManifest(deviceId);
      final currentTarget = WebDavSyncManifest.fromJson(
        await _codec.openDocument(
          key: scan.root.key,
          encoded: currentTargetBytes.bytes,
          circleId: scan.root.document.circleId,
          deviceId: deviceId,
          logicalName: 'manifest',
          schemaVersion: WebDavSyncManifest.schemaVersion,
          maxBytes: WebDavSyncLimits.maxManifestBytes,
        ),
      );
      if (WebDavSyncCodec.canonicalJson(currentTarget.toJson()) !=
          WebDavSyncCodec.canonicalJson(target.toJson())) {
        throw StateError('The selected sync device changed; try again');
      }
      if (!await _isManagingAdmin(authorization)) {
        throw StateError('Forgetting a sync device requires an Admin');
      }
      await transport.deleteDeviceDirectory(deviceId);
      await _stateRepository.update(scan.namespace.id, (current) {
        final currentDeviceIds = Set<String>.from(current.currentDeviceIds)
          ..remove(deviceId);
        return current.copyWith(
          currentDeviceIds: Set<String>.unmodifiable(currentDeviceIds),
        );
      });
    } finally {
      transport.close();
    }
  }

  Future<void> _verifyGraph({
    required WebDavSyncTransport transport,
    required WebDavSyncActiveGraphSnapshot scan,
    required WebDavSyncManifest manifest,
    required WebDavSyncGraphKind kind,
    required WebDavSyncSectionReference reference,
  }) async {
    final encoded = await WebDavSyncLargeSectionIo(codec: _codec).readVerified(
      transport: transport,
      deviceId: manifest.deviceId,
      reference: reference,
      maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
    );
    await WebDavSyncGraphReader.open(
      codec: _codec,
      key: scan.root.key,
      circleId: scan.root.document.circleId,
      deviceId: manifest.deviceId,
      kind: kind,
      reference: reference,
      encoded: encoded,
      profileMap: manifest.profileMap,
      resourceMap: manifest.resourceMap,
    );
  }

  Future<WebDavSyncBinding> _activeBinding() async {
    final active = (await _bindingStore.load()).activeBinding;
    if (active == null || active.lifecycle != WebDavSyncLifecycle.active) {
      throw StateError('WebDAV sync is not Active');
    }
    return active;
  }

  Future<bool> _isManagingAdmin(
    ProfileAuthorizationContext authorization,
  ) async {
    final profile = await authorization.validate(
      _graphBuilder.packageService.registry,
    );
    return profile.isAdmin &&
        profile.allows(ProfileFeature.manageProfiles) &&
        profile.allows(ProfileFeature.backupRestore);
  }

  static WebDavSyncIdentityMaps _requireMaps(WebDavSyncEngineState state) {
    if (!state.hasAuthenticatedMaps) {
      throw StateError('WebDAV sync identity maps are unavailable');
    }
    return WebDavSyncIdentityMaps(
      circleToLocalProfiles: state.circleToLocalProfiles!,
      circleToLocalResources: state.circleToLocalResources!,
    );
  }

  static WebDavSyncGraphChange _change(WebDavSyncDiscoveredGraph candidate) {
    final reference = candidate.manifest.section(
      WebDavSyncGraphKind.graph.logicalName,
    )!;
    return WebDavSyncGraphChange(
      semanticDigest: candidate.document.semanticDigest,
      deviceId: candidate.manifest.deviceId,
      updatedAtMs: reference.updatedAtMs,
    );
  }

  static bool _sameSet(Iterable<String> left, Iterable<String> right) {
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
  }

  static void _requireDigest(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'semanticDigest');
    }
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |=
          (index < left.length ? left[index] : 0) ^
          (index < right.length ? right[index] : 0);
    }
    return difference == 0;
  }
}
