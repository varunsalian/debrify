import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:flutter/material.dart';

class EditProfileDependencies {
  final EditProfileOwners owners;
  final EditProfileSections Function() sections;
  final ProfileRegistry Function() registry;
  final ProfilePinService Function() pins;
  final UserProfile? Function() profile;
  final Future<(List<ConnectionResource>, List<ProfileEngineAssignment>)>
  Function()?
  Function()
  setupOptionsLoader;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final ProfileAuthorizationContext Function() readAuthorization;
  final void Function(ProfileAuthorizationContext) writeAuthorization;
  final bool Function() readShowFeaturePolicyControls;
  final ProfilePolicy Function({
    required UserProfileRole role,
    required Set<ProfileFeature> selected,
    ProfilePolicy? existing,
    bool controlsShown,
  })
  policyFor;
  EditProfileDependencies({
    required this.owners,
    required this.sections,
    required this.registry,
    required this.pins,
    required this.profile,
    required this.setupOptionsLoader,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.readAuthorization,
    required this.writeAuthorization,
    required this.readShowFeaturePolicyControls,
    required this.policyFor,
  });
  ProfileAuthorizationContext get authorization => readAuthorization();
  set authorization(ProfileAuthorizationContext value) =>
      writeAuthorization(value);
  bool get showFeaturePolicyControls => readShowFeaturePolicyControls();
}
