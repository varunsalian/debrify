import 'profile_session_unavailable.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'profile_lock_controller.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';

class ProfileAuthorizationContext {
  final String profileId;
  final int authorizationRevision;
  final int sessionEpoch;

  const ProfileAuthorizationContext._({
    required this.profileId,
    required this.authorizationRevision,
    required this.sessionEpoch,
  });

  static Future<ProfileAuthorizationContext> capture(
    ProfileRegistry registry,
  ) async {
    final scope = ProfileRuntime.capture();
    final profile = await registry.getProfile(scope.profileId);
    if (profile == null || !profile.isEnabled) {
      throw ProfileSessionUnavailable('Active profile is unavailable');
    }
    return ProfileAuthorizationContext._(
      profileId: profile.id,
      authorizationRevision: profile.authorizationRevision,
      sessionEpoch: scope.sessionEpoch,
    );
  }

  /// Converts the picker lock back into a local Admin session after either a
  /// successful PIN verification or an explicit choice of an unpinned Admin.
  /// The profile and runtime are re-read around the async boundary so a stale
  /// picker card cannot unlock a changed, disabled, or different profile.
  static Future<UserProfile> unlockActiveAdminForManagement(
    ProfileRegistry registry, {
    required UserProfile expectedProfile,
    required bool pinVerified,
  }) async {
    final before = ProfileRuntime.capture();
    if (before.profileId != expectedProfile.id ||
        ProfileLockController.instance.lockedProfileId.value !=
            expectedProfile.id) {
      throw StateError('Profile management session is unavailable');
    }
    final current = await registry.getProfile(expectedProfile.id);
    final after = ProfileRuntime.capture();
    if (after != before ||
        current == null ||
        !current.isEnabled ||
        current.authorizationRevision !=
            expectedProfile.authorizationRevision ||
        !current.isAdmin ||
        !current.allows(ProfileFeature.manageProfiles) ||
        current.pinResetRequired ||
        (current.hasPin && !pinVerified)) {
      throw StateError('Profile management authorization has changed');
    }
    ProfileLockController.instance.unlock(current);
    return current;
  }

  Future<UserProfile> validate(ProfileRegistry registry) async {
    if (ProfileRuntime.isInMaintenance) {
      throw StateError('Profile storage is in maintenance mode');
    }
    if (ProfileLockController.instance.lockedProfileId.value != null) {
      throw ProfileSessionUnavailable('Profile session is locked');
    }
    final scope = ProfileRuntime.capture();
    if (scope.profileId != profileId || scope.sessionEpoch != sessionEpoch) {
      throw ProfileSessionUnavailable(
        'Profile authorization session has ended',
      );
    }
    final profile = await registry.getProfile(profileId);
    if (profile == null || !profile.isEnabled) {
      throw ProfileSessionUnavailable('Authorized profile is unavailable');
    }
    if (profile.authorizationRevision != authorizationRevision) {
      throw ProfileSessionUnavailable('Profile authorization has changed');
    }
    return profile;
  }
}
