import 'dart:convert';
import 'dart:math';

import '../../models/profiles/profile_policy.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';

final class WebDavSyncLocalCircleValue<T> {
  const WebDavSyncLocalCircleValue({
    required this.value,
    required this.updatedAtMs,
  });

  final T value;
  final int updatedAtMs;
}

enum WebDavSyncCircleDeletionKind { profile, resource, grant, setting, binding }

final class WebDavSyncCircleDeletion {
  const WebDavSyncCircleDeletion({
    required this.kind,
    required this.timeMs,
    required this.originDeviceId,
    this.circleProfileId,
    this.circleResourceId,
    this.slot,
  });

  final WebDavSyncCircleDeletionKind kind;
  final int timeMs;
  final String originDeviceId;
  final String? circleProfileId;
  final String? circleResourceId;
  final String? slot;
}

final class WebDavSyncResourcesBuildInput {
  const WebDavSyncResourcesBuildInput({
    required this.deviceId,
    required this.localNowMs,
    required this.clockOffsetMs,
    required this.serverNowMs,
    required this.resources,
    required this.secrets,
    required this.grants,
    required this.settings,
    required this.bindings,
    this.deletions = const <WebDavSyncCircleDeletion>[],
    this.previous,
  });

  final String deviceId;
  final int localNowMs;
  final int clockOffsetMs;
  final int serverNowMs;
  final Map<String, WebDavSyncLocalCircleValue<WebDavSyncResourceMetadata>>
  resources;
  final Map<String, WebDavSyncLocalCircleValue<WebDavSyncResourceSecretConfig>>
  secrets;
  final Map<
    String,
    Map<String, WebDavSyncLocalCircleValue<WebDavSyncGrantValue>>
  >
  grants;
  final Map<
    String,
    Map<String, WebDavSyncLocalCircleValue<WebDavSyncSettingsValue>>
  >
  settings;
  final Map<
    String,
    Map<String, WebDavSyncLocalCircleValue<WebDavSyncBindingValue>>
  >
  bindings;
  final List<WebDavSyncCircleDeletion> deletions;
  final WebDavSyncResourcesDocument? previous;
}

final class WebDavSyncProfilesBuildInput {
  const WebDavSyncProfilesBuildInput({
    required this.deviceId,
    required this.localNowMs,
    required this.clockOffsetMs,
    required this.serverNowMs,
    required this.profiles,
    this.deletions = const <WebDavSyncCircleDeletion>[],
    this.previous,
  });

  final String deviceId;
  final int localNowMs;
  final int clockOffsetMs;
  final int serverNowMs;
  final Map<String, WebDavSyncLocalCircleValue<WebDavSyncProfileValue>>
  profiles;
  final List<WebDavSyncCircleDeletion> deletions;
  final WebDavSyncProfilesDocument? previous;
}

