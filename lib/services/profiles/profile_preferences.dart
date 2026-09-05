import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import 'profile_preference_budget.dart';
import 'profile_preference_portability.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';
import 'profile_credential_facade.dart';
import 'tvos_profile_recovery_store.dart';

typedef WebDavSyncLocalChangeSink =
    void Function(String localProfileId, String logicalKey);

/// SharedPreferences-compatible facade that applies the captured profile
/// generation in committed mode and is byte-for-byte legacy-compatible before
/// migration commits.
enum CapturedProfilePreferenceAccess {
  nativeProjectionReadOnly,
  migration,
  profileCreation,
  restore,
  connectionGrant,
  syncApply,

  /// The dev audit export, which inventories every profile's keys. Read-only
  /// like [nativeProjectionReadOnly] — a diagnostic that can write is a
  /// diagnostic that can corrupt the thing it is measuring.
  diagnosticsReadOnly,
}

/// Opaque proof that no scoped profile preference changed after a coordinated
/// read. Callers may carry this across network work, but only
/// [ProfilePreferences.runIfMutationSnapshotCurrent] can validate it.
final class ProfilePreferenceMutationToken {
  const ProfilePreferenceMutationToken._(this._revision);

  final int _revision;
}

/// A routine optimistic-concurrency miss: local profile state changed while a
/// sync target or complete seed was being prepared.
final class ProfilePreferenceMutationConflict implements Exception {
  const ProfilePreferenceMutationConflict();

  @override
  String toString() =>
      'Local profile data changed while WebDAV sync was preparing; try again';
}

class ProfilePreferences implements SharedPreferences {
  static const String webDavSyncRegistryLogicalKey =
      'remote_webdav_sync_registry_records_v1';

  /// Notification-only key: playback writes still sync without save UI.
  static const String webDavSyncPlaybackLibraryLogicalKey =
      'remote_webdav_sync_playback_library_v1';

  static const String webDavSyncLibraryLogicalKey =
      'remote_webdav_sync_library_records_v1';
  static final Lock _atomicStringListMutationLock = Lock();
  static final Object _exclusiveMutationZoneKey = Object();
  static int _mutationRevision = 0;
  static int _activeMutations = 0;
  static Completer<void>? _activeMutationsDrained;
  static Completer<void>? _exclusiveMutationReleased;

  ProfilePreferences._(
    this._delegate,
    this._scope, {
    required bool enforceCurrentSession,
    CapturedProfilePreferenceAccess? capturedAccess,
  }) : _enforceCurrentSession = enforceCurrentSession,
       _capturedAccess = capturedAccess;

  final SharedPreferences _delegate;
  final ProfileScope? _scope;
  final bool _enforceCurrentSession;
  final CapturedProfilePreferenceAccess? _capturedAccess;

  /// Runs a coherent profile-preference read and captures its mutation token.
  /// Ordinary writers are excluded only for the duration of [read].
  static Future<T> captureMutationSnapshot<T>(
    Future<T> Function(ProfilePreferenceMutationToken token) read,
  ) => _runExclusiveMutation(
    () => read(ProfilePreferenceMutationToken._(_mutationRevision)),
  );

  /// Captures a revision without holding the preference barrier across later
  /// asynchronous work. The caller must validate it at its commit edge.
  static Future<ProfilePreferenceMutationToken> captureMutationToken() =>
      captureMutationSnapshot((token) async => token);

  /// Runs [operation] only when [token] still describes current local profile
  /// preferences. The lock stays held through the operation's commit edge so a
  /// writer cannot slip between the comparison and a local/server commit.
  static Future<T> runIfMutationSnapshotCurrent<T>(
    ProfilePreferenceMutationToken token,
    Future<T> Function() operation,
  ) => _runExclusiveMutation(operation, expectedToken: token);

  /// Coordinates an external mutation that belongs to profile hot state, such
  /// as the tombstone journal written immediately before a preference removal.
  static Future<T> synchronizeExternalMutation<T>(
    Future<T> Function() operation, {
    required bool marksMutation,
  }) => _runOrdinaryMutation((markMutated) async {
    final result = await operation();
    if (marksMutation) markMutated();
    return result;
  });

