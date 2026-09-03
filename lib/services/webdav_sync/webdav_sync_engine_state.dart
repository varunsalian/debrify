import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../utils/app_storage.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_adoption_models.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_clock.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_transport.dart';

final class WebDavSyncPendingApply {
  const WebDavSyncPendingApply({
    required this.localProfileId,
    required this.values,
    required this.target,
  });

  final String localProfileId;
  final Map<String, Object> values;
  final WebDavSyncHotDocument target;

  Map<String, Object?> toJson() => <String, Object?>{
    'localProfileId': localProfileId,
    'values': values,
    'target': target.toJson(),
  };

  factory WebDavSyncPendingApply.fromJson(Object? source) {
    final json = _map(source, 'pending apply');
    final localProfileId = json['localProfileId'];
    final rawValues = json['values'];
    if (localProfileId is! String ||
        !_safeSyncIdentifier.hasMatch(localProfileId) ||
        rawValues is! Map ||
        rawValues.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Invalid WebDAV sync pending apply');
    }
    final values = <String, Object>{};
    for (final entry in rawValues.entries) {
      if (entry.key is! String ||
          entry.key.isEmpty ||
          utf8.encode(entry.key as String).length >
              WebDavSyncLimits.maxLogicalKeyBytes ||
          entry.value == null) {
        throw const FormatException('Invalid WebDAV sync pending value');
      }
      final value = entry.value;
      if (value is double && !value.isFinite) {
        throw const FormatException('Invalid WebDAV sync pending value');
      }
      if (value is! bool &&
          value is! int &&
          value is! double &&
          value is! String &&
          !(value is List && value.every((item) => item is String))) {
        throw const FormatException('Invalid WebDAV sync pending value');
      }
      values[entry.key as String] = value is List
          ? List<String>.unmodifiable(value.cast<String>())
          : value as Object;
    }
    return WebDavSyncPendingApply(
      localProfileId: localProfileId,
      values: Map<String, Object>.unmodifiable(values),
      target: WebDavSyncHotDocument.fromJson(json['target']),
    );
  }
}

final class WebDavSyncPendingCircleApply {
  const WebDavSyncPendingCircleApply({
    required this.profiles,
    required this.resources,
    this.registryVersions = const WebDavSyncRegistryVersionSnapshot(),
  });

  final WebDavSyncProfilesDocument profiles;
  final WebDavSyncResourcesDocument resources;
  final WebDavSyncRegistryVersionSnapshot registryVersions;

  Map<String, Object?> toJson() => <String, Object?>{
    'profiles': profiles.toJson(),
    'resources': resources.toJson(),
    if (registryVersions.enforce ||
        registryVersions.updatedAtMsByRecord.isNotEmpty)
      'registryVersions': registryVersions.toJson(),
  };

  factory WebDavSyncPendingCircleApply.fromJson(Object? source) {
    final json = _map(source, 'pending circle apply');
    if (json.length < 2 ||
        json.length > 3 ||
        !json.containsKey('profiles') ||
        !json.containsKey('resources') ||
        json.keys.any(
          (key) =>
              key != 'profiles' &&
              key != 'resources' &&
              key != 'registryVersions',
        )) {
      throw const FormatException('Invalid WebDAV sync pending circle apply');
    }
    return WebDavSyncPendingCircleApply(
      profiles: WebDavSyncProfilesDocument.fromJson(json['profiles']),
      resources: WebDavSyncResourcesDocument.fromJson(json['resources']),
      registryVersions: WebDavSyncRegistryVersionSnapshot.fromJson(
        json['registryVersions'],
      ),
    );
  }
}

/// The row timestamps observed by the transactionally consistent registry
/// projection used to build a circle section. Missing keys mean the row was
/// absent. The snapshot is journaled with a pending apply so crash replay uses
/// the same optimistic-concurrency evidence as the original attempt.
final class WebDavSyncRegistryVersionSnapshot {
  const WebDavSyncRegistryVersionSnapshot({
    this.updatedAtMsByRecord = const <String, int>{},
    this.enforce = false,
  });

  final Map<String, int> updatedAtMsByRecord;
  final bool enforce;

  int? expectedUpdatedAtMs(String recordStorageKey) =>
      updatedAtMsByRecord[recordStorageKey];

  Map<String, Object?> toJson() => <String, Object?>{
    'updatedAtMsByRecord': updatedAtMsByRecord,
    'enforce': enforce,
  };

  factory WebDavSyncRegistryVersionSnapshot.fromJson(Object? source) {
    if (source == null) {
      return const WebDavSyncRegistryVersionSnapshot(enforce: true);
    }
    final json = _map(source, 'registry version snapshot');
    if (json.length != 2 ||
        !json.containsKey('updatedAtMsByRecord') ||
        json['enforce'] is! bool) {
      throw const FormatException('Invalid registry version snapshot');
    }
    final raw = json['updatedAtMsByRecord'];
    if (raw is! Map ||
        raw.length >
            WebDavSyncLimits.maxRecordsPerHotDocument +
                WebDavSyncLimits.maxMapEntries) {
      throw const FormatException('Invalid registry version snapshot');
    }
    final versions = <String, int>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          utf8.encode(entry.key as String).length > 512 ||
          entry.value is! int ||
          (entry.value as int) < 0 ||
          (entry.value as int) > WebDavSyncLimits.maxTimestampMs) {
        throw const FormatException('Invalid registry version snapshot');
      }
      versions[entry.key as String] = entry.value as int;
    }
    return WebDavSyncRegistryVersionSnapshot(
      updatedAtMsByRecord: Map<String, int>.unmodifiable(versions),
      enforce: json['enforce']! as bool,
    );
  }
}

enum WebDavSyncPendingActiveProfileReason { deleted, disabled }

