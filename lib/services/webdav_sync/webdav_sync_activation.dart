import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';

import '../profiles/profile_authorization.dart';
import '../profiles/profile_preferences.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_graph.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_large_section_io.dart';
import 'webdav_sync_local_adapter.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_transport.dart';

final class WebDavSyncSeedSection {
  const WebDavSyncSeedSection({
    required this.name,
    required this.schemaVersion,
    required this.payload,
    required this.semanticDigest,
    required this.maxBytes,
  });

  final String name;
  final int schemaVersion;
  final Object payload;
  final String semanticDigest;
  final int maxBytes;
}

final class WebDavSyncSeedMaterial {
  const WebDavSyncSeedMaterial({
    required this.identityMaps,
    required this.profileMap,
    required this.resourceMap,
    required this.sections,
    required this.profileStates,
    required this.bootstrapDatabaseDigest,
    required this.beforeRootCommit,
    this.preferenceMutationToken,
    this.originalProfileTombstones =
        const <String, Map<String, WebDavSyncTombstone>>{},
    this.circleProfiles,
    this.circleResources,
  });

  final WebDavSyncIdentityMaps identityMaps;
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;
  final List<WebDavSyncSeedSection> sections;
  final Map<String, WebDavSyncProfileEngineState> profileStates;
  final String bootstrapDatabaseDigest;
  final Future<void> Function() beforeRootCommit;
  final ProfilePreferenceMutationToken? preferenceMutationToken;
  final Map<String, Map<String, WebDavSyncTombstone>> originalProfileTombstones;
  final WebDavSyncProfilesDocument? circleProfiles;
  final WebDavSyncResourcesDocument? circleResources;

  Future<T> commitIfPreferencesUnchanged<T>(Future<T> Function() operation) {
    final token = preferenceMutationToken;
    return token == null
        ? operation()
        : ProfilePreferences.runIfMutationSnapshotCurrent(token, operation);
  }

  /// Applies the prepared baselines without erasing a tombstone journal entry
  /// that arrived after preparation. Entries unchanged from the preparation
  /// snapshot may still be intentionally absent (for example a local re-add),
  /// so only genuinely changed/current tombstones are carried forward.
  Map<String, WebDavSyncProfileEngineState> profileStatesForCommit(
    Map<String, WebDavSyncProfileEngineState> currentProfiles,
  ) {
    final result = <String, WebDavSyncProfileEngineState>{};
    for (final entry in profileStates.entries) {
      final seeded = entry.value;
      final original =
          originalProfileTombstones[entry.key] ??
          const <String, WebDavSyncTombstone>{};
      final current = currentProfiles[entry.key];
      final tombstones = Map<String, WebDavSyncTombstone>.from(
        seeded.tombstones,
      );
      for (final tombstone
          in current?.tombstones.entries ??
              const Iterable<MapEntry<String, WebDavSyncTombstone>>.empty()) {
        if (!_sameTombstone(tombstone.value, original[tombstone.key])) {
          tombstones[tombstone.key] = tombstone.value;
        }
      }
      result[entry.key] = seeded.copyWith(
        tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(tombstones),
        pendingApply: current?.pendingApply,
      );
    }
    return Map<String, WebDavSyncProfileEngineState>.unmodifiable(result);
  }

  static bool _sameTombstone(
    WebDavSyncTombstone value,
    WebDavSyncTombstone? other,
  ) =>
      other != null &&
      value.key == other.key &&
      value.stamp.normalizedTimeMs == other.stamp.normalizedTimeMs &&
      value.stamp.originDeviceId == other.stamp.originDeviceId &&
      value.firstPublishedAtMs == other.firstPublishedAtMs &&
      value.rawLocalTime == other.rawLocalTime;
}

abstract interface class WebDavSyncSeedSource {
  Future<WebDavSyncSeedMaterial> prepare({
    required String namespaceId,
    required String deviceId,
    required ProfileAuthorizationContext authorization,
    required int localNowMs,
    required int serverNowMs,
    required int clockOffsetMs,
    String? circleId,
    WebDavSyncCircleKey? circleKey,
  });
}

/// Production seed builder. It persists newly minted identities before any
/// export or server write, then prepares every section required by a usable
/// first manifest.
final class DefaultWebDavSyncSeedSource implements WebDavSyncSeedSource {
  const DefaultWebDavSyncSeedSource({
    required WebDavSyncGraphBuilder graphBuilder,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncLocalAdapter localAdapter,
  }) : _graphBuilder = graphBuilder,
       _stateRepository = stateRepository,
       _localAdapter = localAdapter;

  final WebDavSyncGraphBuilder _graphBuilder;
  final WebDavSyncEngineStateRepository _stateRepository;
  final WebDavSyncLocalAdapter _localAdapter;