  /// Runs an ordinary preference mutation. Unlike a process-wide async mutex,
  /// this permits unrelated writes to make progress together; it only waits
  /// while WebDAV owns the short snapshot/commit barrier. State changes before
  /// the first await are atomic on Dart's isolate, so an exclusive acquirer
  /// cannot slip between the barrier check and active-writer registration.
  static Future<T> _runOrdinaryMutation<T>(
    Future<T> Function(void Function() markMutated) operation,
  ) async {
    _assertMutationOutsideExclusive();
    while (true) {
      final released = _exclusiveMutationReleased;
      if (released == null) break;
      await released.future;
    }
    _activeMutations++;
    _activeMutationsDrained ??= Completer<void>();
    var mutated = false;
    try {
      return await operation(() => mutated = true);
    } finally {
      if (mutated) _mutationRevision++;
      _activeMutations--;
      if (_activeMutations == 0) {
        _activeMutationsDrained?.complete();
        _activeMutationsDrained = null;
      }
    }
  }

  static void _assertMutationOutsideExclusive() {
    if (Zone.current[_exclusiveMutationZoneKey] != true) return;
    throw StateError(
      'A profile preference mutation cannot run inside a WebDAV snapshot',
    );
  }

  /// Serializes WebDAV snapshot/commit edges and waits for already-started
  /// ordinary mutations to settle. Nested read-only guards are allowed, but a
  /// mutation attempted from inside one fails immediately instead of creating
  /// a lock inversion.
  static Future<T> _runExclusiveMutation<T>(
    Future<T> Function() operation, {
    ProfilePreferenceMutationToken? expectedToken,
  }) async {
    if (Zone.current[_exclusiveMutationZoneKey] == true) {
      if (expectedToken != null &&
          expectedToken._revision != _mutationRevision) {
        throw const ProfilePreferenceMutationConflict();
      }
      return operation();
    }

    while (true) {
      final released = _exclusiveMutationReleased;
      if (released == null) break;
      await released.future;
    }
    final released = Completer<void>();
    _exclusiveMutationReleased = released;
    try {
      final drained = _activeMutationsDrained;
      if (drained != null) await drained.future;
      if (expectedToken != null &&
          expectedToken._revision != _mutationRevision) {
        throw const ProfilePreferenceMutationConflict();
      }
      return await runZoned(
        operation,
        zoneValues: <Object, Object>{_exclusiveMutationZoneKey: true},
      );
    } finally {
      _exclusiveMutationReleased = null;
      released.complete();
    }
  }

  /// Scalar preferences consumed directly by native Android components.
  /// Successful runtime mutations of these keys must refresh the atomic
  /// native projection before the setter returns.
  static const Set<String> nativeProjectionKeys = <String>{
    'tv_trailer_underlay_enabled',
    'tv_ui_scale_percent',
    'tv_low_res_render',
    'recording_engine_enabled',
    'iptv_player_guide_style',
    'tv_player_controls_style',
    'debrify_tv_player_style',
    'subtitle_auto_sync_enabled',
    'player_default_aspect_index_tv',
    'player_night_mode_index',
    'player_system_audio_effects',
    'skip_segments_enabled',
    'skip_segment_provider',
    'player_default_subtitle_language',
    'player_default_audio_language',
    'subtitle_size_index',
    'subtitle_style_index',
    'subtitle_color_index',
    'subtitle_bg_index',
    'subtitle_outline_color_index',
    'subtitle_elevation_index',
    'subtitle_bold',
    'subtitle_selected_font_id',
  };

  /// Installed by the native authority bridge after bootstrap. Keeping the
  /// callback here avoids coupling this preference facade back to the
  /// projection implementation that already depends on it.
  static Future<void> Function(ProfileScope scope)? nativeProjectionPublisher;

