import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_profile_projection.dart';
import 'profile_lock_controller.dart';
import 'profile_runtime.dart';

/// Keeps native profile authority aligned with the foreground profile gate.
///
/// Bootstrap publishes before the gate decides whether the active profile may
/// enter. A locked picker must revoke that snapshot; a later successful PIN or
/// profile selection must publish it again. Registry callbacks cannot cover
/// this transition because the lock is intentionally session-only state.
class ProfileNativeLockBridge {
  ProfileNativeLockBridge._();

  static bool _installed = false;

  static void initialize() {
    if (_installed) return;
    _installed = true;
    ProfileLockController.instance.authorityRevision.addListener(
      _authorityChanged,
    );
  }

  static void _authorityChanged() {
    unawaited(
      _synchronize().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Native profile lock synchronization failed: $error');
      }),
    );
  }

  static Future<void> _synchronize() {
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileRuntime.isInMaintenance) {
      return Future<void>.value();
    }
    final lock = ProfileLockController.instance;
    return lock.hasActivatedProfile && lock.isUnlocked
        ? NativeProfileProjection.publish(ProfileRuntime.capture())
        : NativeProfileProjection.invalidate();
  }

  @visibleForTesting
  static Future<void> debugSynchronize() => _synchronize();

  @visibleForTesting
  static void debugReset() {
    if (_installed) {
      ProfileLockController.instance.authorityRevision.removeListener(
        _authorityChanged,
      );
    }
    _installed = false;
  }
}
