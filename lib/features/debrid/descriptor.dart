/// Identity and static traits of one debrid provider.
///
/// Three id spaces exist in persisted data and none of them can be rewritten
/// without a migration: the default-provider preference and the playback flow
/// use [id] (Real-Debrid is `debrid` there), the cloud hub and playlist items
/// use [cloudKey] (`realdebrid`), and `SeriesSource.debridService` uses
/// [sourceKey] (`rd`). Only Real-Debrid actually differs across the three.
/// Read paths normalise through [DebridProviderIds.normalize]; write paths keep
/// using the field for the space they write into.
class DebridProviderDescriptor {
  final String id;
  final String cloudKey;
  final String sourceKey;

  /// Every spelling that resolves to this provider, [id]/[cloudKey]/[sourceKey]
  /// included. Lowercase; matched after trimming and lowercasing the input.
  final Set<String> aliases;

  final String displayName;

  /// One line of what the provider is, for pickers that explain the choice.
  final String tagline;

  /// Two-letter glyph for cache badges and the pipeline loader chip.
  final String shortCode;

  /// SharedPreferences key the remote-control credential transfer names.
  final String credentialKey;

  final DebridCapabilities capabilities;

  const DebridProviderDescriptor({
    required this.id,
    required this.cloudKey,
    required this.sourceKey,
    required this.aliases,
    required this.displayName,
    required this.tagline,
    required this.shortCode,
    required this.credentialKey,
    required this.capabilities,
  });
}

/// What a provider can do, where the flows branch on ability rather than name.
class DebridCapabilities {
  /// The provider answers a cache lookup before adding, so the play pipeline
  /// runs a cache-check stage and bulk add can skip uncached picks.
  final bool cacheCheck;

  /// Adding is refused outright when the torrent is not cached, rather than
  /// queueing a cloud download.
  final bool cachedOnlyAdds;

  /// Has a file-browsing screen in the cloud hub and the nav rail.
  final bool cloudTab;

  /// Adding queues a real download against the account rather than handing
  /// back an already-cached file, so the app probes at most one torrent per
  /// play and never auto-pins a binding behind the user's back.
  final bool addsQueueDownloads;

  /// The provider refuses some torrents outright (Real-Debrid's blocked
  /// hosters), so the user can ask for those to be filtered out of results.
  final bool skipsBlockedTorrents;

  const DebridCapabilities({
    this.cacheCheck = false,
    this.cachedOnlyAdds = false,
    this.cloudTab = true,
    this.addsQueueDownloads = false,
    this.skipsBlockedTorrents = false,
  });
}

/// Canonical ids, kept as constants so call sites stop spelling them.
abstract final class DebridProviderIds {
  static const realDebrid = 'debrid';
  static const torbox = 'torbox';
  static const premiumize = 'premiumize';
  static const allDebrid = 'alldebrid';
  static const pikpak = 'pikpak';

  /// Cloud sources that are not debrid providers but share the hub's plumbing.
  static const webdav = 'webdav';

  static const all = <String>[
    realDebrid,
    torbox,
    premiumize,
    allDebrid,
    pikpak,
  ];

  static const _byAlias = <String, String>{
    'debrid': realDebrid,
    'realdebrid': realDebrid,
    'real-debrid': realDebrid,
    'real_debrid': realDebrid,
    'rd': realDebrid,
    'torbox': torbox,
    'premiumize': premiumize,
    'alldebrid': allDebrid,
    'all-debrid': allDebrid,
    'all_debrid': allDebrid,
    'pikpak': pikpak,
    'pik-pak': pikpak,
    'pik_pak': pikpak,
  };

  /// Canonical id for any spelling, or null when it names no debrid provider
  /// (`none`, `auto`, `webdav`, a local binding, an addon stream).
  static String? normalize(String? raw) {
    if (raw == null) return null;
    return _byAlias[raw.trim().toLowerCase()];
  }
}

