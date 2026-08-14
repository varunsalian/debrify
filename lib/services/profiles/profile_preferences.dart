import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  void _assertWritable() {
    _assertReadable();
    if (_capturedAccess ==
        CapturedProfilePreferenceAccess.nativeProjectionReadOnly) {
      throw StateError('Native projection preference access is read-only');
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
  Future<bool> setBool(String key, bool value) =>
      _write(() => _delegate.setBool(_physical(key), value));

  @override
  Future<bool> setInt(String key, int value) =>
      _write(() => _delegate.setInt(_physical(key), value));

  @override
  Future<bool> setDouble(String key, double value) =>
      _write(() => _delegate.setDouble(_physical(key), value));

  @override
  Future<bool> setString(String key, String value) =>
      _write(() => _delegate.setString(_physical(key), value));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(() => _delegate.setStringList(_physical(key), value));

  @override
  Future<bool> remove(String key) async {
    _assertWritable();
    if (_scope != null && await ProfileCredentialFacade.remove(key)) {
      return true;
    }
    return _write(() => _delegate.remove(_physical(key)));
  }

  Future<bool> _write(Future<bool> Function() operation) async {
    _assertWritable();
    final success = await operation();
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

  static const Set<String> allowedKeys = <String>{
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
