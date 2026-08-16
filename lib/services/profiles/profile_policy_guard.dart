import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';

class ProfilePolicyGuard {
  ProfilePolicyGuard._();

  /// Synchronous mirror of the ACTIVE profile for build-path gating (nav
  /// tabs, Home rows, the keyword segment). The gate updates it on every
  /// unlock/switch and main's policy load refreshes it; the async [allows]
  /// remains the operation-boundary check. Once profile mode is committed,
  /// a missing snapshot fails CLOSED — briefly hiding a surface is
  /// recoverable, rendering a forbidden one is not.
  static UserProfile? _active;

  static void updateActiveProfile(UserProfile? profile) => _active = profile;

  static bool allowsSync(ProfileFeature feature) {
    if (!ProfileRuntime.isProfileCommitted) return true;
    if (ProfileRuntime.isInMaintenance) return false;
    final profile = _active;
    return profile != null && profile.isEnabled && profile.allows(feature);
  }

  static Future<bool> allows(ProfileFeature feature) async {
    if (!ProfileRuntime.isProfileCommitted) return true;
    if (ProfileRuntime.isInMaintenance) return false;
    final profile = await ProfileBootstrap.registry.getProfile(
      ProfileRuntime.capture().profileId,
    );
    return profile != null && profile.isEnabled && profile.allows(feature);
  }

  static Future<void> require(ProfileFeature feature) async {
    if (!await allows(feature)) {
      throw StateError('This feature is disabled for the active profile');
    }
  }
}
