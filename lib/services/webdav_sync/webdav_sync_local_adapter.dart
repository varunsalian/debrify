import 'dart:convert';

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
import 'webdav_sync_active_profile_refresh.dart';
import 'webdav_sync_circle_merge.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_hot_merge.dart';
import 'webdav_sync_hot_models.dart';
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

/// ProfilePreferences-backed adapter used once M5 arms the engine.
final class ProfileWebDavSyncLocalAdapter
    implements
        WebDavSyncLocalAdapter,
        WebDavSyncCircleLocalAdapter,
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
