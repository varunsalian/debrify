import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:flutter/material.dart';

class EditProfileTvFocusState {
  EditProfileTvSection tvSection = EditProfileTvSection.profile;
  late final List<FocusNode> tvTabFocusNodes;
  final tvContentFocus = FocusNode(
    debugLabel: 'Edit profile content',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final tvBackFocus = FocusNode(debugLabel: 'Edit profile back');
  FocusNode? tvLastContentFocus;
  int tvFocusRequest = 0;
}