/// Durable handoff for a merged profile value which cannot be applied while
/// that profile owns the active runtime session.
final class WebDavSyncPendingActiveProfile {
  const WebDavSyncPendingActiveProfile({
    required this.localProfileId,
    required this.reason,
    this.circleProfileId,
    this.profileLeaf,
    this.expectedPriorUpdatedAtMs,
  });

  const WebDavSyncPendingActiveProfile.legacyDeletion(this.localProfileId)
    : reason = WebDavSyncPendingActiveProfileReason.deleted,
      circleProfileId = null,
      profileLeaf = null,
      expectedPriorUpdatedAtMs = null;

  final String localProfileId;
  final WebDavSyncPendingActiveProfileReason reason;
  final String? circleProfileId;
  final WebDavSyncCircleLeaf<WebDavSyncProfileValue>? profileLeaf;
  final int? expectedPriorUpdatedAtMs;

  bool get isLegacyDeletion =>
      reason == WebDavSyncPendingActiveProfileReason.deleted &&
      circleProfileId == null &&
      profileLeaf == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'localProfileId': localProfileId,
    'reason': reason.name,
    if (circleProfileId != null) 'circleProfileId': circleProfileId,
    if (profileLeaf != null)
      'profileLeaf': profileLeaf!.toJson((value) => value.toJson()),
    if (expectedPriorUpdatedAtMs != null)
      'expectedPriorUpdatedAtMs': expectedPriorUpdatedAtMs,
  };

  factory WebDavSyncPendingActiveProfile.fromJson(Object? source) {
    final json = _map(source, 'pending active profile');
    final localProfileId = json['localProfileId'];
    final rawReason = json['reason'];
    final circleProfileId = json['circleProfileId'];
    final rawLeaf = json['profileLeaf'];
    final expectedPriorUpdatedAtMs = json['expectedPriorUpdatedAtMs'];
    if (json.length < 2 ||
        json.length > 5 ||
        localProfileId is! String ||
        !_safeSyncIdentifier.hasMatch(localProfileId) ||
        rawReason is! String ||
        (circleProfileId != null &&
            (circleProfileId is! String ||
                !_safeSyncIdentifier.hasMatch(circleProfileId))) ||
        (rawLeaf == null) != (circleProfileId == null) ||
        (expectedPriorUpdatedAtMs != null &&
            (expectedPriorUpdatedAtMs is! int ||
                expectedPriorUpdatedAtMs < 0 ||
                expectedPriorUpdatedAtMs > WebDavSyncLimits.maxTimestampMs))) {
      throw const FormatException('Invalid WebDAV sync pending active profile');
    }
    late final WebDavSyncPendingActiveProfileReason reason;
    try {
      reason = WebDavSyncPendingActiveProfileReason.values.byName(rawReason);
    } on ArgumentError {
      throw const FormatException('Invalid WebDAV sync pending active profile');
    }
    WebDavSyncCircleLeaf<WebDavSyncProfileValue>? leaf;
    if (circleProfileId != null) {
      leaf = WebDavSyncProfilesDocument.fromJson(<String, Object?>{
        'version': WebDavSyncProfilesDocument.schemaVersion,
        'profiles': <String, Object?>{circleProfileId: rawLeaf},
      }).profiles[circleProfileId];
      if ((reason == WebDavSyncPendingActiveProfileReason.deleted) !=
          (leaf?.value == null)) {
        throw const FormatException(
          'Invalid WebDAV sync pending active profile reason',
        );
      }
    }
    return WebDavSyncPendingActiveProfile(
      localProfileId: localProfileId,
      reason: reason,
      circleProfileId: circleProfileId as String?,
      profileLeaf: leaf,
      expectedPriorUpdatedAtMs: expectedPriorUpdatedAtMs as int?,
    );
  }
}

final class WebDavSyncProfileEngineState {
  const WebDavSyncProfileEngineState({
    this.baseline,
    this.pendingApply,
    this.tombstones = const <String, WebDavSyncTombstone>{},
    this.lastPushedHotDigest,
    this.lastPushedTombstoneDigest,
  });

  final WebDavSyncHotDocument? baseline;
  final WebDavSyncPendingApply? pendingApply;
  final Map<String, WebDavSyncTombstone> tombstones;
  final String? lastPushedHotDigest;
  final String? lastPushedTombstoneDigest;

  WebDavSyncProfileEngineState copyWith({
    WebDavSyncHotDocument? baseline,
    WebDavSyncPendingApply? pendingApply,
    bool clearPendingApply = false,
    Map<String, WebDavSyncTombstone>? tombstones,
    String? lastPushedHotDigest,
    bool clearLastPushedHotDigest = false,
    String? lastPushedTombstoneDigest,
    bool clearLastPushedTombstoneDigest = false,
  }) => WebDavSyncProfileEngineState(
    baseline: baseline ?? this.baseline,
    pendingApply: clearPendingApply
        ? null
        : (pendingApply ?? this.pendingApply),
    tombstones: tombstones ?? this.tombstones,
    lastPushedHotDigest: clearLastPushedHotDigest
        ? null
        : (lastPushedHotDigest ?? this.lastPushedHotDigest),
    lastPushedTombstoneDigest: clearLastPushedTombstoneDigest
        ? null
        : (lastPushedTombstoneDigest ?? this.lastPushedTombstoneDigest),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (pendingApply != null) 'pendingApply': pendingApply!.toJson(),
    'tombstones': <String, Object?>{
      for (final entry in tombstones.entries)
        entry.key: <String, Object?>{
          ...entry.value.toJson(),
          if (entry.value.rawLocalTime) 'rawLocalTime': true,
        },
    },
    if (lastPushedHotDigest != null) 'lastPushedHotDigest': lastPushedHotDigest,
    if (lastPushedTombstoneDigest != null)
      'lastPushedTombstoneDigest': lastPushedTombstoneDigest,
  };

