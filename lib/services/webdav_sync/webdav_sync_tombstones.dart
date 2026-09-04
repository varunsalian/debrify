import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../utils/app_storage.dart';
import '../profiles/profile_runtime.dart';
import '../profiles/profile_preferences.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';

typedef WebDavSyncTombstoneDebugSink =
    FutureOr<void> Function(String localProfileId, Set<String> keys);

typedef WebDavSyncRegistryTombstoneDebugSink =
    FutureOr<void> Function(Set<WebDavSyncRegistryRecordId> records);

final class WebDavSyncRegistryTombstoneOutboxTarget {
  const WebDavSyncRegistryTombstoneOutboxTarget({
    required this.namespaceId,
    required this.deviceId,
  });

  final String namespaceId;
  final String deviceId;
}

enum WebDavSyncRegistryRecordKind { profile, resource, grant, setting, binding }

/// A registry leaf expressed only in local IDs. [ownerProfileId] and the
/// binding's [resourceId] are retained as parent-expansion metadata; record
/// identity still follows the database/wire keys.
final class WebDavSyncRegistryRecordId {
  const WebDavSyncRegistryRecordId._({
    required this.kind,
    this.profileId,
    this.resourceId,
    this.slot,
    this.ownerProfileId,
  });

  factory WebDavSyncRegistryRecordId.profile(String profileId) =>
      WebDavSyncRegistryRecordId._(
        kind: WebDavSyncRegistryRecordKind.profile,
        profileId: _checkedRegistryId(profileId, 'profileId'),
      );

  factory WebDavSyncRegistryRecordId.resource(
    String resourceId, {
    required String ownerProfileId,
  }) => WebDavSyncRegistryRecordId._(
    kind: WebDavSyncRegistryRecordKind.resource,
    resourceId: _checkedRegistryId(resourceId, 'resourceId'),
    ownerProfileId: _checkedRegistryId(ownerProfileId, 'ownerProfileId'),
  );

  factory WebDavSyncRegistryRecordId.grant(
    String profileId,
    String resourceId,
  ) => WebDavSyncRegistryRecordId._(
    kind: WebDavSyncRegistryRecordKind.grant,
    profileId: _checkedRegistryId(profileId, 'profileId'),
    resourceId: _checkedRegistryId(resourceId, 'resourceId'),
  );

  factory WebDavSyncRegistryRecordId.setting(
    String profileId,
    String resourceId,
  ) => WebDavSyncRegistryRecordId._(
    kind: WebDavSyncRegistryRecordKind.setting,
    profileId: _checkedRegistryId(profileId, 'profileId'),
    resourceId: _checkedRegistryId(resourceId, 'resourceId'),
  );

  factory WebDavSyncRegistryRecordId.binding(
    String profileId,
    String slot, {
    required String resourceId,
  }) => WebDavSyncRegistryRecordId._(
    kind: WebDavSyncRegistryRecordKind.binding,
    profileId: _checkedRegistryId(profileId, 'profileId'),
    slot: _checkedRegistryId(slot, 'slot'),
    resourceId: _checkedRegistryId(resourceId, 'resourceId'),
  );

  final WebDavSyncRegistryRecordKind kind;
  final String? profileId;
  final String? resourceId;
  final String? slot;
  final String? ownerProfileId;

  String get storageKey {
    String encode(String? value) => base64UrlEncode(utf8.encode(value ?? ''));
    return switch (kind) {
      WebDavSyncRegistryRecordKind.profile =>
        '${kind.name}:${encode(profileId)}',
      WebDavSyncRegistryRecordKind.resource =>
        '${kind.name}:${encode(resourceId)}',
      WebDavSyncRegistryRecordKind.grant ||
      WebDavSyncRegistryRecordKind.setting =>
        '${kind.name}:${encode(profileId)}:${encode(resourceId)}',
      WebDavSyncRegistryRecordKind.binding =>
        '${kind.name}:${encode(profileId)}:${encode(slot)}',
    };
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    if (profileId != null) 'profileId': profileId,
    if (resourceId != null) 'resourceId': resourceId,
    if (slot != null) 'slot': slot,
    if (ownerProfileId != null) 'ownerProfileId': ownerProfileId,
  };