final class WebDavSyncDeterministicCircleValidationException
    implements Exception {
  const WebDavSyncDeterministicCircleValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pure record-level rebuild and merge for the two circle-wide sections.
abstract final class WebDavSyncCircleMerge {
  static WebDavSyncProfilesDocument rebuildProfiles(
    WebDavSyncProfilesBuildInput input,
  ) {
    final result =
        Map<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>.from(
          input.previous?.profiles ?? const {},
        );
    for (final entry in input.profiles.entries) {
      final old = input.previous?.profiles[entry.key];
      result[entry.key] = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
        stamp:
            old != null &&
                old.value != null &&
                _equalJson(old.value!.toJson(), entry.value.value.toJson())
            ? old.stamp
            : _stamp(input, entry.value.updatedAtMs),
        value: entry.value.value,
      );
    }
    for (final deletion in input.deletions.where(
      (value) => value.kind == WebDavSyncCircleDeletionKind.profile,
    )) {
      final id = deletion.circleProfileId;
      if (id == null) throw StateError('Profile deletion has no profile ID');
      final tombstone = WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
        stamp: _deletionStamp(input, deletion),
        value: null,
      );
      final old = result[id];
      if (old == null || _compareLeaf(tombstone, old) > 0) {
        result[id] = tombstone;
      }
    }
    if (result.length > WebDavSyncLimits.maxMapEntries) {
      throw StateError('WebDAV sync profiles exceed their safe limit');
    }
    return WebDavSyncProfilesDocument(
      profiles:
          Map<
            String,
            WebDavSyncCircleLeaf<WebDavSyncProfileValue>
          >.unmodifiable(result),
    );
  }

  static WebDavSyncResourcesDocument rebuildResources(
    WebDavSyncResourcesBuildInput input,
  ) {
    final resources = Map<String, WebDavSyncResourceEntry>.from(
      input.previous?.resources ?? const {},
    );
    for (final entry in input.resources.entries) {
      final old = input.previous?.resources[entry.key];
      final metadata = WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
        stamp:
            old?.metadata.value != null &&
                _equalJson(
                  old!.metadata.value!.toJson(),
                  entry.value.value.toJson(),
                )
            ? old.metadata.stamp
            : _stamp(input, entry.value.updatedAtMs),
        value: entry.value.value,
      );
      final secretInput = input.secrets[entry.key];
      WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>? secret =
          old?.secretConfig;
      if (secretInput != null) {
        secret = WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
          stamp:
              old?.secretConfig?.value != null &&
                  _sameSecret(old!.secretConfig!.value!, secretInput.value)
              ? old.secretConfig!.stamp
              : _stamp(input, secretInput.updatedAtMs),
          // Preserve the old randomized envelope byte-for-byte when the
          // canonical secret and its attachment fields did not change.
          value:
              old?.secretConfig?.value != null &&
                  _sameSecret(old!.secretConfig!.value!, secretInput.value)
              ? old.secretConfig!.value
              : secretInput.value,
        );
      }
      resources[entry.key] = WebDavSyncResourceEntry(
        metadata: metadata,
        secretConfig: secret,
      );
    }

    final grants = _rebuildNested<WebDavSyncGrantValue>(
      input.grants,
      input.previous?.grants ?? const {},
      input,
      (value) => value.toJson(),
    );
    final settings = _rebuildNested<WebDavSyncSettingsValue>(
      input.settings,
      input.previous?.settings ?? const {},
      input,
      (value) => value.toJson(),
    );
    final bindings = _rebuildNested<WebDavSyncBindingValue>(
      input.bindings,
      input.previous?.bindings ?? const {},
      input,
      (value) => value.toJson(),
    );

    for (final deletion in input.deletions) {
      final stamp = _deletionStamp(input, deletion);
      switch (deletion.kind) {
        case WebDavSyncCircleDeletionKind.profile:
          break;
        case WebDavSyncCircleDeletionKind.resource:
          final id = deletion.circleResourceId;
          if (id == null) {
            throw StateError('Resource deletion has no resource ID');
          }
          final old = resources[id];
          final metadata = WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: stamp,
            value: null,
          );
          final secretTombstone = old?.secretConfig == null
              ? null
              : WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
                  stamp: stamp,
                  value: null,
                );
          final secret = secretTombstone == null
              ? null
              : _newer(secretTombstone, old!.secretConfig!);
          resources[id] = WebDavSyncResourceEntry(
            metadata: old == null ? metadata : _newer(metadata, old.metadata),
            secretConfig: secret,
          );
          break;
        case WebDavSyncCircleDeletionKind.grant:
          _installNestedTombstone<WebDavSyncGrantValue>(
            grants,
            deletion,
            stamp,
          );
          break;
        case WebDavSyncCircleDeletionKind.setting:
          _installNestedTombstone<WebDavSyncSettingsValue>(
            settings,
            deletion,
            stamp,
          );
          break;
        case WebDavSyncCircleDeletionKind.binding:
          _installNestedTombstone<WebDavSyncBindingValue>(
            bindings,
            deletion,
            stamp,
            binding: true,
          );
          break;
      }
    }
    final document = WebDavSyncResourcesDocument(
      resources: Map<String, WebDavSyncResourceEntry>.unmodifiable(resources),
      grants: _freezeNested(grants),
      settings: _freezeNested(settings),
      bindings: _freezeNested(bindings),
    );
    if (document.leafCount > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw StateError('WebDAV sync resources exceed their safe limit');
    }
    return document;
  }

  static WebDavSyncProfilesDocument mergeProfiles(
    Iterable<WebDavSyncProfilesDocument> documents,
  ) {
    final inputs = documents.toList(growable: false);
    final result = <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{};
    for (final document in inputs) {
      for (final entry in document.profiles.entries) {
        final old = result[entry.key];
        if (old == null || _compareLeaf(entry.value, old) > 0) {
          result[entry.key] = entry.value;
        }
      }
    }
    if (!result.values.any(_isManagingAdminLeaf)) {
      MapEntry<String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>? survivor;
      for (final document in inputs) {
        for (final entry in document.profiles.entries) {
          if (!_isManagingAdminLeaf(entry.value)) continue;
          final current = survivor;
          if (current == null ||
              _compareStamp(entry.value.stamp, current.value.stamp) > 0 ||
              (_compareStamp(entry.value.stamp, current.value.stamp) == 0 &&
                  entry.key.compareTo(current.key) > 0)) {
            survivor = entry;
          }
        }
      }
      if (survivor != null) result[survivor.key] = survivor.value;
    }
    if (result.length > WebDavSyncLimits.maxMapEntries) {
      throw StateError('WebDAV sync profiles exceed their safe limit');
    }
    return WebDavSyncProfilesDocument(
      profiles:
          Map<
            String,
            WebDavSyncCircleLeaf<WebDavSyncProfileValue>
          >.unmodifiable(result),
    );
  }

  static WebDavSyncResourcesDocument mergeResources(
    Iterable<WebDavSyncResourcesDocument> documents,
  ) {
    final resources = <String, WebDavSyncResourceEntry>{};
    final grants =
        <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{};
    final settings =
        <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>>{};
    final bindings =
        <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>>{};
    for (final document in documents) {
      for (final entry in document.resources.entries) {
        final old = resources[entry.key];
        resources[entry.key] = WebDavSyncResourceEntry(
          metadata: old == null
              ? entry.value.metadata
              : _newer(entry.value.metadata, old.metadata),
          secretConfig: _mergeOptional(
            entry.value.secretConfig,
            old?.secretConfig,
          ),
        );
      }
      _mergeNested(grants, document.grants);
      _mergeNested(settings, document.settings);
      _mergeNested(bindings, document.bindings);
    }
    final result = WebDavSyncResourcesDocument(
      resources: Map<String, WebDavSyncResourceEntry>.unmodifiable(resources),
      grants: _freezeNested(grants),
      settings: _freezeNested(settings),
      bindings: _freezeNested(bindings),
    );
    if (result.leafCount > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw StateError('WebDAV sync resources exceed their safe limit');
    }
    return result;
  }

  /// Removes live child winners that cannot exist after the merged parent
  /// winners are applied. Tombstones retain the rejected leaf's stamp so the
  /// projection is deterministic and remains deletion-shaped for local rows.
  static WebDavSyncResourcesDocument deriveApplicableResources({
    required WebDavSyncProfilesDocument profiles,
    required WebDavSyncResourcesDocument resources,
  }) {
    final liveProfiles = profiles.profiles.entries
        .where((entry) => entry.value.value != null)
        .map((entry) => entry.key)
        .toSet();
    final applicableResources = <String, WebDavSyncResourceEntry>{};
    for (final entry in resources.resources.entries) {
      final metadata = entry.value.metadata;
      if (metadata.value != null &&
          !liveProfiles.contains(metadata.value!.ownerCircleProfileId)) {
        applicableResources[entry.key] = WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: metadata.stamp,
            value: null,
          ),
          secretConfig: entry.value.secretConfig == null
              ? null
              : WebDavSyncCircleLeaf<WebDavSyncResourceSecretConfig>(
                  stamp: entry.value.secretConfig!.stamp,
                  value: null,
                ),
        );
      } else {
        applicableResources[entry.key] = entry.value;
      }
    }
    final liveResources = applicableResources.entries
        .where((entry) => entry.value.metadata.value != null)
        .map((entry) => entry.key)
        .toSet();
    final grants = _suppressNested<WebDavSyncGrantValue>(
      resources.grants,
      keep: (profileId, resourceId, _) =>
          liveProfiles.contains(profileId) &&
          liveResources.contains(resourceId),
    );
    final settings = _suppressNested<WebDavSyncSettingsValue>(
      resources.settings,
      keep: (profileId, resourceId, _) =>
          liveProfiles.contains(profileId) &&
          liveResources.contains(resourceId) &&
          grants[profileId]?[resourceId]?.value != null,
    );
    final bindings = _suppressNested<WebDavSyncBindingValue>(
      resources.bindings,
      keep: (profileId, _, value) =>
          liveProfiles.contains(profileId) &&
          liveResources.contains(value.circleResourceId) &&
          grants[profileId]?[value.circleResourceId]?.value != null,
    );
    return WebDavSyncResourcesDocument(
      resources: Map<String, WebDavSyncResourceEntry>.unmodifiable(
        applicableResources,
      ),
      grants: _freezeNested(grants),
      settings: _freezeNested(settings),
      bindings: _freezeNested(bindings),
    );
  }

  /// Deterministically simulates the relational projection before a target is
  /// journaled or replayed. Failures here never depend on device-local rows.
  static void validateApplicableState({
    required WebDavSyncProfilesDocument profiles,
    required WebDavSyncResourcesDocument resources,
  }) {
    if (!profiles.profiles.values.any(_isManagingAdminLeaf)) {
      throw const WebDavSyncDeterministicCircleValidationException(
        'Circle target has no enabled managing Admin',
      );
    }
    final liveProfiles = profiles.profiles.entries
        .where((entry) => entry.value.value != null)
        .map((entry) => entry.key)
        .toSet();
    final liveResources = <String>{};
    for (final entry in resources.resources.entries) {
      final metadata = entry.value.metadata.value;
      if (metadata == null) continue;
      if (!liveProfiles.contains(metadata.ownerCircleProfileId)) {
        throw const WebDavSyncDeterministicCircleValidationException(
          'Circle resource owner is unavailable',
        );
      }
      liveResources.add(entry.key);
    }
    for (final outer in resources.grants.entries) {
      for (final inner in outer.value.entries) {
        if (inner.value.value != null &&
            (!liveProfiles.contains(outer.key) ||
                !liveResources.contains(inner.key))) {
          throw const WebDavSyncDeterministicCircleValidationException(
            'Circle grant parent is unavailable',
          );
        }
      }
    }
    for (final outer in resources.settings.entries) {
      for (final inner in outer.value.entries) {
        if (inner.value.value != null &&
            (!liveProfiles.contains(outer.key) ||
                !liveResources.contains(inner.key) ||
                resources.grants[outer.key]?[inner.key]?.value == null)) {
          throw const WebDavSyncDeterministicCircleValidationException(
            'Circle settings parent is unavailable',
          );
        }
      }
    }
    for (final outer in resources.bindings.entries) {
      for (final inner in outer.value.entries) {
        final value = inner.value.value;
        if (value != null &&
            (!liveProfiles.contains(outer.key) ||
                !liveResources.contains(value.circleResourceId) ||
                resources.grants[outer.key]?[value.circleResourceId]?.value ==
                    null)) {
          throw const WebDavSyncDeterministicCircleValidationException(
            'Circle binding parent is unavailable',
          );
        }
      }
    }
  }

  static Map<String, Map<String, WebDavSyncCircleLeaf<T>>> _suppressNested<T>(
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> source, {
    required bool Function(String profileId, String key, T value) keep,
  }) => <String, Map<String, WebDavSyncCircleLeaf<T>>>{
    for (final outer in source.entries)
      outer.key: <String, WebDavSyncCircleLeaf<T>>{
        for (final inner in outer.value.entries)
          inner.key:
              inner.value.value == null ||
                  keep(outer.key, inner.key, inner.value.value as T)
              ? inner.value
              : WebDavSyncCircleLeaf<T>(stamp: inner.value.stamp, value: null),
      },
  };

  static bool _isManagingAdminLeaf(
    WebDavSyncCircleLeaf<WebDavSyncProfileValue> leaf,
  ) {
    final value = leaf.value;
    if (value == null ||
        !value.enabled ||
        value.role != UserProfileRole.admin) {
      return false;
    }
    return ProfilePolicy.decode(
      jsonEncode(value.policy),
      value.role,
    ).allows(value.role, ProfileFeature.manageProfiles);
  }

  static Map<String, Map<String, WebDavSyncCircleLeaf<T>>> _rebuildNested<T>(
    Map<String, Map<String, WebDavSyncLocalCircleValue<T>>> local,
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> previous,
    Object input,
    Object? Function(T value) encode,
  ) {
    final result = <String, Map<String, WebDavSyncCircleLeaf<T>>>{
      for (final entry in previous.entries)
        entry.key: Map<String, WebDavSyncCircleLeaf<T>>.from(entry.value),
    };
    for (final outer in local.entries) {
      final target = result.putIfAbsent(
        outer.key,
        () => <String, WebDavSyncCircleLeaf<T>>{},
      );
      for (final inner in outer.value.entries) {
        final old = previous[outer.key]?[inner.key];
        target[inner.key] = WebDavSyncCircleLeaf<T>(
          stamp:
              old?.value != null &&
                  _equalJson(encode(old!.value as T), encode(inner.value.value))
              ? old.stamp
              : _stamp(input, inner.value.updatedAtMs),
          value: inner.value.value,
        );
      }
    }
    return result;
  }

  static void _installNestedTombstone<T>(
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> target,
    WebDavSyncCircleDeletion deletion,
    WebDavSyncStamp stamp, {
    bool binding = false,
  }) {
    final profileId = deletion.circleProfileId;
    final key = binding ? deletion.slot : deletion.circleResourceId;
    if (profileId == null || key == null) {
      throw StateError('Nested circle deletion has an incomplete key');
    }
    final values = target.putIfAbsent(
      profileId,
      () => <String, WebDavSyncCircleLeaf<T>>{},
    );
    final tombstone = WebDavSyncCircleLeaf<T>(stamp: stamp, value: null);
    final old = values[key];
    if (old == null || _compareLeaf(tombstone, old) > 0) {
      values[key] = tombstone;
    }
  }

  static void _mergeNested<T>(
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> target,
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> source,
  ) {
    for (final outer in source.entries) {
      final values = target.putIfAbsent(
        outer.key,
        () => <String, WebDavSyncCircleLeaf<T>>{},
      );
      for (final inner in outer.value.entries) {
        final old = values[inner.key];
        if (old == null || _compareLeaf(inner.value, old) > 0) {
          values[inner.key] = inner.value;
        }
      }
    }
  }

  static Map<String, Map<String, WebDavSyncCircleLeaf<T>>> _freezeNested<T>(
    Map<String, Map<String, WebDavSyncCircleLeaf<T>>> source,
  ) => Map<String, Map<String, WebDavSyncCircleLeaf<T>>>.unmodifiable(<
    String,
    Map<String, WebDavSyncCircleLeaf<T>>
  >{
    for (final entry in source.entries)
      entry.key: Map<String, WebDavSyncCircleLeaf<T>>.unmodifiable(entry.value),
  });

  static WebDavSyncCircleLeaf<T> _newer<T>(
    WebDavSyncCircleLeaf<T> left,
    WebDavSyncCircleLeaf<T> right,
  ) => _compareLeaf(left, right) > 0 ? left : right;

  static WebDavSyncCircleLeaf<T>? _mergeOptional<T>(
    WebDavSyncCircleLeaf<T>? left,
    WebDavSyncCircleLeaf<T>? right,
  ) {
    if (left == null) return right;
    if (right == null) return left;
    return _newer(left, right);
  }

  static int _compareLeaf<T>(
    WebDavSyncCircleLeaf<T> left,
    WebDavSyncCircleLeaf<T> right,
  ) {
    final stamp = _compareStamp(left.stamp, right.stamp);
    if (stamp != 0) return stamp;
    return semanticDigestOf(
      _wireValue(left.value),
    ).compareTo(semanticDigestOf(_wireValue(right.value)));
  }

  static Object? _wireValue(Object? value) => switch (value) {
    WebDavSyncResourceMetadata value => value.toJson(),
    WebDavSyncResourceSecretConfig value => value.toJson(),
    WebDavSyncGrantValue value => value.toJson(),
    WebDavSyncSettingsValue value => value.toJson(),
    WebDavSyncBindingValue value => value.toJson(),
    WebDavSyncProfileValue value => value.toJson(),
    _ => value,
  };

  static int _compareStamp(WebDavSyncStamp left, WebDavSyncStamp right) {
    final time = left.normalizedTimeMs.compareTo(right.normalizedTimeMs);
    return time != 0
        ? time
        : left.originDeviceId.compareTo(right.originDeviceId);
  }

  static WebDavSyncStamp _stamp(Object input, int rawTime) {
    late final String deviceId;
    late final int localNowMs;
    late final int offset;
    late final int serverNowMs;
    if (input is WebDavSyncResourcesBuildInput) {
      deviceId = input.deviceId;
      localNowMs = input.localNowMs;
      offset = input.clockOffsetMs;
      serverNowMs = input.serverNowMs;
    } else if (input is WebDavSyncProfilesBuildInput) {
      deviceId = input.deviceId;
      localNowMs = input.localNowMs;
      offset = input.clockOffsetMs;
      serverNowMs = input.serverNowMs;
    } else {
      throw StateError('Unknown WebDAV sync circle build input');
    }
    final local = rawTime < 0 ? localNowMs : rawTime;
    return WebDavSyncStamp(
      normalizedTimeMs: min(max(0, local + offset), serverNowMs),
      originDeviceId: deviceId,
    );
  }

  static WebDavSyncStamp _deletionStamp(
    Object input,
    WebDavSyncCircleDeletion deletion,
  ) {
    late final int offset;
    late final int serverNowMs;
    if (input is WebDavSyncResourcesBuildInput) {
      offset = input.clockOffsetMs;
      serverNowMs = input.serverNowMs;
    } else if (input is WebDavSyncProfilesBuildInput) {
      offset = input.clockOffsetMs;
      serverNowMs = input.serverNowMs;
    } else {
      throw StateError('Unknown WebDAV sync circle build input');
    }
    return WebDavSyncStamp(
      normalizedTimeMs: min(max(0, deletion.timeMs + offset), serverNowMs),
      originDeviceId: deletion.originDeviceId,
    );
  }

  static bool _sameSecret(
    WebDavSyncResourceSecretConfig left,
    WebDavSyncResourceSecretConfig right,
  ) =>
      left.semanticDigest == right.semanticDigest &&
      left.type == right.type &&
      left.ownerCircleProfileId == right.ownerCircleProfileId &&
      left.publicSchemaVersion == right.publicSchemaVersion &&
      left.payloadVersion == right.payloadVersion;

  static bool _equalJson(Object? left, Object? right) =>
      WebDavSyncCodec.canonicalJson(left) ==
      WebDavSyncCodec.canonicalJson(right);
}
