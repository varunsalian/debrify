enum ConnectionResourceType {
  realDebrid,
  torbox,
  premiumize,
  pikpak,
  allDebrid,
  webDav,
  trakt,
  simkl,
  mdblist,
  iptvM3u,
  iptvXtream,
  xmltv,
  stremioAddon,
  jackett,
  prowlarr,
  reddit,
}

extension ConnectionResourceTypeBinding on ConnectionResourceType {
  /// The compatibility slot used by scalar credential APIs. Collection
  /// resources intentionally have no singleton slot because a profile may
  /// use several of them at once.
  String? get singletonCredentialBindingSlot => switch (this) {
    ConnectionResourceType.realDebrid => 'provider.realDebrid',
    ConnectionResourceType.torbox => 'provider.torbox',
    ConnectionResourceType.premiumize => 'provider.premiumize',
    ConnectionResourceType.pikpak => 'provider.pikpak',
    ConnectionResourceType.allDebrid => 'provider.allDebrid',
    ConnectionResourceType.trakt => 'tracker.trakt',
    ConnectionResourceType.simkl => 'tracker.simkl',
    ConnectionResourceType.mdblist => 'tracker.mdblist',
    ConnectionResourceType.reddit => 'tracker.reddit',
    ConnectionResourceType.webDav ||
    ConnectionResourceType.iptvM3u ||
    ConnectionResourceType.iptvXtream ||
    ConnectionResourceType.xmltv ||
    ConnectionResourceType.stremioAddon ||
    ConnectionResourceType.jackett ||
    ConnectionResourceType.prowlarr => null,
  };
}

enum ResourcePermission {
  use(1 << 0),
  download(1 << 1),
  writeRemote(1 << 2),
  manage(1 << 3),
  revealSecret(1 << 4),
  share(1 << 5);

  const ResourcePermission(this.bit);
  final int bit;
}

class ConnectionResource {
  final String id;
  final ConnectionResourceType type;
  final String label;
  final String ownerProfileId;
  final Map<String, dynamic> publicConfig;
  final int publicSchemaVersion;
  final int authorizationRevision;
  final bool enabled;
  final bool secretPending;

  const ConnectionResource({
    required this.id,
    required this.type,
    required this.label,
    required this.ownerProfileId,
    required this.publicConfig,
    this.publicSchemaVersion = 1,
    required this.authorizationRevision,
    required this.enabled,
    this.secretPending = false,
  });
}

class ProfileResourceGrant {
  final String profileId;
  final String resourceId;
  final int permissions;

  const ProfileResourceGrant({
    required this.profileId,
    required this.resourceId,
    required this.permissions,
  });

  bool allows(ResourcePermission permission) =>
      permissions & permission.bit == permission.bit;
}

class ProfileResourceSettings {
  final String profileId;
  final String resourceId;
  final bool enabled;
  final Map<String, dynamic> settings;

  const ProfileResourceSettings({
    required this.profileId,
    required this.resourceId,
    required this.enabled,
    this.settings = const <String, dynamic>{},
  });
}