  factory WebDavSyncProfileEngineState.fromJson(Object? source) {
    if (source == null) return const WebDavSyncProfileEngineState();
    final json = _map(source, 'profile engine state');
    final rawTombstones = json['tombstones'];
    if (rawTombstones is! Map ||
        rawTombstones.length > WebDavSyncLimits.maxTombstonesPerProfile) {
      throw const FormatException('Invalid WebDAV sync tombstone state');
    }
    final tombstones = <String, WebDavSyncTombstone>{};
    for (final entry in rawTombstones.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid WebDAV sync tombstone state');
      }
      final itemJson = Map<String, dynamic>.from(entry.value as Map);
      final rawLocal = itemJson.remove('rawLocalTime') == true;
      final item = WebDavSyncTombstone.fromJson(itemJson);
      if (item.key != entry.key) {
        throw const FormatException('WebDAV sync tombstone key mismatch');
      }
      tombstones[entry.key as String] = item.copyWith(rawLocalTime: rawLocal);
    }
    String? digest(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw const FormatException('Invalid WebDAV sync engine digest');
      }
      return value;
    }

    return WebDavSyncProfileEngineState(
      baseline: json['baseline'] == null
          ? null
          : WebDavSyncHotDocument.fromJson(json['baseline']),
      pendingApply: json['pendingApply'] == null
          ? null
          : WebDavSyncPendingApply.fromJson(json['pendingApply']),
      tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(tombstones),
      lastPushedHotDigest: digest('lastPushedHotDigest'),
      lastPushedTombstoneDigest: digest('lastPushedTombstoneDigest'),
    );
  }
}

final class WebDavSyncEngineState {
  const WebDavSyncEngineState({
    this.circleToLocalProfiles,
    this.circleToLocalResources,
    this.clock = const WebDavSyncClockState(),
    this.deviceClockWarning = false,
    this.lastClockPauseReason,
    this.profiles = const <String, WebDavSyncProfileEngineState>{},
    this.pendingLocalProfiles = const <String, WebDavSyncProfileEngineState>{},
    this.circleProfilesBaseline,
    this.circleResourcesBaseline,
    this.pendingCircleApply,
    this.lastPushedProfilesDigest,
    this.lastPushedResourcesDigest,
    this.pendingActiveProfile,
    this.pendingAdminSafetyProfile,
    this.statusHint,
    this.peerManifestHighWater = const <String, int>{},
    this.peerManifestValidators = const <String, WebDavSyncManifestValidator>{},
    this.currentDeviceIds = const <String>{},
    this.lastSuccessfulSyncMs,
    this.lastPushMs,
    this.lastRemoteChangeMs,
    this.ownManifest,
    this.schemaRatchet = 1,
    this.lastBootstrapCheckMs,
    this.publishedBootstrapDatabaseDigest,
    this.adoption,
    this.prunePendingProfileIds = const <String>{},
    this.safetyProtectedProfileIds = const <String>{},
  });

  final Map<String, String>? circleToLocalProfiles;
  final Map<String, String>? circleToLocalResources;
  final WebDavSyncClockState clock;
  final bool deviceClockWarning;
  final WebDavSyncClockPauseReason? lastClockPauseReason;
  final Map<String, WebDavSyncProfileEngineState> profiles;
  final Map<String, WebDavSyncProfileEngineState> pendingLocalProfiles;
  final WebDavSyncProfilesDocument? circleProfilesBaseline;
  final WebDavSyncResourcesDocument? circleResourcesBaseline;
  final WebDavSyncPendingCircleApply? pendingCircleApply;
  final String? lastPushedProfilesDigest;
  final String? lastPushedResourcesDigest;
  final WebDavSyncPendingActiveProfile? pendingActiveProfile;

  /// Compatibility view for callers which only need the deferred local ID.
  String? get pendingActiveProfileDeletion =>
      pendingActiveProfile?.localProfileId;
  final String? pendingAdminSafetyProfile;
  final String? statusHint;
  final Map<String, int> peerManifestHighWater;
  final Map<String, WebDavSyncManifestValidator> peerManifestValidators;
  final Set<String> currentDeviceIds;
  final int? lastSuccessfulSyncMs;
  final int? lastPushMs;
  final int? lastRemoteChangeMs;
  final WebDavSyncManifest? ownManifest;
  final int schemaRatchet;
  final int? lastBootstrapCheckMs;
  final String? publishedBootstrapDatabaseDigest;
  final WebDavSyncAdoptionRecord? adoption;
  final Set<String> prunePendingProfileIds;
  final Set<String> safetyProtectedProfileIds;

  bool get blocksAllPushes => adoption?.blocksPushes ?? false;
  bool get blocksSeedPushes =>
      blocksAllPushes || prunePendingProfileIds.isNotEmpty;

  bool get hasAuthenticatedMaps =>
      circleToLocalProfiles != null && circleToLocalResources != null;

