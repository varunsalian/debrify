import 'profile_policy.dart';

enum UserProfileLifecycle { staging, active }

class UserProfile {
  final String id;
  final String name;
  final String? avatarKey;
  final UserProfileRole role;
  final ProfilePolicy policy;
  final int authorizationRevision;
  final UserProfileLifecycle lifecycle;
  final int visibleDataGeneration;
  final bool setupComplete;
  final bool pinResetRequired;
  final bool hasPin;
  final bool lockOnResume;
  final int? inactivityTimeoutMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? disabledAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.policy,
    required this.authorizationRevision,
    required this.lifecycle,
    required this.visibleDataGeneration,
    required this.setupComplete,
    required this.pinResetRequired,
    required this.hasPin,
    required this.lockOnResume,
    required this.createdAt,
    required this.updatedAt,
    this.avatarKey,
    this.inactivityTimeoutMinutes,
    this.disabledAt,
  });

  bool get isEnabled => disabledAt == null;
  bool get isAdmin => role == UserProfileRole.admin;
  bool allows(ProfileFeature feature) => policy.allows(role, feature);
}