  /// Armed only while recurring WebDAV sync has an active scheduler. The
  /// callback is deliberately synchronous; preference writes never await sync.
  static WebDavSyncLocalChangeSink? webDavSyncLocalChangeSink;

  static void notifyWebDavSyncLocalChange(
    String localProfileId,
    String logicalKey,
  ) {
    try {
      webDavSyncLocalChangeSink?.call(localProfileId, logicalKey);
    } catch (_) {
      // Sync scheduling must never turn a successful local write into failure.
    }
  }

  static Future<ProfilePreferences> instance() async {
    if (!ProfileRuntime.isInitialized) {
      throw StateError('ProfilePreferences opened before ProfileBootstrap');
    }
    final delegate = await SharedPreferences.getInstance();
    final captured = ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted
        ? ProfileRuntime.capture()
        : null;
    return ProfilePreferences._(
      delegate,
      captured,
      enforceCurrentSession: captured != null,
    );
  }

  static Future<ProfilePreferences> forCapturedScope(
    ProfileScope scope,
    CapturedProfilePreferenceAccess access,
  ) async => ProfilePreferences._(
    await SharedPreferences.getInstance(),
    scope,
    enforceCurrentSession: false,
    capturedAccess: access,
  );

  void _assertReadable() {
    if (_enforceCurrentSession &&
        (!ProfileRuntime.isInitialized ||
            !ProfileRuntime.isProfileCommitted ||
            ProfileRuntime.capture() != _scope)) {
      throw StateError(
        'A stale ProfilePreferences instance crossed a profile session',
      );
    }
  }

  static const Set<CapturedProfilePreferenceAccess> _readOnlyAccess =
      <CapturedProfilePreferenceAccess>{
        CapturedProfilePreferenceAccess.nativeProjectionReadOnly,
        CapturedProfilePreferenceAccess.diagnosticsReadOnly,
      };

  void _assertWritable() {
    _assertReadable();
    if (_readOnlyAccess.contains(_capturedAccess)) {
      throw StateError(
        '${_capturedAccess!.name} preference access is read-only',
      );
    }
  }

  String _physical(String logical) => _scope?.preferenceKey(logical) ?? logical;

  String? _logical(String physical) {
    final scope = _scope;
    if (scope == null) return physical;
    final prefix = scope.preferencePrefix;
    return physical.startsWith(prefix)
        ? physical.substring(prefix.length)
        : null;
  }

  @override
  Set<String> getKeys() {
    _assertReadable();
    return _delegate.getKeys().map(_logical).whereType<String>().toSet();
  }

  @override
  Object? get(String key) {
    _assertReadable();
    return _delegate.get(_physical(key));
  }

  @override
  bool? getBool(String key) {
    _assertReadable();
    return _delegate.getBool(_physical(key));
  }

  @override
  int? getInt(String key) {
    _assertReadable();
    return _delegate.getInt(_physical(key));
  }

  @override
  double? getDouble(String key) {
    _assertReadable();
    return _delegate.getDouble(_physical(key));
  }

  @override
  String? getString(String key) {
    _assertReadable();
    return _delegate.getString(_physical(key));
  }

  @override
  List<String>? getStringList(String key) {
    _assertReadable();
    return _delegate.getStringList(_physical(key));
  }

  @override
  bool containsKey(String key) {
    _assertReadable();
    return _delegate.containsKey(_physical(key));
  }

  @override
  Future<bool> setBool(String key, bool value) => _write(
    () => _delegate.setBool(_physical(key), value),
    logicalKey: key,
    budgetKey: _physical(key),
    budgetValue: value,
  );

  @override
  Future<bool> setInt(String key, int value) => _write(
    () => _delegate.setInt(_physical(key), value),
    logicalKey: key,
    budgetKey: _physical(key),
    budgetValue: value,
  );

  @override
  Future<bool> setDouble(String key, double value) => _write(
    () => _delegate.setDouble(_physical(key), value),
    logicalKey: key,
    budgetKey: _physical(key),
    budgetValue: value,
  );