  @override
  Future<WebDavSyncSeedMaterial> prepare({
    required String namespaceId,
    required String deviceId,
    required ProfileAuthorizationContext authorization,
    required int localNowMs,
    required int serverNowMs,
    required int clockOffsetMs,
    String? circleId,
    WebDavSyncCircleKey? circleKey,
  }) async {
    if ((circleId == null) != (circleKey == null)) {
      throw ArgumentError('WebDAV sync circle seed context is incomplete');
    }
    final mutationToken = await ProfilePreferences.captureMutationToken();
    return _prepare(
      namespaceId: namespaceId,
      deviceId: deviceId,
      authorization: authorization,
      localNowMs: localNowMs,
      serverNowMs: serverNowMs,
      clockOffsetMs: clockOffsetMs,
      circleId: circleId,
      circleKey: circleKey,
      mutationToken: mutationToken,
    );
  }

  Future<WebDavSyncSeedMaterial> _prepare({
    required String namespaceId,
    required String deviceId,
    required ProfileAuthorizationContext authorization,
    required int localNowMs,
    required int serverNowMs,
    required int clockOffsetMs,
    required String? circleId,
    required WebDavSyncCircleKey? circleKey,
    required ProfilePreferenceMutationToken mutationToken,
  }) async {
    var state = await _stateRepository.load(namespaceId);
    final registry = _graphBuilder.packageService.registry;
    final profiles = await registry.listProfiles(includeDisabled: true);
    final resources = await registry.listAllResourcesIncludingDisabled();
    final plan = WebDavSyncGraphIdentityPlanner.ensure(
      localProfileIds: profiles.map((profile) => profile.id),
      localResourceIds: resources.map((resource) => resource.id),
      currentCircleToLocalProfiles: state.circleToLocalProfiles,
      currentCircleToLocalResources: state.circleToLocalResources,
    );
    state = await _stateRepository.update(
      namespaceId,
      (current) => current.copyWith(
        circleToLocalProfiles: plan.maps.circleToLocalProfiles,
        circleToLocalResources: plan.maps.circleToLocalResources,
      ),
    );
    final bootstrap = await _graphBuilder.build(
      kind: WebDavSyncGraphKind.bootstrap,
      authorization: authorization,
      identityMaps: plan.maps,
    );
    final sections = <WebDavSyncSeedSection>[
      WebDavSyncSeedSection(
        name: WebDavSyncGraphKind.bootstrap.logicalName,
        schemaVersion: WebDavSyncGraphBuilder.schemaVersion,
        payload: bootstrap.payload,
        semanticDigest: bootstrap.semanticDigest,
        maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
      ),
    ];
    final seededStates = <String, WebDavSyncProfileEngineState>{};
    final originalTombstones = <String, Map<String, WebDavSyncTombstone>>{};
    final session = await _localAdapter.beginCycle();
    if (_localAdapter is! WebDavSyncCircleLocalAdapter) {
      throw StateError('WebDAV sync circle seed support is unavailable');
    }
    final circle = await (_localAdapter as WebDavSyncCircleLocalAdapter)
        .buildCircleState(
          session,
          WebDavSyncCircleBuildRequest(
            identityMaps: plan.maps,
            deviceId: deviceId,
            circleId: circleId,
            circleKey: circleKey,
            localNowMs: localNowMs,
            clockOffsetMs: clockOffsetMs,
            serverNowMs: serverNowMs,
            previousProfiles: state.circleProfilesBaseline,
            previousResources: state.circleResourcesBaseline,
          ),
        );
    sections
      ..add(
        WebDavSyncSeedSection(
          name: 'profiles',
          schemaVersion: WebDavSyncProfilesDocument.schemaVersion,
          payload: circle.profiles.toJson(),
          semanticDigest: circle.profiles.semanticDigest,
          maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
        ),
      )
      ..add(
        WebDavSyncSeedSection(
          name: 'resources',
          schemaVersion: WebDavSyncResourcesDocument.schemaVersion,
          payload: circle.resources.toJson(),
          semanticDigest: circle.resources.semanticDigest,
          maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
        ),
      );
    for (final mapping in plan.maps.circleToLocalProfiles.entries) {
      final prior =
          state.profiles[mapping.key] ?? const WebDavSyncProfileEngineState();
      originalTombstones[mapping.key] =
          Map<String, WebDavSyncTombstone>.unmodifiable(prior.tombstones);
      final local = await _localAdapter.readProfile(session, mapping.value);
      final built = WebDavSyncHotMerge.build(
        WebDavSyncBuildInput(
          circleProfileId: mapping.key,
          deviceId: deviceId,
          rawPreferences: local.rawPreferences,
          portablePreferences: local.portablePreferences,
          identityMaps: plan.maps,
          localNowMs: localNowMs,
          clockOffsetMs: clockOffsetMs,
          serverNowMs: serverNowMs,
          previous: prior.baseline,
        ),
      );
      final tombstones = _publishableTombstones(
        prior.tombstones,
        identityMaps: plan.maps,
        currentRecordKeys: built.document.watchState.records.keys.toSet(),
        deviceId: deviceId,
        clockOffsetMs: clockOffsetMs,
        serverNowMs: serverNowMs,
      );
      final tombstoneDocument = WebDavSyncTombstoneDocument(
        circleProfileId: mapping.key,
        items: tombstones,
      );
      plan.maps.assertContainsNoLocalIds(built.document.toJson());
      plan.maps.assertContainsNoLocalIds(tombstoneDocument.toJson());
      sections
        ..add(
          WebDavSyncSeedSection(
            name: 'hot/${mapping.key}',
            schemaVersion: WebDavSyncHotDocument.schemaVersion,
            payload: built.document.toJson(),
            semanticDigest: built.document.semanticDigest,
            maxBytes: WebDavSyncLimits.maxHotDocumentBytes,
          ),
        )
        ..add(
          WebDavSyncSeedSection(
            name: 'tombstones/${mapping.key}',
            schemaVersion: WebDavSyncTombstoneDocument.schemaVersion,
            payload: tombstoneDocument.toJson(),
            semanticDigest: tombstoneDocument.semanticDigest,
            maxBytes: WebDavSyncLimits.maxTombstoneDocumentBytes,
          ),
        );
      seededStates[mapping.key] = prior.copyWith(
        baseline: built.document,
        tombstones: tombstones,
        lastPushedHotDigest: built.document.semanticDigest,
        lastPushedTombstoneDigest: tombstoneDocument.semanticDigest,
      );
    }
    _requireCompleteSeedSections(plan.maps, sections);
    return WebDavSyncSeedMaterial(
      identityMaps: plan.maps,
      profileMap: bootstrap.profileMap,
      resourceMap: bootstrap.resourceMap,
      sections: List<WebDavSyncSeedSection>.unmodifiable(sections),
      profileStates: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
        seededStates,
      ),
      bootstrapDatabaseDigest:
          bootstrap.bootstrapDatabaseDigest ??
          (throw StateError('WebDAV sync bootstrap digest is missing')),
      preferenceMutationToken: mutationToken,
      originalProfileTombstones:
          Map<String, Map<String, WebDavSyncTombstone>>.unmodifiable(
            originalTombstones,
          ),
      circleProfiles: circle.profiles,
      circleResources: circle.resources,
      beforeRootCommit: () async {
        await authorization.validate(registry);
        final currentProfiles = await registry.listProfiles(
          includeDisabled: true,
        );
        final currentResources = await registry
            .listAllResourcesIncludingDisabled();
        if (!_sameSet(
              currentProfiles.map((profile) => profile.id),
              plan.maps.localToCircleProfiles.keys,
            ) ||
            !_sameSet(
              currentResources.map((resource) => resource.id),
              plan.maps.localToCircleResources.keys,
            )) {
          throw StateError(
            'Profiles or connections changed while WebDAV sync was preparing',
          );
        }
      },
    );
  }

  static Map<String, WebDavSyncTombstone> _publishableTombstones(
    Map<String, WebDavSyncTombstone> source, {
    required WebDavSyncIdentityMaps identityMaps,
    required Set<String> currentRecordKeys,
    required String deviceId,
    required int clockOffsetMs,
    required int serverNowMs,
  }) {
    final result = <String, WebDavSyncTombstone>{};
    for (final entry in source.entries) {
      final wireKey = WebDavSyncRecordKey.projectLocalTombstoneKey(
        entry.key,
        identityMaps,
      );
      if (wireKey == null) continue;
      // The deletion hook writes its journal entry before mutating prefs. If
      // the process died before that mutation, or the user re-added the same
      // value before a cycle, current local state is the authoritative result.
      if (entry.value.rawLocalTime && currentRecordKeys.contains(wireKey)) {
        continue;
      }
      final rawStamp = entry.value.stamp;
      final normalizedTime = entry.value.rawLocalTime
          ? min(max(0, rawStamp.normalizedTimeMs + clockOffsetMs), serverNowMs)
          : min(rawStamp.normalizedTimeMs, serverNowMs);
      final normalized = WebDavSyncTombstone(
        key: wireKey,
        stamp: WebDavSyncStamp(
          normalizedTimeMs: normalizedTime,
          originDeviceId: rawStamp.originDeviceId.isEmpty
              ? deviceId
              : rawStamp.originDeviceId,
        ),
        firstPublishedAtMs: max(
          min(entry.value.firstPublishedAtMs ?? serverNowMs, serverNowMs),
          normalizedTime,
        ),
      );
      final existing = result[wireKey];
      if (existing == null || _newer(normalized, existing)) {
        result[wireKey] = normalized;
      }
    }
    return Map<String, WebDavSyncTombstone>.unmodifiable(result);
  }

  static bool _newer(WebDavSyncTombstone left, WebDavSyncTombstone right) =>
      left.stamp.normalizedTimeMs > right.stamp.normalizedTimeMs ||
      left.stamp.normalizedTimeMs == right.stamp.normalizedTimeMs &&
          left.stamp.originDeviceId.compareTo(right.stamp.originDeviceId) > 0;
}

