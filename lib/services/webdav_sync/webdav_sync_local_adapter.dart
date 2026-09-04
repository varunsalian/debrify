import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/device_key_provider.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_lock_controller.dart';
import '../profiles/profile_package_service.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_registry.dart';
import '../profiles/profile_runtime.dart';
import '../profiles/profile_scope.dart';
import '../diagnostic_log.dart';
import '../debrify_tv_database.dart';
import '../iptv_catalog_db.dart';
import '../iptv_catalog_key.dart';
import '../storage_service.dart';
import 'webdav_sync_active_profile_refresh.dart';
import 'webdav_sync_circle_merge.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_library_models.dart';
import 'webdav_sync_tombstones.dart';

final class WebDavSyncLocalSession {
  const WebDavSyncLocalSession(this.scope, {void Function()? revalidate})
    : _revalidate = revalidate;

  final ProfileScope scope;
  final void Function()? _revalidate;

  void validate() => _revalidate?.call();
}

final class WebDavSyncLocalProfileSnapshot {
  const WebDavSyncLocalProfileSnapshot({
    required this.localProfileId,
    required this.rawPreferences,
    required this.portablePreferences,
    this.mutationToken,
  });

  final String localProfileId;
  final Map<String, Object?> rawPreferences;
  final Map<String, Object?> portablePreferences;
  final ProfilePreferenceMutationToken? mutationToken;
}

final class WebDavSyncMappedProfileUnavailable extends StateError {
  WebDavSyncMappedProfileUnavailable()
    : super('A mapped WebDAV sync profile is unavailable');
}

abstract interface class WebDavSyncLocalAdapter {
  Future<WebDavSyncLocalSession> beginCycle();

  Future<WebDavSyncLocalProfileSnapshot> readProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
  );

  /// Returns the logical keys committed by this batch. Pending-target replay
  /// returns the complete durable target so a prior partial write still
  /// republishes every affected process/UI mirror.
  Future<Set<String>> applyProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
    Map<String, Object> values, {
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  });
}

final class WebDavSyncCircleInventory {
  const WebDavSyncCircleInventory({
    required this.localProfileIds,
    required this.localResourceIds,
    this.localGrantIds = const <WebDavSyncCircleGrantId>{},
    this.managingAdminLocalProfileIds = const <String>{},
    this.localProfileNames = const <String, String>{},
  });

  final Set<String> localProfileIds;
  final Set<String> localResourceIds;
  final Set<WebDavSyncCircleGrantId> localGrantIds;
  final Set<String> managingAdminLocalProfileIds;
  final Map<String, String> localProfileNames;
}

final class WebDavSyncCircleBuildRequest {
  const WebDavSyncCircleBuildRequest({
    required this.identityMaps,
    required this.deviceId,
    this.circleId,
    this.circleKey,
    required this.localNowMs,
    required this.clockOffsetMs,
    required this.serverNowMs,
    this.previousProfiles,
    this.previousResources,
    this.suppressedLocalProfileIds = const <String>{},
  });

  final WebDavSyncIdentityMaps identityMaps;
  final String deviceId;
  final String? circleId;
  final WebDavSyncCircleKey? circleKey;
  final int localNowMs;
  final int clockOffsetMs;
  final int serverNowMs;
  final WebDavSyncProfilesDocument? previousProfiles;
  final WebDavSyncResourcesDocument? previousResources;
  final Set<String> suppressedLocalProfileIds;
}

final class WebDavSyncBuiltCircleState {
  const WebDavSyncBuiltCircleState({
    required this.profiles,
    required this.resources,
    this.registryOutboxRowCount = 0,
    this.registryVersions = const WebDavSyncRegistryVersionSnapshot(),
  });

  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
  final int registryOutboxRowCount;
  final WebDavSyncRegistryVersionSnapshot registryVersions;
}

final class WebDavSyncCircleApplyRequest {
  const WebDavSyncCircleApplyRequest({
    required this.identityMaps,
    required this.circleId,
    required this.circleKey,
    required this.profiles,
    required this.resources,
    this.registryVersions = const WebDavSyncRegistryVersionSnapshot(),
    this.deferredActiveCircleProfileId,
    this.deferredAdminCircleProfileId,
  });

  final WebDavSyncIdentityMaps identityMaps;
  final String circleId;
  final WebDavSyncCircleKey circleKey;
  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
  final WebDavSyncRegistryVersionSnapshot registryVersions;
  final String? deferredActiveCircleProfileId;
  final String? deferredAdminCircleProfileId;
}

enum WebDavSyncCircleApplyResult { applied, conflict }

/// Optional circle-registry boundary. Keeping it separate preserves the small
/// hot-only fake adapters while production and circle-engine fixtures opt in.
abstract interface class WebDavSyncCircleLocalAdapter {
  Future<WebDavSyncCircleInventory> readCircleInventory(
    WebDavSyncLocalSession session,
  );

  Future<WebDavSyncBuiltCircleState> buildCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleBuildRequest request,
  );

  Future<WebDavSyncCircleApplyResult> applyCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleApplyRequest request, {
    bool replayingPending = false,
  });
}

/// Optional registry-backed hook used to publish only tombstones whose SQL
/// deletions have committed.
abstract interface class WebDavSyncRegistryTombstoneOutboxDrainer {
  Future<bool> drainRegistryTombstoneOutbox();
}

final class WebDavSyncLocalLibrarySnapshot {
  const WebDavSyncLocalLibrarySnapshot({
    required this.document,
    required this.revisions,
    this.hiddenGroupNamesByWireKey = const <String, String>{},
  });

  final WebDavSyncLibraryDocument document;
  final WebDavSyncDatabaseRevisions revisions;

  /// Local-only hash preimages needed to materialize nullable leaves. The
  /// field kept its Round 2a name for adapter compatibility; it now also
  /// carries IPTV group, URL, and resume-key identities and is never encoded.
  final Map<String, String> hiddenGroupNamesByWireKey;
}

final class WebDavSyncLibraryBuildRequest {
  const WebDavSyncLibraryBuildRequest({
    required this.circleProfileId,
    required this.identityMaps,
    required this.clockOffsetMs,
    required this.serverNowMs,
  });

  final String circleProfileId;
  final WebDavSyncIdentityMaps identityMaps;
  final int clockOffsetMs;
  final int serverNowMs;
}

final class WebDavSyncLibraryApplyRequest {
  const WebDavSyncLibraryApplyRequest({
    required this.circleProfileId,
    required this.identityMaps,
    required this.document,
    required this.observedRevisions,
    required this.hiddenGroupNamesByWireKey,
  });

  final String circleProfileId;
  final WebDavSyncIdentityMaps identityMaps;
  final WebDavSyncLibraryDocument document;
  final WebDavSyncDatabaseRevisions observedRevisions;
  final Map<String, String> hiddenGroupNamesByWireKey;
}

final class WebDavSyncLibraryApplyOutcome {
  const WebDavSyncLibraryApplyOutcome({
    required this.result,
    this.appliedNamespaces = const <String>{},
  });

  final WebDavSyncLibraryApplyResult result;
  final Set<String> appliedNamespaces;
}

/// Optional durable-library boundary. Hot-only test adapters remain valid;
/// production opts in without widening preference mutation APIs.
abstract interface class WebDavSyncLibraryLocalAdapter {
  Future<WebDavSyncLocalLibrarySnapshot> readLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryBuildRequest request,
  );

  Future<WebDavSyncLibraryApplyOutcome> applyLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryApplyRequest request, {
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  });
}

