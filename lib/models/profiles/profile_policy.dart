import 'dart:convert';

enum ProfileFeature {
  /// OPERATION feature: debrid/cloud provider credentials and API calls —
  /// the plumbing stream resolution rides on. The Cloud file-browsing PAGES
  /// are [cloudFiles]; hiding the surface must never sever the plumbing
  /// (a Member without the Cloud tab still streams through Real-Debrid).
  cloud,

  /// OPERATION feature: engine/indexer/torrent-service execution — what
  /// resolves streams for titles, feeds Debrify TV channels, and serves
  /// magnet deep links. The keyword-search UI is [keywordSearch]; a Kid
  /// with this on and [keywordSearch] off plays curated titles fine but
  /// never sees a raw release list.
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

  // ── v2 SURFACE features (the questionnaire's toggles) ──────────────────
  // Split from the operation features above (policy schema v2, 2026-08-16):
  // the mock's "Keyword search" and "Cloud files" gate what a profile SEES,
  // while the operation features keep gating what runs on its behalf.

  /// SURFACE: the keyword/raw-release search UI (search screen segment and
  /// its results). Catalog title-search is never a permission.
  keywordSearch,

  /// SURFACE: the cloud file-browsing pages (Real-Debrid cloud, TorBox,
  /// PikPak, WebDAV tabs and provider screens) — a shared account's file
  /// list is the owner's viewing history, so this defaults off for
  /// non-admins while [cloud] stays on for playback.
  cloudFiles,

  // ── v3 OPERATION feature ───────────────────────────────────────────────

  /// OPERATION feature (policy schema v3): READING granted Stremio addons —
  /// catalog rows, title search, metadata, stream resolution. Split from
  /// [addonsAndEngines], which is the MANAGEMENT surface (Addons page,
  /// add/remove/import/refresh — the questionnaire's "Manage own sources").
  /// Every role default keeps this on and the questionnaire never asks:
  /// a Kid with "Manage own sources" off still gets Home shelves and
  /// catalog search from the addons an admin granted. Which addons are
  /// visible stays a per-resource GRANT decision, never this bit.
  addonUse,
}

enum UserProfileRole { admin, member, child }

/// Stable, versioned feature policy. Unknown fields never grant authority.
class ProfilePolicy {
  /// v2 (2026-08-16): introduced the surface features ([ProfileFeature
  /// .keywordSearch], [ProfileFeature.cloudFiles]). v3 (same day):
  /// [ProfileFeature.addonUse], the addon-read operation. Older policies
  /// upgrade at decode — see [decode].
  static const int currentSchemaVersion = 3;

  /// Features by the schema version that introduced them. A policy stored
  /// under an older version predates these entirely, so their absence there
  /// means "never asked", not "denied" — decode seeds them from the role's
  /// current defaults.
  static const Map<int, Set<ProfileFeature>> _featuresIntroducedIn =
      <int, Set<ProfileFeature>>{
        2: <ProfileFeature>{
          ProfileFeature.keywordSearch,
          ProfileFeature.cloudFiles,
        },
        3: <ProfileFeature>{ProfileFeature.addonUse},
      };

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

  /// The questionnaire's role presets (design/mockups/profile_features_mockup
  /// — mock v6 matrix). Operations stay on where the mock only hides a
  /// surface: a Member without [ProfileFeature.cloudFiles] still streams
  /// through debrid; a Kid without [ProfileFeature.keywordSearch] still
  /// plays curated titles through engines and keeps Debrify TV (whose
  /// channels ARE keyword operations under the hood).
  factory ProfilePolicy.defaultsFor(UserProfileRole role) {
    final features = ProfileFeature.values.toSet();
    switch (role) {
      case UserProfileRole.admin:
        return ProfilePolicy(enabled: features);
      case UserProfileRole.member:
        features
          ..remove(ProfileFeature.manageProfiles)
          // A shared debrid account's file list is the owner's viewing
          // history — Members start without the Cloud pages, deliberately
          // grantable back (default, not ceiling).
          ..remove(ProfileFeature.cloudFiles);
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
          ..remove(ProfileFeature.allowAdultContent)
          // The Kid preset: shelves + Debrify TV + title search only.
          // Surfaces off; the operation features (cloud, torrentSearch)
          // stay on so playback and Debrify TV keep working.
          ..remove(ProfileFeature.keywordSearch)
          ..remove(ProfileFeature.cloudFiles)
          ..remove(ProfileFeature.addonsAndEngines)
          ..remove(ProfileFeature.stremioTv)
          ..remove(ProfileFeature.iptv)
          ..remove(ProfileFeature.youtube)
          ..remove(ProfileFeature.remoteControl);
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
      if (version is! int || version < 1 || version > currentSchemaVersion) {
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
      if (version < currentSchemaVersion) {
        // Decode-time upgrade, not a stored migration: an older policy
        // predates the features later versions introduced, so their absence
        // is "never asked", not "denied" — seed exactly those from the
        // role's current defaults and touch nothing else, so any
        // customization of the stored-era bits survives. Deterministic from
        // the stored bytes, which is what makes skipping a persisted rewrite
        // safe: the stored policy plus this decode IS the authority, so no
        // authorizationRevision churn is needed. The profile re-encodes as
        // the current version on its next ordinary save.
        final defaults = ProfilePolicy.defaultsFor(role).enabled;
        for (final entry in _featuresIntroducedIn.entries) {
          if (version >= entry.key) continue;
          for (final feature in entry.value) {
            if (defaults.contains(feature) &&
                _roleCeilingAllows(role, feature)) {
              enabled.add(feature);
            }
          }
        }
      }
      if (role == UserProfileRole.child) {
        enabled.remove(ProfileFeature.allowAdultContent);
      }
      return ProfilePolicy(
        schemaVersion: currentSchemaVersion,
        enabled: enabled,
      );
    } on Object {
      // Corrupt or future policy data must never widen access. Returning an
      // empty policy keeps the profile recoverable by an Admin while denying
      // every gated feature until it is repaired.
      return const ProfilePolicy(enabled: <ProfileFeature>{});
    }
  }
}