/// The provider table: static identity and traits, with no client code behind
/// it. UI reads from here; only code that actually calls a provider needs the
/// infrastructure registry.
abstract final class DebridProviders {
  static const realDebrid = DebridProviderDescriptor(
    id: DebridProviderIds.realDebrid,
    cloudKey: 'realdebrid',
    sourceKey: 'rd',
    aliases: {'debrid', 'realdebrid', 'real-debrid', 'real_debrid', 'rd'},
    displayName: 'Real-Debrid',
    tagline: 'Premium link generator',
    shortCode: 'RD',
    credentialKey: 'real_debrid_api_key',
    capabilities: DebridCapabilities(skipsBlockedTorrents: true),
  );

  static const torbox = DebridProviderDescriptor(
    id: DebridProviderIds.torbox,
    cloudKey: DebridProviderIds.torbox,
    sourceKey: DebridProviderIds.torbox,
    aliases: {'torbox'},
    displayName: 'TorBox',
    tagline: 'Fast cloud torrent service',
    shortCode: 'TB',
    credentialKey: 'torbox_api_key',
    capabilities: DebridCapabilities(cacheCheck: true, cachedOnlyAdds: true),
  );

  static const premiumize = DebridProviderDescriptor(
    id: DebridProviderIds.premiumize,
    cloudKey: DebridProviderIds.premiumize,
    sourceKey: DebridProviderIds.premiumize,
    aliases: {'premiumize'},
    displayName: 'Premiumize',
    tagline: 'Premium cloud downloader',
    shortCode: 'PM',
    credentialKey: 'premiumize_api_key',
    capabilities: DebridCapabilities(cacheCheck: true, cachedOnlyAdds: true),
  );

  static const allDebrid = DebridProviderDescriptor(
    id: DebridProviderIds.allDebrid,
    cloudKey: DebridProviderIds.allDebrid,
    sourceKey: DebridProviderIds.allDebrid,
    aliases: {'alldebrid', 'all-debrid', 'all_debrid'},
    displayName: 'AllDebrid',
    tagline: 'Premium link generator',
    shortCode: 'AD',
    credentialKey: 'alldebrid_api_key',
    capabilities: DebridCapabilities(),
  );

  static const pikpak = DebridProviderDescriptor(
    id: DebridProviderIds.pikpak,
    cloudKey: DebridProviderIds.pikpak,
    sourceKey: DebridProviderIds.pikpak,
    aliases: {'pikpak', 'pik-pak', 'pik_pak'},
    displayName: 'PikPak',
    tagline: 'Cloud storage service',
    shortCode: 'PP',
    credentialKey: 'pikpak_email',
    capabilities: DebridCapabilities(addsQueueDownloads: true),
  );

  static const _byId = <String, DebridProviderDescriptor>{
    DebridProviderIds.realDebrid: realDebrid,
    DebridProviderIds.torbox: torbox,
    DebridProviderIds.premiumize: premiumize,
    DebridProviderIds.allDebrid: allDebrid,
    DebridProviderIds.pikpak: pikpak,
  };

  /// Registration order — also the order pickers and settings list them in.
  static const all = <DebridProviderDescriptor>[
    realDebrid,
    torbox,
    premiumize,
    allDebrid,
    pikpak,
  ];

  /// The descriptor for any spelling of a provider id, or null when the id
  /// names no debrid provider (`none`, `auto`, `webdav`, a local binding, an
  /// addon stream).
  static DebridProviderDescriptor? find(String? rawId) {
    final id = DebridProviderIds.normalize(rawId);
    return id == null ? null : _byId[id];
  }

  /// Human-readable name, falling back to [orElse] (or the raw id) for sources
  /// that are not debrid providers.
  static String displayName(String? rawId, {String? orElse}) =>
      find(rawId)?.displayName ?? orElse ?? (rawId ?? '');

  /// Traits of a provider, or the all-false default for a non-provider source.
  static DebridCapabilities capabilities(String? rawId) =>
      find(rawId)?.capabilities ?? const DebridCapabilities();
}