  @override
  Future<bool> setString(String key, String value) => _write(
    () => _delegate.setString(_physical(key), value),
    logicalKey: key,
    budgetKey: _physical(key),
    budgetValue: value,
  );

  @override
  Future<bool> setStringList(String key, List<String> value) => _write(
    () => _delegate.setStringList(_physical(key), value),
    logicalKey: key,
    budgetKey: _physical(key),
    budgetValue: value,
  );

  /// Serializes a string-list read/modify/write against every scoped instance.
  /// The lock covers the physical profile key, so callers can safely update an
  /// inactive captured profile without racing an active-session mutation.
  /// Returning null from [update] leaves the stored value unchanged.
  Future<bool> mutateStringListAtomically(
    String key,
    List<String>? Function(List<String>? current) update,
  ) {
    // Check before taking the list-specific lock. Otherwise a guarded WebDAV
    // callback could wait on a writer that is itself waiting for the WebDAV
    // barrier, recreating the lock inversion this guard is meant to prevent.
    _assertMutationOutsideExclusive();
    return _atomicStringListMutationLock.synchronized(() async {
      _assertWritable();
      final physical = _physical(key);
      final current = _delegate.getStringList(physical);
      final next = update(
        current == null ? null : List<String>.unmodifiable(current),
      );
      if (next == null) return true;
      final frozen = List<String>.unmodifiable(next);
      return _write(
        () => _delegate.setStringList(physical, frozen),
        logicalKey: key,
        budgetKey: physical,
        budgetValue: frozen,
      );
    });
  }

