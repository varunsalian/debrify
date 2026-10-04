/// What the hub is managing: Stremio addons or torrent-engine plugins. They are
/// different features, so they get their own top-level dropdown instead of being
/// mixed into one source list.
enum AddonHubKind { addons, engines }

/// Which addon list is shown when [_HubKind.addons] is active. Official/Community
/// are 1-click marketplaces (Stremio's official collection + the community
/// `addon_catalog`).
enum AddonHubSource { installed, official, community }
