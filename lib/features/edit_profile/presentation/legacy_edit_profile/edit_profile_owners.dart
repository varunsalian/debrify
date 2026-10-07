import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart';

class EditProfileOwners {
  final EditProfileFormState form = EditProfileFormState();
  final EditProfileTvFocusState tv = EditProfileTvFocusState();
  final EditProfileAccessState access = EditProfileAccessState();
}
