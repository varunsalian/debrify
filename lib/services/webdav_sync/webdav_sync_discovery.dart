import 'dart:math';
import 'dart:typed_data';

import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_large_section_io.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_setup_service.dart';
import 'webdav_sync_transport.dart';

typedef WebDavSyncDiscoveryDiagnostic =
    void Function(String message, Object? error);

typedef WebDavSyncDiscoveryTransportFactory =
    WebDavSyncTransport Function({
      required WebDavSyncBinding binding,
      required WebDavSyncSecrets secrets,
    });

final class WebDavSyncBootstrapUnavailableException implements Exception {
  const WebDavSyncBootstrapUnavailableException();

  @override
  String toString() =>
      'This WebDAV sync folder has no authentic, complete bootstrap';
}

final class WebDavSyncDiscoveredGraph {
  const WebDavSyncDiscoveredGraph({
    required this.manifest,
    required this.document,
  });

  final WebDavSyncManifest manifest;
  final OpenedWebDavSyncGraph document;
}

final class WebDavSyncExistingRootSnapshot {
  const WebDavSyncExistingRootSnapshot({
    required this.binding,
    required this.namespace,
    required this.root,
    required this.markerBytes,
    required this.serverNowMs,
    required this.manifests,
    required this.bootstrap,
    required this.latestGraph,
    required this.schemaRatchet,
  });

  final WebDavSyncBinding binding;
  final WebDavSyncNamespace namespace;
  final OpenedWebDavSyncRoot root;
  final Uint8List markerBytes;
  final int serverNowMs;
  final Map<String, WebDavSyncManifest> manifests;
  final WebDavSyncDiscoveredGraph bootstrap;
  final WebDavSyncDiscoveredGraph? latestGraph;
  final int schemaRatchet;

  bool get requiresGraphUpgrade =>
      schemaRatchet > WebDavSyncGraphBuilder.schemaVersion;
}

final class WebDavSyncActiveGraphSnapshot {
  const WebDavSyncActiveGraphSnapshot({
    required this.binding,
    required this.namespace,
    required this.root,
    required this.markerBytes,
    required this.serverNowMs,
    required this.manifests,
    required this.latestGraph,
    required this.schemaRatchet,
  });

  final WebDavSyncBinding binding;
  final WebDavSyncNamespace namespace;
  final OpenedWebDavSyncRoot root;
  final Uint8List markerBytes;
  final int serverNowMs;
  final Map<String, WebDavSyncManifest> manifests;
  final WebDavSyncDiscoveredGraph? latestGraph;
  final int schemaRatchet;

  bool get requiresGraphUpgrade =>
      schemaRatchet > WebDavSyncGraphBuilder.schemaVersion;
}

abstract interface class WebDavSyncExistingRootDiscoverer {
  Future<WebDavSyncExistingRootSnapshot> discover({required String bindingId});
}

abstract interface class WebDavSyncActiveGraphDiscoverer {
  Future<WebDavSyncActiveGraphSnapshot> scanActive({required String bindingId});
}