  factory WebDavSyncRegistryRecordId.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Invalid registry tombstone record');
    }
    final json = Map<String, Object?>.from(source);
    final kind = WebDavSyncRegistryRecordKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final profileId = json['profileId'];
    final resourceId = json['resourceId'];
    final slot = json['slot'];
    final ownerProfileId = json['ownerProfileId'];
    try {
      return switch (kind) {
        WebDavSyncRegistryRecordKind.profile
            when profileId is String &&
                resourceId == null &&
                slot == null &&
                ownerProfileId == null =>
          WebDavSyncRegistryRecordId.profile(profileId),
        WebDavSyncRegistryRecordKind.resource
            when profileId == null &&
                resourceId is String &&
                slot == null &&
                ownerProfileId is String =>
          WebDavSyncRegistryRecordId.resource(
            resourceId,
            ownerProfileId: ownerProfileId,
          ),
        WebDavSyncRegistryRecordKind.grant
            when profileId is String &&
                resourceId is String &&
                slot == null &&
                ownerProfileId == null =>
          WebDavSyncRegistryRecordId.grant(profileId, resourceId),
        WebDavSyncRegistryRecordKind.setting
            when profileId is String &&
                resourceId is String &&
                slot == null &&
                ownerProfileId == null =>
          WebDavSyncRegistryRecordId.setting(profileId, resourceId),
        WebDavSyncRegistryRecordKind.binding
            when profileId is String &&
                resourceId is String &&
                slot is String &&
                ownerProfileId == null =>
          WebDavSyncRegistryRecordId.binding(
            profileId,
            slot,
            resourceId: resourceId,
          ),
        _ => throw const FormatException('Invalid registry tombstone record'),
      };
    } on ArgumentError {
      throw const FormatException('Invalid registry tombstone record');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WebDavSyncRegistryRecordId && storageKey == other.storageKey;

  @override
  int get hashCode => storageKey.hashCode;
}

final class WebDavSyncRegistryRecordTombstone {
  const WebDavSyncRegistryRecordTombstone({
    required this.record,
    required this.timeMs,
    required this.originDeviceId,
    this.normalizedTimeFrozen = false,
    int? rawLocalTimeMs,
  }) : rawLocalTimeMs = rawLocalTimeMs ?? timeMs;

  final WebDavSyncRegistryRecordId record;
  final int timeMs;
  final String originDeviceId;
  final bool normalizedTimeFrozen;
  final int rawLocalTimeMs;

  WebDavSyncRegistryRecordTombstone copyWith({
    int? timeMs,
    bool? normalizedTimeFrozen,
    int? rawLocalTimeMs,
  }) => WebDavSyncRegistryRecordTombstone(
    record: record,
    timeMs: timeMs ?? this.timeMs,
    originDeviceId: originDeviceId,
    normalizedTimeFrozen: normalizedTimeFrozen ?? this.normalizedTimeFrozen,
    rawLocalTimeMs: rawLocalTimeMs ?? this.rawLocalTimeMs,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'record': record.toJson(),
    'timeMs': timeMs,
    'originDeviceId': originDeviceId,
    'normalizedTimeFrozen': normalizedTimeFrozen,
    'rawLocalTimeMs': rawLocalTimeMs,
  };

  factory WebDavSyncRegistryRecordTombstone.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Invalid registry tombstone');
    }
    final json = Map<String, Object?>.from(source);
    final timeMs = json['timeMs'];
    final originDeviceId = json['originDeviceId'];
    final normalizedTimeFrozen = json['normalizedTimeFrozen'] ?? false;
    final rawLocalTimeMs = json['rawLocalTimeMs'] ?? timeMs;
    if (timeMs is! int ||
        timeMs < 0 ||
        originDeviceId is! String ||
        normalizedTimeFrozen is! bool ||
        rawLocalTimeMs is! int ||
        rawLocalTimeMs < 0 ||
        !_safeRegistryDeviceId.hasMatch(originDeviceId)) {
      throw const FormatException('Invalid registry tombstone');
    }
    return WebDavSyncRegistryRecordTombstone(
      record: WebDavSyncRegistryRecordId.fromJson(json['record']),
      timeMs: timeMs,
      originDeviceId: originDeviceId,
      normalizedTimeFrozen: normalizedTimeFrozen,
      rawLocalTimeMs: rawLocalTimeMs,
    );
  }
}

