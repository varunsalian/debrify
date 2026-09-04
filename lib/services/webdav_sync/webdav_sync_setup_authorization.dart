import '../../models/profiles/profile_policy.dart';
import '../profiles/profile_async_authorization.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_bootstrap.dart';
import '../profiles/profile_runtime.dart';

abstract interface class WebDavSyncSetupAuthorization {
  Future<void> requireAdmin();

  Future<T> runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  );

  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  );
}

/// Profile-facing authorization used only while configuring sync.
///
/// Once M5 activates a binding, ordinary cycles use the engine's sealed copy
/// of the transport credentials and intentionally have no active-profile
/// dependency. Setup remains an Admin operation and revalidates the captured
/// Admin session around every asynchronous request and commit.
final class ProfileWebDavSyncSetupAuthorization
    implements WebDavSyncSetupAuthorization {
  const ProfileWebDavSyncSetupAuthorization();

  @override
  Future<void> requireAdmin() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      throw StateError('WebDAV Sync requires committed Profiles');
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final profile = await context.validate(registry);
    if (!profile.isAdmin ||
        !profile.allows(ProfileFeature.manageProfiles) ||
        !profile.allows(ProfileFeature.backupRestore)) {
      throw StateError('Only an authorized Admin can configure WebDAV Sync');
    }
  }

  @override
  Future<T> runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => _runForAdminSession(body);

  @override
  Future<T> runForActiveBinding<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) => _runForAdminSession(body);

  Future<T> _runForAdminSession<T>(
    Future<T> Function(Future<void> Function()? beforeSend) body,
  ) async {
    await requireAdmin();
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.backupRestore,
    );
    if (capability == null) {
      throw StateError('WebDAV Sync setup authorization is unavailable');
    }
    Future<void> validateAdmin() => capability.runIfCurrent(() async {
      final profile = await capability.authorization.validate(
        ProfileBootstrap.registry,
      );
      if (!profile.isAdmin ||
          !profile.allows(ProfileFeature.manageProfiles) ||
          !profile.allows(ProfileFeature.backupRestore)) {
        throw StateError('Only an authorized Admin can configure WebDAV Sync');
      }
    });

    return capability.runIfCurrentAsOutbound(() async {
      await validateAdmin();
      return body(() async {
        await ProfileAsyncAuthorization.currentOutboundBarrier?.call();
        await validateAdmin();
      });
    });
  }
}
