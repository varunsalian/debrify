import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_guard.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_setup_options.dart';

class EditProfileSections {
  final EditProfileSetupOptions setup;
  final EditProfileAdminGuard admin;
  final EditProfileSelection selection;
  EditProfileSections(EditProfileDependencies deps)
    : setup = EditProfileSetupOptions(deps),
      admin = EditProfileAdminGuard(deps),
      selection = EditProfileSelection(deps);
}
