import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/connection_resource.dart';
import 'profile_authorization.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';

enum DeviceJobKind { download, recording, schedule, retry }

/// Registry-side ownership ledger shared by all execution backends. Backends
/// remain authoritative for execution; this ledger is the cross-platform
/// authority for ownership, deletion checks, and Admin reconciliation.
class DeviceJobStore {
  DeviceJobStore._();

  static Future<ProfileJobAuthorization?> authorize(
    ProfileFeature feature,
  ) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return null;
    }
    final context = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await context.validate(ProfileBootstrap.registry);
    if (!profile.allows(feature)) {
      throw StateError('Profile feature is disabled');
    }
    return ProfileJobAuthorization(
      profileId: profile.id,
      profileAuthorizationRevision: profile.authorizationRevision,
      sessionEpoch: context.sessionEpoch,
    );
  }

  static Future<void> register({
    required String backend,
    required String externalJobId,
    required DeviceJobKind kind,
    required ProfileJobAuthorization authorization,
    String? resourceId,
    int? resourceAuthorizationRevision,
  }) => ProfileBootstrap.registry.upsertJobOwnership(
    backend: backend,
    externalJobId: externalJobId,
    kind: kind.name,
    ownerProfileId: authorization.profileId,
    resourceId: resourceId,
    profileAuthorizationRevision: authorization.profileAuthorizationRevision,
    resourceAuthorizationRevision: resourceAuthorizationRevision,
  );

  static Future<void> registerSnapshot({
    required String backend,
    required String externalJobId,
    required DeviceJobKind kind,
    required String ownerProfileId,
    required int profileAuthorizationRevision,
    String? resourceId,
    int? resourceAuthorizationRevision,
    bool terminal = false,
  }) => ProfileBootstrap.registry.upsertJobOwnership(
    backend: backend,
    externalJobId: externalJobId,
    kind: kind.name,
    ownerProfileId: ownerProfileId,
    resourceId: resourceId,
    profileAuthorizationRevision: profileAuthorizationRevision,
    resourceAuthorizationRevision: resourceAuthorizationRevision,
    terminalAtMs: terminal ? DateTime.now().millisecondsSinceEpoch : null,
  );

  static Future<void> reconcileBackend({
    required String backend,
    required String ownerProfileId,
    required Iterable<String> presentExternalJobIds,
  }) => ProfileBootstrap.registry.markMissingJobsTerminal(
    backend: backend,
    ownerProfileId: ownerProfileId,
    presentExternalJobIds: presentExternalJobIds.toSet(),
  );

  static Future<bool> validateAuthorization({
    required String profileId,
    required int profileAuthorizationRevision,
    required ProfileFeature feature,
    String? resourceId,
    int? resourceAuthorizationRevision,
    ResourcePermission requiredResourcePermission = ResourcePermission.download,
  }) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return profileId == 'legacy-admin-v1';
    }
    final profile = await ProfileBootstrap.registry.getProfile(profileId);
    final profileValid =
        profile != null &&
        profile.isEnabled &&
        profile.authorizationRevision == profileAuthorizationRevision &&
        profile.allows(feature);
    if (!profileValid) return false;
    if (resourceId == null) return resourceAuthorizationRevision == null;
    if (resourceAuthorizationRevision == null) return false;
    final resource = await ProfileBootstrap.registry.getResource(resourceId);
    final grant = await ProfileBootstrap.registry.getGrant(
      profileId,
      resourceId,
    );
    return resource != null &&
        resource.enabled &&
        resource.authorizationRevision == resourceAuthorizationRevision &&
        grant != null &&
        grant.allows(requiredResourcePermission);
  }

  static Future<void> markTerminal({
    required String backend,
    required String externalJobId,
  }) => ProfileBootstrap.registry.markJobTerminal(
    backend: backend,
    externalJobId: externalJobId,
  );
}

class ProfileJobAuthorization {
  final String profileId;
  final int profileAuthorizationRevision;
  final int sessionEpoch;

  const ProfileJobAuthorization({
    required this.profileId,
    required this.profileAuthorizationRevision,
    required this.sessionEpoch,
  });

  Map<String, Object?> toNativeArguments() => <String, Object?>{
    'ownerProfileId': profileId,
    'profileAuthorizationRevision': profileAuthorizationRevision,
  };
}
