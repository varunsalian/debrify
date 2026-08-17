import 'dart:async';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/connection_resource.dart';
import 'profile_authorization.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

/// A revocable capability for work that may finish after the visible profile
/// changes (OAuth polling, token refreshes, and similar network operations).
///
/// The work stays bound to the initiating profile's storage generation. Before
/// it commits any result, the profile must still exist, be enabled, retain the
/// same authorization revision, and continue to allow [feature].
class ProfileAsyncAuthorization {
  static final Object _outboundCapabilityZoneKey = Object();
  final ProfileScope scope;
  final ProfileAuthorizationContext authorization;
  final ProfileFeature feature;
  final String? resourceId;
  final int? resourceAuthorizationRevision;
  final ResourcePermission resourcePermission;

  const ProfileAsyncAuthorization._({
    required this.scope,
    required this.authorization,
    required this.feature,
    required this.resourceId,
    required this.resourceAuthorizationRevision,
    required this.resourcePermission,
  });

  bool get isCurrentlyActive => ProfileRuntime.scope.value == scope;

  /// Returns null in legacy compatibility mode, where existing unscoped
  /// behavior must remain unchanged while the rollout flags are disabled.
  static Future<ProfileAsyncAuthorization?> capture(
    ProfileFeature feature, {
    String? resourceId,
    int? resourceAuthorizationRevision,
    ResourcePermission resourcePermission = ResourcePermission.use,
  }) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return null;
    }
    final scope = ProfileRuntime.capture();
    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final capability = ProfileAsyncAuthorization._(
      scope: scope,
      authorization: authorization,
      feature: feature,
      resourceId: resourceId,
      resourceAuthorizationRevision: resourceAuthorizationRevision,
      resourcePermission: resourcePermission,
    );
    await capability.run(() async {});
    return capability;
  }

  Future<T> run<T>(Future<T> Function() body) {
    return ProfileRuntime.withCapturedScope(scope, () async {
      final profile = await authorization.validate(ProfileBootstrap.registry);
      if (!profile.allows(feature)) {
        throw StateError('Profile authorization does not allow this feature');
      }
      final expectedResourceId = resourceId;
      final expectedResourceRevision = resourceAuthorizationRevision;
      if ((expectedResourceId == null) != (expectedResourceRevision == null)) {
        throw StateError('Incomplete resource authorization capability');
      }
      if (expectedResourceId != null) {
        final registry = ProfileBootstrap.registry;
        final resource = await registry.getResource(expectedResourceId);
        final grant = await registry.getGrant(
          authorization.profileId,
          expectedResourceId,
        );
        await authorization.validate(registry);
        if (resource == null ||
            !resource.enabled ||
            resource.authorizationRevision != expectedResourceRevision ||
            grant == null ||
            !grant.allows(resourcePermission)) {
          throw StateError('Connection authorization has changed');
        }
      }
      return body();
    });
  }

  /// Runs an interactive completion only while the initiating session is still
  /// the visible session. Background work that is intentionally allowed to
  /// finish for a retired scope can use [run]; account connection, settings,
  /// and UI cache publications must use this stricter form.
  Future<T> runIfCurrent<T>(Future<T> Function() body) async {
    if (!isCurrentlyActive) {
      throw StateError('Profile session changed before async completion');
    }
    return run(() async {
      if (!isCurrentlyActive) {
        throw StateError('Profile session changed before async completion');
      }
      return body();
    });
  }

  /// Runs payload construction and transport under one capability. Remote
  /// transport reads [currentOutboundBarrier] immediately before emitting
  /// bytes, closing the read/seal/send authorization gap without asking every
  /// compatibility getter to carry a second return value.
  Future<T> runIfCurrentAsOutbound<T>(Future<T> Function() body) =>
      runIfCurrent(
        () => runZoned(
          body,
          zoneValues: <Object, Object>{_outboundCapabilityZoneKey: this},
        ),
      );

  static Future<void> Function()? get currentOutboundBarrier {
    final capability = Zone.current[_outboundCapabilityZoneKey];
    if (capability is! ProfileAsyncAuthorization) return null;
    return () => capability.runIfCurrent(() async {});
  }
}
