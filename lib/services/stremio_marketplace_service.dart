import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A single addon offered by a Stremio addon collection / `addon_catalog`.
///
/// Built from the raw manifest embedded in a collection entry (Stremio's
/// `addonscollection.json` and `addon_catalog` resources both return
/// `{ transportUrl, manifest }` objects), so we can render an install card and,
/// for configurable addons, an "Configure" branch — all without touching the
/// user's installed list until they act.
class MarketplaceAddon {
  final String id;
  final String name;
  final String? description;
  final String? logo;
  final String? version;
  final String transportUrl;
  final List<String> types;
  final List<String> resources;

  /// Whether the addon must be configured (in a browser) before it works — from
  /// `behaviorHints.configurationRequired`, or a `[config]` placeholder still
  /// present in the transport URL. Such addons can't be blind-installed.
  final bool configurationRequired;

  /// Whether the addon exposes an optional configuration page
  /// (`behaviorHints.configurable`) — offer Configure alongside Install.
  final bool configurable;

  const MarketplaceAddon({
    required this.id,
    required this.name,
    required this.transportUrl,
    this.description,
    this.logo,
    this.version,
    this.types = const [],
    this.resources = const [],
    this.configurationRequired = false,
    this.configurable = false,
  });

  /// The addon's configuration page URL (Stremio convention: swap the trailing
  /// `/manifest.json` for `/configure`).
  String get configureUrl {
    var url = transportUrl;
    // Resolve a `[config]` placeholder to the addon's configure entry point.
    url = url.replaceFirst('/[config]', '');
    if (url.endsWith('/manifest.json')) {
      url = url.substring(0, url.length - '/manifest.json'.length);
    }
    return '$url/configure';
  }

  static MarketplaceAddon? _fromEntry(dynamic entry) {
    if (entry is! Map) return null;
    final transportUrl = entry['transportUrl'] as String?;
    final manifest = entry['manifest'];
    if (transportUrl == null || manifest is! Map) return null;

    final behaviorHints = manifest['behaviorHints'];
    final configRequired = behaviorHints is Map &&
        behaviorHints['configurationRequired'] == true;
    final configurable =
        behaviorHints is Map && behaviorHints['configurable'] == true;

    List<String> stringList(dynamic raw) {
      if (raw is! List) return const [];
      final out = <String>[];
      for (final v in raw) {
        if (v is String) {
          out.add(v);
        } else if (v is Map && v['name'] is String) {
          out.add(v['name'] as String);
        }
      }
      return out;
    }

    return MarketplaceAddon(
      id: manifest['id'] as String? ?? transportUrl,
      name: manifest['name'] as String? ?? 'Unknown Addon',
      description: manifest['description'] as String?,
      logo: manifest['logo'] as String?,
      version: manifest['version'] as String?,
      transportUrl: transportUrl,
      types: stringList(manifest['types']),
      resources: stringList(manifest['resources']),
      configurationRequired:
          configRequired || transportUrl.contains('/[config]/'),
      configurable: configurable,
    );
  }
}

/// Fetches curated lists of Stremio addons for the 1-click "Discover" tab of the
/// Addons hub. The official collection is a stable public JSON endpoint; each
/// entry carries a `transportUrl` we can feed straight into
/// `StremioService.addAddon`.
class StremioMarketplaceService {
  StremioMarketplaceService._();
  static final StremioMarketplaceService instance =
      StremioMarketplaceService._();

  /// Stremio's official curated addon collection (~46 entries). A bare JSON
  /// array of `{transportUrl, manifest}`.
  static const String officialCollectionUrl =
      'https://api.strem.io/addonscollection.json';

  /// The community directory, exposed as a Stremio `addon_catalog` resource
  /// (the native protocol mechanism for listing other addons). Returns
  /// `{"addons": [{transportUrl, manifest}, …]}` — ~70+ entries.
  static const String communityCatalogUrl =
      'https://stremio-addons.com/addon_catalog/all/community.json';

  static const Duration _timeout = Duration(seconds: 15);

  final Map<String, List<MarketplaceAddon>> _cache = {};

  /// The official/curated collection. Cached for the session; pass
  /// [forceRefresh] to bypass.
  Future<List<MarketplaceAddon>> fetchOfficial({bool forceRefresh = false}) {
    return _fetchCollection(officialCollectionUrl, forceRefresh: forceRefresh);
  }

  /// The larger community directory (via `addon_catalog`).
  Future<List<MarketplaceAddon>> fetchCommunity({bool forceRefresh = false}) {
    return _fetchCollection(communityCatalogUrl, forceRefresh: forceRefresh);
  }

  Future<List<MarketplaceAddon>> _fetchCollection(String url,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(url)) return _cache[url]!;

    final response = await http.get(Uri.parse(url)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to load addons (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    // Official collection is a bare array; an addon_catalog resource wraps the
    // same entries in {"addons": [...]}. Accept both.
    final List<dynamic> entries;
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map && decoded['addons'] is List) {
      entries = decoded['addons'] as List;
    } else {
      throw Exception('Unexpected addon collection format');
    }

    final addons = <MarketplaceAddon>[];
    final seen = <String>{};
    for (final entry in entries) {
      final addon = MarketplaceAddon._fromEntry(entry);
      if (addon == null) continue;
      // Collapse duplicate transport URLs (a collection can list the same addon
      // twice under different catalogs).
      if (!seen.add(addon.transportUrl)) continue;
      addons.add(addon);
    }

    debugPrint('StremioMarketplace: loaded ${addons.length} addons from $url');
    _cache[url] = addons;
    return addons;
  }
}
