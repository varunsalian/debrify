import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_preference_budget.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';
import 'profile_credential_facade.dart';
import 'tvos_profile_recovery_store.dart';

/// SharedPreferences-compatible facade that applies the captured profile
/// generation in committed mode and is byte-for-byte legacy-compatible before
/// migration commits.
enum CapturedProfilePreferenceAccess {
  nativeProjectionReadOnly,
  migration,
  profileCreation,
  restore,

  /// The dev audit export, which inventories every profile's keys. Read-only
  /// like [nativeProjectionReadOnly] — a diagnostic that can write is a
  /// diagnostic that can corrupt the thing it is measuring.
  diagnosticsReadOnly,
}

class ProfilePreferences implements SharedPreferences {
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

    var success = true;
    for (final entry in values.entries) {
      _assertWritable();
      final physical = _physical(entry.key);
      success =
          switch (entry.value) {
            bool value => await _delegate.setBool(physical, value),
            int value => await _delegate.setInt(physical, value),
            String value => await _delegate.setString(physical, value),
            _ => false,
          } &&
          success;
    }
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