/// ProfilePreferences-backed adapter used once M5 arms the engine.
final class ProfileWebDavSyncLocalAdapter
    implements
        WebDavSyncLocalAdapter,
        WebDavSyncCircleLocalAdapter,
        WebDavSyncLibraryLocalAdapter,
        WebDavSyncRegistryTombstoneOutboxDrainer {
  ProfileWebDavSyncLocalAdapter(
    this.registry, {
    WebDavSyncActiveProfileRefresher? activeProfileRefresher,
    void Function(String message)? diagnostic,
  }) : _activeProfileRefresher =
           activeProfileRefresher ??
           const DefaultWebDavSyncActiveProfileRefresher(),
       _diagnostic = diagnostic ?? _recordRedactedDiagnostic;

  final ProfileRegistry registry;
  final WebDavSyncActiveProfileRefresher _activeProfileRefresher;
  final void Function(String message) _diagnostic;

  @override
  Future<bool> drainRegistryTombstoneOutbox() =>
      registry.drainWebDavSyncTombstoneOutbox();

  @override
  Future<WebDavSyncLocalSession> beginCycle() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      throw StateError('WebDAV sync requires committed Profiles');
    }
    final scope = ProfileRuntime.capture();
    return WebDavSyncLocalSession(
      scope,
      revalidate: () => _validateScope(scope),
    );
  }

  @override
  Future<WebDavSyncLocalProfileSnapshot> readProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
  ) async {
    _validateSession(session);
    final profile = await registry.getProfile(localProfileId);
    _validateSession(session);
    if (profile == null) {
      throw WebDavSyncMappedProfileUnavailable();
    }
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: session.scope.sessionEpoch,
    );
    return ProfilePreferences.captureMutationSnapshot((mutationToken) async {
      _validateSession(session);
      final prefs = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.diagnosticsReadOnly,
      );
      final raw = <String, Object?>{
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      final portable = await ProfilePackageService.exportPortablePreferences(
        scope,
        includeCredentialEngineSettings: false,
      );
      _validateSession(session);
      return WebDavSyncLocalProfileSnapshot(
        localProfileId: localProfileId,
        rawPreferences: Map<String, Object?>.unmodifiable(raw),
        portablePreferences: Map<String, Object?>.unmodifiable(portable),
        mutationToken: mutationToken,
      );
    });
  }

  @override
  Future<Set<String>> applyProfile(
    WebDavSyncLocalSession session,
    String localProfileId,
    Map<String, Object> values, {
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  }) async {
    _validateSession(session);
    final profile = await registry.getProfile(localProfileId);
    _validateSession(session);
    if (profile == null) {
      throw WebDavSyncMappedProfileUnavailable();
    }
    // Read the visible generation immediately before apply. Adoption and
    // profile refresh can replace it between the cycle's read and write.
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: session.scope.sessionEpoch,
    );
    final prefs = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    var appliedKeys = const <String>{};
    if (!await prefs.applySyncBatch(
      values,
      authorizationBarrier: () => _validateSession(session),
      expectedMutationToken: expectedMutationToken,
      beforeWrite: beforeWrite,
      replayCommittedTarget: replayingPending,
      afterApply: (appliedScope, changedKeys) async {
        // A pending target may have committed only a prefix before the prior
        // process stopped. Replaying that durable batch must republish every
        // key in the target, including values already present on re-entry.
        appliedKeys = replayingPending
            ? Set<String>.unmodifiable(values.keys)
            : changedKeys;
        if (appliedScope != session.scope) return;
        await _activeProfileRefresher.refresh(
          appliedKeys,
          authorizationBarrier: () => _validateSession(session),
        );
      },
    )) {
      throw StateError('Could not apply WebDAV sync preferences');
    }
    _validateSession(session);
    return appliedKeys;
  }

  @override
  Future<WebDavSyncLocalLibrarySnapshot> readLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryBuildRequest request,
  ) async {
    _validateSession(session);
    final scope = await _profileScope(session, localProfileId);
    final mappings = await _catalogWireMappings(
      session,
      localProfileId,
      request.identityMaps,
    );
    final tv = await DebrifyTvDatabase.instance.readWebDavSyncState(
      scope,
      clockOffsetMs: request.clockOffsetMs,
      serverNowMs: request.serverNowMs,
    );
    final catalog = await IptvCatalogDb.readWebDavSyncState(
      scope,
      clockOffsetMs: request.clockOffsetMs,
      serverNowMs: request.serverNowMs,
    );
    _validateSession(session);
    final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
    final localIdentities = <String, String>{};
    for (final state in catalog.records) {
      if (state.kind != WebDavSyncLibraryKinds.hiddenGroups &&
          state.kind != WebDavSyncLibraryKinds.categoryManualOrders) {
        continue;
      }
      var mapping = mappings.byCatalogKey[state.ownerKey];
      if (mapping == null) {
        final hint = WebDavSyncCatalogOwnerReference.tryFromAux(state.aux);
        if (hint != null &&
            mappings.grantedLocalResourceIds.contains(hint.localResourceId)) {
          final circleResourceId =
              request.identityMaps.localToCircleResources[hint.localResourceId];
          if (circleResourceId != null) {
            mapping = _CatalogWireIdentity(
              circleResourceId: circleResourceId,
              variant: hint.variant,
            );
          }
        }
      }
      if (mapping == null) continue;
      final wireKey = state.kind == WebDavSyncLibraryKinds.hiddenGroups
          ? _hiddenGroupWireKey(mapping, state.itemKey)
          : _categoryOrderWireKey(mapping);
      final candidate = WebDavSyncCircleLeaf<Map<String, Object?>>(
        stamp: state.stamp,
        value: state.deleted ? null : state.value,
      );
      if (!state.deleted && state.value == null) continue;
      final current = records[wireKey];
      if (current == null ||
          WebDavSyncLibraryMerge.compareLeaves(candidate, current) > 0) {
        localIdentities[wireKey] = state.itemKey;
        records[wireKey] = candidate;
      }
    }
    for (final state in tv.records) {
      final kind = state.kind;
      if (kind == WebDavSyncLibraryKinds.tvChannels ||
          kind == WebDavSyncLibraryKinds.tvPoolGeneration) {
        final encodedChannelId = _base64Part(state.ownerKey);
        final wireKey = kind == WebDavSyncLibraryKinds.tvChannels
            ? 'tv/ch/$encodedChannelId'
            : 'tv/pool-gen/$encodedChannelId';
        if (!state.deleted && state.value == null) continue;
        records[wireKey] = WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: state.stamp,
          value: state.deleted ? null : state.value,
        );
        continue;
      }
      if (kind == WebDavSyncLibraryKinds.iptvLists) {
        if (state.ownerKey == DebrifyTvDatabase.favoritesListId) continue;
        final wireKey = 'iptv/list/${_base64Part(state.ownerKey)}';
        if (!state.deleted && state.value == null) continue;
        records[wireKey] = WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: state.stamp,
          value: state.deleted ? null : state.value,
        );
        continue;
      }
      if (kind == WebDavSyncLibraryKinds.iptvListChannels) {
        final wireKey =
            'iptv/list-ch/${_base64Part(state.ownerKey)}/'
            '${_sha256Text(state.itemKey)}';
        if (!state.deleted && state.value == null) continue;
        Map<String, Object?>? wireValue;
        if (!state.deleted) {
          final localValue = state.value!;
          final playlistId = localValue['playlistId'];
          final headers = localValue['httpHeaders'];
          final oversizedHeaders =
              headers != null &&
              utf8.encode(jsonEncode(headers)).length >
                  _maxIptvListMemberHeaderBytes;
          if (oversizedHeaders) {
            _diagnostic('Omitted oversized IPTV-list member HTTP headers');
          }
          wireValue = <String, Object?>{
            for (final entry in localValue.entries)
              if (entry.key != 'playlistId' &&
                  (!oversizedHeaders || entry.key != 'httpHeaders'))
                entry.key: entry.value,
            'sourceRef': playlistId is String && playlistId.isNotEmpty
                ? request.identityMaps.localToCircleResources[playlistId] ?? ''
                : '',
          };
        }
        final candidate = WebDavSyncCircleLeaf<Map<String, Object?>>(
          stamp: state.stamp,
          value: wireValue,
        );
        final current = records[wireKey];
        if (current == null ||
            WebDavSyncLibraryMerge.compareLeaves(candidate, current) > 0) {
          localIdentities[wireKey] = state.itemKey;
          records[wireKey] = candidate;
        }
        continue;
      }
      String? circleResourceId;
      if (kind == WebDavSyncLibraryKinds.videoResume && state.ownerKey == '_') {
        circleResourceId = '_';
      } else {
        if (!mappings.grantedLocalResourceIds.contains(state.ownerKey)) {
          continue;
        }
        circleResourceId =
            request.identityMaps.localToCircleResources[state.ownerKey];
      }
      if (circleResourceId == null) continue;
      final wireKey = switch (kind) {
        WebDavSyncLibraryKinds.iptvCategoryChannelOrders =>
          'iptv/order/$circleResourceId/${_sha256Text(state.itemKey)}',
        WebDavSyncLibraryKinds.iptvWatchHistory =>
          'iptv/watch/$circleResourceId/${_sha256Text(state.itemKey)}',
        WebDavSyncLibraryKinds.videoResume =>
          'resume/$circleResourceId/${_sha256Text(state.itemKey)}',
        _ => null,
      };
      if (wireKey == null || (!state.deleted && state.value == null)) continue;
      final candidate = WebDavSyncCircleLeaf<Map<String, Object?>>(
        stamp: state.stamp,
        value: state.deleted ? null : state.value,
      );
      final current = records[wireKey];
      if (current == null ||
          WebDavSyncLibraryMerge.compareLeaves(candidate, current) > 0) {
        localIdentities[wireKey] = state.itemKey;
        records[wireKey] = candidate;
      }
    }
    for (final pool in tv.tvPools) {
      final wireKey =
          'tv/pool/${_base64Part(pool.channelId)}/${pool.infohash.toLowerCase()}';
      final candidate = WebDavSyncCircleLeaf<Map<String, Object?>>(
        stamp: pool.stamp,
        value: <String, Object?>{
          'generationId': pool.generationId,
          'name': pool.name,
          'sizeBytes': pool.sizeBytes,
          'keywords': pool.keywords,
          'rank': pool.rank,
        },
      );
      final current = records[wireKey];
      if (current == null ||
          WebDavSyncLibraryMerge.compareLeaves(candidate, current) > 0) {
        records[wireKey] = candidate;
      }
    }
    // Running the local projection through the same merge normalizer prunes
    // superseded pool generations and every child of a channel tombstone.
    final document = WebDavSyncLibraryMerge.merge(
      circleProfileId: request.circleProfileId,
      documents: <WebDavSyncLibraryDocument>[
        WebDavSyncLibraryDocument(
          circleProfileId: request.circleProfileId,
          records:
              Map<
                String,
                WebDavSyncCircleLeaf<Map<String, Object?>>
              >.unmodifiable(records),
        ),
      ],
    );
    request.identityMaps.assertContainsNoLocalIds(document.toJson());
    return WebDavSyncLocalLibrarySnapshot(
      document: document,
      revisions: WebDavSyncDatabaseRevisions(
        debrifyTv: tv.mutationRevision,
        iptvCatalog: catalog.mutationRevision,
      ),
      hiddenGroupNamesByWireKey: Map<String, String>.unmodifiable(
        localIdentities,
      ),
    );
  }

  @override
  Future<WebDavSyncLibraryApplyOutcome> applyLibrary(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncLibraryApplyRequest request, {
    Future<void> Function()? beforeWrite,
    bool replayingPending = false,
  }) async {
    _validateSession(session);
    final scope = await _profileScope(session, localProfileId);
    final mappings = await _catalogWireMappings(
      session,
      localProfileId,
      request.identityMaps,
    );
    final channelTargets = <WebDavSyncTvChannelTarget>[];
    final generationTargets = <WebDavSyncTvPoolGenerationTarget>[];
    final poolTargets = <WebDavSyncTvPoolTarget>[];
    final hiddenTargets = <WebDavSyncHiddenGroupTarget>[];
    final categoryOrderTargets = <WebDavSyncCategoryOrderTarget>[];
    final listTargets = <WebDavSyncIptvListTarget>[];
    final listChannelTargets = <WebDavSyncIptvListChannelTarget>[];
    final orderTargets = <WebDavSyncIptvOrderTarget>[];
    final watchTargets = <WebDavSyncIptvWatchTarget>[];
    final resumeTargets = <WebDavSyncVideoResumeTarget>[];
    String? localSource(String circleResourceId) {
      final local =
          request.identityMaps.circleToLocalResources[circleResourceId];
      return local != null && mappings.grantedLocalResourceIds.contains(local)
          ? local
          : null;
    }

    for (final entry in request.document.records.entries) {
      final parts = entry.key.split('/');
      if (parts.length == 3 && parts[0] == 'tv' && parts[1] == 'ch') {
        final channelId = _decodeCanonicalBase64Part(parts[2]);
        final value = entry.value.value;
        final decoded = value == null ? null : _tvChannelValue(value);
        if (channelId == null || value != null && decoded == null) {
          _diagnostic('Ignored an invalid Debrify TV channel library leaf');
          continue;
        }
        channelTargets.add(
          WebDavSyncTvChannelTarget(
            channelId: channelId,
            name: decoded?.name ?? '',
            avoidNsfw: decoded?.avoidNsfw ?? true,
            desiredChannelNumber: decoded?.channelNumber ?? 1,
            createdAtMs: decoded?.createdAtMs ?? 0,
            keywords: decoded?.keywords ?? const <String>[],
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 3 && parts[0] == 'tv' && parts[1] == 'pool-gen') {
        final channelId = _decodeCanonicalBase64Part(parts[2]);
        final value = entry.value.value;
        final generationId = value == null || value.length != 1
            ? null
            : value['generationId'];
        if (channelId == null ||
            generationId is! String ||
            !_validGenerationId.hasMatch(generationId)) {
          _diagnostic('Ignored an invalid Debrify TV generation library leaf');
          continue;
        }
        generationTargets.add(
          WebDavSyncTvPoolGenerationTarget(
            channelId: channelId,
            generationId: generationId,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 4 && parts[0] == 'tv' && parts[1] == 'pool') {
        final channelId = _decodeCanonicalBase64Part(parts[2]);
        final infohash = parts[3];
        final value = entry.value.value;
        final decoded = value == null ? null : _tvPoolValue(value);
        if (channelId == null ||
            !_validInfohash.hasMatch(infohash) ||
            infohash != infohash.toLowerCase() ||
            decoded == null) {
          _diagnostic('Ignored an invalid Debrify TV pool library leaf');
          continue;
        }
        poolTargets.add(
          WebDavSyncTvPoolTarget(
            channelId: channelId,
            infohash: infohash,
            generationId: decoded.generationId,
            name: decoded.name,
            sizeBytes: decoded.sizeBytes,
            keywords: decoded.keywords,
            rank: decoded.rank,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 5 && parts[0] == 'catalog' && parts[1] == 'hidden') {
        final catalogKey =
            mappings.byWireResourceVariant['${parts[2]}/${parts[3]}'];
        if (catalogKey == null) continue;
        final value = entry.value.value;
        final group = value == null
            ? request.hiddenGroupNamesByWireKey[entry.key]
            : value.length == 1 && value['group'] is String
            ? value['group'] as String
            : null;
        if (group == null || group.isEmpty || _sha256Text(group) != parts[4]) {
          _diagnostic('Ignored an invalid catalog library leaf');
          continue;
        }
        hiddenTargets.add(
          WebDavSyncHiddenGroupTarget(
            catalogKey: catalogKey,
            group: group,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 4 &&
          parts[0] == 'catalog' &&
          parts[1] == 'category-order') {
        final catalogKey =
            mappings.byWireResourceVariant['${parts[2]}/${parts[3]}'];
        if (catalogKey == null) continue;
        final value = entry.value.value;
        final groups = value == null
            ? const <String>[]
            : _stringVector(value, 'groups');
        if (groups == null) {
          _diagnostic('Ignored an invalid category-order library leaf');
          continue;
        }
        categoryOrderTargets.add(
          WebDavSyncCategoryOrderTarget(
            catalogKey: catalogKey,
            groups: groups,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 3 && parts[0] == 'iptv' && parts[1] == 'list') {
        final listId = _decodeCanonicalBase64Part(parts[2]);
        final value = entry.value.value;
        final decoded = value == null ? null : _iptvListValue(value);
        if (listId == null ||
            listId == DebrifyTvDatabase.favoritesListId ||
            !_validIptvListId.hasMatch(listId) ||
            value != null && decoded == null) {
          _diagnostic('Ignored an invalid IPTV-list library leaf');
          continue;
        }
        listTargets.add(
          WebDavSyncIptvListTarget(
            listId: listId,
            name: decoded?.name ?? '',
            desiredPosition: decoded?.position ?? 1,
            createdAtMs: decoded?.createdAtMs ?? 0,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 4 && parts[0] == 'iptv' && parts[1] == 'list-ch') {
        final listId = _decodeCanonicalBase64Part(parts[2]);
        final value = entry.value.value;
        String? url;
        if (value == null) {
          url = request.hiddenGroupNamesByWireKey[entry.key];
        } else {
          if (!_validIptvListChannelValue(value)) {
            _diagnostic('Ignored an invalid IPTV-list member library leaf');
            continue;
          }
          url = value['url']! as String;
        }
        if (listId == null ||
            (listId != DebrifyTvDatabase.favoritesListId &&
                !_validIptvListId.hasMatch(listId)) ||
            url == null ||
            url.isEmpty ||
            _sha256Text(url) != parts[3]) {
          _diagnostic('Ignored an invalid IPTV-list member library leaf');
          continue;
        }
        final sourceRef = value?['sourceRef'];
        listChannelTargets.add(
          WebDavSyncIptvListChannelTarget(
            listId: listId,
            url: url,
            localSourceId: sourceRef is String && sourceRef.isNotEmpty
                ? request.identityMaps.circleToLocalResources[sourceRef] ?? ''
                : '',
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 4 && parts[0] == 'iptv' && parts[1] == 'order') {
        final sourceId = localSource(parts[2]);
        if (sourceId == null) continue;
        final value = entry.value.value;
        final group = value == null
            ? request.hiddenGroupNamesByWireKey[entry.key]
            : value['group'] as String?;
        final items = value == null
            ? const <WebDavSyncIptvOrderItem>[]
            : _iptvOrderItems(value);
        if (group == null ||
            group.isEmpty ||
            _sha256Text(group) != parts[3] ||
            items == null) {
          _diagnostic('Ignored an invalid IPTV-order library leaf');
          continue;
        }
        orderTargets.add(
          WebDavSyncIptvOrderTarget(
            sourceId: sourceId,
            group: group,
            items: items,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 4 && parts[0] == 'iptv' && parts[1] == 'watch') {
        final sourceId = localSource(parts[2]);
        if (sourceId == null) continue;
        final value = entry.value.value;
        final url = value == null
            ? request.hiddenGroupNamesByWireKey[entry.key]
            : value['url'] as String?;
        if (url == null ||
            url.isEmpty ||
            _sha256Text(url) != parts[3] ||
            (value != null && !_validWatchValue(value))) {
          _diagnostic('Ignored an invalid IPTV-watch library leaf');
          continue;
        }
        watchTargets.add(
          WebDavSyncIptvWatchTarget(
            sourceId: sourceId,
            url: url,
            leaf: entry.value,
          ),
        );
        continue;
      }
      if (parts.length == 3 && parts[0] == 'resume') {
        final sourceId = parts[1] == '_' ? null : localSource(parts[1]);
        if (parts[1] != '_' && sourceId == null) continue;
        final value = entry.value.value;
        final resumeKey = value == null
            ? request.hiddenGroupNamesByWireKey[entry.key]
            : value['resumeKey'] as String?;
        if (resumeKey == null ||
            resumeKey.isEmpty ||
            _sha256Text(resumeKey) != parts[2] ||
            (value != null && !_validResumeValue(value))) {
          _diagnostic('Ignored an invalid resume library leaf');
          continue;
        }
        resumeTargets.add(
          WebDavSyncVideoResumeTarget(
            sourceId: sourceId,
            resumeKey: resumeKey,
            leaf: entry.value,
          ),
        );
      }
    }
    final liveChannelIds = channelTargets
        .where((target) => target.leaf.value != null)
        .map((target) => target.channelId)
        .toSet();
    final applicableGenerations = generationTargets
        .where((target) => liveChannelIds.contains(target.channelId))
        .toList(growable: false);
    final generationByChannel = <String, String>{
      for (final target in applicableGenerations)
        target.channelId: target.generationId,
    };
    final applicablePools = poolTargets
        .where(
          (target) =>
              generationByChannel[target.channelId] == target.generationId,
        )
        .toList(growable: false);
    await beforeWrite?.call();
    _validateSession(session);
    final tvResult = await DebrifyTvDatabase.instance.applyWebDavSyncFamilies(
      scope,
      expectedRevision: request.observedRevisions.debrifyTv,
      channelTargets: channelTargets,
      generationTargets: applicableGenerations,
      poolTargets: applicablePools,
      listTargets: listTargets,
      listChannelTargets: listChannelTargets,
      orderTargets: orderTargets,
      watchTargets: watchTargets,
      resumeTargets: resumeTargets,
    );
    if (tvResult.result == WebDavSyncLibraryApplyResult.conflict) {
      return const WebDavSyncLibraryApplyOutcome(
        result: WebDavSyncLibraryApplyResult.conflict,
      );
    }
    final catalogResult = await IptvCatalogDb.applyWebDavCatalogFamilies(
      scope,
      expectedRevision: request.observedRevisions.iptvCatalog,
      hiddenTargets: hiddenTargets,
      categoryOrderTargets: categoryOrderTargets,
    );
    _validateSession(session);
    if (catalogResult.result == WebDavSyncLibraryApplyResult.conflict) {
      return const WebDavSyncLibraryApplyOutcome(
        result: WebDavSyncLibraryApplyResult.conflict,
      );
    }
    return WebDavSyncLibraryApplyOutcome(
      result: WebDavSyncLibraryApplyResult.applied,
      appliedNamespaces: Set<String>.unmodifiable(<String>{
        ...tvResult.touchedNamespaces,
        ...catalogResult.touchedNamespaces,
      }),
    );
  }

  Future<ProfileScope> _profileScope(
    WebDavSyncLocalSession session,
    String localProfileId,
  ) async {
    final profile = await registry.getProfile(localProfileId);
    _validateSession(session);
    if (profile == null) throw WebDavSyncMappedProfileUnavailable();
    return ProfileScope(
      profileId: profile.id,
      dataGeneration: profile.visibleDataGeneration,
      sessionEpoch: session.scope.sessionEpoch,
    );
  }

  Future<_CatalogWireMappings> _catalogWireMappings(
    WebDavSyncLocalSession session,
    String localProfileId,
    WebDavSyncIdentityMaps identityMaps,
  ) async {
    if (localProfileId != session.scope.profileId) {
      return const _CatalogWireMappings();
    }
    final playlists = await StorageService.getIptvPlaylists(forSettings: true);
    _validateSession(session);
    final byCatalogKey = <String, _CatalogWireIdentity>{};
    final byWireResourceVariant = <String, String>{};
    final grantedLocalResourceIds = <String>{};
    void add(String catalogKey, String localResourceId, String variant) {
      grantedLocalResourceIds.add(localResourceId);
      final circleResourceId =
          identityMaps.localToCircleResources[localResourceId];
      if (circleResourceId == null) return;
      final identity = _CatalogWireIdentity(
        circleResourceId: circleResourceId,
        variant: variant,
      );
      byCatalogKey[catalogKey] = identity;
      byWireResourceVariant['$circleResourceId/$variant'] = catalogKey;
    }

    for (final playlist in playlists) {
      final resourceId = playlist.connectionResourceId;
      if (resourceId == null) continue;
      if (playlist.isLocalFile) {
        add(
          IptvCatalogKey.forLocalCategoryOrder(playlist.id),
          resourceId,
          'local',
        );
      } else if (playlist.isXtreamCodes) {
        for (final type in IptvCatalogKey.xtreamContentTypes) {
          add(
            IptvCatalogKey.forXtream(
              playlist.serverUrl!,
              playlist.username ?? '',
              type,
            ),
            resourceId,
            'xc-$type',
          );
        }
      } else if (playlist.url.isNotEmpty) {
        add(IptvCatalogKey.forUrl(playlist.url), resourceId, 'm3u');
      }
    }
    return _CatalogWireMappings(
      byCatalogKey: Map<String, _CatalogWireIdentity>.unmodifiable(
        byCatalogKey,
      ),
      byWireResourceVariant: Map<String, String>.unmodifiable(
        byWireResourceVariant,
      ),
      grantedLocalResourceIds: Set<String>.unmodifiable(
        grantedLocalResourceIds,
      ),
    );
  }

  @override
  Future<WebDavSyncCircleInventory> readCircleInventory(
    WebDavSyncLocalSession session,
  ) async {
    _validateSession(session);
    final profiles = await registry.readProfileSyncProjection();
    final resources = await registry.readRegistrySyncProjection();
    _validateSession(session);
    return WebDavSyncCircleInventory(
      localProfileIds: Set<String>.unmodifiable(
        profiles.map((entry) => entry.profile.id),
      ),
      localResourceIds: Set<String>.unmodifiable(
        resources.resources.map((entry) => entry.resource.id),
      ),
      localGrantIds: Set<WebDavSyncCircleGrantId>.unmodifiable(
        resources.grants.map(
          (entry) => (
            circleProfileId: entry.profileId,
            circleResourceId: entry.resourceId,
          ),
        ),
      ),
      managingAdminLocalProfileIds: Set<String>.unmodifiable(
        profiles
            .where((entry) => _isManagingAdmin(entry.profile))
            .map((entry) => entry.profile.id),
      ),
      localProfileNames: Map<String, String>.unmodifiable(<String, String>{
        for (final entry in profiles) entry.profile.id: entry.profile.name,
      }),
    );
  }

  @override
  Future<WebDavSyncBuiltCircleState> buildCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleBuildRequest request,
  ) async {
    _validateSession(session);
    final circleProjection = await registry.readCircleSyncProjection();
    final profileProjection = circleProjection.profiles;
    final registryProjection = circleProjection.registry;
    final tombstones =
        await WebDavSyncTombstoneRecorder.loadRegistryRecordTombstones(
          clockOffsetMs: request.clockOffsetMs,
          serverNowMs: request.serverNowMs,
        );
    _validateSession(session);
    final maps = request.identityMaps;

    final profiles =
        <String, WebDavSyncLocalCircleValue<WebDavSyncProfileValue>>{};
    for (final entry in profileProjection) {
      if (request.suppressedLocalProfileIds.contains(entry.profile.id)) {
        continue;
      }
      final circleId = maps.localToCircleProfiles[entry.profile.id];
      if (circleId == null) {
        throw StateError('WebDAV sync profile mapping is incomplete');
      }
      final profile = entry.profile;
      final pin = entry.pin;
      final priorAvatar =
          request.previousProfiles?.profiles[circleId]?.value?.avatarKey;
      final parsedAvatar = ProfileAvatar.tryParse(profile.avatarKey);
      final avatarKey = profile.avatarKey == null
          ? null
          : parsedAvatar == null || parsedAvatar.kind == ProfileAvatarKind.image
          ? priorAvatar
          : parsedAvatar.format();
      profiles[circleId] = WebDavSyncLocalCircleValue<WebDavSyncProfileValue>(
        updatedAtMs: entry.updatedAtMs,
        value: WebDavSyncProfileValue(
          name: profile.name,
          avatarKey: avatarKey,
          role: profile.role,
          policy: Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(
              jsonDecode(profile.policy.encode()) as Map,
            ),
          ),
          enabled: profile.isEnabled,
          lockOnResume: profile.lockOnResume,
          inactivityTimeoutMinutes: profile.inactivityTimeoutMinutes,
          setupComplete: profile.setupComplete,
          lifecycle: profile.lifecycle,
          pin: WebDavSyncProfilePin(
            hash: pin.hash == null ? null : base64Encode(pin.hash!),
            salt: pin.salt == null ? null : base64Encode(pin.salt!),
            paramsJson: pin.paramsJson,
            recoveryHash: pin.recoveryHash == null
                ? null
                : base64Encode(pin.recoveryHash!),
            recoverySalt: pin.recoverySalt == null
                ? null
                : base64Encode(pin.recoverySalt!),
            recoveryParamsJson: pin.recoveryParamsJson,
            resetRequired: pin.resetRequired,
          ),
        ),
      );
    }

    final resources =
        <String, WebDavSyncLocalCircleValue<WebDavSyncResourceMetadata>>{};
    for (final entry in registryProjection.resources) {
      final resource = entry.resource;
      final circleId = maps.localToCircleResources[resource.id];
      final ownerCircleId = maps.localToCircleProfiles[resource.ownerProfileId];
      if (circleId == null || ownerCircleId == null) {
        throw StateError('WebDAV sync resource mapping is incomplete');
      }
      resources[circleId] =
          WebDavSyncLocalCircleValue<WebDavSyncResourceMetadata>(
            updatedAtMs: entry.updatedAtMs,
            value: WebDavSyncResourceMetadata(
              type: resource.type,
              label: resource.label,
              ownerCircleProfileId: ownerCircleId,
              publicConfig: Map<String, Object?>.unmodifiable(
                Map<String, Object?>.from(resource.publicConfig),
              ),
              publicSchemaVersion: resource.publicSchemaVersion,
              enabled: resource.enabled,
            ),
          );
    }

    final secrets =
        <String, WebDavSyncLocalCircleValue<WebDavSyncResourceSecretConfig>>{};
    final activeCircleProfileId =
        maps.localToCircleProfiles[session.scope.profileId];
    ProfileAuthorizationContext? authorization;
    if (activeCircleProfileId != null &&
        request.circleId != null &&
        request.circleKey != null) {
      try {
        authorization = await ProfileAuthorizationContext.capture(registry);
      } catch (_) {
        authorization = null;
      }
    }
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final codec = WebDavSyncCodec();
    for (final entry in registryProjection.resources) {
      final resource = entry.resource;
      final circleResourceId = maps.localToCircleResources[resource.id]!;
      final ownerCircleId =
          maps.localToCircleProfiles[resource.ownerProfileId]!;
      if (authorization == null ||
          ownerCircleId != activeCircleProfileId ||
          resource.secretPending) {
        continue;
      }
      try {
        final secret = await service.revealOwnedSecretForProfileBackup(
          context: authorization,
          resourceId: resource.id,
        );
        _validateSession(session);
        final digest = semanticDigestOf(secret);
        final prior = request
            .previousResources
            ?.resources[circleResourceId]
            ?.secretConfig
            ?.value;
        final same =
            prior != null &&
            prior.semanticDigest == digest &&
            prior.type == resource.type &&
            prior.ownerCircleProfileId == ownerCircleId &&
            prior.publicSchemaVersion == resource.publicSchemaVersion &&
            prior.payloadVersion ==
                ConnectionResourceService.secretPayloadVersion;
        final value = same
            ? prior
            : WebDavSyncResourceSecretConfig(
                semanticDigest: digest,
                type: resource.type,
                ownerCircleProfileId: ownerCircleId,
                publicSchemaVersion: resource.publicSchemaVersion,
                payloadVersion: ConnectionResourceService.secretPayloadVersion,
                envelope: base64Encode(
                  await codec.sealDocument(
                    key: request.circleKey!,
                    circleId: request.circleId!,
                    deviceId: request.deviceId,
                    logicalName: 'resource-secret/$circleResourceId',
                    schemaVersion: 1,
                    payload: secret,
                    maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
                    runInBackground: true,
                  ),
                ),
              );
        secrets[circleResourceId] = WebDavSyncLocalCircleValue(
          value: value,
          updatedAtMs: entry.updatedAtMs,
        );
      } catch (_) {
        // Metadata still publishes. A receiver without a compatible local
        // secret records secret_pending and a later authorized owner cycle can
        // complete the independently stamped leaf.
      }
    }

    Map<String, Map<String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>>
    grants =
        <
          String,
          Map<String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>
        >{};
    for (final entry in registryProjection.grants) {
      final profileId = maps.localToCircleProfiles[entry.profileId];
      final resourceId = maps.localToCircleResources[entry.resourceId];
      if (profileId == null || resourceId == null) {
        throw StateError('WebDAV sync grant mapping is incomplete');
      }
      grants.putIfAbsent(
        profileId,
        () => {},
      )[resourceId] = WebDavSyncLocalCircleValue(
        value: WebDavSyncGrantValue(permissions: entry.permissions),
        updatedAtMs: entry.updatedAtMs,
      );
    }
    final settings =
        <
          String,
          Map<String, WebDavSyncLocalCircleValue<WebDavSyncSettingsValue>>
        >{};
    for (final entry in registryProjection.settings) {
      final profileId = maps.localToCircleProfiles[entry.profileId];
      final resourceId = maps.localToCircleResources[entry.resourceId];
      if (profileId == null || resourceId == null) {
        throw StateError('WebDAV sync settings mapping is incomplete');
      }
      settings.putIfAbsent(
        profileId,
        () => {},
      )[resourceId] = WebDavSyncLocalCircleValue(
        value: WebDavSyncSettingsValue(
          enabled: entry.enabled,
          settings: Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(entry.settings),
          ),
        ),
        updatedAtMs: entry.updatedAtMs,
      );
    }
    final bindings =
        <
          String,
          Map<String, WebDavSyncLocalCircleValue<WebDavSyncBindingValue>>
        >{};
    for (final entry in registryProjection.bindings) {
      final profileId = maps.localToCircleProfiles[entry.profileId];
      final resourceId = maps.localToCircleResources[entry.resourceId];
      if (profileId == null || resourceId == null) {
        throw StateError('WebDAV sync binding mapping is incomplete');
      }
      bindings.putIfAbsent(
        profileId,
        () => {},
      )[entry.slot] = WebDavSyncLocalCircleValue(
        value: WebDavSyncBindingValue(circleResourceId: resourceId),
        updatedAtMs: entry.updatedAtMs,
      );
    }

    final deletions = <WebDavSyncCircleDeletion>[];
    for (final tombstone in tombstones.values) {
      final record = tombstone.record;
      final profileId = record.profileId == null
          ? null
          : maps.localToCircleProfiles[record.profileId!];
      final resourceId = record.resourceId == null
          ? null
          : maps.localToCircleResources[record.resourceId!];
      if (record.profileId != null && profileId == null ||
          record.resourceId != null && resourceId == null) {
        continue;
      }
      deletions.add(
        WebDavSyncCircleDeletion(
          kind: WebDavSyncCircleDeletionKind.values.byName(record.kind.name),
          timeMs: tombstone.timeMs,
          originDeviceId: tombstone.originDeviceId,
          normalizedTimeFrozen: tombstone.normalizedTimeFrozen,
          circleProfileId: profileId,
          circleResourceId: resourceId,
          slot: record.slot,
        ),
      );
    }

    final profileDocument = WebDavSyncCircleMerge.rebuildProfiles(
      WebDavSyncProfilesBuildInput(
        deviceId: request.deviceId,
        localNowMs: request.localNowMs,
        clockOffsetMs: request.clockOffsetMs,
        serverNowMs: request.serverNowMs,
        profiles: profiles,
        deletions: deletions,
        previous: request.previousProfiles,
      ),
    );
    final resourceDocument = WebDavSyncCircleMerge.rebuildResources(
      WebDavSyncResourcesBuildInput(
        deviceId: request.deviceId,
        localNowMs: request.localNowMs,
        clockOffsetMs: request.clockOffsetMs,
        serverNowMs: request.serverNowMs,
        resources: resources,
        secrets: secrets,
        grants: grants,
        settings: settings,
        bindings: bindings,
        deletions: deletions,
        previous: request.previousResources,
      ),
    );
    maps.assertContainsNoLocalIds(profileDocument.toJson());
    maps.assertContainsNoLocalIds(resourceDocument.toJson());
    return WebDavSyncBuiltCircleState(
      profiles: profileDocument,
      resources: resourceDocument,
      registryOutboxRowCount: circleProjection.outboxRowCount,
      registryVersions: WebDavSyncRegistryVersionSnapshot(
        enforce: true,
        updatedAtMsByRecord: Map<String, int>.unmodifiable(<String, int>{
          for (final entry in profileProjection)
            WebDavSyncRegistryRecordId.profile(entry.profile.id).storageKey:
                entry.updatedAtMs,
          for (final entry in registryProjection.resources)
            WebDavSyncRegistryRecordId.resource(
              entry.resource.id,
              ownerProfileId: entry.resource.ownerProfileId,
            ).storageKey: entry.updatedAtMs,
          for (final entry in registryProjection.grants)
            WebDavSyncRegistryRecordId.grant(
              entry.profileId,
              entry.resourceId,
            ).storageKey: entry.updatedAtMs,
          for (final entry in registryProjection.settings)
            WebDavSyncRegistryRecordId.setting(
              entry.profileId,
              entry.resourceId,
            ).storageKey: entry.updatedAtMs,
          for (final entry in registryProjection.bindings)
            WebDavSyncRegistryRecordId.binding(
              entry.profileId,
              entry.slot,
              resourceId: entry.resourceId,
            ).storageKey: entry.updatedAtMs,
        }),
      ),
    );
  }

  @override
  Future<WebDavSyncCircleApplyResult> applyCircleState(
    WebDavSyncLocalSession session,
    WebDavSyncCircleApplyRequest request, {
    bool replayingPending = false,
  }) async {
    _validateSession(session);
    final maps = request.identityMaps;
    final currentCircleProjection = await registry.readCircleSyncProjection();
    final currentProfileProjection = currentCircleProjection.profiles;
    final currentProfiles = <String, UserProfile>{
      for (final entry in currentProfileProjection)
        entry.profile.id: entry.profile,
    };
    final currentProfileVersions = <String, int>{
      for (final entry in currentProfileProjection)
        entry.profile.id: entry.updatedAtMs,
    };
    final currentPins = <String, ProfilePinRecord>{
      for (final entry in currentProfileProjection) entry.profile.id: entry.pin,
    };
    final currentRegistry = currentCircleProjection.registry;
    final currentResources = <String, ConnectionResource>{
      for (final entry in currentRegistry.resources)
        entry.resource.id: entry.resource,
    };
    final currentResourceVersions = <String, int>{
      for (final entry in currentRegistry.resources)
        entry.resource.id: entry.updatedAtMs,
    };
    int? expectedVersion(WebDavSyncRegistryRecordId id, int? currentVersion) =>
        request.registryVersions.enforce
        ? request.registryVersions.expectedUpdatedAtMs(id.storageKey)
        : currentVersion;
    _validateSession(session);
    final profileRecords = <SyncedRegistryProfileRecord>[];
    final profileDeletes = <SyncedRegistryDeleteRecord>[];
    final prePins = <String, ProfilePinRecord?>{};
    for (final entry in request.profiles.profiles.entries) {
      final localId = maps.circleToLocalProfiles[entry.key];
      if (localId == null) continue;
      if (entry.key == request.deferredAdminCircleProfileId ||
          entry.key == request.deferredActiveCircleProfileId) {
        continue;
      }
      if (entry.value.value == null) {
        if (currentProfiles.containsKey(localId)) {
          final id = WebDavSyncRegistryRecordId.profile(localId);
          profileDeletes.add(
            SyncedRegistryDeleteRecord(
              record: id,
              expectedPriorUpdatedAtMs: expectedVersion(
                id,
                currentProfileVersions[localId],
              ),
            ),
          );
        }
        continue;
      }
      final value = entry.value.value!;
      final current = currentProfiles[localId];
      final currentPin = currentPins[localId];
      final localPin = _localPin(value.pin);
      final record = SyncedRegistryProfileRecord(
        id: localId,
        name: value.name,
        avatarKey: value.avatarKey,
        role: value.role,
        policy: ProfilePolicy.decode(jsonEncode(value.policy), value.role),
        enabled: value.enabled,
        lockOnResume: value.lockOnResume,
        inactivityTimeoutMinutes: value.inactivityTimeoutMinutes,
        setupComplete: value.setupComplete,
        lifecycle: value.lifecycle,
        pin: localPin,
        applyPin: current == null || !_samePin(currentPin, localPin),
        updatedAtMs: entry.value.stamp.normalizedTimeMs,
        expectedPriorUpdatedAtMs: expectedVersion(
          WebDavSyncRegistryRecordId.profile(localId),
          currentProfileVersions[localId],
        ),
      );
      if (current != null &&
          currentPin != null &&
          _sameSyncedProfile(current, currentPin, record)) {
        continue;
      }
      prePins[localId] = currentPin;
      profileRecords.add(record);
    }

    final resourceRecords = <SyncedRegistryResourceRecord>[];
    final resourceDeletes = <SyncedRegistryDeleteRecord>[];
    final codec = WebDavSyncCodec();
    final cipher = DeviceKeyProvider.cipher;
    for (final entry in request.resources.resources.entries) {
      final localResourceId = maps.circleToLocalResources[entry.key];
      if (localResourceId == null) continue;
      final metadata = entry.value.metadata.value;
      if (metadata == null) {
        final existing = currentResources[localResourceId];
        if (existing != null) {
          final id = WebDavSyncRegistryRecordId.resource(
            localResourceId,
            ownerProfileId: existing.ownerProfileId,
          );
          resourceDeletes.add(
            SyncedRegistryDeleteRecord(
              record: id,
              expectedPriorUpdatedAtMs: expectedVersion(
                id,
                currentResourceVersions[localResourceId],
              ),
            ),
          );
        }
        continue;
      }
      final ownerId = maps.circleToLocalProfiles[metadata.ownerCircleProfileId];
      if (ownerId == null) {
        throw StateError('Synced resource owner mapping is unavailable');
      }
      String? sealedSecret;
      int? secretVersion;
      var clearSecret = false;
      var localSecretMatches = false;
      var ignoredSecret = false;
      final secretLeaf = entry.value.secretConfig;
      final secret = secretLeaf?.value;
      if (secret != null &&
          secret.type == metadata.type &&
          secret.ownerCircleProfileId == metadata.ownerCircleProfileId &&
          secret.publicSchemaVersion == metadata.publicSchemaVersion) {
        try {
          final payload = await codec.openDocument(
            key: request.circleKey,
            encoded: base64Decode(secret.envelope),
            circleId: request.circleId,
            deviceId: secretLeaf!.stamp.originDeviceId,
            logicalName: 'resource-secret/${entry.key}',
            schemaVersion: 1,
            maxBytes: WebDavSyncLimits.maxGraphDocumentBytes,
            runInBackground: true,
          );
          if (payload is! Map ||
              semanticDigestOf(payload) != secret.semanticDigest) {
            throw const FormatException('Synced resource secret mismatch');
          }
          final canonical = Map<String, Object?>.from(payload);
          secretVersion = secret.payloadVersion;
          localSecretMatches = await _localSecretMatches(
            registry: registry,
            cipher: cipher,
            resourceId: localResourceId,
            metadata: metadata,
            ownerProfileId: ownerId,
            secret: secret,
          );
          if (!localSecretMatches) {
            sealedSecret = await cipher.seal(
              utf8.encode(WebDavSyncCodec.canonicalJson(canonical)),
              associatedData: ConnectionResourceService.associatedDataForSecret(
                resourceId: localResourceId,
                type: metadata.type,
                ownerProfileId: ownerId,
                publicSchemaVersion: metadata.publicSchemaVersion,
                payloadVersion: secretVersion,
              ),
            );
          }
        } catch (_) {
          sealedSecret = null;
          secretVersion = null;
          ignoredSecret = true;
          _diagnostic('Ignored an unreadable synced resource secret');
        }
      } else if (secretLeaf?.value == null && secretLeaf != null) {
        // Only an explicit winning null leaf is deletion evidence. A live leaf
        // attached to different metadata can be a stale pre-transfer envelope.
        clearSecret = true;
      } else if (secretLeaf != null) {
        ignoredSecret = true;
        _diagnostic(
          'Ignored an attachment-incompatible synced resource secret',
        );
      }
      final incoming = ConnectionResource(
        id: localResourceId,
        type: metadata.type,
        label: metadata.label,
        ownerProfileId: ownerId,
        publicConfig: Map<String, dynamic>.from(metadata.publicConfig),
        publicSchemaVersion: metadata.publicSchemaVersion,
        authorizationRevision: 1,
        enabled: metadata.enabled,
        secretPending: sealedSecret == null,
      );
      final current = currentResources[localResourceId];
      final secretNeedsApply =
          secretLeaf != null &&
          !ignoredSecret &&
          (clearSecret ? current?.secretPending != true : !localSecretMatches);
      if (current != null &&
          _sameResourceMetadata(current, incoming) &&
          !secretNeedsApply) {
        continue;
      }
      resourceRecords.add(
        SyncedRegistryResourceRecord(
          resource: incoming,
          updatedAtMs: entry.value.metadata.stamp.normalizedTimeMs,
          sealedSecretPayload: sealedSecret,
          secretPayloadVersion: secretVersion,
          clearSecret: clearSecret,
          expectedPriorUpdatedAtMs: expectedVersion(
            WebDavSyncRegistryRecordId.resource(
              localResourceId,
              ownerProfileId: ownerId,
            ),
            currentResourceVersions[localResourceId],
          ),
        ),
      );
    }

    final grantRecords = <SyncedRegistryGrantRecord>[];
    final settingRecords = <SyncedRegistrySettingsRecord>[];
    final bindingRecords = <SyncedRegistryBindingRecord>[];
    final nestedDeletes = <SyncedRegistryDeleteRecord>[];
    final currentGrants = <String, RegistrySyncGrantProjection>{
      for (final item in currentRegistry.grants)
        _pairKey(item.profileId, item.resourceId): item,
    };
    final currentSettings = <String, RegistrySyncSettingsProjection>{
      for (final item in currentRegistry.settings)
        _pairKey(item.profileId, item.resourceId): item,
    };
    final currentBindings = <String, RegistrySyncBindingProjection>{
      for (final item in currentRegistry.bindings)
        _pairKey(item.profileId, item.slot): item,
    };
    for (final outer in request.resources.grants.entries) {
      final profileId = maps.circleToLocalProfiles[outer.key];
      if (profileId == null) continue;
      for (final inner in outer.value.entries) {
        final resourceId = maps.circleToLocalResources[inner.key];
        if (resourceId == null) continue;
        final value = inner.value.value;
        final current = currentGrants[_pairKey(profileId, resourceId)];
        if (value == null) {
          if (current != null) {
            final id = WebDavSyncRegistryRecordId.grant(profileId, resourceId);
            nestedDeletes.add(
              SyncedRegistryDeleteRecord(
                record: id,
                expectedPriorUpdatedAtMs: expectedVersion(
                  id,
                  current.updatedAtMs,
                ),
              ),
            );
          }
        } else {
          if (current?.permissions == value.permissions) continue;
          grantRecords.add(
            SyncedRegistryGrantRecord(
              profileId: profileId,
              resourceId: resourceId,
              permissions: value.permissions,
              updatedAtMs: inner.value.stamp.normalizedTimeMs,
              expectedPriorUpdatedAtMs: expectedVersion(
                WebDavSyncRegistryRecordId.grant(profileId, resourceId),
                current?.updatedAtMs,
              ),
            ),
          );
        }
      }
    }
    for (final outer in request.resources.settings.entries) {
      final profileId = maps.circleToLocalProfiles[outer.key];
      if (profileId == null) continue;
      for (final inner in outer.value.entries) {
        final resourceId = maps.circleToLocalResources[inner.key];
        if (resourceId == null) continue;
        final value = inner.value.value;
        final current = currentSettings[_pairKey(profileId, resourceId)];
        if (value == null) {
          if (current != null) {
            final id = WebDavSyncRegistryRecordId.setting(
              profileId,
              resourceId,
            );
            nestedDeletes.add(
              SyncedRegistryDeleteRecord(
                record: id,
                expectedPriorUpdatedAtMs: expectedVersion(
                  id,
                  current.updatedAtMs,
                ),
              ),
            );
          }
        } else {
          if (current != null &&
              current.enabled == value.enabled &&
              WebDavSyncCodec.canonicalJson(current.settings) ==
                  WebDavSyncCodec.canonicalJson(value.settings)) {
            continue;
          }
          settingRecords.add(
            SyncedRegistrySettingsRecord(
              profileId: profileId,
              resourceId: resourceId,
              enabled: value.enabled,
              settings: Map<String, dynamic>.from(value.settings),
              updatedAtMs: inner.value.stamp.normalizedTimeMs,
              expectedPriorUpdatedAtMs: expectedVersion(
                WebDavSyncRegistryRecordId.setting(profileId, resourceId),
                current?.updatedAtMs,
              ),
            ),
          );
        }
      }
    }
    for (final outer in request.resources.bindings.entries) {
      final profileId = maps.circleToLocalProfiles[outer.key];
      if (profileId == null) continue;
      for (final inner in outer.value.entries) {
        final value = inner.value.value;
        final current = currentBindings[_pairKey(profileId, inner.key)];
        if (value == null) {
          if (current != null) {
            final id = WebDavSyncRegistryRecordId.binding(
              profileId,
              inner.key,
              resourceId: current.resourceId,
            );
            nestedDeletes.add(
              SyncedRegistryDeleteRecord(
                record: id,
                expectedPriorUpdatedAtMs: expectedVersion(
                  id,
                  current.updatedAtMs,
                ),
              ),
            );
          }
        } else {
          final resourceId =
              maps.circleToLocalResources[value.circleResourceId];
          if (resourceId == null) {
            throw StateError('Synced binding mapping is unavailable');
          }
          if (current?.resourceId == resourceId) continue;
          bindingRecords.add(
            SyncedRegistryBindingRecord(
              profileId: profileId,
              slot: inner.key,
              resourceId: resourceId,
              updatedAtMs: inner.value.stamp.normalizedTimeMs,
              expectedPriorUpdatedAtMs: expectedVersion(
                WebDavSyncRegistryRecordId.binding(
                  profileId,
                  inner.key,
                  resourceId: resourceId,
                ),
                current?.updatedAtMs,
              ),
            ),
          );
        }
      }
    }
    _validateSession(session);
    if (profileRecords.isEmpty &&
        resourceRecords.isEmpty &&
        grantRecords.isEmpty &&
        settingRecords.isEmpty &&
        bindingRecords.isEmpty &&
        profileDeletes.isEmpty &&
        resourceDeletes.isEmpty &&
        nestedDeletes.isEmpty) {
      return WebDavSyncCircleApplyResult.applied;
    }
    final result = await registry.applySyncedRegistryDelta(
      SyncedRegistryDelta(
        profiles: profileRecords,
        resources: resourceRecords,
        grants: grantRecords,
        settings: settingRecords,
        bindings: bindingRecords,
        deletes: <SyncedRegistryDeleteRecord>[
          ...profileDeletes,
          ...resourceDeletes,
          ...nestedDeletes,
        ],
      ),
    );
    if (result == SyncedRegistryApplyResult.conflict) {
      return WebDavSyncCircleApplyResult.conflict;
    }
    _validateSession(session);

    for (final item in profileRecords) {
      if (item.id != session.scope.profileId) continue;
      final before = prePins[item.id];
      if (!_samePin(before, item.pin)) {
        ProfileLockController.instance.armLockOnNextResume(item.id);
      }
      final refreshed = await registry.getProfile(item.id);
      if (refreshed != null) {
        ProfileLockController.instance.refreshProfileIfCurrent(refreshed);
        MainPageBridge.reloadProfilePolicy?.call();
      }
    }
    return WebDavSyncCircleApplyResult.applied;
  }

  static ProfilePinRecord _localPin(WebDavSyncProfilePin pin) =>
      ProfilePinRecord(
        hash: pin.hash == null ? null : base64Decode(pin.hash!),
        salt: pin.salt == null ? null : base64Decode(pin.salt!),
        paramsJson: pin.paramsJson,
        resetRequired: pin.resetRequired,
        recoveryHash: pin.recoveryHash == null
            ? null
            : base64Decode(pin.recoveryHash!),
        recoverySalt: pin.recoverySalt == null
            ? null
            : base64Decode(pin.recoverySalt!),
        recoveryParamsJson: pin.recoveryParamsJson,
      );

  static bool _samePin(ProfilePinRecord? left, ProfilePinRecord right) =>
      left != null &&
      _sameBytes(left.hash, right.hash) &&
      _sameBytes(left.salt, right.salt) &&
      left.paramsJson == right.paramsJson &&
      left.resetRequired == right.resetRequired &&
      _sameBytes(left.recoveryHash, right.recoveryHash) &&
      _sameBytes(left.recoverySalt, right.recoverySalt) &&
      left.recoveryParamsJson == right.recoveryParamsJson;

  static bool _sameBytes(List<int>? left, List<int>? right) {
    if (left == null || right == null) return left == null && right == null;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _sameSyncedProfile(
    UserProfile current,
    ProfilePinRecord currentPin,
    SyncedRegistryProfileRecord incoming,
  ) {
    final effectiveAvatar =
        incoming.avatarKey ??
        (current.avatarKey?.startsWith('file:') == true
            ? current.avatarKey
            : null);
    return current.name == incoming.name.trim() &&
        current.avatarKey == effectiveAvatar &&
        current.role == incoming.role &&
        current.policy.encode() == incoming.policy.encode() &&
        current.isEnabled == incoming.enabled &&
        current.lockOnResume == incoming.lockOnResume &&
        current.inactivityTimeoutMinutes == incoming.inactivityTimeoutMinutes &&
        current.setupComplete == incoming.setupComplete &&
        current.lifecycle == incoming.lifecycle &&
        _samePin(currentPin, incoming.pin);
  }

  static bool _isManagingAdmin(UserProfile profile) =>
      profile.isEnabled &&
      profile.role == UserProfileRole.admin &&
      profile.policy.allows(profile.role, ProfileFeature.manageProfiles);

  static bool _sameResourceMetadata(
    ConnectionResource current,
    ConnectionResource incoming,
  ) =>
      current.type == incoming.type &&
      current.label == incoming.label &&
      current.ownerProfileId == incoming.ownerProfileId &&
      current.publicSchemaVersion == incoming.publicSchemaVersion &&
      WebDavSyncCodec.canonicalJson(current.publicConfig) ==
          WebDavSyncCodec.canonicalJson(incoming.publicConfig) &&
      current.enabled == incoming.enabled;

  static Future<bool> _localSecretMatches({
    required ProfileRegistry registry,
    required DeviceSecretCipher cipher,
    required String resourceId,
    required WebDavSyncResourceMetadata metadata,
    required String ownerProfileId,
    required WebDavSyncResourceSecretConfig secret,
  }) async {
    try {
      final current = await registry.getSealedResourceSecret(
        resourceId,
        includeDisabled: true,
      );
      if (current == null ||
          current.type != metadata.type ||
          current.ownerProfileId != ownerProfileId ||
          current.publicSchemaVersion != metadata.publicSchemaVersion ||
          current.payloadVersion != secret.payloadVersion) {
        return false;
      }
      final plaintext = await cipher.open(
        current.envelope,
        associatedData: ConnectionResourceService.associatedDataForSecret(
          resourceId: resourceId,
          type: metadata.type,
          ownerProfileId: ownerProfileId,
          publicSchemaVersion: metadata.publicSchemaVersion,
          payloadVersion: secret.payloadVersion,
        ),
      );
      final payload = jsonDecode(utf8.decode(plaintext));
      return payload is Map &&
          semanticDigestOf(payload) == secret.semanticDigest;
    } catch (_) {
      return false;
    }
  }

  static String _pairKey(String first, String second) => '$first\u0000$second';

  static void _validateSession(WebDavSyncLocalSession session) {
    _validateScope(session.scope);
  }

  static void _validateScope(ProfileScope scope) {
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileRuntime.scope.value != scope) {
      throw StateError('Profile session changed during WebDAV sync');
    }
  }

  static void _recordRedactedDiagnostic(String message) {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'resource_secret_leaf_ignored',
      level: DiagnosticLevel.warning,
      fields: <String, Object?>{'reason': DiagnosticLabel(message)},
    );
  }
}

final class _CatalogWireIdentity {
  const _CatalogWireIdentity({
    required this.circleResourceId,
    required this.variant,
  });

  final String circleResourceId;
  final String variant;
}

final class _CatalogWireMappings {
  const _CatalogWireMappings({
    this.byCatalogKey = const <String, _CatalogWireIdentity>{},
    this.byWireResourceVariant = const <String, String>{},
    this.grantedLocalResourceIds = const <String>{},
  });

  final Map<String, _CatalogWireIdentity> byCatalogKey;
  final Map<String, String> byWireResourceVariant;
  final Set<String> grantedLocalResourceIds;
}

String _hiddenGroupWireKey(_CatalogWireIdentity identity, String group) =>
    'catalog/hidden/${identity.circleResourceId}/${identity.variant}/'
    '${_sha256Text(group)}';

String _categoryOrderWireKey(_CatalogWireIdentity identity) =>
    'catalog/category-order/${identity.circleResourceId}/${identity.variant}';

List<String>? _stringVector(Map<String, Object?> value, String key) {
  if (value.length != 1 || value[key] is! List) return null;
  final result = <String>[];
  final seen = <String>{};
  for (final item in value[key]! as List) {
    if (item is! String || item.isEmpty || !seen.add(item)) return null;
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

List<WebDavSyncIptvOrderItem>? _iptvOrderItems(Map<String, Object?> value) {
  if (value.length != 2 ||
      value['group'] is! String ||
      value['items'] is! List) {
    return null;
  }
  final result = <WebDavSyncIptvOrderItem>[];
  final seen = <(String, String, int)>{};
  for (final raw in value['items']! as List) {
    if (raw is! Map) return null;
    final item = Map<String, Object?>.from(raw);
    final url = item['url'];
    final name = item['name'];
    final occurrence = item['occurrence'];
    if (item.length != 3 ||
        url is! String ||
        url.isEmpty ||
        name is! String ||
        occurrence is! int ||
        occurrence < 0 ||
        !seen.add((url, name, occurrence))) {
      return null;
    }
    result.add(
      WebDavSyncIptvOrderItem(url: url, name: name, occurrence: occurrence),
    );
  }
  return List<WebDavSyncIptvOrderItem>.unmodifiable(result);
}

({String name, int position, int createdAtMs})? _iptvListValue(
  Map<String, Object?> value,
) {
  final name = value['name'];
  final position = value['position'];
  final createdAt = value['createdAt'];
  if (value.length != 3 ||
      name is! String ||
      utf8.encode(name).length > 4096 ||
      position is! int ||
      position < 0 ||
      position > 2147383647 ||
      createdAt is! int ||
      createdAt < 0 ||
      createdAt > 0x7fffffffffffffff) {
    return null;
  }
  return (name: name, position: position, createdAtMs: createdAt);
}

bool _validIptvListChannelValue(Map<String, Object?> value) {
  const required = <String>{
    'url',
    'name',
    'logoUrl',
    'group',
    'sourceRef',
    'addedAt',
    'position',
  };
  const allowed = <String>{
    ...required,
    'channelNumber',
    'contentType',
    'duration',
    'httpHeaders',
  };
  if (!value.keys.toSet().containsAll(required) ||
      !value.keys.every(allowed.contains)) {
    return false;
  }
  for (final key in const <String>['url', 'name', 'logoUrl', 'group']) {
    final item = value[key];
    if (item is! String ||
        (key == 'url' && item.isEmpty) ||
        utf8.encode(item).length > 16384) {
      return false;
    }
  }
  final sourceRef = value['sourceRef'];
  if (sourceRef is! String ||
      (sourceRef.isNotEmpty && !_validWireResourceId.hasMatch(sourceRef))) {
    return false;
  }
  final channelNumber = value['channelNumber'];
  if (value.containsKey('channelNumber') &&
      (channelNumber is! int ||
          channelNumber < -0x8000000000000000 ||
          channelNumber > 0x7fffffffffffffff)) {
    return false;
  }
  final contentType = value['contentType'];
  if (value.containsKey('contentType') &&
      (contentType is! String || utf8.encode(contentType).length > 256)) {
    return false;
  }
  final duration = value['duration'];
  if (value.containsKey('duration') &&
      (duration is! int ||
          duration < -0x8000000000000000 ||
          duration > 0x7fffffffffffffff)) {
    return false;
  }
  for (final key in const <String>['addedAt', 'position']) {
    final item = value[key];
    if (item is! int || item < 0 || item > 0x7fffffffffffffff) return false;
  }
  final headers = value['httpHeaders'];
  if (value.containsKey('httpHeaders')) {
    if (headers is! Map || headers.isEmpty) return false;
    for (final entry in headers.entries) {
      if (entry.key is! String || entry.value is! String) return false;
    }
  }
  return true;
}

bool _validWatchValue(Map<String, Object?> value) {
  if (value['url'] is! String ||
      (value['url']! as String).isEmpty ||
      value['name'] is! String ||
      value['logoUrl'] is! String ||
      value['group'] is! String ||
      value['lastPlayedAt'] is! int) {
    return false;
  }
  for (final key in const <String>['seriesId', 'seriesName']) {
    if (value[key] != null && value[key] is! String) return false;
  }
  for (final key in const <String>['season', 'episode']) {
    if (value[key] != null && value[key] is! int) return false;
  }
  if (value['hasNext'] != null && value['hasNext'] is! bool) return false;
  final headers = value['headers'];
  if (headers != null) {
    if (headers is! Map) return false;
    for (final entry in headers.entries) {
      if (entry.key is! String || entry.value is! String) return false;
    }
  }
  return true;
}

bool _validResumeValue(Map<String, Object?> value) {
  final speed = value['speed'];
  return value.length == 5 &&
      value['resumeKey'] is String &&
      (value['resumeKey']! as String).isNotEmpty &&
      value['position'] is int &&
      (value['position']! as int) >= 0 &&
      value['duration'] is int &&
      (value['duration']! as int) >= 0 &&
      speed is num &&
      speed.isFinite &&
      value['aspectRatio'] is String;
}

({
  String name,
  bool avoidNsfw,
  int channelNumber,
  int createdAtMs,
  List<String> keywords,
})?
_tvChannelValue(Map<String, Object?> value) {
  final name = value['name'];
  final avoidNsfw = value['avoidNsfw'];
  final channelNumber = value['channelNumber'];
  final createdAt = value['createdAt'];
  final keywords = _boundedStringList(value['keywords']);
  if (value.length != 5 ||
      name is! String ||
      name.isEmpty ||
      utf8.encode(name).length > 4096 ||
      avoidNsfw is! bool ||
      channelNumber is! int ||
      channelNumber <= 0 ||
      channelNumber > 2147383647 ||
      createdAt is! int ||
      createdAt < 0 ||
      createdAt > 0x7fffffffffffffff ||
      keywords == null) {
    return null;
  }
  return (
    name: name,
    avoidNsfw: avoidNsfw,
    channelNumber: channelNumber,
    createdAtMs: createdAt,
    keywords: keywords,
  );
}

({
  String generationId,
  String name,
  int sizeBytes,
  List<String> keywords,
  int rank,
})?
_tvPoolValue(Map<String, Object?> value) {
  final generationId = value['generationId'];
  final name = value['name'];
  final sizeBytes = value['sizeBytes'];
  final keywords = _boundedStringList(value['keywords']);
  final rank = value['rank'];
  if (value.length != 5 ||
      generationId is! String ||
      !_validGenerationId.hasMatch(generationId) ||
      name is! String ||
      name.isEmpty ||
      utf8.encode(name).length > 16384 ||
      sizeBytes is! int ||
      sizeBytes < 0 ||
      sizeBytes > 0x7fffffffffffffff ||
      keywords == null ||
      rank is! int ||
      rank < 0 ||
      rank >= WebDavSyncLibraryDocument.maxLeaves) {
    return null;
  }
  return (
    generationId: generationId,
    name: name,
    sizeBytes: sizeBytes,
    keywords: keywords,
    rank: rank,
  );
}

List<String>? _boundedStringList(Object? source) {
  if (source is! List || source.length > WebDavSyncLibraryDocument.maxLeaves) {
    return null;
  }
  final result = <String>[];
  for (final value in source) {
    if (value is! String || value.isEmpty || utf8.encode(value).length > 4096) {
      return null;
    }
    result.add(value);
  }
  return List<String>.unmodifiable(result);
}

String? _decodeCanonicalBase64Part(String source) {
  try {
    final decoded = WebDavSyncRecordKey.decodePart(source);
    return decoded.isNotEmpty &&
            utf8.encode(decoded).length <= 256 &&
            !decoded.contains('\u0000') &&
            _base64Part(decoded) == source
        ? decoded
        : null;
  } on FormatException {
    return null;
  }
}

String _sha256Text(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();

String _base64Part(String value) =>
    base64UrlEncode(utf8.encode(value)).replaceAll('=', '');

final RegExp _validGenerationId = RegExp(r'^[A-Za-z0-9_-]{1,96}$');
final RegExp _validInfohash = RegExp(r'^[a-z0-9]{1,128}$');
const int _maxIptvListMemberHeaderBytes = 2048;
final RegExp _validIptvListId = RegExp(r'^list_[0-9]+_[A-Za-z0-9_-]+$');
final RegExp _validWireResourceId = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$',
);
