import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import 'connection_resource_service.dart';
import 'device_key_provider.dart';
import 'profile_authorization.dart';
import 'profile_bootstrap.dart';
import 'profile_runtime.dart';

/// Bridges collection-shaped legacy APIs to encrypted connection resources.
/// Callers retain their existing model API, while committed profile mode never
/// persists credential-bearing collection data in profile preferences.
class ProfileCollectionResourceFacade {
  ProfileCollectionResourceFacade._();

  static bool get active =>
      ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted;

  static Future<List<Map<String, dynamic>>> read({
    required Set<ConnectionResourceType> types,
    required ProfileFeature feature,
    bool forSettings = false,
    bool forRemoteTransfer = false,
  }) async {
    if (!active) return const <Map<String, dynamic>>[];
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final resources = (await registry.listGrantedResources(
      context.profileId,
    )).where((resource) => types.contains(resource.type));
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final result = <Map<String, dynamic>>[];
    for (final resource in resources) {
      final grant = await registry.getGrant(context.profileId, resource.id);
      if (grant == null) continue;
      final localSettings = await registry.getProfileResourceSettings(
        context.profileId,
        resource.id,
      );
      if (!forSettings && localSettings?.enabled == false) continue;
      final readOnly =
          resource.ownerProfileId != context.profileId ||
          !grant.allows(ResourcePermission.manage);
      final canReveal =
          !readOnly && grant.allows(ResourcePermission.revealSecret);
      Map<String, dynamic> secret;
      if (resource.secretPending && !forSettings) {
        continue;
      } else if (resource.secretPending) {
        secret = _redactedSettingsRecord(resource);
      } else if (forRemoteTransfer) {
        if (!grant.allows(ResourcePermission.writeRemote)) continue;
        secret = await service.resolveSecretForUse(
          context: context,
          resourceId: resource.id,
          feature: ProfileFeature.remoteTransfer,
          permission: ResourcePermission.writeRemote,
        );
      } else if (forSettings && !canReveal) {
        secret = _redactedSettingsRecord(resource);
      } else if (forSettings) {
        secret = await service.revealSecret(
          context: context,
          resourceId: resource.id,
          feature: ProfileFeature.manageConnections,
        );
      } else {
        // An independently restricted grant is not an error for the rest of
        // the collection. Preflight that stable property before decryption;
        // authorization exceptions from resolve must still propagate because
        // they can mean the profile/session changed during this read.
        if (!grant.allows(ResourcePermission.use)) continue;
        secret = await service.resolveSecretForUse(
          context: context,
          resourceId: resource.id,
          feature: feature,
        );
      }
      result.add(<String, dynamic>{
        ...secret,
        'enabled':
            localSettings?.enabled ?? (secret['enabled'] as bool? ?? true),
        // Preserve the provider identity before exposing the configuration's
        // resource identity to existing Home, Discover and cache consumers.
        if (resource.type == ConnectionResourceType.stremioAddon &&
            secret['manifest_id'] == null &&
            secret['id'] != resource.id &&
            secret['id'] is String)
          'manifest_id': secret['id'],
        'id': resource.id,
        '_connectionResourceId': resource.id,
        '_connectionResourceRevision': resource.authorizationRevision,
        '_connectionResourceReadOnly': readOnly,
        '_connectionResourceCredentialsRedacted':
            forSettings && (!canReveal || resource.secretPending),
        '_connectionResourceSecretPending': resource.secretPending,
      });
    }
    // Close the collection-level race after the final item. Callers that do
    // not install their own async authorization barrier must never receive a
    // partial collection decrypted under a session that has since ended.
    await context.validate(registry);
    return result;
  }

  static Future<void> setLocalEnabled({
    required String resourceId,
    required int resourceRevision,
    required ProfileFeature feature,
    required bool enabled,
  }) async {
    if (!active) throw StateError('Connection resources are not active');
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    await registry.setProfileResourceSettings(
      profileId: context.profileId,
      resourceId: resourceId,
      enabled: enabled,
      settings: const <String, dynamic>{},
      actingAuthorizationRevision: context.authorizationRevision,
      expectedResourceAuthorizationRevision: resourceRevision,
      feature: feature,
    );
    await context.validate(registry);
  }

