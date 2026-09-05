import 'dart:math';

import '../profiles/profile_authorization.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_activation.dart';
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

typedef WebDavSyncManifestPublisherTransportFactory =
    WebDavSyncTransport Function({
      required WebDavSyncBinding binding,
      required WebDavSyncSecrets secrets,
    });

final class WebDavSyncPublishedSeed {
  const WebDavSyncPublishedSeed({
    required this.material,
    required this.manifest,
    required this.serverNowMs,
  });

  final WebDavSyncSeedMaterial material;
  final WebDavSyncManifest manifest;
  final int serverNowMs;
}

abstract interface class WebDavSyncSeedPublisher {
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  });
}

/// Publishes this device's complete bootstrap/circle/hot seed after an
/// existing-root adoption. The marker is checked both before and after the
/// manifest commit, and every immutable section plus the manifest is read
/// back and authenticated before local state can point at it.
final class WebDavSyncOwnManifestPublisher implements WebDavSyncSeedPublisher {
  WebDavSyncOwnManifestPublisher({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncSeedSource seedSource,
    WebDavSyncCodec? codec,
    WebDavSyncManifestPublisherTransportFactory? transportFactory,
    DateTime Function()? clock,
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository,
       _seedSource = seedSource,
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

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncSeedSource _seedSource;
  final WebDavSyncCodec _codec;
  final WebDavSyncManifestPublisherTransportFactory _transportFactory;
  final DateTime Function() _clock;

  @override
  Future<WebDavSyncPublishedSeed> publish({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  }) async {
    final stored = await _bindingStore.load();
    final binding = stored.bindings[bindingId];
    final namespace = binding == null ? null : stored.namespaceFor(binding);
    final markerPin = namespace?.markerBytes;
    if (binding == null ||
        namespace == null ||
        binding.circleId == null ||
        markerPin == null ||
        markerPin.isEmpty ||
        (binding.lifecycle != WebDavSyncLifecycle.awaitingAdoption &&
            binding.lifecycle != WebDavSyncLifecycle.rootVerified &&
            binding.lifecycle != WebDavSyncLifecycle.active)) {
      throw StateError('WebDAV sync binding is not ready to publish');
    }
    final secrets = await _bindingStore.readSecrets(binding);
    final root = await _codec.openPinnedAuthority(
      markerPin,
      secrets.syncPassphrase,
      runInBackground: true,
    );
    if (root.document.circleId != binding.circleId) {
      throw const WebDavSyncRootChangedException();
    }
    final transport = _transportFactory(binding: binding, secrets: secrets);
    try {
      final rootRead = await transport.readRootMarker();
      _requireMarker(namespace.pinnedAuthorityHash!, rootRead.bytes);
      final listing = await transport.listDeviceIds();
      if (listing.deviceIds.length > WebDavSyncLimits.maxPeers) {
        throw StateError('WebDAV sync peer limit exceeded');
      }
      final state = await _stateRepository.load(namespace.id);
      if (state.blocksAllPushes || !state.hasAuthenticatedMaps) {
        throw StateError('WebDAV sync adoption is not complete');
      }
      final localNowMs = _clock().toUtc().millisecondsSinceEpoch;
      final clockDecision = WebDavSyncClockPolicy.observe(
        prior: state.clock,
        localNowMs: localNowMs,
        serverDate: rootRead.metadata.serverDate ?? listing.metadata.serverDate,
      );
      await _stateRepository.update(
        namespace.id,
        (current) => current.copyWith(
          clock: clockDecision.state,
          deviceClockWarning: clockDecision.deviceClockWarning,
          lastClockPauseReason: clockDecision.pauseReason,
          clearClockPauseReason: clockDecision.pauseReason == null,
        ),
      );
      if (!clockDecision.mayPublish ||
          clockDecision.serverNowMs == null ||
          clockDecision.state.acceptedOffsetMs == null) {
        throw StateError(
          'WebDAV server time is required to publish sync safely',
        );
      }
      final material = await _seedSource.prepare(
        namespaceId: namespace.id,
        deviceId: namespace.deviceId,
        authorization: authorization,
        localNowMs: localNowMs,
        serverNowMs: clockDecision.serverNowMs!,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        circleId: root.document.circleId,
        circleKey: root.key,
      );
      _requireCompleteSeed(material);
      await transport.ensureOwnLayout(namespace.deviceId);
      final references = <WebDavSyncSectionReference>[];
      final sectionIo = WebDavSyncLargeSectionIo(codec: _codec);
      for (final section in material.sections.where(
        (section) => section.name != WebDavSyncGraphKind.graph.logicalName,
      )) {
        final reference = await sectionIo.sealWriteVerify(
          transport: transport,
          key: root.key,
          circleId: root.document.circleId,
          deviceId: namespace.deviceId,
          logicalName: section.name,
          schemaVersion: section.schemaVersion,
          payload: section.payload,
          semanticDigest: section.semanticDigest,
          updatedAtMs: clockDecision.serverNowMs!,
          maxBytes: section.maxBytes,
        );
        references.add(reference);
      }
      await material.beforeRootCommit();
      references.sort((left, right) => left.name.compareTo(right.name));
      final manifest = WebDavSyncManifest(
        circleId: root.document.circleId,
        deviceId: namespace.deviceId,
        updatedAtMs: clockDecision.serverNowMs!,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        graphSchemaClaim: WebDavSyncGraphBuilder.schemaVersion,
        profileMap: material.profileMap,
        resourceMap: material.resourceMap,
        sections: List<WebDavSyncSectionReference>.unmodifiable(references),
      );
      material.identityMaps.assertContainsNoLocalIds(manifest.toJson());
      final manifestBytes = await _codec.sealDocument(
        key: root.key,
        circleId: root.document.circleId,
        deviceId: namespace.deviceId,
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        payload: manifest.toJson(),
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
      // The marker is immutable by protocol, but re-read it at the actual
      // manifest commit edge so an external replacement cannot make this
      // device overwrite a manifest under a different root. The profile
      // mutation token rejects edits made while preparing. Subsequent local
      // edits remain differences against this uploaded baseline; they must
      // neither wait for the network nor be marked as already uploaded.
      final commitRootRead = await transport.readRootMarker();
      _requireMarker(namespace.pinnedAuthorityHash!, commitRootRead.bytes);
      await material.beforeRootCommit();
      await material.validatePreferencesUnchanged();
      await transport.writeManifest(namespace.deviceId, manifestBytes);
      final manifestReadBack = await transport.readManifest(namespace.deviceId);
      if (!_bytesEqual(manifestBytes, manifestReadBack.bytes)) {
        throw StateError('WebDAV sync seed manifest verification failed');
      }
      final verifiedManifest = WebDavSyncManifest.fromJson(
        await _codec.openDocument(
          key: root.key,
          encoded: manifestReadBack.bytes,
          circleId: root.document.circleId,
          deviceId: namespace.deviceId,
          logicalName: 'manifest',
          schemaVersion: WebDavSyncManifest.schemaVersion,
          maxBytes: WebDavSyncLimits.maxManifestBytes,
        ),
      );
      final finalRootRead = await transport.readRootMarker();
      _requireMarker(namespace.pinnedAuthorityHash!, finalRootRead.bytes);
      await _stateRepository.update(
        namespace.id,
        (current) => current.copyWith(
          circleToLocalProfiles: material.identityMaps.circleToLocalProfiles,
          circleToLocalResources: material.identityMaps.circleToLocalResources,
          clock: clockDecision.state,
          profiles: material.profileStatesForCommit(current.profiles),
          circleProfilesBaseline: material.circleProfiles,
          circleResourcesBaseline: material.circleResources,
          lastPushedProfilesDigest: material.circleProfiles?.semanticDigest,
          lastPushedResourcesDigest: material.circleResources?.semanticDigest,
          currentDeviceIds: Set<String>.unmodifiable(<String>{
            ...current.currentDeviceIds,
            namespace.deviceId,
          }),
          ownManifest: verifiedManifest,
          lastBootstrapCheckMs: localNowMs,
          publishedBootstrapDatabaseDigest: material.bootstrapDatabaseDigest,
          lastSuccessfulSyncMs: clockDecision.serverNowMs!,
        ),
      );
      return WebDavSyncPublishedSeed(
        material: material,
        manifest: verifiedManifest,
        serverNowMs: clockDecision.serverNowMs!,
      );
    } finally {
      transport.close();
    }
  }

  static void _requireCompleteSeed(WebDavSyncSeedMaterial material) {
    final names = material.sections.map((section) => section.name).toSet();
    final hasCircleProfiles = material.circleProfiles != null;
    final hasCircleResources = material.circleResources != null;
    if (material.sections.isEmpty ||
        !names.contains(WebDavSyncGraphKind.bootstrap.logicalName) ||
        names.contains(WebDavSyncGraphKind.graph.logicalName) ||
        !hasCircleProfiles ||
        !hasCircleResources ||
        !names.contains('profiles') ||
        !names.contains('resources') ||
        material.identityMaps.circleToLocalProfiles.keys.any(
          (circleId) =>
              !names.contains('hot/$circleId') ||
              !names.contains('tombstones/$circleId'),
        )) {
      throw StateError('WebDAV sync refuses an incomplete seed manifest');
    }
  }

  static void _requireMarker(String expected, List<int> actual) {
    if (expected != webDavSyncAuthorityHash(actual)) {
      throw const WebDavSyncRootChangedException();
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