/// Authenticates the complete peer set for a pinned existing root and locates
/// the restore base. Bootstrap selection deliberately ignores heartbeat age;
/// graph selection retains the ordinary 30-day freshness rule.
final class WebDavSyncExistingRootDiscovery
    implements
        WebDavSyncExistingRootDiscoverer,
        WebDavSyncActiveGraphDiscoverer {
  WebDavSyncExistingRootDiscovery({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    WebDavSyncCodec? codec,
    WebDavSyncDiscoveryTransportFactory? transportFactory,
    DateTime Function()? clock,
    WebDavSyncDiscoveryDiagnostic? diagnostic,
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository,
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
       _clock = clock ?? DateTime.now,
       _diagnostic = diagnostic ?? _ignoreDiagnostic;

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncCodec _codec;
  final WebDavSyncDiscoveryTransportFactory _transportFactory;
  final DateTime Function() _clock;
  final WebDavSyncDiscoveryDiagnostic _diagnostic;

  /// Scans only the live graph tier for an already-Active binding. Unlike
  /// first connection this does not download a potentially large bootstrap
  /// and never changes the binding lifecycle.
  @override
  Future<WebDavSyncActiveGraphSnapshot> scanActive({
    required String bindingId,
  }) async {
    final stored = await _bindingStore.load();
    final binding = stored.bindings[bindingId];
    if (binding == null ||
        stored.activeBindingId != bindingId ||
        binding.lifecycle != WebDavSyncLifecycle.active ||
        binding.circleId == null) {
      throw StateError('WebDAV sync binding is not Active');
    }
    final namespace = stored.namespaceFor(binding);
    final markerPin = namespace?.markerBytes;
    if (namespace == null || markerPin == null || markerPin.isEmpty) {
      throw StateError('WebDAV sync marker pin is unavailable');
    }
    final secrets = await _bindingStore.readSecrets(binding);
    final transport = _transportFactory(binding: binding, secrets: secrets);
    try {
      final rootRead = await _readRequiredRoot(transport);
      if (!_bytesEqual(markerPin, rootRead.bytes)) {
        throw const WebDavSyncRootChangedException();
      }
      final root = await _codec.openRoot(
        rootRead.bytes,
        secrets.syncPassphrase,
        runInBackground: true,
      );
      if (root.document.circleId != binding.circleId) {
        throw const WebDavSyncRootChangedException();
      }
      final state = await _stateRepository.load(namespace.id);
      if (state.blocksAllPushes) {
        throw StateError(
          'An interrupted WebDAV sync adoption must be recovered first',
        );
      }
      final listing = await transport.listDeviceIds();
      if (listing.deviceIds.length > WebDavSyncLimits.maxPeers) {
        throw StateError('WebDAV sync peer count exceeds its limit');
      }
      final clockDecision = WebDavSyncClockPolicy.observe(
        prior: state.clock,
        localNowMs: _clock().toUtc().millisecondsSinceEpoch,
        serverDate: rootRead.metadata.serverDate ?? listing.metadata.serverDate,
      );
      await _persistClockDecision(namespace.id, clockDecision);
      if (!clockDecision.mayPublish || clockDecision.serverNowMs == null) {
        throw StateError('WebDAV server time is required to sync safely');
      }
      final manifests = await _readManifests(
        transport: transport,
        root: root,
        deviceIds: listing.deviceIds,
        highWater: state.peerManifestHighWater,
        serverNowMs: clockDecision.serverNowMs!,
      );
      final graphSelection = WebDavSyncGraphArbitration.selectGraph(
        manifests: manifests.values,
        serverNowMs: clockDecision.serverNowMs!,
        persistedSchemaRatchet: state.schemaRatchet,
      );
      final latestGraph =
          graphSelection.schemaRatchet == WebDavSyncGraphBuilder.schemaVersion
          ? await _firstComplete(
              transport: transport,
              root: root,
              kind: WebDavSyncGraphKind.graph,
              candidates: graphSelection.candidates,
            )
          : null;
      final highWater = Map<String, int>.from(state.peerManifestHighWater);
      for (final entry in manifests.entries) {
        highWater[entry.key] = max(
          highWater[entry.key] ?? 0,
          entry.value.updatedAtMs,
        );
      }
      await _stateRepository.update(
        namespace.id,
        (current) => current.copyWith(
          clock: clockDecision.state,
          deviceClockWarning: clockDecision.deviceClockWarning,
          lastClockPauseReason: clockDecision.pauseReason,
          clearClockPauseReason: clockDecision.pauseReason == null,
          peerManifestHighWater: boundedPeerManifestHighWater(
            highWater,
            currentDeviceIds: listing.deviceIds,
          ),
          schemaRatchet: max(
            current.schemaRatchet,
            graphSelection.schemaRatchet,
          ),
        ),
      );
      return WebDavSyncActiveGraphSnapshot(
        binding: binding,
        namespace: namespace,
        root: root,
        markerBytes: Uint8List.fromList(rootRead.bytes),
        serverNowMs: clockDecision.serverNowMs!,
        manifests: Map<String, WebDavSyncManifest>.unmodifiable(manifests),
        latestGraph: latestGraph,
        schemaRatchet: graphSelection.schemaRatchet,
      );
    } on WebDavSyncRootMissingException catch (error) {
      await _bindingStore.markError(binding.id, error);
      rethrow;
    } on WebDavSyncRootChangedException catch (error) {
      await _bindingStore.markError(binding.id, error);
      rethrow;
    } finally {
      transport.close();
    }
  }

  @override
  Future<WebDavSyncExistingRootSnapshot> discover({
    required String bindingId,
  }) async {
    final stored = await _bindingStore.load();
    final binding = stored.bindings[bindingId];
    if (binding == null ||
        (binding.lifecycle != WebDavSyncLifecycle.rootVerified &&
            binding.lifecycle != WebDavSyncLifecycle.awaitingAdoption) ||
        binding.circleId == null) {
      throw StateError('WebDAV sync binding is not ready for adoption');
    }
    final namespace = stored.namespaceFor(binding);
    final markerPin = namespace?.markerBytes;
    if (namespace == null || markerPin == null || markerPin.isEmpty) {
      throw StateError('WebDAV sync marker pin is unavailable');
    }
    final secrets = await _bindingStore.readSecrets(binding);
    final transport = _transportFactory(binding: binding, secrets: secrets);
    try {
      final rootRead = await _readRequiredRoot(transport);
      if (!_bytesEqual(markerPin, rootRead.bytes)) {
        throw const WebDavSyncRootChangedException();
      }
      final root = await _codec.openRoot(
        rootRead.bytes,
        secrets.syncPassphrase,
        runInBackground: true,
      );
      if (root.document.circleId != binding.circleId) {
        throw const WebDavSyncRootChangedException();
      }

      final state = await _stateRepository.load(namespace.id);
      if (state.blocksAllPushes) {
        throw StateError(
          'An interrupted WebDAV sync adoption must be recovered first',
        );
      }
      final listing = await transport.listDeviceIds();
      if (listing.deviceIds.length > WebDavSyncLimits.maxPeers) {
        throw StateError('WebDAV sync peer count exceeds its limit');
      }
      final clockDecision = WebDavSyncClockPolicy.observe(
        prior: state.clock,
        localNowMs: _clock().toUtc().millisecondsSinceEpoch,
        serverDate: rootRead.metadata.serverDate ?? listing.metadata.serverDate,
      );
      await _persistClockDecision(namespace.id, clockDecision);
      if (!clockDecision.mayPublish || clockDecision.serverNowMs == null) {
        throw StateError(
          'WebDAV server time is required to connect sync safely',
        );
      }
      final manifests = await _readManifests(
        transport: transport,
        root: root,
        deviceIds: listing.deviceIds,
        highWater: state.peerManifestHighWater,
        serverNowMs: clockDecision.serverNowMs!,
      );

      final bootstrap = await _firstComplete(
        transport: transport,
        root: root,
        kind: WebDavSyncGraphKind.bootstrap,
        candidates: WebDavSyncGraphArbitration.bootstrapCandidates(
          manifests.values,
        ),
      );
      if (bootstrap == null) {
        throw const WebDavSyncBootstrapUnavailableException();
      }

      final graphSelection = WebDavSyncGraphArbitration.selectGraph(
        manifests: manifests.values,
        serverNowMs: clockDecision.serverNowMs!,
        persistedSchemaRatchet: state.schemaRatchet,
      );
      final latestGraph =
          graphSelection.schemaRatchet == WebDavSyncGraphBuilder.schemaVersion
          ? await _firstComplete(
              transport: transport,
              root: root,
              kind: WebDavSyncGraphKind.graph,
              candidates: graphSelection.candidates,
            )
          : null;

      final highWater = Map<String, int>.from(state.peerManifestHighWater);
      for (final entry in manifests.entries) {
        highWater[entry.key] = max(
          highWater[entry.key] ?? 0,
          entry.value.updatedAtMs,
        );
      }
      await _stateRepository.update(
        namespace.id,
        (current) => current.copyWith(
          clock: clockDecision.state,
          deviceClockWarning: clockDecision.deviceClockWarning,
          lastClockPauseReason: clockDecision.pauseReason,
          clearClockPauseReason: clockDecision.pauseReason == null,
          peerManifestHighWater: boundedPeerManifestHighWater(
            highWater,
            currentDeviceIds: listing.deviceIds,
          ),
          schemaRatchet: max(
            current.schemaRatchet,
            graphSelection.schemaRatchet,
          ),
        ),
      );
      final awaiting = binding.lifecycle == WebDavSyncLifecycle.awaitingAdoption
          ? binding
          : await _bindingStore.setLifecycle(
              binding.id,
              WebDavSyncLifecycle.awaitingAdoption,
            );
      return WebDavSyncExistingRootSnapshot(
        binding: awaiting,
        namespace: namespace,
        root: root,
        markerBytes: Uint8List.fromList(rootRead.bytes),
        serverNowMs: clockDecision.serverNowMs!,
        manifests: Map<String, WebDavSyncManifest>.unmodifiable(manifests),
        bootstrap: bootstrap,
        latestGraph: latestGraph,
        schemaRatchet: graphSelection.schemaRatchet,
      );
    } on WebDavSyncRootMissingException catch (error) {
      await _bindingStore.markError(binding.id, error);
      rethrow;
    } on WebDavException catch (error) {
      await _bindingStore.markError(binding.id, error);
      rethrow;
    } on WebDavSyncRootChangedException catch (error) {
      await _bindingStore.markError(binding.id, error);
      rethrow;
    } finally {
      transport.close();
    }
  }

  static Future<WebDavBytesResult> _readRequiredRoot(
    WebDavSyncTransport transport,
  ) async {
    try {
      return await transport.readRootMarker();
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.notFound) {
        throw const WebDavSyncRootMissingException();
      }
      rethrow;
    }
  }

  Future<Map<String, WebDavSyncManifest>> _readManifests({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required List<String> deviceIds,
    required Map<String, int> highWater,
    required int serverNowMs,
  }) async {
    final result = <String, WebDavSyncManifest>{};
    for (final deviceId in deviceIds.toSet().toList()..sort()) {
      try {
        final read = await transport.readManifest(deviceId);
        final clear = await _codec.openDocument(
          key: root.key,
          encoded: read.bytes,
          circleId: root.document.circleId,
          deviceId: deviceId,
          logicalName: 'manifest',
          schemaVersion: WebDavSyncManifest.schemaVersion,
          maxBytes: WebDavSyncLimits.maxManifestBytes,
        );
        final manifest = WebDavSyncManifest.fromJson(clear);
        if (manifest.circleId != root.document.circleId ||
            manifest.deviceId != deviceId) {
          throw const FormatException('WebDAV sync manifest identity mismatch');
        }
        if (!WebDavSyncClockPolicy.acceptsRemoteTimestamp(
          timestampMs: manifest.updatedAtMs,
          serverNowMs: serverNowMs,
        )) {
          _diagnostic('Ignored a future-dated WebDAV sync manifest', null);
          continue;
        }
        if (manifest.updatedAtMs < (highWater[deviceId] ?? 0)) {
          _diagnostic('Ignored a regressed WebDAV sync manifest', null);
          continue;
        }
        result[deviceId] = manifest;
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a removed WebDAV sync peer', error);
      } on FormatException catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync peer manifest', error);
      }
    }
    return result;
  }

  Future<WebDavSyncDiscoveredGraph?> _firstComplete({
    required WebDavSyncTransport transport,
    required OpenedWebDavSyncRoot root,
    required WebDavSyncGraphKind kind,
    required Iterable<WebDavSyncGraphCandidate> candidates,
  }) async {
    for (final candidate in candidates) {
      try {
        if (candidate.reference.size > WebDavSyncLimits.maxGraphDocumentBytes) {
          throw const FormatException('WebDAV sync graph exceeds its limit');
        }
        final encoded = await WebDavSyncLargeSectionIo(codec: _codec)
            .readVerified(
              transport: transport,
              deviceId: candidate.manifest.deviceId,
              reference: candidate.reference,
              maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
            );
        final opened = await WebDavSyncGraphReader.open(
          codec: _codec,
          key: root.key,
          circleId: root.document.circleId,
          deviceId: candidate.manifest.deviceId,
          kind: kind,
          reference: candidate.reference,
          encoded: encoded,
          profileMap: candidate.manifest.profileMap,
          resourceMap: candidate.manifest.resourceMap,
        );
        return WebDavSyncDiscoveredGraph(
          manifest: candidate.manifest,
          document: opened,
        );
      } on WebDavException catch (error) {
        if (error.kind != WebDavErrorKind.notFound) rethrow;
        _diagnostic('Ignored a missing WebDAV sync ${kind.name}', error);
      } on FormatException catch (error) {
        _diagnostic('Ignored an invalid WebDAV sync ${kind.name}', error);
      }
    }
    return null;
  }

  Future<void> _persistClockDecision(
    String namespaceId,
    WebDavSyncClockDecision decision,
  ) => _stateRepository.update(
    namespaceId,
    (current) => current.copyWith(
      clock: decision.state,
      deviceClockWarning: decision.deviceClockWarning,
      lastClockPauseReason: decision.pauseReason,
      clearClockPauseReason: decision.pauseReason == null,
    ),
  );

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

  static void _ignoreDiagnostic(String message, Object? error) {}
}
