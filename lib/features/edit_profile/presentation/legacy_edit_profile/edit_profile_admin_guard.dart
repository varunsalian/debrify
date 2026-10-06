import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';

class EditProfileAdminGuard {
  final EditProfileDependencies _deps;
  EditProfileAdminGuard(this._deps);
  EditProfileSections get _sections => _deps.sections();
  Future<void> validateManagingAdmin(
    ProfileAuthorizationContext context,
  ) async {
    final actor = await context.validate(_deps.registry());
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
  }

  Future<ProfileAuthorizationContext> refreshSameManagingAdmin(
    String initiatingProfileId,
  ) async {
    final refreshed = await ProfileAuthorizationContext.capture(
      _deps.registry(),
    );
    if (refreshed.profileId != initiatingProfileId) {
      throw StateError('Managing profile session changed');
    }
    await _sections.admin.validateManagingAdmin(refreshed);
    return refreshed;
  }
}