  WebDavSyncEngineState copyWith({
    Map<String, String>? circleToLocalProfiles,
    Map<String, String>? circleToLocalResources,
    WebDavSyncClockState? clock,
    bool? deviceClockWarning,
    WebDavSyncClockPauseReason? lastClockPauseReason,
    bool clearClockPauseReason = false,
    Map<String, WebDavSyncProfileEngineState>? profiles,
    Map<String, WebDavSyncProfileEngineState>? pendingLocalProfiles,
    WebDavSyncProfilesDocument? circleProfilesBaseline,
    WebDavSyncResourcesDocument? circleResourcesBaseline,
    WebDavSyncPendingCircleApply? pendingCircleApply,
    bool clearPendingCircleApply = false,
    String? lastPushedProfilesDigest,
    bool clearLastPushedProfilesDigest = false,
    String? lastPushedResourcesDigest,
    bool clearLastPushedResourcesDigest = false,
    WebDavSyncPendingActiveProfile? pendingActiveProfile,
    bool clearPendingActiveProfileDeletion = false,
    String? pendingAdminSafetyProfile,
    bool clearPendingAdminSafetyProfile = false,
    String? statusHint,
    bool clearStatusHint = false,
    Map<String, int>? peerManifestHighWater,
    Map<String, WebDavSyncManifestValidator>? peerManifestValidators,
    Set<String>? currentDeviceIds,
    int? lastSuccessfulSyncMs,
    int? lastPushMs,
    int? lastRemoteChangeMs,
    WebDavSyncManifest? ownManifest,
    int? schemaRatchet,
    int? lastBootstrapCheckMs,
    String? publishedBootstrapDatabaseDigest,
    WebDavSyncAdoptionRecord? adoption,
    bool clearAdoption = false,
    Set<String>? prunePendingProfileIds,
    Set<String>? safetyProtectedProfileIds,
  }) => WebDavSyncEngineState(
    circleToLocalProfiles: circleToLocalProfiles ?? this.circleToLocalProfiles,
    circleToLocalResources:
        circleToLocalResources ?? this.circleToLocalResources,
    clock: clock ?? this.clock,
    deviceClockWarning: deviceClockWarning ?? this.deviceClockWarning,
    lastClockPauseReason: clearClockPauseReason
        ? null
        : (lastClockPauseReason ?? this.lastClockPauseReason),
    profiles: profiles ?? this.profiles,
    pendingLocalProfiles: pendingLocalProfiles ?? this.pendingLocalProfiles,
    circleProfilesBaseline:
        circleProfilesBaseline ?? this.circleProfilesBaseline,
    circleResourcesBaseline:
        circleResourcesBaseline ?? this.circleResourcesBaseline,
    pendingCircleApply: clearPendingCircleApply
        ? null
        : (pendingCircleApply ?? this.pendingCircleApply),
    lastPushedProfilesDigest: clearLastPushedProfilesDigest
        ? null
        : (lastPushedProfilesDigest ?? this.lastPushedProfilesDigest),
    lastPushedResourcesDigest: clearLastPushedResourcesDigest
        ? null
        : (lastPushedResourcesDigest ?? this.lastPushedResourcesDigest),
    pendingActiveProfile: clearPendingActiveProfileDeletion
        ? null
        : (pendingActiveProfile ?? this.pendingActiveProfile),
    pendingAdminSafetyProfile: clearPendingAdminSafetyProfile
        ? null
        : (pendingAdminSafetyProfile ?? this.pendingAdminSafetyProfile),
    statusHint: clearStatusHint ? null : (statusHint ?? this.statusHint),
    peerManifestHighWater: peerManifestHighWater ?? this.peerManifestHighWater,
    peerManifestValidators:
        peerManifestValidators ?? this.peerManifestValidators,
    currentDeviceIds: currentDeviceIds ?? this.currentDeviceIds,
    lastSuccessfulSyncMs: lastSuccessfulSyncMs ?? this.lastSuccessfulSyncMs,
    lastPushMs: lastPushMs ?? this.lastPushMs,
    lastRemoteChangeMs: lastRemoteChangeMs ?? this.lastRemoteChangeMs,
    ownManifest: ownManifest ?? this.ownManifest,
    schemaRatchet: schemaRatchet ?? this.schemaRatchet,
    lastBootstrapCheckMs: lastBootstrapCheckMs ?? this.lastBootstrapCheckMs,
    publishedBootstrapDatabaseDigest:
        publishedBootstrapDatabaseDigest ??
        this.publishedBootstrapDatabaseDigest,
    adoption: clearAdoption ? null : (adoption ?? this.adoption),
    prunePendingProfileIds:
        prunePendingProfileIds ?? this.prunePendingProfileIds,
    safetyProtectedProfileIds:
        safetyProtectedProfileIds ?? this.safetyProtectedProfileIds,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    if (circleToLocalProfiles != null)
      'circleToLocalProfiles': circleToLocalProfiles,
    if (circleToLocalResources != null)
      'circleToLocalResources': circleToLocalResources,
    'clock': clock.toJson(),
    if (deviceClockWarning) 'deviceClockWarning': true,
    if (lastClockPauseReason != null)
      'lastClockPauseReason': lastClockPauseReason!.name,
    'profiles': <String, Object?>{
      for (final entry in profiles.entries) entry.key: entry.value.toJson(),
    },
    if (pendingLocalProfiles.isNotEmpty)
      'pendingLocalProfiles': <String, Object?>{
        for (final entry in pendingLocalProfiles.entries)
          entry.key: entry.value.toJson(),
      },
    if (circleProfilesBaseline != null)
      'circleProfilesBaseline': circleProfilesBaseline!.toJson(),
    if (circleResourcesBaseline != null)
      'circleResourcesBaseline': circleResourcesBaseline!.toJson(),
    if (pendingCircleApply != null)
      'pendingCircleApply': pendingCircleApply!.toJson(),
    if (lastPushedProfilesDigest != null)
      'lastPushedProfilesDigest': lastPushedProfilesDigest,
    if (lastPushedResourcesDigest != null)
      'lastPushedResourcesDigest': lastPushedResourcesDigest,
    if (pendingActiveProfile != null)
      'pendingActiveProfile': pendingActiveProfile!.toJson(),
    if (pendingAdminSafetyProfile != null)
      'pendingAdminSafetyProfile': pendingAdminSafetyProfile,
    if (statusHint != null) 'statusHint': statusHint,
    'peerManifestHighWater': peerManifestHighWater,
    if (peerManifestValidators.isNotEmpty)
      'peerManifestValidators': <String, Object?>{
        for (final entry in peerManifestValidators.entries)
          entry.key: entry.value.toJson(),
      },
    if (currentDeviceIds.isNotEmpty)
      'currentDeviceIds': currentDeviceIds.toList()..sort(),
    if (lastSuccessfulSyncMs != null)
      'lastSuccessfulSyncMs': lastSuccessfulSyncMs,
    if (lastPushMs != null) 'lastPushMs': lastPushMs,
    if (lastRemoteChangeMs != null) 'lastRemoteChangeMs': lastRemoteChangeMs,
    if (ownManifest != null) 'ownManifest': ownManifest!.toJson(),
    'schemaRatchet': schemaRatchet,
    if (lastBootstrapCheckMs != null)
      'lastBootstrapCheckMs': lastBootstrapCheckMs,
    if (publishedBootstrapDatabaseDigest != null)
      'publishedBootstrapDatabaseDigest': publishedBootstrapDatabaseDigest,
    if (adoption != null) 'adoption': adoption!.toJson(),
    'prunePendingProfileIds': prunePendingProfileIds.toList()..sort(),
    if (safetyProtectedProfileIds.isNotEmpty)
      'safetyProtectedProfileIds': safetyProtectedProfileIds.toList()..sort(),
  };