  static Future<void> replace({
    required Set<ConnectionResourceType> types,
    required ProfileFeature feature,
    required List<ResourceCollectionItem> items,
    bool revokeBorrowers = false,
  }) async {
    if (!active) {
      throw StateError('Connection resources are not active');
    }
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    await ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    ).replaceOwnedCollection(
      context: context,
      types: types,
      feature: feature,
      items: items,
      revokeBorrowers: revokeBorrowers,
    );
  }

  static Future<int> ownedBorrowerCount({
    required String resourceId,
    required ProfileFeature feature,
  }) async {
    if (!active) return 0;
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final resource = await service.authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: feature,
    );
    if (resource.ownerProfileId != context.profileId) {
      throw const ResourceAuthorizationException(
        'Only the connection owner can inspect sharing',
      );
    }
    final count = await registry.countResourceBorrowers(
      resourceId: resourceId,
      ownerProfileId: context.profileId,
    );
    await context.validate(registry);
    return count;
  }

  static Future<void> deleteOwned({
    required String resourceId,
    required bool revokeBorrowers,
  }) async {
    if (!active) throw StateError('Connection resources are not active');
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    final service = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    if (revokeBorrowers) {
      await service.deleteOwnedResourceForAll(
        context: context,
        resourceId: resourceId,
      );
      return;
    }
    final resource = await service.authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    if (resource.ownerProfileId != context.profileId) {
      throw const ResourceAuthorizationException(
        'Only the connection owner can delete it',
      );
    }
    await registry.deleteOwnedResource(
      resourceId: resourceId,
      ownerProfileId: context.profileId,
      revokeBorrowers: false,
      actingProfileId: context.profileId,
      actingAuthorizationRevision: context.authorizationRevision,
      expectedResourceAuthorizationRevision: resource.authorizationRevision,
    );
  }

  /// Replaces a compatibility collection and returns the only records callers
  /// may publish or execute afterwards.
  ///
  /// Collection inputs are not capabilities: new entries have no resource
  /// authority and retained entries receive a new authorization revision.
  /// Binding the readback to the visible scope also prevents a profile switch
  /// from redirecting UI/cache publication to another profile.
  static Future<List<Map<String, dynamic>>> replaceAndRead({
    required Set<ConnectionResourceType> types,
    required ProfileFeature feature,
    required List<ResourceCollectionItem> items,
    bool forSettings = false,
    bool revokeBorrowers = false,
  }) async {
    if (!active) {
      throw StateError('Connection resources are not active');
    }
    final expectedScope = ProfileRuntime.scope.value;
    if (expectedScope == null) {
      throw StateError('No visible profile scope');
    }
    await replace(
      types: types,
      feature: feature,
      items: items,
      revokeBorrowers: revokeBorrowers,
    );
    if (ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while saving connections');
    }
    final records = await read(
      types: types,
      feature: feature,
      forSettings: forSettings,
    );
    if (ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while loading saved connections');
    }
    return records;
  }

  /// Revalidates a credential-bearing compatibility model immediately before
  /// use. The embedded revision makes an object captured before revoke,
  /// rotation, profile switch, or restore unusable even though it still holds
  /// decrypted fields in memory.
  static Future<void> authorizeExecution({
    required String? resourceId,
    required int? resourceRevision,
    required Set<ConnectionResourceType> acceptedTypes,
    required ProfileFeature feature,
    bool allowUnbound = false,
  }) async {
    if (!active) return;
    final registry = ProfileBootstrap.registry;
    final context = await ProfileAuthorizationContext.capture(registry);
    if (resourceId == null || resourceRevision == null) {
      if (!allowUnbound) {
        throw const ResourceAuthorizationException(
          'Connection authority is missing',
        );
      }
      final profile = await context.validate(registry);
      if (!profile.allows(feature)) {
        throw const ResourceAuthorizationException(
          'Profile feature is disabled',
        );
      }
      return;
    }
    final resource =
        await ConnectionResourceService(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
        ).authorize(
          context: context,
          resourceId: resourceId,
          permission: ResourcePermission.use,
          feature: feature,
        );
    if (!acceptedTypes.contains(resource.type) ||
        resource.authorizationRevision != resourceRevision) {
      throw const ResourceAuthorizationException(
        'Connection authority changed',
      );
    }
  }

  static Map<String, dynamic> _redactedSettingsRecord(
    ConnectionResource resource,
  ) => switch (resource.type) {
    ConnectionResourceType.webDav => <String, dynamic>{
      'id': resource.id,
      'name': resource.label,
      'baseUrl': '',
      'username': '',
      'password': '',
    },
    ConnectionResourceType.jackett ||
    ConnectionResourceType.prowlarr => <String, dynamic>{
      'id': resource.id,
      'name': resource.label,
      'type': resource.type == ConnectionResourceType.prowlarr
          ? 'prowlarr'
          : 'jackett',
      'base_url': '',
      'api_key': '',
      'enabled': true,
    },
    ConnectionResourceType.iptvM3u ||
    ConnectionResourceType.iptvXtream => <String, dynamic>{
      'id': resource.id,
      'name': resource.label,
      'url': '',
      'addedAt': DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ).toIso8601String(),
    },
    ConnectionResourceType.stremioAddon => <String, dynamic>{
      'id': resource.id,
      'name': resource.publicConfig['addonName'] as String? ?? resource.label,
      'manifest_url': '',
      'base_url': '',
      'enabled': true,
      'types':
          (resource.publicConfig['contentKinds'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      'resources': const <String>[],
    },
    _ => <String, dynamic>{'id': resource.id, 'name': resource.label},
  };
}
