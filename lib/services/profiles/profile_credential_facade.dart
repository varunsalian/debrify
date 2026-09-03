import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import 'connection_resource_service.dart';
import 'device_key_provider.dart';
import 'profile_authorization.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';
import 'profile_registry.dart';

typedef ProfileCredentialRead = ({bool handled, String? value});
typedef ProfileCredentialPresence = ({
  bool handled,
  bool configured,
  bool pending,
});
typedef ProfileCredentialResourceAuthority = ({
  String resourceId,
  int resourceAuthorizationRevision,
});

enum ProfileCredentialDisconnectDisposition {
  legacy,
  noBinding,
  borrowerDetached,
  ownerDeleted;

  bool get handled => this != ProfileCredentialDisconnectDisposition.legacy;
  bool get shouldRevokeRemote =>
      this == ProfileCredentialDisconnectDisposition.ownerDeleted;
}

/// Compatibility routing for existing scalar StorageService credential APIs.
/// Legacy mode remains byte-for-byte on SecretVault; committed mode resolves
/// the explicitly bound resource and never creates a scoped credential key.
class ProfileCredentialFacade {
  ProfileCredentialFacade._();

  static const Map<String, _CredentialField> _fields =
      <String, _CredentialField>{
        'real_debrid_api_key': _CredentialField(
          ConnectionResourceType.realDebrid,
          'provider.realDebrid',
          'apiKey',
          'Real-Debrid',
          ProfileFeature.cloud,
        ),
        'torbox_api_key': _CredentialField(
          ConnectionResourceType.torbox,
          'provider.torbox',
          'apiKey',
          'TorBox',
          ProfileFeature.cloud,
        ),
        'premiumize_api_key': _CredentialField(
          ConnectionResourceType.premiumize,
          'provider.premiumize',
          'apiKey',
          'Premiumize',
          ProfileFeature.cloud,
        ),
        'alldebrid_api_key': _CredentialField(
          ConnectionResourceType.allDebrid,
          'provider.allDebrid',
          'apiKey',
          'AllDebrid',
          ProfileFeature.cloud,
        ),
        'mdblist_api_key': _CredentialField(
          ConnectionResourceType.mdblist,
          'tracker.mdblist',
          'apiKey',
          'MDBList',
          ProfileFeature.trackersAndDiscovery,
        ),
        'reddit_access_token': _CredentialField(
          ConnectionResourceType.reddit,
          'tracker.reddit',
          'accessToken',
          'Reddit',
          ProfileFeature.trackersAndDiscovery,
        ),
        'reddit_refresh_token': _CredentialField(
          ConnectionResourceType.reddit,
          'tracker.reddit',
          'refreshToken',
          'Reddit',
          ProfileFeature.trackersAndDiscovery,
        ),
        'trakt_access_token': _CredentialField(
          ConnectionResourceType.trakt,
          'tracker.trakt',
          'accessToken',
          'Trakt',
          ProfileFeature.trackersAndDiscovery,
        ),
        'trakt_refresh_token': _CredentialField(
          ConnectionResourceType.trakt,
          'tracker.trakt',
          'refreshToken',
          'Trakt',
          ProfileFeature.trackersAndDiscovery,
        ),
        'simkl_access_token': _CredentialField(
          ConnectionResourceType.simkl,
          'tracker.simkl',
          'accessToken',
          'Simkl',
          ProfileFeature.trackersAndDiscovery,
        ),
        'pikpak_email': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'email',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_password': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'password',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_access_token': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'accessToken',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_refresh_token': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'refreshToken',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_device_id': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'deviceId',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_captcha_token': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'captchaToken',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'pikpak_user_id': _CredentialField(
          ConnectionResourceType.pikpak,
          'provider.pikpak',
          'userId',
          'PikPak',
          ProfileFeature.cloud,
        ),
        'webdav_base_url': _CredentialField(
          ConnectionResourceType.webDav,
          'provider.webDav.legacy',
          'baseUrl',
          'WebDAV',
          ProfileFeature.cloud,
        ),
        'webdav_username': _CredentialField(
          ConnectionResourceType.webDav,
          'provider.webDav.legacy',
          'username',
          'WebDAV',
          ProfileFeature.cloud,
        ),
        'webdav_password': _CredentialField(
          ConnectionResourceType.webDav,
          'provider.webDav.legacy',
          'password',
          'WebDAV',
          ProfileFeature.cloud,
        ),
      };

  static bool handles(String key) => _fields.containsKey(key);

  /// Resolves the durable resource authority behind a compatibility scalar
  /// credential. Long-lived work stores this pair so rotating, revoking, or
  /// unsharing the connection invalidates the work before it can execute.
  static Future<ProfileCredentialResourceAuthority?> boundAuthority(
    String key,
  ) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return null;
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) return null;
    final resource = await _service(registry).authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.use,
      feature: field.feature,
    );
    if (resource.secretPending) return null;
    return (
      resourceId: resource.id,
      resourceAuthorizationRevision: resource.authorizationRevision,
    );
  }

  static Future<ProfileCredentialRead> read(String key) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return (handled: false, value: null);
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) return (handled: true, value: null);
    final resource = await registry.getResource(resourceId);
    if (resource?.secretPending == true) {
      return (handled: true, value: null);
    }
    final secret = await _service(registry).resolveSecretForUse(
      context: context,
      resourceId: resourceId,
      feature: field.feature,
    );
    return (handled: true, value: secret[field.field] as String?);
  }

  /// Answers whether the active profile has a usable binding without opening
  /// the secret. Settings and summary UIs use this instead of pulling API keys
  /// into widget state merely to render a Connected badge.
  static Future<ProfileCredentialPresence> isConfigured(String key) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return (handled: false, configured: false, pending: false);
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) {
      return (handled: true, configured: false, pending: false);
    }
    try {
      final resource = await _service(registry).authorize(
        context: context,
        resourceId: resourceId,
        permission: ResourcePermission.use,
        feature: field.feature,
      );
      if (resource.secretPending) {
        return (handled: true, configured: false, pending: true);
      }
      return (handled: true, configured: true, pending: false);
    } on ResourceAuthorizationException {
      return (handled: true, configured: false, pending: false);
    }
  }

  /// Resolves a scalar credential specifically for an encrypted setup
  /// transfer. Ordinary `use` access is intentionally insufficient: the
  /// resource grant must include [ResourcePermission.writeRemote] and the
  /// initiating profile must still allow remote transfer.
  static Future<ProfileCredentialRead> readForRemoteTransfer(String key) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return (handled: false, value: null);
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) return (handled: true, value: null);
    final resource = await registry.getResource(resourceId);
    if (resource?.secretPending == true) {
      return (handled: true, value: null);
    }
    try {
      final secret = await _service(registry).resolveSecretForUse(
        context: context,
        resourceId: resourceId,
        feature: ProfileFeature.remoteTransfer,
        permission: ResourcePermission.writeRemote,
      );
      return (handled: true, value: secret[field.field] as String?);
    } on ResourceAuthorizationException {
      // A use-only shared account remains usable by provider services, but it
      // must not become exportable merely because an old compatibility getter
      // can resolve it for execution.
      return (handled: true, value: null);
    }
  }

  static Future<bool> write(String key, String value) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return false;
    }
    final registry = ProfileBootstrap.registry;
    var context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    final service = _service(registry);
    if (resourceId == null) {
      await service.create(
        context: context,
        type: field.type,
        label: field.label,
        publicConfig: <String, dynamic>{'accountLabel': field.label},
        secretConfig: <String, dynamic>{field.field: value},
        bindingSlot: field.slot,
      );
      return true;
    }
    context = await ProfileAuthorizationContext.capture(registry);
    final resource = await registry.getResource(resourceId);
    if (resource?.secretPending == true) {
      await service.updateSecret(
        context: context,
        resourceId: resourceId,
        secretConfig: <String, dynamic>{field.field: value},
      );
      return true;
    }
    final current = await service.resolveSecretForUse(
      context: context,
      resourceId: resourceId,
      feature: ProfileFeature.manageConnections,
      permission: ResourcePermission.manage,
    );
    context = await ProfileAuthorizationContext.capture(registry);
    await service.updateSecret(
      context: context,
      resourceId: resourceId,
      secretConfig: <String, dynamic>{...current, field.field: value},
    );
    return true;
  }

  static Future<bool> remove(String key) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return false;
    }
    final registry = ProfileBootstrap.registry;
    var context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) return true;
    final service = _service(registry);
    final authorized = await service.authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    final current = authorized.secretPending
        ? <String, dynamic>{}
        : await service.resolveSecretForUse(
            context: context,
            resourceId: resourceId,
            feature: ProfileFeature.manageConnections,
            permission: ResourcePermission.manage,
          );
    current.remove(field.field);
    context = await ProfileAuthorizationContext.capture(registry);
    await service.updateSecret(
      context: context,
      resourceId: resourceId,
      secretConfig: current,
      allowEmpty: true,
    );
    return true;
  }

  /// Routes an explicit sign-out/disconnect independently from scalar field
  /// deletion so a borrower can detach without mutating the owner's secret.
  static Future<bool> disconnect(String key) async {
    return (await disconnectWithDisposition(key)).handled;
  }

  static Future<ProfileCredentialDisconnectDisposition>
  disconnectWithDisposition(String key) async {
    final field = _fields[key];
    if (field == null ||
        !ProfileRuntime.isInitialized ||
        ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      return ProfileCredentialDisconnectDisposition.legacy;
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      field.slot,
    );
    if (resourceId == null) {
      return ProfileCredentialDisconnectDisposition.noBinding;
    }
    final disposition = await _service(registry).disconnectBinding(
      context: context,
      slot: field.slot,
      resourceId: resourceId,
    );
    return disposition == ResourceDisconnectDisposition.ownerDeleted
        ? ProfileCredentialDisconnectDisposition.ownerDeleted
        : ProfileCredentialDisconnectDisposition.borrowerDetached;
  }

  static ConnectionResourceService _service(ProfileRegistry registry) =>
      ConnectionResourceService(
        registry: registry,
        cipher: DeviceKeyProvider.cipher,
      );
}

class _CredentialField {
  final ConnectionResourceType type;
  final String slot;
  final String field;
  final String label;
  final ProfileFeature feature;

  const _CredentialField(
    this.type,
    this.slot,
    this.field,
    this.label,
    this.feature,
  );
}
