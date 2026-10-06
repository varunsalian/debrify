import 'dart:typed_data';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';

/// Immutable save input. The form is also focus/pointer locked while saving,
/// but the snapshot is the correctness boundary: no value is re-read after an
/// authorization, PIN KDF, grant write, or engine copy yields to the event
/// loop.
class _ProfileEditSnapshot {
  final String name;
  final String pin;
  final UserProfileRole role;
  final Set<ProfileFeature> features;
  final bool copyDefaults;
  final bool lockOnResume;
  final int inactivityMinutes;
  final String avatarKey;
  final Uint8List? pendingAvatarBytes;
  final List<ConnectionResource> resources;
  final Set<String> selectedResources;
  final Map<String, Set<ResourcePermission>> resourcePermissions;
  final Set<String> selectedEngines;

  const _ProfileEditSnapshot({
    required this.name,
    required this.pin,
    required this.role,
    required this.features,
    required this.copyDefaults,
    required this.lockOnResume,
    required this.inactivityMinutes,
    required this.avatarKey,
    required this.pendingAvatarBytes,
    required this.resources,
    required this.selectedResources,
    required this.resourcePermissions,
    required this.selectedEngines,
  });
}

typedef EditProfileSnapshot = _ProfileEditSnapshot;
