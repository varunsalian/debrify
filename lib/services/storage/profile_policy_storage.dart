import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';

final class ProfilePolicyStorage {
  const ProfilePolicyStorage._();

  static Future<bool> profileAllowsAdultContent() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    try {
      final scope = ProfileRuntime.capture();
      final profile = await ProfileBootstrap.registry.getProfile(
        scope.profileId,
      );
      return profile?.allows(ProfileFeature.allowAdultContent) == true;
    } catch (_) {
      return false;
    }
  }
}
