import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_actions.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_guard.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_avatar_picker.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_grants.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_form.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_parts.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_save.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_setup_options.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_editor.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_profile_pane.dart';

class EditProfileSections {
  final EditProfileSetupOptions setup;
  final EditProfileAdminGuard admin;
  final EditProfileAdminActions adminActions;
  final EditProfileAvatarPicker avatar;
  final EditProfileSave save;
  final EditProfileGrants grants;
  final EditProfileSelection selection;
  final EditProfileTvNavigation tvNav;
  final EditProfilePhoneForm phone;
  final EditProfilePhoneParts phoneParts;
  final EditProfileTvEditor tvEditor;
  final EditProfileTvProfilePane tvProfile;
  final EditProfileTvPanes tvPanes;
  final EditProfileAccessRows access;
  EditProfileSections(EditProfileDependencies deps)
    : setup = EditProfileSetupOptions(deps),
      admin = EditProfileAdminGuard(deps),
      adminActions = EditProfileAdminActions(deps),
      avatar = EditProfileAvatarPicker(deps),
      save = EditProfileSave(deps),
      grants = EditProfileGrants(deps),
      selection = EditProfileSelection(deps),
      tvNav = EditProfileTvNavigation(deps),
      phone = EditProfilePhoneForm(deps),
      phoneParts = EditProfilePhoneParts(deps),
      tvEditor = EditProfileTvEditor(deps),
      tvProfile = EditProfileTvProfilePane(deps),
      tvPanes = EditProfileTvPanes(deps),
      access = EditProfileAccessRows(deps);
}
