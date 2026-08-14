import 'dart:convert';

enum ProfileFeature {
  cloud,
  torrentSearch,
  addonsAndEngines,
  trackersAndDiscovery,
  iptv,
  debrifyTv,
  stremioTv,
  youtube,
  downloads,
  recordings,
  externalPlayers,
  incomingLinks,
  remoteControl,
  remoteTransfer,
  backupRestore,
  manageConnections,
  manageProfiles,
  appUpdates,
  allowAdultContent,
}

enum UserProfileRole { admin, member, child }

/// Stable, versioned feature policy. Unknown fields never grant authority.
class ProfilePolicy {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final Set<ProfileFeature> enabled;

  const ProfilePolicy({
    this.schemaVersion = currentSchemaVersion,
    required this.enabled,
  });

  /// Every feature the role ceiling permits. The profile editor uses this
  /// while its fine-grained feature controls are hidden, so saving cannot
  /// preserve an invisible stale restriction.
  factory ProfilePolicy.allAllowedFor(UserProfileRole role) => ProfilePolicy(
    enabled: ProfileFeature.values
        .where((feature) => _roleCeilingAllows(role, feature))
        .toSet(),
  );

  factory ProfilePolicy.defaultsFor(UserProfileRole role) {
    final features = ProfileFeature.values.toSet();
    switch (role) {
      case UserProfileRole.admin:
        return ProfilePolicy(enabled: features);
      case UserProfileRole.member:
        features.remove(ProfileFeature.manageProfiles);
        return ProfilePolicy(enabled: features);
      case UserProfileRole.child:
        features
          ..remove(ProfileFeature.manageProfiles)
          ..remove(ProfileFeature.manageConnections)
          ..remove(ProfileFeature.appUpdates)
          ..remove(ProfileFeature.backupRestore)
          ..remove(ProfileFeature.remoteTransfer)
          ..remove(ProfileFeature.downloads)
          ..remove(ProfileFeature.recordings)
          ..remove(ProfileFeature.allowAdultContent);
        return ProfilePolicy(enabled: features);
    }
  }

  bool allows(UserProfileRole role, ProfileFeature feature) {
    if (!_roleCeilingAllows(role, feature)) return false;
    return enabled.contains(feature);
  }

  static bool _roleCeilingAllows(UserProfileRole role, ProfileFeature feature) {
    if (role == UserProfileRole.admin) return true;
    if (feature == ProfileFeature.manageProfiles) return false;
    if (role == UserProfileRole.member) return true;
    return feature != ProfileFeature.manageConnections &&
        feature != ProfileFeature.appUpdates &&
        feature != ProfileFeature.backupRestore &&
        feature != ProfileFeature.remoteTransfer &&
        feature != ProfileFeature.allowAdultContent;
  }

  String encode() => jsonEncode(<String, Object>{
    'schemaVersion': schemaVersion,
    'enabled': enabled.map((feature) => feature.name).toList()..sort(),
  });

  factory ProfilePolicy.decode(String source, UserProfileRole role) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Profile policy must be an object');
      }
      final version = decoded['schemaVersion'];
      if (version != currentSchemaVersion) {
        throw FormatException('Unsupported profile policy version: $version');
      }
      final raw = decoded['enabled'];
      if (raw is! List) {
        throw const FormatException('Profile policy enabled must be a list');
      }
      final enabled = <ProfileFeature>{};
      for (final value in raw) {
        if (value is! String) continue;
        final feature = ProfileFeature.values.where(
          (item) => item.name == value,
        );
        if (feature.isNotEmpty && _roleCeilingAllows(role, feature.first)) {
          enabled.add(feature.first);
        }
      }
      if (role == UserProfileRole.child) {
        enabled.remove(ProfileFeature.allowAdultContent);
      }
      return ProfilePolicy(schemaVersion: version as int, enabled: enabled);
    } on Object {
      // Corrupt or future policy data must never widen access. Returning an
      // empty policy keeps the profile recoverable by an Admin while denying
      // every gated feature until it is repaired.
      return const ProfilePolicy(enabled: <ProfileFeature>{});
    }
  }
}
