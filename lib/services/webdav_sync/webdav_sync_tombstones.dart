import 'dart:async';
import 'dart:convert';

import '../profiles/profile_runtime.dart';
import '../profiles/profile_preferences.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';

typedef WebDavSyncTombstoneDebugSink =
    FutureOr<void> Function(String localProfileId, Set<String> keys);

/// Central write-side deletion hook for recurring hot state.
///
/// Callers record exact record keys before committing the corresponding local
/// removal. A staged root-last initializer also participates once selected, so
/// a deletion cannot slip across its final preference-mutation barrier without
/// a journal entry in the namespace that becomes active.
abstract final class WebDavSyncTombstoneRecorder {
  static WebDavSyncBindingStore _bindingStore = WebDavSyncBindingStore();
  static WebDavSyncEngineStateRepository? _stateRepository;
  static WebDavSyncTombstoneDebugSink? _debugSink;

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
    WebDavSyncTombstoneDebugSink? sink,
  }) {
    if (bindingStore != null) _bindingStore = bindingStore;
    _stateRepository = stateRepository;
    _debugSink = sink;
  }

  static void debugReset() {
    _bindingStore = WebDavSyncBindingStore();
    _stateRepository = null;
    _debugSink = null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