  /// Persist a coherent group of native-consumed scalar settings and publish
  /// their projection once. Used by native UI surfaces that return a complete
  /// settings snapshot after one interaction.
  Future<bool> setNativeProjectionBatch(Map<String, Object> values) async {
    _assertWritable();
    for (final entry in values.entries) {
      if (!nativeProjectionKeys.contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'key',
          'Not a native projection key',
        );
      }
      if (entry.value is! bool &&
          entry.value is! int &&
          entry.value is! String) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Unsupported scalar type',
        );
      }
      final physical = _physical(entry.key);
      if (_capturedAccess == null &&
          !ProfilePreferenceBudget.admits(_delegate, physical, entry.value)) {
        return false;
      }
    }

    final success = await _runOrdinaryMutation((markMutated) async {
      var success = true;
      var mutated = false;
      try {
        for (final entry in values.entries) {
          _assertWritable();
          final physical = _physical(entry.key);
          final wrote = switch (entry.value) {
            bool value => await _delegate.setBool(physical, value),
            int value => await _delegate.setInt(physical, value),
            String value => await _delegate.setString(physical, value),
            _ => false,
          };
          mutated = wrote || mutated;
          success = wrote && success;
        }
        return success;
      } finally {
        if (mutated) markMutated();
      }
    });
    final scope = _scope;
    final publisher = nativeProjectionPublisher;
    _assertWritable();
    if (success &&
        scope != null &&
        _capturedAccess == null &&
        publisher != null) {
      await publisher(scope);
    }
    if (success &&
        scope != null &&
        TvOsProfileRecoveryStore.supported &&
        ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted) {
      await TvOsProfileRecoveryStore.checkpointPreferenceMutation();
    }
    return success;
  }

  /// Applies a recurring-sync target verbatim to one captured profile scope.
  ///
  /// Null is intentionally unsupported: omission and null never delete local
  /// state in hot sync; deletions travel through authenticated tombstones.
  /// A persisted engine-side pending target makes this redo-safe if one of the
  /// underlying SharedPreferences writes fails part-way through.
  Future<bool> applySyncBatch(
    Map<String, Object> values, {
    required void Function() authorizationBarrier,
    ProfilePreferenceMutationToken? expectedMutationToken,
    Future<void> Function()? beforeWrite,
    bool replayCommittedTarget = false,
    Future<void> Function(ProfileScope scope, Set<String> changedKeys)?
    afterApply,
  }) async {
    _assertWritable();
    authorizationBarrier();
    if (_capturedAccess != CapturedProfilePreferenceAccess.syncApply ||
        _scope == null) {
      throw StateError('Sync batch apply requires a captured profile scope');
    }
    for (final entry in values.entries) {
      _validateSyncEntry(entry.key, entry.value);
    }

    final writes =
        <({String logical, String physical, Object value, int delta})>[];
    final success = await _runExclusiveMutation(() async {
      _assertWritable();

      for (final entry in values.entries) {
        final physical = _physical(entry.key);
        final existed = _delegate.containsKey(physical);
        final current = existed ? _delegate.get(physical) : null;
        if (existed && _sameSyncValue(current, entry.value)) continue;
        writes.add((
          logical: entry.key,
          physical: physical,
          value: entry.value,
          delta:
              ProfilePreferenceBudget.entryFootprint(physical, entry.value) -
              (existed
                  ? ProfilePreferenceBudget.entryFootprint(physical, current)
                  : 0),
        ));
      }
      writes.sort((left, right) {
        final byGrowth = left.delta.compareTo(right.delta);
        return byGrowth != 0 ? byGrowth : left.logical.compareTo(right.logical);
      });
      if (ProfilePreferenceBudget.enforced) {
        var projectedBytes = ProfilePreferenceBudget.measure(_delegate);
        for (final write in writes) {
          if (!ProfilePreferenceBudget.admitsProjectedDelta(
            currentBytes: projectedBytes,
            deltaBytes: write.delta,
          )) {
            return false;
          }
          projectedBytes += write.delta;
        }
      }

      // Persist the crash-replay target only after the optimistic revision
      // check, while every ordinary writer is excluded from the gap before the
      // first local write.
      authorizationBarrier();
      if (beforeWrite != null) {
        await beforeWrite();
        authorizationBarrier();
      }
      if (writes.isEmpty && !replayCommittedTarget) return true;

      var success = true;
      var mutated = false;
      try {
        for (final write in writes) {
          _assertWritable();
          // Recheck against the live database as well as the all-or-nothing
          // preflight. A non-profile raw writer can still consume tvOS
          // headroom while this async batch is in flight.
          if (ProfilePreferenceBudget.enforced &&
              !ProfilePreferenceBudget.admits(
                _delegate,
                write.physical,
                write.value,
              )) {
            return false;
          }
          final wrote = switch (write.value) {
            bool value => await _delegate.setBool(write.physical, value),
            int value => await _delegate.setInt(write.physical, value),
            double value => await _delegate.setDouble(write.physical, value),
            String value => await _delegate.setString(write.physical, value),
            List<String> value => await _delegate.setStringList(
              write.physical,
              value,
            ),
            _ => false,
          };
          mutated = wrote || mutated;
          authorizationBarrier();
          success = wrote && success;
          if (!wrote) break;
        }
        return success;
      } finally {
        if (mutated) _mutationRevision++;
      }
    }, expectedToken: expectedMutationToken);
    if (!success) return false;
    if (writes.isEmpty && !replayCommittedTarget) return true;

    _assertWritable();
    authorizationBarrier();
    final scope = _scope;
    final changedKeys = Set<String>.unmodifiable(
      writes.isEmpty ? values.keys : writes.map((write) => write.logical),
    );
    if (ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        ProfileRuntime.scope.value == scope &&
        changedKeys.any(nativeProjectionKeys.contains)) {
      await nativeProjectionPublisher?.call(scope);
      authorizationBarrier();
    }
    if (TvOsProfileRecoveryStore.supported &&
        ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted) {
      await TvOsProfileRecoveryStore.checkpointPreferenceMutation();
      authorizationBarrier();
    }
    if (afterApply != null) {
      authorizationBarrier();
      await afterApply(scope, changedKeys);
      authorizationBarrier();
    }
    return true;
  }

  static bool _sameSyncValue(Object? current, Object next) {
    if (current is List && next is List<String>) {
      return current.length == next.length &&
          Iterable<int>.generate(
            next.length,
          ).every((index) => current[index] == next[index]);
    }
    // SharedPreferences preserves int and double as distinct storage types.
    // Dart's numeric equality considers `1 == 1.0`, but skipping that write
    // would leave getDouble/getInt observing the wrong type after sync.
    return current.runtimeType == next.runtimeType && current == next;
  }

  static void _validateSyncEntry(String key, Object value) {
    if (key.isEmpty || key.length > 256 || key.contains('\u0000')) {
      throw ArgumentError.value(key, 'key', 'Invalid sync preference key');
    }
    if (value is double && !value.isFinite) {
      throw ArgumentError.value(value, key, 'Sync value must be finite');
    }
    if (value is bool || value is int || value is double || value is String) {
      return;
    }
    if (value is List<String>) return;
    throw ArgumentError.value(value, key, 'Unsupported sync preference value');
  }

  @override
  Future<bool> remove(String key) async {
    _assertWritable();
    if (_scope != null && await ProfileCredentialFacade.remove(key)) {
      return true;
    }
    return _write(() => _delegate.remove(_physical(key)), logicalKey: key);
  }

  /// [budgetKey]/[budgetValue] describe the growth this write would cause.
  /// Omitting them skips admission, which is correct for `remove`: shrinking
  /// the database is always safe.
  Future<bool> _write(
    Future<bool> Function() operation, {
    String? logicalKey,
    String? budgetKey,
    Object? budgetValue,
  }) async {
    _assertWritable();
    var unchanged = false;
    final success = await _runOrdinaryMutation((markMutated) async {
      _assertWritable();
      if (_capturedAccess == null && budgetKey != null) {
        final previous = _delegate.get(budgetKey);
        unchanged =
            previous == budgetValue ||
            (previous is List<String> &&
                budgetValue is List<String> &&
                listEquals(previous, budgetValue));
      }
      // Only ordinary runtime writes are gated. Every captured-scope caller
      // (migration, restore, profile creation) treats a `false` result as fatal
      // and throws, and during bootstrap an uncaught throw prevents the app from
      // starting — trading the platform kill for a Dart one. Those paths are
      // bounded elsewhere: migration by its preflight, restore by the recovery
      // envelope caps, creation by its fixed 24-key scalar list. Ordinary writes
      // are both the sole source of unbounded growth and the only ones whose
      // result is never inspected, so refusing them can only skip a save.
      if (budgetKey != null &&
          _capturedAccess == null &&
          !ProfilePreferenceBudget.admits(_delegate, budgetKey, budgetValue)) {
        return false;
      }
      final success = await operation();
      if (success && !unchanged) markMutated();
      return success;
    });
    final scope = _scope;
    final publisher = nativeProjectionPublisher;
    if (success &&
        scope != null &&
        _capturedAccess == null &&
        logicalKey != null &&
        nativeProjectionKeys.contains(logicalKey) &&
        publisher != null) {
      await publisher(scope);
    }
    if (success &&
        _scope != null &&
        TvOsProfileRecoveryStore.supported &&
        ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted) {
      await TvOsProfileRecoveryStore.checkpointPreferenceMutation();
    }
    if (success &&
        _capturedAccess == null &&
        scope != null &&
        logicalKey != null &&
        !unchanged) {
      // Keep key admission (including special library keys) in the scheduler,
      // but omit values that the portable payload deliberately excludes. Use
      // this mutation's value, not a later read that could race another save.
      // A remove has a null value and remains eligible for synchronization.
      final excludedValue =
          ProfilePreferencePortability.allowsKey(logicalKey) &&
          !ProfilePreferencePortability.prepareValue(
            logicalKey,
            budgetValue,
          ).include;
      if (!excludedValue) {
        notifyWebDavSyncLocalChange(scope.profileId, logicalKey);
      }
    }
    return success;
  }

  @override
  Future<bool> clear() async {
    _assertWritable();
    if (_scope == null) return _delegate.clear();
    var success = true;
    for (final key in getKeys()) {
      success = await remove(key) && success;
    }
    return success;
  }

  @override
  Future<void> reload() => _delegate.reload();

  @override
  @Deprecated('This method is now a no-op, and should no longer be called.')
  Future<bool> commit() => _delegate.commit();

  @visibleForTesting
  ProfileScope? get debugScope => _scope;

  @visibleForTesting
  static void debugResetMutationTracking() => _mutationRevision = 0;
}

