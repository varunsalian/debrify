import 'dart:typed_data';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileFormState {
  late final TextEditingController name;
  final TextEditingController pin = TextEditingController();
  late UserProfileRole role;
  late Set<ProfileFeature> features;
  bool saving = false;
  bool copyDefaults = true;
  late bool lockOnResume;
  late int inactivityMinutes;
  late String avatarKey;

  /// Set on the first Pages toggle — until then a save preserves the stored
  /// policy (edit) or the role defaults (create), same as when no feature
  /// control existed at all.
  bool policyTouched = false;
  late bool seedDownloads;
  late bool seedRemote;

  /// A picked-but-not-saved image. Held in memory and ingested at save time,
  /// once the target profile's id exists (a created profile has none until
  /// `createStaged`). Nothing touches disk if the user backs out.
  Uint8List? pendingAvatarBytes;
}
