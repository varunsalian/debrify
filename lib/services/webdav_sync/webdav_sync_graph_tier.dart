import 'dart:math';

import '../../models/profiles/profile_policy.dart';
import '../profiles/profile_authorization.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_adoption.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_discovery.dart';
import 'webdav_sync_engine.dart';
import 'webdav_sync_engine_state.dart';
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
  adminRequired,
  updateRequired,
  skipped,
}

final class WebDavSyncGraphTierReport {
  const WebDavSyncGraphTierReport({required this.disposition});

  final WebDavSyncGraphTierDisposition disposition;
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

/// Admin-only maintenance tier for identity reconciliation, complete seed
/// repair, daily bootstrap regeneration, and guarded device cleanup.
final class WebDavSyncGraphTier {
  WebDavSyncGraphTier({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncActiveRootDiscoverer discovery,
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
  final WebDavSyncActiveRootDiscoverer _discovery;
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
    // The legacy field now ratchets bootstrap schema versions only.
    if (state.schemaRatchet > WebDavSyncGraphBuilder.schemaVersion) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.updateRequired,
      );
    }
    if (state.prunePendingProfileIds.isNotEmpty) {
      await _adoption.retryPendingPrunes(active.namespaceId);
      state = await _stateRepository.load(active.namespaceId);
      if (state.blocksSeedPushes) {
        return const WebDavSyncGraphTierReport(
          disposition: WebDavSyncGraphTierDisposition.skipped,
        );
      }
    }
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    final lastBootstrapCheck = state.lastBootstrapCheckMs;
    final bootstrapDue =
        runBootstrapMaintenance &&
        (force ||
            lastBootstrapCheck == null ||
            nowMs < lastBootstrapCheck ||
            nowMs - lastBootstrapCheck >= bootstrapCadence.inMilliseconds);

    // An unresolved adoption or predecessor prune remains a seed blocker.
    if (state.blocksSeedPushes) {
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
    if (identitiesChanged) {
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }

    final scan = await _discovery.scanActive(bindingId: active.id);
    if (scan.requiresBootstrapUpgrade) {
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.updateRequired,
      );
    }
    final ownManifest = scan.manifests[scan.namespace.deviceId];
    if (!_isCompleteOwnManifest(ownManifest, maps)) {
      await _publisher.publish(
        bindingId: active.id,
        authorization: authorization,
      );
      return const WebDavSyncGraphTierReport(
        disposition: WebDavSyncGraphTierDisposition.localPublished,
      );
    }
    if (state.ownManifest == null ||
        ownManifest!.updatedAtMs > state.ownManifest!.updatedAtMs) {
      state = await _stateRepository.update(
        active.namespaceId,
        (current) => current.copyWith(ownManifest: ownManifest),
      );
    }
    if (bootstrapDue) {
      final bootstrap = await _graphBuilder.build(
        kind: WebDavSyncGraphKind.bootstrap,
        authorization: authorization,
        identityMaps: maps,
      );
      final publishedBootstrap = ownManifest!.section(
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
    return const WebDavSyncGraphTierReport(
      disposition: WebDavSyncGraphTierDisposition.unchanged,
    );
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
    var bootstrap = own?.section(WebDavSyncGraphKind.bootstrap.logicalName);
    if (bootstrap == null) {
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
      if (own == null || bootstrap == null) {
        throw StateError('Bootstrap continuity could not be published');
      }
    }
    final secrets = await _bindingStore.readSecrets(active);
    final transport = _transportFactory(binding: active, secrets: secrets);
    try {
      await _verifyBootstrap(
        transport: transport,
        scan: scan,
        manifest: own!,
        reference: bootstrap,
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

  Future<void> _verifyBootstrap({
    required WebDavSyncTransport transport,
    required WebDavSyncActiveRootSnapshot scan,
    required WebDavSyncManifest manifest,
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
      kind: WebDavSyncGraphKind.bootstrap,
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

  static bool _sameSet(Iterable<String> left, Iterable<String> right) {
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
  }

  static bool _isCompleteOwnManifest(
    WebDavSyncManifest? manifest,
    WebDavSyncIdentityMaps maps,
  ) {
    if (manifest == null ||
        manifest.section(WebDavSyncGraphKind.bootstrap.logicalName) == null ||
        manifest.section('profiles') == null ||
        manifest.section('resources') == null ||
        manifest.section(WebDavSyncGraphKind.graph.logicalName) != null ||
        !_sameSet(
          manifest.profileMap.values,
          maps.circleToLocalProfiles.keys,
        ) ||
        !_sameSet(
          manifest.resourceMap.values,
          maps.circleToLocalResources.keys,
        )) {
      return false;
    }
    return maps.circleToLocalProfiles.keys.every(
      (circleId) =>
          manifest.section('hot/$circleId') != null &&
          manifest.section('tombstones/$circleId') != null,
    );
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
