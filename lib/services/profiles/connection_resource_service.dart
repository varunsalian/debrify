import 'dart:convert';
import 'dart:math';

import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import 'device_key_provider.dart';
import 'profile_authorization.dart';
import 'profile_registry.dart';

class ResourceAuthorizationException implements Exception {
  final String message;
  const ResourceAuthorizationException(this.message);

  @override
  String toString() => message;
}

class ResourceImpactRequiredException extends ResourceAuthorizationException {
  const ResourceImpactRequiredException(super.message);
}

enum ResourceDisconnectDisposition { borrowerDetached, ownerDeleted }

class ConnectionResourceService {
  static const int secretPayloadVersion = 1;

  final ProfileRegistry registry;
  final DeviceSecretCipher cipher;

  ConnectionResourceService({required this.registry, required this.cipher});

  Future<ConnectionResource> create({
    required ProfileAuthorizationContext context,
    required ConnectionResourceType type,
    required String label,
    required Map<String, dynamic> publicConfig,
    required Map<String, dynamic> secretConfig,
    String? bindingSlot,
  }) async {
    final owner = await context.validate(registry);
    if (!owner.allows(ProfileFeature.manageConnections) ||
        owner.role == UserProfileRole.child) {
      throw const ResourceAuthorizationException(
        'Profile cannot manage connections',
      );
    }
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty) throw ArgumentError.value(label, 'label');
    final normalizedPublic = _normalizePublicConfig(type, publicConfig);
    if (secretConfig.isEmpty) {
      throw ArgumentError.value(
        secretConfig,
        'secretConfig',
        'Secret required',
      );
    }
    final id = _newId();
    final aad = _associatedData(
      resourceId: id,
      type: type,
      ownerProfileId: owner.id,
      publicSchemaVersion: 1,
      payloadVersion: secretPayloadVersion,
    );
    final sealed = await cipher.seal(
      utf8.encode(jsonEncode(secretConfig)),
      associatedData: aad,
    );
    final resource = ConnectionResource(
      id: id,
      type: type,
      label: normalizedLabel,
      ownerProfileId: owner.id,
      publicConfig: Map<String, dynamic>.unmodifiable(normalizedPublic),
      publicSchemaVersion: 1,
      authorizationRevision: 1,
      enabled: true,
    );
    // Sealing can be deliberately expensive and may yield to a profile
    // switch, lock, policy change, or Admin revocation.  Never publish a
    // resource merely because its actor was valid before that await.
    await context.validate(registry);
    await registry.insertResource(
      resource: resource,
      sealedSecretPayload: sealed,
      secretPayloadVersion: secretPayloadVersion,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
      bindingSlot: bindingSlot,
      actingProfileId: context.profileId,
      actingAuthorizationRevision: context.authorizationRevision,
    );
    return resource;
  }

  /// Replaces one of the compatibility collection APIs as a single registry
  /// transaction. Encryption happens before the transaction; none of the new
  /// resources become visible until every envelope has been prepared.
  Future<void> replaceOwnedCollection({
    required ProfileAuthorizationContext context,
    required Set<ConnectionResourceType> types,
    required ProfileFeature feature,
    required List<ResourceCollectionItem> items,
  }) async {
    final owner = await context.validate(registry);
    if (!owner.allows(ProfileFeature.manageConnections) ||
        !owner.allows(feature) ||
        owner.role == UserProfileRole.child) {
      throw const ResourceAuthorizationException(
        'Profile cannot manage connections',
      );
    }
    final replacements = <PreparedConnectionResource>[];
    for (final item in items) {
      if (!types.contains(item.type)) {
        throw ArgumentError.value(item.type, 'items');
      }
      final sourceId = item.sourceResourceId;
      if (sourceId != null) {
        final source = await registry.getResource(sourceId);
        final grant = await registry.getGrant(owner.id, sourceId);
        if (source == null || grant == null || !types.contains(source.type)) {
          throw const ResourceAuthorizationException(
            'Collection source is unavailable',
          );
        }
        if (source.ownerProfileId != owner.id) {
          // Borrowed connections stay in the graph unchanged. In particular,
          // never turn a decrypted use-only compatibility model into a new
          // borrower-owned secret.
          continue;
        }
        if (!grant.allows(ResourcePermission.manage)) {
          throw const ResourceAuthorizationException(
            'Collection source cannot be managed',
          );
        }
      }
      final id = _newId();
      final publicConfig = _normalizePublicConfig(item.type, item.publicConfig);
      final sealed = await cipher.seal(
        utf8.encode(jsonEncode(item.secretConfig)),
        associatedData: _associatedData(
          resourceId: id,
          type: item.type,
          ownerProfileId: owner.id,
          publicSchemaVersion: 1,
          payloadVersion: secretPayloadVersion,
        ),
      );
      replacements.add(
        PreparedConnectionResource(
          resource: ConnectionResource(
            id: id,
            type: item.type,
            label: item.label.trim().isEmpty
                ? item.type.name
                : item.label.trim(),
            ownerProfileId: owner.id,
            publicConfig: publicConfig,
            publicSchemaVersion: 1,
            authorizationRevision: 1,
            enabled: true,
          ),
          sealedSecretPayload: sealed,
          secretPayloadVersion: secretPayloadVersion,
        ),
      );
    }
    await context.validate(registry);
    await registry.replaceOwnedResourceCollection(
      ownerProfileId: owner.id,
      types: types,
      replacements: replacements,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
      actingProfileId: context.profileId,
      actingAuthorizationRevision: context.authorizationRevision,
      actingFeature: feature,
    );
  }

  Future<Map<String, dynamic>> revealSecret({
    required ProfileAuthorizationContext context,
    required String resourceId,
    ProfileFeature feature = ProfileFeature.manageConnections,
  }) async {
    final authorized = await authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.revealSecret,
      feature: feature,
    );
    final value = await _openSecret(resourceId);
    await _revalidateResource(
      context: context,
      expected: authorized,
      permission: ResourcePermission.revealSecret,
      feature: feature,
    );
    return value;
  }

  /// Comprehensive device export is an Admin operation over the whole graph,
  /// including resources owned by profiles that did not grant the active
  /// Admin ordinary use access. It deliberately cannot be used as a provider
  /// operation or by a non-Admin profile.
  Future<Map<String, dynamic>> revealSecretForDeviceBackup({
    required ProfileAuthorizationContext context,
    required String resourceId,
  }) async {
    final actor = await context.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw const ResourceAuthorizationException(
        'Comprehensive backup requires an Admin',
      );
    }
    final resource = await registry.getResource(resourceId);
    if (resource == null || !resource.enabled) {
      throw const ResourceAuthorizationException('Resource is unavailable');
    }
    final secret = await _openSecret(resourceId);
    final currentActor = await context.validate(registry);
    final currentResource = await registry.getResource(resourceId);
    if (currentActor.role != UserProfileRole.admin ||
        !currentActor.allows(ProfileFeature.manageProfiles) ||
        !currentActor.allows(ProfileFeature.backupRestore) ||
        currentResource == null ||
        !currentResource.enabled ||
        currentResource.authorizationRevision !=
            resource.authorizationRevision) {
      throw const ResourceAuthorizationException(
        'Comprehensive backup authorization changed',
      );
    }
    return secret;
  }

  /// Internal credential resolution for an authorized provider operation.
  /// This does not imply UI/API permission to reveal the secret to the user.
  Future<Map<String, dynamic>> resolveSecretForUse({
    required ProfileAuthorizationContext context,
    required String resourceId,
    required ProfileFeature feature,
    ResourcePermission permission = ResourcePermission.use,
  }) async {
    final authorized = await authorize(
      context: context,
      resourceId: resourceId,
      permission: permission,
      feature: feature,
    );
    final secret = await _openSecret(resourceId);
    await _revalidateResource(
      context: context,
      expected: authorized,
      permission: permission,
      feature: feature,
    );
    return secret;
  }

  Future<void> updateSecret({
    required ProfileAuthorizationContext context,
    required String resourceId,
    required Map<String, dynamic> secretConfig,
  }) async {
    final authorized = await authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    if (secretConfig.isEmpty) {
      throw ArgumentError.value(
        secretConfig,
        'secretConfig',
        'Secret required',
      );
    }
    final resource = await registry.getResource(resourceId);
    if (resource == null ||
        resource.authorizationRevision != authorized.authorizationRevision) {
      throw StateError('Resource is unavailable');
    }
    final sealed = await cipher.seal(
      utf8.encode(jsonEncode(secretConfig)),
      associatedData: _associatedData(
        resourceId: resource.id,
        type: resource.type,
        ownerProfileId: resource.ownerProfileId,
        publicSchemaVersion: resource.publicSchemaVersion,
        payloadVersion: secretPayloadVersion,
      ),
    );
    await _revalidateResource(
      context: context,
      expected: authorized,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    await registry.updateResourceSecret(
      resourceId: resourceId,
      sealedSecretPayload: sealed,
      secretPayloadVersion: secretPayloadVersion,
      actingProfileId: context.profileId,
      actingAuthorizationRevision: context.authorizationRevision,
      expectedResourceAuthorizationRevision: authorized.authorizationRevision,
    );
  }

  Future<Map<String, dynamic>> _openSecret(String resourceId) async {
    final sealed = await registry.getSealedResourceSecret(resourceId);
    if (sealed == null) throw StateError('Resource secret is unavailable');
    final opened = await cipher.open(
      sealed.envelope,
      associatedData: _associatedData(
        resourceId: sealed.resourceId,
        type: sealed.type,
        ownerProfileId: sealed.ownerProfileId,
        publicSchemaVersion: sealed.publicSchemaVersion,
        payloadVersion: sealed.payloadVersion,
      ),
    );
    final value = jsonDecode(utf8.decode(opened));
    if (value is! Map) throw const FormatException('Invalid resource secret');
    return Map<String, dynamic>.from(value);
  }

  Future<ConnectionResource> authorize({
    required ProfileAuthorizationContext context,
    required String resourceId,
    required ResourcePermission permission,
    required ProfileFeature feature,
  }) async {
    var profile = await _validateContext(context);
    final resource = await registry.getResource(resourceId);
    final grant = await registry.getGrant(context.profileId, resourceId);
    // Registry reads are independent awaits. Revalidate the initiating
    // profile after them so a stale context cannot be used to return even a
    // resource descriptor.
    profile = await _validateContext(context);
    if (resource == null || !resource.enabled) {
      throw const ResourceAuthorizationException('Resource is unavailable');
    }
    if (!profile.allows(feature)) {
      throw const ResourceAuthorizationException('Profile feature is disabled');
    }
    if (grant == null || !grant.allows(permission)) {
      throw const ResourceAuthorizationException('Resource permission denied');
    }
    if (profile.role == UserProfileRole.child &&
        const <ResourcePermission>{
          ResourcePermission.writeRemote,
          ResourcePermission.manage,
          ResourcePermission.revealSecret,
          ResourcePermission.share,
        }.contains(permission)) {
      throw const ResourceAuthorizationException('Role ceiling denied');
    }
    return resource;
  }

  Future<UserProfile> _validateContext(
    ProfileAuthorizationContext context,
  ) async {
    try {
      return await context.validate(registry);
    } on StateError catch (error) {
      throw ResourceAuthorizationException(error.message);
    }
  }

  Future<ConnectionResource> _revalidateResource({
    required ProfileAuthorizationContext context,
    required ConnectionResource expected,
    required ResourcePermission permission,
    required ProfileFeature feature,
  }) async {
    final current = await authorize(
      context: context,
      resourceId: expected.id,
      permission: permission,
      feature: feature,
    );
    if (current.authorizationRevision != expected.authorizationRevision ||
        current.type != expected.type ||
        current.ownerProfileId != expected.ownerProfileId) {
      throw const ResourceAuthorizationException(
        'Connection authority changed',
      );
    }
    return current;
  }

  Future<void> grant({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required String resourceId,
    required Set<ResourcePermission> permissions,
  }) async {
    if (permissions.isEmpty) {
      throw ArgumentError.value(permissions, 'permissions', 'Grant is empty');
    }
    final actorProfile = await actor.validate(registry);
    if (!actorProfile.allows(ProfileFeature.manageProfiles)) {
      throw const ResourceAuthorizationException('Profile sharing denied');
    }
    final resource = await authorize(
      context: actor,
      resourceId: resourceId,
      permission: ResourcePermission.share,
      feature: ProfileFeature.manageProfiles,
    );
    final target = await registry.getProfile(targetProfileId);
    if (target == null || !target.isEnabled) {
      throw const ResourceAuthorizationException('Target profile unavailable');
    }
    final effective = permissions.where((permission) {
      if (target.role != UserProfileRole.child) return true;
      return permission != ResourcePermission.writeRemote &&
          permission != ResourcePermission.manage &&
          permission != ResourcePermission.revealSecret &&
          permission != ResourcePermission.share;
    });
    if (effective.isEmpty) {
      throw const ResourceAuthorizationException(
        'No requested permission is allowed for the target role',
      );
    }
    final mask = effective.fold<int>(0, (value, item) => value | item.bit);
    await actor.validate(registry);
    await registry.upsertGrant(
      profileId: targetProfileId,
      resourceId: resourceId,
      permissions: mask,
      grantedByProfileId: actor.profileId,
      origin: <String, dynamic>{'origin': 'profileShare'},
      bindingSlot: resource.type.singletonCredentialBindingSlot,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      expectedResourceAuthorizationRevision: resource.authorizationRevision,
      expectedTargetAuthorizationRevision: target.authorizationRevision,
    );
  }

  Future<void> revokeGrant({
    required ProfileAuthorizationContext actor,
    required String targetProfileId,
    required String resourceId,
  }) async {
    final actorProfile = await actor.validate(registry);
    if (actorProfile.role != UserProfileRole.admin ||
        !actorProfile.allows(ProfileFeature.manageProfiles)) {
      throw const ResourceAuthorizationException('Profile sharing denied');
    }
    final authorizedResource = await authorize(
      context: actor,
      resourceId: resourceId,
      permission: ResourcePermission.share,
      feature: ProfileFeature.manageProfiles,
    );
    final resource = await registry.getResource(resourceId);
    if (resource == null || !resource.enabled) {
      throw const ResourceAuthorizationException('Resource is unavailable');
    }
    if (resource.ownerProfileId == targetProfileId) {
      throw const ResourceAuthorizationException(
        'An owner grant cannot be revoked',
      );
    }
    final target = await registry.getProfile(targetProfileId);
    if (target == null || !target.isEnabled) {
      throw const ResourceAuthorizationException('Target profile unavailable');
    }
    await actor.validate(registry);
    await registry.revokeGrant(
      targetProfileId,
      resourceId,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      expectedResourceAuthorizationRevision:
          authorizedResource.authorizationRevision,
    );
  }

  /// Disconnects the active profile from a bound resource. A borrower may
  /// always reduce its own privilege: every binding and its grant are removed
  /// together. An owner disconnect deletes only an unshared, idle resource;
  /// shared or active-job impact must go through an explicit disposition.
  Future<ResourceDisconnectDisposition> disconnectBinding({
    required ProfileAuthorizationContext context,
    required String slot,
    required String resourceId,
  }) async {
    final profile = await context.validate(registry);
    final bound = await registry.getBoundResourceId(profile.id, slot);
    if (bound != resourceId) {
      throw const ResourceAuthorizationException('Connection binding changed');
    }
    final resource = await registry.getResource(resourceId);
    final grant = await registry.getGrant(profile.id, resourceId);
    if (resource == null || grant == null) {
      throw const ResourceAuthorizationException('Connection is unavailable');
    }
    if (resource.ownerProfileId != profile.id) {
      await context.validate(registry);
      await registry.detachBorrowedResource(
        profileId: profile.id,
        authorizationRevision: context.authorizationRevision,
        resourceId: resourceId,
        expectedResourceAuthorizationRevision: resource.authorizationRevision,
      );
      return ResourceDisconnectDisposition.borrowerDetached;
    }
    if (!profile.allows(ProfileFeature.manageConnections) ||
        !grant.allows(ResourcePermission.manage)) {
      throw const ResourceAuthorizationException(
        'Profile cannot manage connections',
      );
    }
    try {
      await context.validate(registry);
      await registry.deleteOwnedResource(
        resourceId: resourceId,
        ownerProfileId: profile.id,
        revokeBorrowers: false,
        actingProfileId: context.profileId,
        actingAuthorizationRevision: context.authorizationRevision,
        expectedResourceAuthorizationRevision: resource.authorizationRevision,
      );
      return ResourceDisconnectDisposition.ownerDeleted;
    } on StateError catch (error) {
      throw ResourceImpactRequiredException(error.message);
    }
  }

  /// Explicit owner choice to revoke every borrower and delete the resource.
  /// Active jobs remain a hard blocker and must be separately disposed first.
  Future<void> deleteOwnedResourceForAll({
    required ProfileAuthorizationContext context,
    required String resourceId,
  }) async {
    final profile = await context.validate(registry);
    final resource = await authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    if (resource.ownerProfileId != profile.id) {
      throw const ResourceAuthorizationException(
        'Only the connection owner can delete it',
      );
    }
    await _revalidateResource(
      context: context,
      expected: resource,
      permission: ResourcePermission.manage,
      feature: ProfileFeature.manageConnections,
    );
    await registry.deleteOwnedResource(
      resourceId: resourceId,
      ownerProfileId: profile.id,
      revokeBorrowers: true,
      actingProfileId: context.profileId,
      actingAuthorizationRevision: context.authorizationRevision,
      expectedResourceAuthorizationRevision: resource.authorizationRevision,
    );
  }

  /// Explicit Admin ownership transfer. The secret is opened only after the
  /// actor and destination are validated, then re-sealed with owner-bound AAD
  /// before registry publication.
  Future<void> transferOwnership({
    required ProfileAuthorizationContext actor,
    required String resourceId,
    required String newOwnerProfileId,
  }) async {
    final actorProfile = await actor.validate(registry);
    if (actorProfile.role != UserProfileRole.admin ||
        !actorProfile.allows(ProfileFeature.manageProfiles)) {
      throw const ResourceAuthorizationException(
        'Ownership transfer requires an Admin',
      );
    }
    final resource = await registry.getResource(resourceId);
    final target = await registry.getProfile(newOwnerProfileId);
    if (resource == null || !resource.enabled) {
      throw const ResourceAuthorizationException('Resource is unavailable');
    }
    if (target == null ||
        !target.isEnabled ||
        target.role == UserProfileRole.child ||
        !target.allows(ProfileFeature.manageConnections)) {
      throw const ResourceAuthorizationException('New owner is ineligible');
    }
    if (resource.ownerProfileId == newOwnerProfileId) return;
    final secret = await _openSecret(resourceId);
    final sealed = await cipher.seal(
      utf8.encode(jsonEncode(secret)),
      associatedData: _associatedData(
        resourceId: resource.id,
        type: resource.type,
        ownerProfileId: newOwnerProfileId,
        publicSchemaVersion: resource.publicSchemaVersion,
        payloadVersion: secretPayloadVersion,
      ),
    );
    final currentActor = await actor.validate(registry);
    final currentResource = await registry.getResource(resourceId);
    final currentTarget = await registry.getProfile(newOwnerProfileId);
    if (currentActor.role != UserProfileRole.admin ||
        !currentActor.allows(ProfileFeature.manageProfiles) ||
        currentResource == null ||
        !currentResource.enabled ||
        currentResource.authorizationRevision !=
            resource.authorizationRevision ||
        currentTarget == null ||
        !currentTarget.isEnabled ||
        currentTarget.authorizationRevision != target.authorizationRevision) {
      throw const ResourceAuthorizationException(
        'Ownership transfer authorization changed',
      );
    }
    await registry.transferResourceOwnership(
      resourceId: resourceId,
      currentOwnerProfileId: resource.ownerProfileId,
      newOwnerProfileId: newOwnerProfileId,
      resealedSecretPayload: sealed,
      secretPayloadVersion: secretPayloadVersion,
      ownerPermissions: ResourcePermission.values.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      ),
      transferredByProfileId: actorProfile.id,
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      expectedResourceAuthorizationRevision: resource.authorizationRevision,
      expectedTargetAuthorizationRevision: target.authorizationRevision,
    );
  }

  Future<void> bind({
    required ProfileAuthorizationContext context,
    required String slot,
    required String resourceId,
    required Set<ConnectionResourceType> acceptedTypes,
    required ProfileFeature feature,
  }) async {
    final resource = await authorize(
      context: context,
      resourceId: resourceId,
      permission: ResourcePermission.use,
      feature: feature,
    );
    if (!acceptedTypes.contains(resource.type)) {
      throw const ResourceAuthorizationException(
        'Resource type does not fit slot',
      );
    }
    await _revalidateResource(
      context: context,
      expected: resource,
      permission: ResourcePermission.use,
      feature: feature,
    );
    await registry.bindResource(
      profileId: context.profileId,
      slot: slot,
      resourceId: resourceId,
      actingAuthorizationRevision: context.authorizationRevision,
      expectedResourceAuthorizationRevision: resource.authorizationRevision,
      actingFeature: feature,
    );
  }

  Future<ConnectionResource> resolveBinding({
    required ProfileAuthorizationContext context,
    required String slot,
    required ResourcePermission permission,
    required Set<ConnectionResourceType> acceptedTypes,
    required ProfileFeature feature,
  }) async {
    final resourceId = await registry.getBoundResourceId(
      context.profileId,
      slot,
    );
    if (resourceId == null) {
      throw const ResourceAuthorizationException('No resource is bound');
    }
    final resource = await authorize(
      context: context,
      resourceId: resourceId,
      permission: permission,
      feature: feature,
    );
    if (!acceptedTypes.contains(resource.type)) {
      throw const ResourceAuthorizationException('Bound resource type changed');
    }
    return resource;
  }

  static Map<String, dynamic> _normalizePublicConfig(
    ConnectionResourceType type,
    Map<String, dynamic> config,
  ) {
    final allowed = switch (type) {
      ConnectionResourceType.realDebrid ||
      ConnectionResourceType.torbox ||
      ConnectionResourceType.premiumize ||
      ConnectionResourceType.pikpak ||
      ConnectionResourceType.allDebrid => const <String>{
        'region',
        'accountLabel',
      },
      ConnectionResourceType.webDav => const <String>{'accountLabel'},
      ConnectionResourceType.trakt ||
      ConnectionResourceType.simkl ||
      ConnectionResourceType.mdblist ||
      ConnectionResourceType.reddit => const <String>{
        'accountLabel',
        'username',
      },
      ConnectionResourceType.iptvM3u ||
      ConnectionResourceType.iptvXtream ||
      ConnectionResourceType.xmltv => const <String>{
        'playlistName',
        'providerKind',
      },
      ConnectionResourceType.stremioAddon => const <String>{
        'addonName',
        'contentKinds',
      },
      ConnectionResourceType.jackett ||
      ConnectionResourceType.prowlarr => const <String>{'managerName'},
    };
    for (final entry in config.entries) {
      if (!allowed.contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'publicConfig',
          'Unsupported public field for ${type.name}',
        );
      }
      _validatePublicValue(entry.value);
    }
    return <String, dynamic>{'schemaVersion': 1, ...config};
  }

  static void _validatePublicValue(Object? value) {
    if (value == null || value is bool || value is num) return;
    if (value is String) {
      final uri = Uri.tryParse(value);
      if (uri != null && uri.hasScheme) {
        throw ArgumentError.value(value, 'publicConfig', 'URLs are secret');
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        if (item is Map || item is List) {
          throw ArgumentError.value(
            value,
            'publicConfig',
            'Nested data denied',
          );
        }
        _validatePublicValue(item);
      }
      return;
    }
    throw ArgumentError.value(
      value,
      'publicConfig',
      'Unsupported public value',
    );
  }

  static List<int> _associatedData({
    required String resourceId,
    required ConnectionResourceType type,
    required String ownerProfileId,
    required int publicSchemaVersion,
    required int payloadVersion,
  }) => utf8.encode(
    'debrify-resource|id=$resourceId|type=${type.name}|owner=$ownerProfileId|'
    'public=$publicSchemaVersion|secret=$payloadVersion',
  );

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return 'resource-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}

class ResourceCollectionItem {
  final ConnectionResourceType type;
  final String label;
  final Map<String, dynamic> publicConfig;
  final Map<String, dynamic> secretConfig;
  final String? sourceResourceId;

  const ResourceCollectionItem({
    required this.type,
    required this.label,
    this.publicConfig = const <String, dynamic>{},
    required this.secretConfig,
    this.sourceResourceId,
  });
}