/// Explicit unscoped store. Device keys must be registered, keeping accidental
/// expansion visible during development and tests.
class DevicePreferences {
  DevicePreferences._(this._delegate);

  final SharedPreferences _delegate;

  /// Activity/process decisions written by native Android before Dart starts.
  /// These describe the running Flutter surface, not any user profile.
  static const String tvTrailerUnderlayEffectiveKey =
      'tv_trailer_underlay_effective';
  static const String tvLowResRenderActiveKey = 'tv_low_res_render_active';
  static const Set<String> nativeLaunchSnapshotKeys = <String>{
    tvTrailerUnderlayEffectiveKey,
    tvLowResRenderActiveKey,
  };

  static const Set<String> allowedKeys = <String>{
    ...nativeLaunchSnapshotKeys,
    'profiles_runtime_mode_v1',
    'profiles_committed_once_v1',
    'profiles_feature_enabled_v1',
    'profiles_native_mirror_v1',
    'profiles_native_projection_v1',
    'profiles_linux_wrapped_key_v1',
    'app_onboarding_complete_v1',
    'remote_static_keypair_v1',
    'remote_paired_devices_v1',
    'remote_known_receivers_v1',
    'remote_control_enabled',
    'remote_intro_shown',
    'remote_tv_device_name',
    'remote_last_device',
    'update_auto_check_enabled',
    'update_ignored_version',
    'support_remote_config_cache_v1',
    'dismissed_donation_campaign_ids_v1',
    'recording_max_concurrent',
    'recording_battery_nudge_dismissed_at',
    'iptv_ios_recording_notice_dismissed',
    'pending_download_queue_v1',
    'paused_download_queue_v1',
    'download_legacy_queue_imported_v2',
    'download_legacy_plugin_authority_v1',
    'subtitle_custom_fonts',
    'tvos_multi_profile_top_shelf_enabled',
    'profile_gate_style_v1',
    'profile_gate_always_ask_v1',
    'webdav_sync_state_v1',
    'webdav_sync_db_adoption_gate_v1',
  };