abstract interface class WebDavSyncRegistryTombstoneRepository {
  Future<Map<String, WebDavSyncRegistryRecordTombstone>> load(
    String namespaceId,
  );

  Future<void> record(
    String namespaceId, {
    required String deviceId,
    required Iterable<WebDavSyncRegistryRecordId> records,
    required int nowMs,
  });

  Future<Map<String, WebDavSyncRegistryRecordTombstone>> freeze(
    String namespaceId, {
    required int clockOffsetMs,
    required int serverNowMs,
  });
}

/// File-backed because a profile/resource cascade can exceed the 64 KiB
/// binding preference budget. The namespace stores only a tiny durable marker.
final class WebDavSyncRegistryTombstoneStore
    implements WebDavSyncRegistryTombstoneRepository {
  WebDavSyncRegistryTombstoneStore({
    WebDavSyncBindingStore? bindingStore,
    WebDavSyncStateDirectoryProvider? directoryProvider,
  }) : _bindingStore = bindingStore ?? WebDavSyncBindingStore(),
       _directoryProvider = directoryProvider ?? AppStorage.support;

  static const String valueKey =
      WebDavSyncBindingStore.registryTombstonesFileValueKey;
  static const int _fileVersion = 1;
  static const int _maxRecords = 100000;
  static const int _maxFileBytes = 64 * 1024 * 1024;
  static const Map<String, Object> _fileMarker = <String, Object>{
    'version': _fileVersion,
    'storage': 'file',
  };
  static final Lock _lock = Lock();

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncStateDirectoryProvider _directoryProvider;

  @override
  Future<Map<String, WebDavSyncRegistryRecordTombstone>> load(
    String namespaceId,
  ) => _lock.synchronized(() => _loadUnlocked(namespaceId));

  @override
  Future<void> record(
    String namespaceId, {
    required String deviceId,
    required Iterable<WebDavSyncRegistryRecordId> records,
    required int nowMs,
  }) => _lock.synchronized(() async {
    final current = await _loadUnlocked(namespaceId);
    final next = Map<String, WebDavSyncRegistryRecordTombstone>.from(current);
    for (final record in records) {
      final incoming = WebDavSyncRegistryRecordTombstone(
        record: record,
        timeMs: nowMs,
        originDeviceId: deviceId,
      );
      final existing = next[record.storageKey];
      if (existing == null ||
          _compareRegistryTombstones(incoming, existing) > 0) {
        next[record.storageKey] = incoming;
      }
      if (next.length > _maxRecords) {
        throw StateError('WebDAV registry tombstones exceed their safe limit');
      }
    }
    final file = await _file(namespaceId);
    await _writeFile(file, next);
    final snapshot = await _bindingStore.load();
    final marker = snapshot.namespaces[namespaceId]?.values[valueKey];
    if (!_isMarker(marker)) {
      await _bindingStore.updateNamespaceValues(namespaceId, (values) {
        return <String, Object?>{...values, valueKey: _fileMarker};
      });
    }
  });

  @override
  Future<Map<String, WebDavSyncRegistryRecordTombstone>> freeze(
    String namespaceId, {
    required int clockOffsetMs,
    required int serverNowMs,
  }) => _lock.synchronized(() async {
    final current = await _loadUnlocked(namespaceId);
    if (current.values.every((item) => item.normalizedTimeFrozen)) {
      return current;
    }
    final frozen = <String, WebDavSyncRegistryRecordTombstone>{
      for (final entry in current.entries)
        entry.key: entry.value.normalizedTimeFrozen
            ? entry.value
            : entry.value.copyWith(
                timeMs: min(
                  max(0, entry.value.timeMs + clockOffsetMs),
                  serverNowMs,
                ),
                normalizedTimeFrozen: true,
              ),
    };
    await _writeFile(await _file(namespaceId), frozen);
    return Map<String, WebDavSyncRegistryRecordTombstone>.unmodifiable(frozen);
  });

  Future<Map<String, WebDavSyncRegistryRecordTombstone>> _loadUnlocked(
    String namespaceId,
  ) async {
    final snapshot = await _bindingStore.load();
    final namespace = snapshot.namespaces[namespaceId];
    if (namespace == null) {
      throw StateError('WebDAV sync namespace is unavailable');
    }
    final file = await _file(namespaceId);
    await _recoverInterruptedWindowsReplace(file);
    if (!await file.exists()) {
      if (_isMarker(namespace.values[valueKey])) {
        throw const WebDavSyncEngineStateMissingException();
      }
      return const <String, WebDavSyncRegistryRecordTombstone>{};
    }
    final length = await file.length();
    if (length <= 0 || length > _maxFileBytes) {
      throw const FormatException('WebDAV registry tombstones exceed limits');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['version'] != _fileVersion ||
        decoded['records'] is! Map) {
      throw const FormatException('Invalid WebDAV registry tombstones');
    }
    final rawRecords = decoded['records'] as Map;
    if (rawRecords.length > _maxRecords) {
      throw const FormatException('WebDAV registry tombstones exceed limits');
    }
    final records = <String, WebDavSyncRegistryRecordTombstone>{};
    for (final entry in rawRecords.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid WebDAV registry tombstones');
      }
      final tombstone = WebDavSyncRegistryRecordTombstone.fromJson(entry.value);
      if (tombstone.record.storageKey != entry.key) {
        throw const FormatException('Registry tombstone key mismatch');
      }
      records[entry.key as String] = tombstone;
    }
    if (!_isMarker(namespace.values[valueKey])) {
      await _bindingStore.updateNamespaceValues(namespaceId, (values) {
        return <String, Object?>{...values, valueKey: _fileMarker};
      });
    }
    return Map<String, WebDavSyncRegistryRecordTombstone>.unmodifiable(records);
  }

  Future<File> _file(String namespaceId) async {
    final snapshot = await _bindingStore.load();
    final deviceId = snapshot.namespaces[namespaceId]?.deviceId;
    if (deviceId == null) {
      throw StateError('WebDAV sync namespace is unavailable');
    }
    final root = await _directoryProvider();
    return File(
      p.join(
        root.path,
        'webdav-sync',
        'registry-tombstones-v1',
        '${contentHashOf(utf8.encode(deviceId))}.json',
      ),
    );
  }

  static bool _isMarker(Object? source) =>
      source is Map &&
      source['version'] == _fileVersion &&
      source['storage'] == 'file';

  static Future<void> _writeFile(
    File file,
    Map<String, WebDavSyncRegistryRecordTombstone> records,
  ) async {
    final json = <String, Object?>{
      'version': _fileVersion,
      'records': <String, Object?>{
        for (final entry in records.entries) entry.key: entry.value.toJson(),
      },
    };
    final encoded = utf8.encode(jsonEncode(json));
    if (encoded.isEmpty || encoded.length > _maxFileBytes) {
      throw const FormatException('WebDAV registry tombstones exceed limits');
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
        if (!await file.exists() && await previous.exists()) {
          await previous.rename(file.path);
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
    if (await previous.exists()) await previous.rename(file.path);
    final temporary = File('${file.path}.next');
    if (await temporary.exists()) await temporary.delete();
  }

  static int _compareRegistryTombstones(
    WebDavSyncRegistryRecordTombstone left,
    WebDavSyncRegistryRecordTombstone right,
  ) {
    final time = left.rawLocalTimeMs.compareTo(right.rawLocalTimeMs);
    return time != 0
        ? time
        : left.originDeviceId.compareTo(right.originDeviceId);
  }
}

/// Central write-side deletion hook for recurring hot state.
///
/// Callers record exact record keys before committing the corresponding local
/// removal. A staged root-last initializer also participates once selected, so
/// a deletion cannot slip across its final preference-mutation barrier without
/// a journal entry in the namespace that becomes active.
abstract final class WebDavSyncTombstoneRecorder {
  static WebDavSyncBindingStore _bindingStore = WebDavSyncBindingStore();
  static WebDavSyncEngineStateRepository? _stateRepository;
  static WebDavSyncRegistryTombstoneRepository _registryRepository =
      WebDavSyncRegistryTombstoneStore();
  static WebDavSyncTombstoneDebugSink? _debugSink;
  static WebDavSyncRegistryTombstoneDebugSink? _registryDebugSink;

  static Future<void> recordForCurrentProfile(Iterable<String> keys) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return;
    }
    final scope = ProfileRuntime.capture();
    await recordForProfile(scope.profileId, keys);
  }

  static Future<bool> shouldRecordForCurrentProfile() async {
    if (_debugSink != null) return true;
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return false;
    }
    return ProfilePreferences.synchronizeExternalMutation(() async {
      try {
        final snapshot = await _bindingStore.load();
        final binding = _bindingForTombstones(snapshot);
        return binding != null && snapshot.namespaceFor(binding) != null;
      } catch (_) {
        // A broken sync journal must not break ordinary playback saves. The
        // runtime recovery/status path will surface the binding problem.
        return false;
      }
    }, marksMutation: false);
  }

  static Future<bool> shouldRecordRegistryRecords() async {
    if (_registryDebugSink != null) return true;
    return ProfilePreferences.synchronizeExternalMutation(() async {
      try {
        final snapshot = await _bindingStore.load();
        final binding = _bindingForTombstones(snapshot);
        return binding != null && snapshot.namespaceFor(binding) != null;
      } catch (_) {
        return false;
      }
    }, marksMutation: false);
  }

  /// Captures the exact namespace/device destination before a registry delete
  /// enters its SQL transaction. A debug sink acts as a bound destination so
  /// transaction/outbox tests exercise the production ordering.
  static Future<WebDavSyncRegistryTombstoneOutboxTarget?>
  registryOutboxTarget() async {
    if (_registryDebugSink != null) {
      return const WebDavSyncRegistryTombstoneOutboxTarget(
        namespaceId: '__debug_registry_outbox__',
        deviceId: '__debug_device__',
      );
    }
    return ProfilePreferences.synchronizeExternalMutation(() async {
      try {
        final snapshot = await _bindingStore.load();
        final binding = _bindingForTombstones(snapshot);
        if (binding == null) return null;
        final namespace = snapshot.namespaceFor(binding);
        if (namespace == null) return null;
        return WebDavSyncRegistryTombstoneOutboxTarget(
          namespaceId: namespace.id,
          deviceId: namespace.deviceId,
        );
      } catch (_) {
        // Devices with no readable binding remain on the existing fail-soft
        // path; a confirmed binding always returns a target and must enqueue.
        return null;
      }
    }, marksMutation: false);
  }

  /// Moves one already-committed SQL outbox batch into the file-backed store.
  /// Errors deliberately propagate so the registry retains the row for retry.
  static Future<void> drainRegistryOutboxBatch({
    required WebDavSyncRegistryTombstoneOutboxTarget target,
    required Set<WebDavSyncRegistryRecordId> records,
    required int timeMs,
  }) async {
    if (records.isEmpty) return;
    final sink = _registryDebugSink;
    if (target.namespaceId == '__debug_registry_outbox__' && sink != null) {
      await sink(Set<WebDavSyncRegistryRecordId>.unmodifiable(records));
      return;
    }
    await _registryRepository.record(
      target.namespaceId,
      deviceId: target.deviceId,
      records: records,
      nowMs: timeMs,
    );
  }

  /// Records circle-registry leaves before their SQL rows disappear. This is
  /// intentionally independent of [ProfileRuntime]: deleting a non-active
  /// profile/resource is still a circle mutation.
  static Future<void> recordRegistryRecords(
    Iterable<WebDavSyncRegistryRecordId> records,
  ) async {
    final sink = _registryDebugSink;
    if (sink != null) {
      final normalized = records.toSet();
      if (normalized.isNotEmpty) {
        await sink(Set<WebDavSyncRegistryRecordId>.unmodifiable(normalized));
      }
      return;
    }
    await ProfilePreferences.synchronizeExternalMutation(() async {
      late final WebDavSyncStoreSnapshot snapshot;
      try {
        snapshot = await _bindingStore.load();
      } catch (_) {
        return;
      }
      final binding = _bindingForTombstones(snapshot);
      if (binding == null) return;
      final namespace = snapshot.namespaceFor(binding);
      if (namespace == null) return;
      final normalized = records.toSet();
      if (normalized.isEmpty) return;
      try {
        await _registryRepository.record(
          namespace.id,
          deviceId: namespace.deviceId,
          records: normalized,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        await _degradeBinding(
          binding,
          'WebDAV sync could not record a registry deletion',
        );
      }
    }, marksMutation: true);
  }

  /// Read surface for the future circle-section builder. Unbound devices have
  /// no journal by definition.
  static Future<Map<String, WebDavSyncRegistryRecordTombstone>>
  loadRegistryRecordTombstones({int? clockOffsetMs, int? serverNowMs}) async {
    final snapshot = await _bindingStore.load();
    final binding = _bindingForTombstones(snapshot);
    if (binding == null) {
      return const <String, WebDavSyncRegistryRecordTombstone>{};
    }
    final namespace = snapshot.namespaceFor(binding);
    if (namespace == null) {
      return const <String, WebDavSyncRegistryRecordTombstone>{};
    }
    if (clockOffsetMs == null && serverNowMs == null) {
      return _registryRepository.load(namespace.id);
    }
    if (clockOffsetMs == null || serverNowMs == null) {
      throw ArgumentError(
        'Registry tombstone normalization requires offset and server time',
      );
    }
    return _registryRepository.freeze(
      namespace.id,
      clockOffsetMs: clockOffsetMs,
      serverNowMs: serverNowMs,
    );
  }

  static Future<void> recordForProfile(
    String localProfileId,
    Iterable<String> keys,
  ) async {
    final sink = _debugSink;
    if (sink != null) {
      final normalized = _normalizeKeys(keys);
      if (normalized.keys.isEmpty || normalized.invalid) return;
      await sink(localProfileId, Set<String>.unmodifiable(normalized.keys));
      return;
    }

    await ProfilePreferences.synchronizeExternalMutation(() async {
      late final WebDavSyncStoreSnapshot snapshot;
      try {
        snapshot = await _bindingStore.load();
      } catch (_) {
        return;
      }
      final binding = _bindingForTombstones(snapshot);
      if (binding == null) return;
      final namespace = snapshot.namespaceFor(binding);
      if (namespace == null) return;
      // Do not even enumerate a potentially huge clear set until sync is
      // actually bound. Unconfigured users must never pay or fail this guard.
      final normalized = _normalizeKeys(keys);
      final normalizedKeys = normalized.keys;
      if (normalizedKeys.isEmpty) return;
      if (normalized.invalid) {
        await _degradeBinding(
          binding,
          'WebDAV sync deletion history reached its safe limit',
        );
        return;
      }
      final repository =
          _stateRepository ??
          WebDavSyncEngineStateStore(bindingStore: _bindingStore);
      final now = DateTime.now().millisecondsSinceEpoch;
      var overflowed = false;
      try {
        await repository.update(namespace.id, (current) {
          final circleProfileId = current.hasAuthenticatedMaps
              ? current.circleToLocalProfiles!.entries
                    .where((entry) => entry.value == localProfileId)
                    .map((entry) => entry.key)
                    .firstOrNull
              : null;
          if (circleProfileId == null) {
            final pending = Map<String, WebDavSyncProfileEngineState>.from(
              current.pendingLocalProfiles,
            );
            final profile =
                pending[localProfileId] ?? const WebDavSyncProfileEngineState();
            final tombstones = Map<String, WebDavSyncTombstone>.from(
              profile.tombstones,
            );
            if (!_canRecordKeys(tombstones, normalizedKeys)) {
              overflowed = true;
              return current;
            }
            _recordKeys(
              tombstones,
              normalizedKeys,
              now: now,
              deviceId: namespace.deviceId,
            );
            pending[localProfileId] = profile.copyWith(
              tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(
                tombstones,
              ),
            );
            return current.copyWith(
              pendingLocalProfiles:
                  Map<String, WebDavSyncProfileEngineState>.unmodifiable(
                    pending,
                  ),
            );
          }
          final profiles = Map<String, WebDavSyncProfileEngineState>.from(
            current.profiles,
          );
          final profile =
              profiles[circleProfileId] ?? const WebDavSyncProfileEngineState();
          final tombstones = Map<String, WebDavSyncTombstone>.from(
            profile.tombstones,
          );
          if (!_canRecordKeys(tombstones, normalizedKeys)) {
            overflowed = true;
            return current;
          }
          _recordKeys(
            tombstones,
            normalizedKeys,
            now: now,
            deviceId: namespace.deviceId,
          );
          profiles[circleProfileId] = profile.copyWith(
            tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(
              tombstones,
            ),
          );
          return current.copyWith(
            profiles: Map<String, WebDavSyncProfileEngineState>.unmodifiable(
              profiles,
            ),
          );
        });
      } catch (_) {
        await _degradeBinding(
          binding,
          'WebDAV sync could not record a local deletion',
        );
        return;
      }
      if (overflowed) {
        await _degradeBinding(
          binding,
          'WebDAV sync deletion history reached its safe limit',
        );
        return;
      }
      for (final key in normalizedKeys) {
        ProfilePreferences.notifyWebDavSyncLocalChange(localProfileId, key);
      }
    }, marksMutation: true);
  }

  static ({Set<String> keys, bool invalid}) _normalizeKeys(
    Iterable<String> source,
  ) {
    final keys = <String>{};
    var invalid = false;
    for (final key in source) {
      if (key.isEmpty) continue;
      if (key.contains('\u0000') ||
          utf8.encode(key).length > WebDavSyncLimits.maxLogicalKeyBytes) {
        invalid = true;
        break;
      }
      keys.add(key);
      if (keys.length > WebDavSyncLimits.maxTombstonesPerProfile) {
        invalid = true;
        break;
      }
    }
    return (keys: keys, invalid: invalid);
  }

  static bool _canRecordKeys(
    Map<String, WebDavSyncTombstone> tombstones,
    Set<String> keys,
  ) {
    var projected = tombstones.length;
    for (final key in keys) {
      if (!tombstones.containsKey(key) &&
          ++projected > WebDavSyncLimits.maxTombstonesPerProfile) {
        return false;
      }
    }
    return true;
  }

  static Future<void> _degradeBinding(
    WebDavSyncBinding binding,
    String message,
  ) async {
    try {
      await _bindingStore.markError(binding.id, StateError(message));
    } catch (_) {
      // Tombstone recording is invoked from ordinary delete paths. A second
      // persistence failure cannot be allowed to cancel the local deletion.
    }
  }

  static bool _recordsTombstones(WebDavSyncBinding binding) =>
      binding.lifecycle == WebDavSyncLifecycle.awaitingSeedCommit ||
      binding.lifecycle == WebDavSyncLifecycle.rootVerified ||
      binding.lifecycle == WebDavSyncLifecycle.awaitingAdoption ||
      binding.lifecycle == WebDavSyncLifecycle.active ||
      binding.lifecycle == WebDavSyncLifecycle.error;

  static WebDavSyncBinding? _bindingForTombstones(
    WebDavSyncStoreSnapshot snapshot,
  ) {
    final active = snapshot.activeBinding;
    if (active != null && _recordsTombstones(active)) return active;
    final staged = snapshot.stagedBinding;
    return staged != null && _recordsTombstones(staged) ? staged : null;
  }

  static void _recordKeys(
    Map<String, WebDavSyncTombstone> tombstones,
    Set<String> keys, {
    required int now,
    required String deviceId,
  }) {
    for (final key in keys) {
      tombstones[key] = WebDavSyncTombstone(
        key: key,
        stamp: WebDavSyncStamp(normalizedTimeMs: now, originDeviceId: deviceId),
        rawLocalTime: true,
      );
    }
  }

  static void debugInstall({
    WebDavSyncBindingStore? bindingStore,
    WebDavSyncEngineStateRepository? stateRepository,
    WebDavSyncRegistryTombstoneRepository? registryRepository,
    WebDavSyncTombstoneDebugSink? sink,
    WebDavSyncRegistryTombstoneDebugSink? registrySink,
  }) {
    if (bindingStore != null) {
      _bindingStore = bindingStore;
      if (registryRepository == null) {
        _registryRepository = WebDavSyncRegistryTombstoneStore(
          bindingStore: bindingStore,
        );
      }
    }
    _stateRepository = stateRepository;
    if (registryRepository != null) {
      _registryRepository = registryRepository;
    }
    _debugSink = sink;
    _registryDebugSink = registrySink;
  }

  static void debugReset() {
    _bindingStore = WebDavSyncBindingStore();
    _stateRepository = null;
    _registryRepository = WebDavSyncRegistryTombstoneStore();
    _debugSink = null;
    _registryDebugSink = null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

String _checkedRegistryId(String value, String name) {
  if (value.isEmpty ||
      value.contains('\u0000') ||
      utf8.encode(value).length > 512) {
    throw ArgumentError.value(value, name, 'Invalid registry record ID');
  }
  return value;
}

final RegExp _safeRegistryDeviceId = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$',
);