  factory WebDavSyncEngineState.fromJson(Object? source) {
    if (source == null) return const WebDavSyncEngineState();
    final json = _map(source, 'engine state');
    if (json['version'] != 1 ||
        json['profiles'] is! Map ||
        json['peerManifestHighWater'] is! Map) {
      throw const FormatException('Unsupported WebDAV sync engine state');
    }
    final rawProfiles = json['profiles'] as Map;
    final rawPendingLocalProfiles =
        json['pendingLocalProfiles'] ?? const <String, Object?>{};
    final rawPeerHighWater = json['peerManifestHighWater'] as Map;
    final rawPeerValidators =
        json['peerManifestValidators'] ?? const <String, Object?>{};
    if (rawProfiles.length > WebDavSyncLimits.maxMapEntries ||
        rawPendingLocalProfiles is! Map ||
        rawPendingLocalProfiles.length > WebDavSyncLimits.maxMapEntries ||
        rawPeerHighWater.length > WebDavSyncLimits.maxMapEntries ||
        rawPeerValidators is! Map ||
        rawPeerValidators.length > WebDavSyncLimits.maxMapEntries) {
      throw const FormatException('WebDAV sync engine state exceeds its limit');
    }
    Map<String, String>? optionalMap(String key, {required int maxEntries}) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! Map || raw.length > maxEntries) {
        throw const FormatException('Invalid WebDAV sync identity map');
      }
      final result = <String, String>{};
      for (final entry in raw.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            !_safeSyncIdentifier.hasMatch(entry.key as String) ||
            !_safeSyncIdentifier.hasMatch(entry.value as String)) {
          throw const FormatException('Invalid WebDAV sync identity map');
        }
        result[entry.key as String] = entry.value as String;
      }
      return Map<String, String>.unmodifiable(result);
    }

    final profiles = <String, WebDavSyncProfileEngineState>{};
    for (final entry in rawProfiles.entries) {
      if (entry.key is! String ||
          !_safeSyncIdentifier.hasMatch(entry.key as String) ||
          entry.value is! Map) {
        throw const FormatException('Invalid WebDAV sync profile state');
      }
      profiles[entry.key as String] = WebDavSyncProfileEngineState.fromJson(
        entry.value,
      );
    }
    final peerHighWater = <String, int>{};
    for (final entry in rawPeerHighWater.entries) {
      if (entry.key is! String ||
          !_safeSyncIdentifier.hasMatch(entry.key as String) ||
          entry.value is! int ||
          entry.value < 0 ||
          entry.value > WebDavSyncLimits.maxTimestampMs) {
        throw const FormatException('Invalid WebDAV sync peer high-water');
      }
      peerHighWater[entry.key as String] = entry.value as int;
    }
    final peerValidators = <String, WebDavSyncManifestValidator>{};
    for (final entry in rawPeerValidators.entries) {
      if (entry.key is! String ||
          !_safeSyncIdentifier.hasMatch(entry.key as String)) {
        throw const FormatException('Invalid WebDAV manifest validator state');
      }
      peerValidators[entry.key as String] =
          WebDavSyncManifestValidator.fromJson(entry.value);
    }
    final pendingLocalProfiles = <String, WebDavSyncProfileEngineState>{};
    for (final entry in rawPendingLocalProfiles.entries) {
      if (entry.key is! String ||
          !_safeSyncIdentifier.hasMatch(entry.key as String)) {
        throw const FormatException(
          'Invalid WebDAV sync pending local profile state',
        );
      }
      final profile = WebDavSyncProfileEngineState.fromJson(entry.value);
      if (profile.baseline != null ||
          profile.pendingApply != null ||
          profile.lastPushedHotDigest != null ||
          profile.lastPushedTombstoneDigest != null) {
        throw const FormatException(
          'Invalid WebDAV sync pending local profile state',
        );
      }
      pendingLocalProfiles[entry.key as String] = profile;
    }
    final successful = json['lastSuccessfulSyncMs'];

    String? circleDigest(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw const FormatException('Invalid WebDAV sync circle digest');
      }
      return value;
    }

    final rawPendingActiveProfile = json['pendingActiveProfile'];
    final legacyPendingActiveProfileDeletion =
        json['pendingActiveProfileDeletion'];
    if (rawPendingActiveProfile != null &&
        legacyPendingActiveProfileDeletion != null) {
      throw const FormatException(
        'Invalid WebDAV sync pending active profile state',
      );
    }
    final WebDavSyncPendingActiveProfile? pendingActiveProfile;
    if (rawPendingActiveProfile != null) {
      pendingActiveProfile = WebDavSyncPendingActiveProfile.fromJson(
        rawPendingActiveProfile,
      );
    } else if (legacyPendingActiveProfileDeletion != null) {
      if (legacyPendingActiveProfileDeletion is! String ||
          !_safeSyncIdentifier.hasMatch(legacyPendingActiveProfileDeletion)) {
        throw const FormatException(
          'Invalid WebDAV sync pending active profile deletion',
        );
      }
      pendingActiveProfile = WebDavSyncPendingActiveProfile.legacyDeletion(
        legacyPendingActiveProfileDeletion,
      );
    } else {
      pendingActiveProfile = null;
    }
    final pendingAdminSafetyProfile = json['pendingAdminSafetyProfile'];
    if (pendingAdminSafetyProfile != null &&
        (pendingAdminSafetyProfile is! String ||
            !_safeSyncIdentifier.hasMatch(pendingAdminSafetyProfile))) {
      throw const FormatException(
        'Invalid WebDAV sync pending Admin safety profile',
      );
    }
    final statusHint = json['statusHint'];
    if (statusHint != null &&
        (statusHint is! String ||
            statusHint.isEmpty ||
            utf8.encode(statusHint).length > 2048)) {
      throw const FormatException('Invalid WebDAV sync status hint');
    }
    if (successful != null &&
        (successful is! int ||
            successful < 0 ||
            successful > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException('Invalid WebDAV sync success timestamp');
    }
    final lastPush = json['lastPushMs'];
    if (lastPush != null &&
        (lastPush is! int ||
            lastPush < 0 ||
            lastPush > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException('Invalid WebDAV sync push timestamp');
    }
    final lastRemoteChange = json['lastRemoteChangeMs'];
    if (lastRemoteChange != null &&
        (lastRemoteChange is! int ||
            lastRemoteChange < 0 ||
            lastRemoteChange > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException(
        'Invalid WebDAV sync remote-change timestamp',
      );
    }
    final deviceClockWarning = json['deviceClockWarning'] ?? false;
    if (deviceClockWarning is! bool) {
      throw const FormatException('Invalid WebDAV sync clock warning');
    }
    final rawClockPauseReason = json['lastClockPauseReason'];
    WebDavSyncClockPauseReason? lastClockPauseReason;
    if (rawClockPauseReason != null) {
      if (rawClockPauseReason is! String) {
        throw const FormatException('Invalid WebDAV sync clock pause reason');
      }
      try {
        lastClockPauseReason = WebDavSyncClockPauseReason.values.byName(
          rawClockPauseReason,
        );
      } on ArgumentError {
        throw const FormatException('Invalid WebDAV sync clock pause reason');
      }
    }
    final schemaRatchet = json['schemaRatchet'] ?? 1;
    if (schemaRatchet is! int ||
        schemaRatchet < 1 ||
        schemaRatchet > 0x7fffffff) {
      throw const FormatException('Invalid WebDAV sync schema ratchet');
    }
    final appliedGraphDigest = json['appliedGraphDigest'];
    if (appliedGraphDigest != null &&
        (appliedGraphDigest is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(appliedGraphDigest))) {
      throw const FormatException('Invalid WebDAV sync applied graph digest');
    }
    final pendingGraphDigest = json['pendingGraphDigest'];
    if (pendingGraphDigest != null &&
        (pendingGraphDigest is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(pendingGraphDigest))) {
      throw const FormatException('Invalid WebDAV sync pending graph digest');
    }
    final lastGraphCheckMs = json['lastGraphCheckMs'];
    if (lastGraphCheckMs != null &&
        (lastGraphCheckMs is! int ||
            lastGraphCheckMs < 0 ||
            lastGraphCheckMs > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException('Invalid WebDAV sync graph check time');
    }
    final lastBootstrapCheckMs = json['lastBootstrapCheckMs'];
    if (lastBootstrapCheckMs != null &&
        (lastBootstrapCheckMs is! int ||
            lastBootstrapCheckMs < 0 ||
            lastBootstrapCheckMs > WebDavSyncLimits.maxTimestampMs)) {
      throw const FormatException('Invalid WebDAV sync bootstrap check time');
    }
    final publishedBootstrapDatabaseDigest =
        json['publishedBootstrapDatabaseDigest'];
    if (publishedBootstrapDatabaseDigest != null &&
        (publishedBootstrapDatabaseDigest is! String ||
            !RegExp(
              r'^[0-9a-f]{64}$',
            ).hasMatch(publishedBootstrapDatabaseDigest))) {
      throw const FormatException('Invalid WebDAV sync bootstrap digest');
    }
    void validateLegacyDigestSet(String key) {
      final raw = json[key] ?? const <Object?>[];
      if (raw is! List || raw.length > WebDavSyncLimits.maxMapEntries) {
        throw const FormatException('Invalid WebDAV sync digest state');
      }
      final result = <String>{};
      for (final value in raw) {
        if (value is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(value) ||
            !result.add(value)) {
          throw const FormatException('Invalid WebDAV sync digest state');
        }
      }
    }

    validateLegacyDigestSet('declinedGraphDigests');

    Set<String> idSet(String key) {
      final raw = json[key] ?? const <Object?>[];
      if (raw is! List || raw.length > WebDavSyncLimits.maxMapEntries) {
        throw const FormatException('Invalid WebDAV sync identity state');
      }
      final result = <String>{};
      for (final value in raw) {
        if (value is! String ||
            !_safeSyncIdentifier.hasMatch(value) ||
            !result.add(value)) {
          throw const FormatException('Invalid WebDAV sync identity state');
        }
      }
      return Set<String>.unmodifiable(result);
    }

    final currentDeviceIds = idSet('currentDeviceIds');
    if (currentDeviceIds.length > WebDavSyncLimits.maxPeers) {
      throw const FormatException('Invalid WebDAV sync current device state');
    }

    return WebDavSyncEngineState(
      circleToLocalProfiles: optionalMap(
        'circleToLocalProfiles',
        maxEntries: WebDavSyncLimits.maxMapEntries,
      ),
      circleToLocalResources: optionalMap(
        'circleToLocalResources',
        maxEntries: WebDavSyncLimits.maxRecordsPerHotDocument,
      ),
      clock: WebDavSyncClockState.fromJson(json['clock']),
      deviceClockWarning: deviceClockWarning,
      lastClockPauseReason: lastClockPauseReason,
      profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
        profiles,
      ),
      pendingLocalProfiles:
          Map<String, WebDavSyncProfileEngineState>.unmodifiable(
            pendingLocalProfiles,
          ),
      circleProfilesBaseline: json['circleProfilesBaseline'] == null
          ? null
          : WebDavSyncProfilesDocument.fromJson(json['circleProfilesBaseline']),
      circleResourcesBaseline: json['circleResourcesBaseline'] == null
          ? null
          : WebDavSyncResourcesDocument.fromJson(
              json['circleResourcesBaseline'],
            ),
      pendingCircleApply: json['pendingCircleApply'] == null
          ? null
          : WebDavSyncPendingCircleApply.fromJson(json['pendingCircleApply']),
      lastPushedProfilesDigest: circleDigest('lastPushedProfilesDigest'),
      lastPushedResourcesDigest: circleDigest('lastPushedResourcesDigest'),
      pendingActiveProfile: pendingActiveProfile,
      pendingAdminSafetyProfile: pendingAdminSafetyProfile as String?,
      statusHint: statusHint as String?,
      peerManifestHighWater: Map<String, int>.unmodifiable(peerHighWater),
      peerManifestValidators:
          Map<String, WebDavSyncManifestValidator>.unmodifiable(peerValidators),
      currentDeviceIds: currentDeviceIds,
      lastSuccessfulSyncMs: successful as int?,
      lastPushMs: lastPush as int?,
      lastRemoteChangeMs: lastRemoteChange as int?,
      ownManifest: json['ownManifest'] == null
          ? null
          : WebDavSyncManifest.fromJson(json['ownManifest']),
      schemaRatchet: schemaRatchet,
      lastBootstrapCheckMs: lastBootstrapCheckMs as int?,
      publishedBootstrapDatabaseDigest:
          publishedBootstrapDatabaseDigest as String?,
      adoption: json['adoption'] == null
          ? null
          : WebDavSyncAdoptionRecord.fromJson(json['adoption']),
      prunePendingProfileIds: idSet('prunePendingProfileIds'),
      safetyProtectedProfileIds: idSet('safetyProtectedProfileIds'),
    );
  }
}

/// Retains rollback protection for the newest historical peers without
/// allowing device churn to grow the engine journal forever. Every currently
/// listed device is protected; only the oldest absent histories are evicted.
Map<String, int> boundedPeerManifestHighWater(
  Map<String, int> source, {
  required Iterable<String> currentDeviceIds,
}) {
  final current = currentDeviceIds.toSet();
  if (current.length > WebDavSyncLimits.maxPeers) {
    throw StateError('WebDAV sync peer count exceeds its limit');
  }
  final result = Map<String, int>.from(source);
  if (result.length <= WebDavSyncLimits.maxMapEntries) {
    return Map<String, int>.unmodifiable(result);
  }
  final removable =
      result.entries
          .where((entry) => !current.contains(entry.key))
          .toList(growable: false)
        ..sort((left, right) {
          final byTime = left.value.compareTo(right.value);
          return byTime != 0 ? byTime : left.key.compareTo(right.key);
        });
  for (final entry in removable) {
    if (result.length <= WebDavSyncLimits.maxMapEntries) break;
    result.remove(entry.key);
  }
  if (result.length > WebDavSyncLimits.maxMapEntries) {
    throw StateError('WebDAV sync peer history exceeds its limit');
  }
  return Map<String, int>.unmodifiable(result);
}

abstract interface class WebDavSyncEngineStateRepository {
  Future<WebDavSyncEngineState> load(String namespaceId);

  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  );
}

