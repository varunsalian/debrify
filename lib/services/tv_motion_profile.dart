import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

/// Optional Spotlight scroll motion, local to this profile and installation.
enum TvMotionProfile {
  snappy('snappy', 'Snappy', 'Keep this TV\'s default Spotlight scrolling'),
  smooth('smooth', 'Smooth', 'Smooth scrolling between Spotlight shelves');

  const TvMotionProfile(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  static TvMotionProfile fromPref(String? value) =>
      value == 'smooth' ? smooth : snappy;
}

abstract final class TvMotionController {
  static const preferenceKey = 'tv_motion_profile';
  static final ValueNotifier<TvMotionProfile> notifier = ValueNotifier(
    TvMotionProfile.snappy,
  );
  static TvMotionProfile get current => notifier.value;
  static int _revision = 0;
  static final Lock _preferences = Lock();

  // Capture before ProfilePreferences.instance's first await. A profile
  // switch must not redirect a pending read/write to the incoming profile.
  static Future<T> _inProfile<T>(Future<T> Function() operation) {
    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      return ProfileRuntime.withCapturedScope(
        ProfileRuntime.capture(),
        operation,
      );
    }
    return operation();
  }

  static void resetProfileScope() {
    _revision++;
    notifier.value = TvMotionProfile.snappy;
  }

  /// Warmed before runApp and during profile activation/rollback.
  static Future<void> warm() async {
    final revision = ++_revision;
    var profile = TvMotionProfile.snappy;
    try {
      profile = await _inProfile(
        () => _preferences.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          return TvMotionProfile.fromPref(prefs.getString(preferenceKey));
        }),
      );
    } catch (_) {
      // Failed reads must not retain another profile's Smooth choice.
      debugPrint(
        'TvMotionController: using default after preference read failed',
      );
    }
    if (revision == _revision) notifier.value = profile;
  }

  /// Publish synchronously so rapid choices retain their input order.
  static Future<void> select(TvMotionProfile profile) async {
    _revision++;
    notifier.value = profile;
    try {
      await _inProfile(
        () => _preferences.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          await prefs.setString(preferenceKey, profile.value);
        }),
      );
    } catch (_) {
      debugPrint('TvMotionController: could not persist motion preference');
    }
  }
}