sealed class WebDavSyncInitializationOutcome {
  const WebDavSyncInitializationOutcome();
}

final class WebDavSyncInitialized extends WebDavSyncInitializationOutcome {
  const WebDavSyncInitialized(this.binding);

  final WebDavSyncBinding binding;
}

final class WebDavSyncConcurrentRoot extends WebDavSyncInitializationOutcome {
  const WebDavSyncConcurrentRoot({
    required this.binding,
    required this.root,
    required this.markerBytes,
  });

  final WebDavSyncBinding binding;
  final OpenedWebDavSyncRoot root;
  final Uint8List markerBytes;
}

typedef WebDavSyncActivationTransportFactory =
    WebDavSyncActivationTransport Function({
      required WebDavSyncBinding binding,
      required WebDavSyncSecrets secrets,
    });

/// Finishes only the durable local tail of a root-last seed transaction.
/// A matching candidate proves this was our committed root; a different
/// pinned marker proves a concurrent initializer won and must be adopted.
final class WebDavSyncSeedActivationRecovery {
  const WebDavSyncSeedActivationRecovery({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
  }) : _bindingStore = bindingStore,
       _stateRepository = stateRepository;

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncEngineStateRepository _stateRepository;

  Future<bool> recover() async {
    final snapshot = await _bindingStore.load();
    final staged = snapshot.stagedBinding;
    if (staged == null ||
        staged.lifecycle != WebDavSyncLifecycle.rootVerified) {
      await clearActiveCandidate();
      return false;
    }
    final namespace = snapshot.namespaceFor(staged);
    final pinnedMarker = namespace?.markerBytes;
    final encodedCandidate =
        namespace?.values[WebDavSyncBindingStore.seedCandidateMarkerValueKey];
    if (encodedCandidate == null) return false;
    if (encodedCandidate is! String ||
        encodedCandidate.isEmpty ||
        pinnedMarker == null) {
      throw StateError('WebDAV sync interrupted seed candidate is invalid');
    }
    late final Uint8List candidateMarker;
    try {
      candidateMarker = Uint8List.fromList(base64Decode(encodedCandidate));
    } on FormatException {
      throw StateError('WebDAV sync interrupted seed candidate is invalid');
    }

    if (!_bytesEqual(candidateMarker, pinnedMarker)) {
      await _bindingStore.setLifecycle(
        staged.id,
        WebDavSyncLifecycle.awaitingAdoption,
      );
      await _clearCandidate(namespace!.id);
      return true;
    }

    final state = await _stateRepository.load(staged.namespaceId);
    final manifest = state.ownManifest;
    if (state.adoption != null ||
        !state.hasAuthenticatedMaps ||
        manifest == null ||
        manifest.circleId != staged.circleId ||
        manifest.deviceId != namespace!.deviceId) {
      throw StateError('WebDAV sync interrupted seed activation is incomplete');
    }
    await _bindingStore.activateAndPromoteStaged(staged.id);
    await clearActiveCandidate();
    return true;
  }