typedef WebDavSyncStateDirectoryProvider = Future<Directory> Function();

final class WebDavSyncEngineStateMissingException implements Exception {
  const WebDavSyncEngineStateMissingException();

  @override
  String toString() => webDavSyncMissingStateMessage;
}

final class WebDavSyncEngineStateStore
    implements WebDavSyncEngineStateRepository {
  WebDavSyncEngineStateStore({
    WebDavSyncBindingStore? bindingStore,
    WebDavSyncStateDirectoryProvider? directoryProvider,
  }) : bindingStore = bindingStore ?? WebDavSyncBindingStore(),
       _directoryProvider = directoryProvider ?? AppStorage.support;

  static const String valueKey = 'm4Engine';
  static const int _fileVersion = 1;
  // A crash window can hold the last-applied and pending 256 MiB resources
  // documents at once. The section limits still police each document.
  static const int _maxFileBytes = 520 * 1024 * 1024;
  static const Map<String, Object> _fileMarker = <String, Object>{
    'version': _fileVersion,
    'storage': 'file',
  };
  static final Lock _fileLock = Lock();

  final WebDavSyncBindingStore bindingStore;
  final WebDavSyncStateDirectoryProvider _directoryProvider;
  final Set<String> _knownMarkedNamespaces = <String>{};
  final Map<String, String> _namespaceDeviceIds = <String, String>{};

  @override
  Future<WebDavSyncEngineState> load(String namespaceId) =>
      _fileLock.synchronized(() => _loadUnlocked(namespaceId));

  Future<WebDavSyncEngineState> _loadUnlocked(String namespaceId) async {
    final snapshot = await bindingStore.load();
    final namespace = snapshot.namespaces[namespaceId];
    if (namespace == null) {
      throw StateError('WebDAV sync namespace is unavailable');
    }
    _namespaceDeviceIds[namespaceId] = namespace.deviceId;
    final markerOrLegacy = namespace.values[valueKey];
    final marked = _isFileMarker(markerOrLegacy);
    if (marked) _knownMarkedNamespaces.add(namespaceId);
    final file = await _stateFile(namespaceId);
    await _recoverInterruptedWindowsReplace(file);
    if (await file.exists()) {
      final state = await _readFile(file);
      if (!marked) await _persistFileMarker(namespaceId);
      return state;
    }
    if (marked) {
      throw const WebDavSyncEngineStateMissingException();
    }
    if (markerOrLegacy != null) {
      final migrated = WebDavSyncEngineState.fromJson(markerOrLegacy);
      await _writeFile(file, migrated);
      await _persistFileMarker(namespaceId);
      return migrated;
    }
    return const WebDavSyncEngineState();
  }

  @override
  Future<WebDavSyncEngineState> update(
    String namespaceId,
    WebDavSyncEngineState Function(WebDavSyncEngineState current) update,
  ) => _fileLock.synchronized(() async {
    final current = await _loadUnlocked(namespaceId);
    final result = update(current);
    final file = await _stateFile(namespaceId);
    await _writeFile(file, result);
    if (!_knownMarkedNamespaces.contains(namespaceId)) {
      await _persistFileMarker(namespaceId);
    }
    return result;
  });

  /// Recreates only a journal that was already proven missing.
  ///
  /// tvOS may purge its Caches-backed Application Support directory. The
  /// binding/marker pin remains in device preferences, but identity maps and
  /// rollback state must never be guessed. After the user re-verifies the
  /// same folder, the activation flow calls this method and performs a normal
  /// consented bootstrap adoption into a fresh journal.
  Future<void> initializeMissingForReconnect(String namespaceId) =>
      _fileLock.synchronized(() async {
        final snapshot = await bindingStore.load();
        final namespace = snapshot.namespaces[namespaceId];
        if (namespace == null || namespace.markerBytes == null) {
          throw StateError('WebDAV sync namespace cannot be reconnected');
        }
        _namespaceDeviceIds[namespaceId] = namespace.deviceId;
        if (!_isFileMarker(namespace.values[valueKey])) {
          throw StateError('WebDAV sync state was not marked as file-backed');
        }
        final file = await _stateFile(namespaceId);
        await _recoverInterruptedWindowsReplace(file);
        if (await file.exists()) {
          throw StateError('WebDAV sync state is not missing');
        }
        await _writeFile(file, const WebDavSyncEngineState());
        _knownMarkedNamespaces.add(namespaceId);
      });

  Future<void> _persistFileMarker(String namespaceId) async {
    await bindingStore.updateNamespaceValues(namespaceId, (values) {
      final next = Map<String, Object?>.from(values);
      next[valueKey] = _fileMarker;
      return next;
    });
    _knownMarkedNamespaces.add(namespaceId);
  }

  Future<File> _stateFile(String namespaceId) async {
    final deviceId = _namespaceDeviceIds[namespaceId];
    if (deviceId == null) {
      throw StateError('WebDAV sync namespace was not loaded');
    }
    final root = await _directoryProvider();
    final directory = Directory(
      p.join(root.path, 'webdav-sync', 'engine-state-v1'),
    );
    return File(
      p.join(directory.path, '${contentHashOf(utf8.encode(deviceId))}.json'),
    );
  }

  static bool _isFileMarker(Object? source) {
    if (source is! Map) return false;
    return source['version'] == _fileVersion && source['storage'] == 'file';
  }

  static Future<WebDavSyncEngineState> _readFile(File file) async {
    final length = await file.length();
    if (length <= 0 || length > _maxFileBytes) {
      throw const FormatException('WebDAV sync engine state exceeds its limit');
    }
    final decoded = jsonDecode(await file.readAsString());
    return WebDavSyncEngineState.fromJson(decoded);
  }

  static Future<void> _writeFile(File file, WebDavSyncEngineState state) async {
    // Reject any caller-created state that the strict restart parser could not
    // read. This keeps a successful update from poisoning the next launch.
    final json = state.toJson();
    WebDavSyncEngineState.fromJson(json);
    final encoded = utf8.encode(jsonEncode(json));
    if (encoded.isEmpty || encoded.length > _maxFileBytes) {
      throw const FormatException('WebDAV sync engine state exceeds its limit');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.next');
    await temporary.writeAsBytes(encoded, flush: true);
    if (Platform.isWindows && await file.exists()) {
      final previous = File('${file.path}.previous');
      if (await previous.exists()) await previous.delete();
      await file.rename(previous.path);
      try {
        await temporary.rename(file.path);
        await previous.delete();
      } catch (error, stackTrace) {
        try {
          if (!await file.exists() && await previous.exists()) {
            await previous.rename(file.path);
          }
        } catch (_) {
          // Preserve the failed replacement as the primary error. Startup
          // recovery still has the `.previous` file to retry from.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    await temporary.rename(file.path);
  }

  static Future<void> _recoverInterruptedWindowsReplace(File file) async {
    if (!Platform.isWindows) return;
    final previous = File('${file.path}.previous');
    if (await file.exists()) {
      if (await previous.exists()) await previous.delete();
      final temporary = File('${file.path}.next');
      if (await temporary.exists()) await temporary.delete();
      return;
    }
    if (await previous.exists()) {
      await previous.rename(file.path);
    }
    final temporary = File('${file.path}.next');
    if (await temporary.exists()) await temporary.delete();
  }
}

Map<String, dynamic> _map(Object? source, String label) {
  if (source is! Map) throw FormatException('Invalid WebDAV sync $label');
  try {
    return Map<String, dynamic>.from(source);
  } on TypeError {
    throw FormatException('Invalid WebDAV sync $label');
  }
}

int encodedEngineStateBytes(WebDavSyncEngineState state) =>
    utf8.encode(jsonEncode(state.toJson())).length;

final RegExp _safeSyncIdentifier = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');