  static Future<DevicePreferences> instance() async =>
      DevicePreferences._(await SharedPreferences.getInstance());

  void _assertAllowed(String key) {
    if (!allowedKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unregistered device preference');
    }
  }

  String? getString(String key) {
    _assertAllowed(key);
    return _delegate.getString(key);
  }

  bool? getBool(String key) {
    _assertAllowed(key);
    return _delegate.getBool(key);
  }

  int? getInt(String key) {
    _assertAllowed(key);
    return _delegate.getInt(key);
  }

  List<String>? getStringList(String key) {
    _assertAllowed(key);
    return _delegate.getStringList(key);
  }

  Future<bool> setString(String key, String value) {
    _assertAllowed(key);
    return _delegate.setString(key, value);
  }

  /// Device-owned collections that can grow must still participate in the
  /// database-wide tvOS budget. Small fixed device flags keep the ordinary
  /// setters; bounded stores such as WebDAV sync use this guarded variant.
  Future<bool> setBudgetedString(String key, String value) async {
    _assertAllowed(key);
    if (!ProfilePreferenceBudget.admits(_delegate, key, value)) return false;
    return _delegate.setString(key, value);
  }

  Future<bool> setBool(String key, bool value) {
    _assertAllowed(key);
    return _delegate.setBool(key, value);
  }

  Future<bool> setInt(String key, int value) {
    _assertAllowed(key);
    return _delegate.setInt(key, value);
  }

  Future<bool> setStringList(String key, List<String> value) {
    _assertAllowed(key);
    return _delegate.setStringList(key, value);
  }

  Future<bool> remove(String key) {
    _assertAllowed(key);
    return _delegate.remove(key);
  }
}
