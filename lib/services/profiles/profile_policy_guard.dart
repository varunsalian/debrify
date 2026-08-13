import '../../models/profiles/profile_policy.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';

class ProfilePolicyGuard {
  ProfilePolicyGuard._();

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
