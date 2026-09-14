import 'dart:async';

import 'package:flutter/foundation.dart';

import 'profile_scope.dart';

enum ProfileRuntimeMode { legacyCompatibility, profileCommitted }

class ProfileRuntime {
  ProfileRuntime._();

  static final ValueNotifier<ProfileScope?> scope =
      ValueNotifier<ProfileScope?>(null);
  static ProfileRuntimeMode? _mode;
  static int _epoch = 0;
  static bool _maintenance = false;
  static final Object _zoneScopeKey = Object();

  static ProfileRuntimeMode get mode =>
      _mode ?? (throw StateError('ProfileRuntime is not initialized'));

  static bool get isInitialized => _mode != null;
  static bool get isProfileCommitted =>
      mode == ProfileRuntimeMode.profileCommitted;
  static int get nextEpoch => ++_epoch;
  static bool get isInMaintenance => _maintenance;

  static void enterMaintenance() {
    if (!isInitialized || !isProfileCommitted) {
      throw StateError('Profile maintenance requires committed profile mode');
    }
    _maintenance = true;
  }

  static void initializeLegacy() {
    if (_mode == ProfileRuntimeMode.profileCommitted) {
      throw StateError(
        'Committed profile runtime cannot return to legacy mode',
      );
    }
    _mode = ProfileRuntimeMode.legacyCompatibility;
    scope.value = null;
  }

  static void initializeCommitted(ProfileScope initialScope) {
    _mode = ProfileRuntimeMode.profileCommitted;
    _epoch = initialScope.sessionEpoch;
    scope.value = initialScope;
  }

  /// Linux can require an interactive vault unlock after Flutter has started.
  /// This is the only supported one-way transition out of compatibility mode.
  static void promoteLegacyToCommitted(ProfileScope initialScope) {
    if (_mode != ProfileRuntimeMode.legacyCompatibility) {
      throw StateError('Only a legacy runtime can be promoted');
    }
    _mode = ProfileRuntimeMode.profileCommitted;
    _epoch = initialScope.sessionEpoch;
    scope.value = initialScope;
  }

  static void publish(ProfileScope next) {
    if (_mode != ProfileRuntimeMode.profileCommitted) {
      throw StateError('Cannot publish a profile in legacy mode');
    }
    scope.value = next;
    if (next.sessionEpoch > _epoch) _epoch = next.sessionEpoch;
  }

  static ProfileScope capture() {
    final overridden = Zone.current[_zoneScopeKey];
    if (overridden is ProfileScope) return overridden;
    return scope.value ?? (throw StateError('No active profile scope'));
  }

  static Future<T> withCapturedScope<T>(
    ProfileScope captured,
    Future<T> Function() body,
  ) => runZoned(body, zoneValues: <Object, Object>{_zoneScopeKey: captured});

  /// Long-lived infrastructure must not inherit the profile that started it.
  /// Keep other zone behavior (including error handling) intact.
  static Future<T> withoutCapturedScope<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: <Object, Object>{_zoneScopeKey: Object()});

  @visibleForTesting
  static void debugReset() {
    _mode = null;
    _epoch = 0;
    _maintenance = false;
    scope.value = null;
  }
}