  Future<void> clearActiveCandidate() async {
    final snapshot = await _bindingStore.load();
    final active = snapshot.activeBinding;
    if (active == null) return;
    final namespace = snapshot.namespaceFor(active);
    if (namespace == null ||
        !namespace.values.containsKey(
          WebDavSyncBindingStore.seedCandidateMarkerValueKey,
        )) {
      return;
    }
    await _clearCandidate(namespace.id);
  }

  Future<void> _clearCandidate(String namespaceId) =>
      _bindingStore.updateNamespaceValues(namespaceId, (values) {
        final next = Map<String, Object?>.from(values)
          ..remove(WebDavSyncBindingStore.seedCandidateMarkerValueKey);
        return next;
      });
}

/// Root-last new-folder transaction. It is the only service allowed to call
/// [WebDavSyncActivationTransport.createRootMarker].
final class WebDavSyncNewRootInitializer {
  WebDavSyncNewRootInitializer({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncEngineStateRepository stateRepository,
    required WebDavSyncSeedSource seedSource,
    WebDavSyncCodec? codec,
    WebDavSyncActivationTransportFactory? transportFactory,
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
  final WebDavSyncActivationTransportFactory _transportFactory;
  final DateTime Function() _clock;
  final Lock _lock = Lock();

  Future<WebDavSyncInitializationOutcome> initialize({
    required String bindingId,
    required ProfileAuthorizationContext authorization,
  }) => _lock.synchronized(() async {
    final snapshot = await _bindingStore.load();
    var binding =
        snapshot.bindings[bindingId] ??
        (throw StateError('WebDAV sync binding is not ready to initialize'));
    if (binding.lifecycle != WebDavSyncLifecycle.awaitingSeedCommit ||
        binding.circleId != null) {
      throw StateError('WebDAV sync binding is not ready to initialize');
    }
    var namespace =
        snapshot.namespaceFor(binding) ??
        (throw StateError('WebDAV sync candidate namespace is invalid'));
    if (namespace.markerBytes != null) {
      throw StateError('WebDAV sync candidate namespace is invalid');
    }
    var secrets = await _bindingStore.readSecrets(binding);
    final transport = _transportFactory(binding: binding, secrets: secrets);
    try {
      // The root collection must be proven to exist before the immutable key
      // claim. MKCOL 405 alone is ambiguous on several WebDAV providers.
      await transport.ensureActivationLayout();
      binding = await _claimRootKey(
        binding: binding,
        secrets: secrets,
        transport: transport,
      );
      await _resetCandidateStateIfRequired(binding);
      final claimedSnapshot = await _bindingStore.load();
      binding = claimedSnapshot.bindings[binding.id]!;
      namespace = claimedSnapshot.namespaceFor(binding)!;
      secrets = await _bindingStore.readSecrets(binding);
      await transport.ensureOwnLayout(namespace.deviceId);

      final candidate = await _loadOrCreateCandidate(
        namespace: namespace,
        passphrase: secrets.syncPassphrase,
      );
      final markerBytes = candidate.markerBytes;
      final root = candidate.root;
      final circleId = root.document.circleId;
      var markerBeforeWrite = await _readMarkerIfPresent(transport);
      final listing = await transport.listDeviceIds();
      if (listing.deviceIds.length > WebDavSyncLimits.maxPeers) {
        throw StateError('WebDAV sync peer limit exceeded');
      }
      final localNowMs = _clock().toUtc().millisecondsSinceEpoch;
      final clockDecision = WebDavSyncClockPolicy.observe(
        prior: const WebDavSyncClockState(),
        localNowMs: localNowMs,
        serverDate: listing.metadata.serverDate,
      );
      if (!clockDecision.mayPublish ||
          clockDecision.serverNowMs == null ||
          clockDecision.state.acceptedOffsetMs == null) {
        throw StateError(
          'WebDAV server time is required to initialize sync safely',
        );
      }
      final seed = await _seedSource.prepare(
        namespaceId: namespace.id,
        deviceId: namespace.deviceId,
        authorization: authorization,
        localNowMs: localNowMs,
        serverNowMs: clockDecision.serverNowMs!,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        circleId: circleId,
        circleKey: root.key,
      );
      _requireCompleteSeedSections(seed.identityMaps, seed.sections);
      // A prior attempt may have committed the candidate marker immediately
      // before the process stopped, or another initializer may have won while
      // this device prepared its seed. Detect that before any write visible
      // through an existing root and put both resume writes and loser cleanup
      // behind the captured Admin/registry barrier.
      markerBeforeWrite ??= await _readMarkerIfPresent(transport);
      if (markerBeforeWrite != null) {
        await seed.beforeRootCommit();
        if (!_bytesEqual(markerBeforeWrite.bytes, markerBytes)) {
          return _followConcurrentRoot(
            binding: binding,
            secrets: secrets,
            transport: transport,
            markerBytes: markerBeforeWrite.bytes,
          );
        }
      }
      final references = <WebDavSyncSectionReference>[];
      final sectionIo = WebDavSyncLargeSectionIo(codec: _codec);
      for (final section in seed.sections.where(
        (section) => section.name != WebDavSyncGraphKind.graph.logicalName,
      )) {
        final reference = await sectionIo.sealWriteVerify(
          transport: transport,
          key: root.key,
          circleId: circleId,
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
      references.sort((left, right) => left.name.compareTo(right.name));
      final manifest = WebDavSyncManifest(
        circleId: circleId,
        deviceId: namespace.deviceId,
        updatedAtMs: clockDecision.serverNowMs!,
        clockOffsetMs: clockDecision.state.acceptedOffsetMs!,
        graphSchemaClaim: WebDavSyncGraphBuilder.schemaVersion,
        profileMap: seed.profileMap,
        resourceMap: seed.resourceMap,
        sections: List<WebDavSyncSectionReference>.unmodifiable(references),
      );
      seed.identityMaps.assertContainsNoLocalIds(manifest.toJson());
      final manifestBytes = await _codec.sealDocument(
        key: root.key,
        circleId: circleId,
        deviceId: namespace.deviceId,
        logicalName: 'manifest',
        schemaVersion: WebDavSyncManifest.schemaVersion,
        payload: manifest.toJson(),
        maxBytes: WebDavSyncLimits.maxManifestBytes,
      );
      return await seed.commitIfPreferencesUnchanged(() async {
        await transport.writeManifest(namespace.deviceId, manifestBytes);
        final manifestReadBack = await transport.readManifest(
          namespace.deviceId,
        );
        if (!_bytesEqual(manifestReadBack.bytes, manifestBytes)) {
          throw StateError('WebDAV sync seed manifest verification failed');
        }
        final verifiedManifest = WebDavSyncManifest.fromJson(
          await _codec.openDocument(
            key: root.key,
            encoded: manifestReadBack.bytes,
            circleId: circleId,
            deviceId: namespace.deviceId,
            logicalName: 'manifest',
            schemaVersion: WebDavSyncManifest.schemaVersion,
            maxBytes: WebDavSyncLimits.maxManifestBytes,
          ),
        );
        await seed.beforeRootCommit();

        final existing = await _readMarkerIfPresent(transport);
        if (existing != null) {
          if (_bytesEqual(existing.bytes, markerBytes)) {
            return _finishCandidate(
              binding: binding,
              namespace: namespace,
              root: root,
              markerBytes: markerBytes,
              seed: seed,
              manifest: verifiedManifest,
              clock: clockDecision.state,
              serverNowMs: clockDecision.serverNowMs!,
            );
          }
          return _followConcurrentRoot(
            binding: binding,
            secrets: secrets,
            transport: transport,
            markerBytes: existing.bytes,
          );
        }

        // The marker probe is a network boundary. Revalidate the captured
        // profile/registry scope immediately before the root-last commit so a
        // profile switch or graph mutation during that probe cannot authorize a
        // new circle with stale setup state.
        await seed.beforeRootCommit();
        try {
          await transport.createRootMarker(markerBytes);
        } on WebDavException catch (error) {
          if (error.kind != WebDavErrorKind.preconditionFailed) rethrow;
          final winner = await transport.readRootMarker();
          if (_bytesEqual(winner.bytes, markerBytes)) {
            return _finishCandidate(
              binding: binding,
              namespace: namespace,
              root: root,
              markerBytes: markerBytes,
              seed: seed,
              manifest: verifiedManifest,
              clock: clockDecision.state,
              serverNowMs: clockDecision.serverNowMs!,
            );
          }
          return _followConcurrentRoot(
            binding: binding,
            secrets: secrets,
            transport: transport,
            markerBytes: winner.bytes,
          );
        }
        final committed = await transport.readRootMarker();
        if (!_bytesEqual(committed.bytes, markerBytes)) {
          return _followConcurrentRoot(
            binding: binding,
            secrets: secrets,
            transport: transport,
            markerBytes: committed.bytes,
          );
        }
        return _finishCandidate(
          binding: binding,
          namespace: namespace,
          root: root,
          markerBytes: markerBytes,
          seed: seed,
          manifest: verifiedManifest,
          clock: clockDecision.state,
          serverNowMs: clockDecision.serverNowMs!,
        );
      });
    } finally {
      transport.close();
    }
  });

  Future<WebDavSyncInitializationOutcome> _finishCandidate({
    required WebDavSyncBinding binding,
    required WebDavSyncNamespace namespace,
    required OpenedWebDavSyncRoot root,
    required Uint8List markerBytes,
    required WebDavSyncSeedMaterial seed,
    required WebDavSyncManifest manifest,
    required WebDavSyncClockState clock,
    required int serverNowMs,
  }) async {
    await _stateRepository.update(
      namespace.id,
      (current) => current.copyWith(
        circleToLocalProfiles: seed.identityMaps.circleToLocalProfiles,
        circleToLocalResources: seed.identityMaps.circleToLocalResources,
        clock: clock,
        profiles: seed.profileStatesForCommit(current.profiles),
        currentDeviceIds: <String>{namespace.deviceId},
        ownManifest: manifest,
        publishedBootstrapDatabaseDigest: seed.bootstrapDatabaseDigest,
        lastBootstrapCheckMs: _clock().toUtc().millisecondsSinceEpoch,
        lastSuccessfulSyncMs: serverNowMs,
      ),
    );
    final verified = await _bindingStore.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: markerBytes,
    );
    final active = await _bindingStore.activateAndPromoteStaged(binding.id);
    await _clearCandidateMarker(verified.namespaceId);
    return WebDavSyncInitialized(active);
  }

  Future<WebDavSyncInitializationOutcome> _followConcurrentRoot({
    required WebDavSyncBinding binding,
    required WebDavSyncSecrets secrets,
    required WebDavSyncActivationTransport transport,
    required Uint8List markerBytes,
  }) async {
    final beforeKeyRefresh = await _bindingStore.load();
    final losingNamespace = beforeKeyRefresh.namespaceFor(binding);
    if (losingNamespace == null) {
      throw StateError('WebDAV sync candidate namespace is unavailable');
    }
    final keyResult = await _readClaimedRootKey(transport);
    final rootKey = _parseClaimedRootKey(keyResult.bytes);
    var currentBinding = binding;
    if (rootKey.syncPassphrase != secrets.syncPassphrase) {
      currentBinding = await _bindingStore.adoptSyncSecret(
        binding.id,
        rootKey.syncPassphrase,
      );
      await _resetCandidateStateIfRequired(currentBinding);
    }
    final currentSnapshot = await _bindingStore.load();
    currentBinding = currentSnapshot.bindings[currentBinding.id]!;
    final currentNamespace = currentSnapshot.namespaceFor(currentBinding)!;
    final currentSecrets = await _bindingStore.readSecrets(currentBinding);
    final winner = await _codec.openRoot(
      markerBytes,
      currentSecrets.syncPassphrase,
      runInBackground: true,
    );
    try {
      await transport.deleteDeviceDirectory(losingNamespace.deviceId);
    } on WebDavException catch (error) {
      if (error.kind != WebDavErrorKind.notFound) rethrow;
    }
    // Seed preparation persisted candidate-only identity maps before the
    // root-last race was decided. They describe the losing root and must not
    // survive promotion into the winner's authenticated namespace.
    await _stateRepository.update(
      currentNamespace.id,
      (_) => const WebDavSyncEngineState(),
    );
    final verified = await _bindingStore.markRootVerified(
      bindingId: currentBinding.id,
      root: winner.document,
      markerBytes: markerBytes,
    );
    await _clearCandidateMarker(verified.namespaceId);
    final awaiting = await _bindingStore.setLifecycle(
      verified.id,
      WebDavSyncLifecycle.awaitingAdoption,
    );
    return WebDavSyncConcurrentRoot(
      binding: awaiting,
      root: winner,
      markerBytes: Uint8List.fromList(markerBytes),
    );
  }

  Future<({Uint8List markerBytes, OpenedWebDavSyncRoot root})>
  _loadOrCreateCandidate({
    required WebDavSyncNamespace namespace,
    required String passphrase,
  }) async {
    final persisted =
        namespace.values[WebDavSyncBindingStore.seedCandidateMarkerValueKey];
    if (persisted != null) {
      if (persisted is! String || persisted.isEmpty) {
        throw const FormatException('Invalid WebDAV sync seed candidate');
      }
      late final Uint8List markerBytes;
      try {
        markerBytes = Uint8List.fromList(base64Decode(persisted));
      } on FormatException {
        throw const FormatException('Invalid WebDAV sync seed candidate');
      }
      if (markerBytes.isEmpty ||
          markerBytes.length > WebDavSyncCodec.rootMarkerMaxBytes) {
        throw const FormatException('Invalid WebDAV sync seed candidate');
      }
      final root = await _codec.openRoot(
        markerBytes,
        passphrase,
        runInBackground: true,
      );
      return (markerBytes: markerBytes, root: root);
    }

    final markerBytes = await _codec.sealRoot(
      passphrase: passphrase,
      circleId: _mintId('circle'),
      createdAt: _clock().toUtc(),
      runInBackground: true,
    );
    final root = await _codec.openRoot(
      markerBytes,
      passphrase,
      runInBackground: true,
    );
    await _bindingStore.updateNamespaceValues(namespace.id, (values) {
      final next = Map<String, Object?>.from(values);
      next[WebDavSyncBindingStore.seedCandidateMarkerValueKey] = base64Encode(
        markerBytes,
      );
      return next;
    });
    return (markerBytes: markerBytes, root: root);
  }

  Future<WebDavSyncBinding> _claimRootKey({
    required WebDavSyncBinding binding,
    required WebDavSyncSecrets secrets,
    required WebDavSyncActivationTransport transport,
  }) async {
    final existing = await _readRootKeyIfPresent(transport);
    if (existing != null) {
      final key = _parseClaimedRootKey(existing.bytes);
      return _adoptRootKey(binding, secrets, key);
    }

    final proposed = WebDavSyncRootKeyFile(
      syncPassphrase: secrets.syncPassphrase,
    ).encode();
    try {
      await transport.createRootKey(proposed);
    } on WebDavException catch (error) {
      if (error.kind != WebDavErrorKind.preconditionFailed) {
        throw const WebDavSyncRootKeyClaimException();
      }
      final winner = await _readClaimedRootKey(transport);
      final key = _parseClaimedRootKey(winner.bytes);
      return _adoptRootKey(binding, secrets, key);
    }
    final committed = await _readClaimedRootKey(transport);
    if (!_bytesEqual(committed.bytes, proposed)) {
      throw const WebDavSyncRootKeyClaimException();
    }
    final key = _parseClaimedRootKey(committed.bytes);
    return _adoptRootKey(binding, secrets, key);
  }

  Future<WebDavSyncBinding> _adoptRootKey(
    WebDavSyncBinding binding,
    WebDavSyncSecrets secrets,
    WebDavSyncRootKeyFile key,
  ) async {
    if (key.syncPassphrase == secrets.syncPassphrase) return binding;
    return _bindingStore.adoptSyncSecret(binding.id, key.syncPassphrase);
  }

  Future<void> _resetCandidateStateIfRequired(WebDavSyncBinding binding) async {
    final snapshot = await _bindingStore.load();
    final current = snapshot.bindings[binding.id];
    final namespace = current == null ? null : snapshot.namespaceFor(current);
    if (namespace?.values[WebDavSyncBindingStore
            .seedCandidateResetRequiredValueKey] !=
        true) {
      return;
    }
    await _stateRepository.update(
      namespace!.id,
      (_) => const WebDavSyncEngineState(),
    );
    await _bindingStore.updateNamespaceValues(namespace.id, (values) {
      final next = Map<String, Object?>.from(values)
        ..remove(WebDavSyncBindingStore.seedCandidateResetRequiredValueKey);
      return next;
    });
  }

  Future<void> _clearCandidateMarker(String namespaceId) =>
      _bindingStore.updateNamespaceValues(namespaceId, (values) {
        final next = Map<String, Object?>.from(values)
          ..remove(WebDavSyncBindingStore.seedCandidateMarkerValueKey);
        return next;
      });

  static Future<WebDavBytesResult?> _readMarkerIfPresent(
    WebDavSyncActivationTransport transport,
  ) async {
    try {
      return await transport.readRootMarker();
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.notFound) return null;
      rethrow;
    }
  }

  static Future<WebDavBytesResult?> _readRootKeyIfPresent(
    WebDavSyncActivationTransport transport,
  ) async {
    try {
      return await transport.readRootKey();
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.notFound) return null;
      rethrow;
    }
  }

  static Future<WebDavBytesResult> _readClaimedRootKey(
    WebDavSyncActivationTransport transport,
  ) async {
    try {
      final result = await _readRootKeyIfPresent(transport);
      if (result == null) throw const WebDavSyncRootKeyClaimException();
      return result;
    } on WebDavSyncRootKeyClaimException {
      rethrow;
    } on Object {
      throw const WebDavSyncRootKeyClaimException();
    }
  }

  static WebDavSyncRootKeyFile _parseClaimedRootKey(List<int> bytes) {
    try {
      return WebDavSyncRootKeyFile.parse(bytes);
    } on WebDavSyncRootKeyFileException {
      throw const WebDavSyncRootKeyClaimException();
    }
  }

  static String _mintId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

void _requireCompleteSeedSections(
  WebDavSyncIdentityMaps identityMaps,
  Iterable<WebDavSyncSeedSection> sections,
) {
  final names = <String>{};
  for (final section in sections) {
    if (section.name == WebDavSyncGraphKind.graph.logicalName) continue;
    if (!names.add(section.name)) {
      throw StateError('WebDAV sync seed contains duplicate sections');
    }
  }
  if (!names.contains(WebDavSyncGraphKind.bootstrap.logicalName) ||
      !names.contains('profiles') ||
      !names.contains('resources') ||
      identityMaps.circleToLocalProfiles.keys.any(
        (circleId) =>
            !names.contains('hot/$circleId') ||
            !names.contains('tombstones/$circleId'),
      )) {
    throw StateError('WebDAV sync refuses an incomplete seed manifest');
  }
}

bool _sameSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

bool _bytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = max(left.length, right.length);
  for (var index = 0; index < length; index++) {
    difference |=
        (index < left.length ? left[index] : 0) ^
        (index < right.length ? right[index] : 0);
  }
  return difference == 0;
}
