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

  /// Adapt a `stremio-addons.net` `/api/v0/addons` entry — which exposes the
  /// install URL as `manifestUrl` and nests the manifest under `manifest` — to
  /// the `{transportUrl, manifest}` shape [_fromEntry] parses.
  static MarketplaceAddon? _fromNetEntry(dynamic entry) {
    if (entry is! Map) return null;
    final manifestUrl = entry['manifestUrl'] ?? entry['transportUrl'];
    if (manifestUrl is! String || manifestUrl.isEmpty) return null;
    return _fromEntry({
      'transportUrl': manifestUrl,
      'manifest': entry['manifest'],
    });
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

  /// Primary community source: the `stremio-addons.net` public REST API (v0).
  /// Read-only, no auth, CORS-open; paginated 100/page (~490 curated addons,
  /// far more than the legacy catalog). Each entry carries `manifestUrl` + the
  /// full `manifest`. Sorted by stars so popular addons surface first.
  ///
  /// The API is documented as experimental ("endpoints may change without
  /// notice"), so [fetchCommunity] falls back to [_legacyCommunityCatalogUrl]
  /// on any failure. Their terms require visible attribution when displaying
  /// this data — see the credit line in the Addons hub's Community list.
  static const String _netCommunityApiBase =
      'https://stremio-addons.net/api/v0/addons';

  /// Fallback community directory: a Stremio `addon_catalog` resource (~70
  /// entries) used only when the primary API is unavailable.
  static const String _legacyCommunityCatalogUrl =
      'https://stremio-addons.com/addon_catalog/all/community.json';

  /// Cache key for the community list (source-agnostic — the primary API and
  /// the legacy fallback share it, so a later call reuses whichever succeeded).
  static const String _communityCacheKey = 'community';

  /// Hard page cap so a misbehaving `totalPages` can never loop forever
  /// (~490 addons ≈ 5 pages today; 20 leaves generous headroom).
  static const int _netMaxPages = 20;

  static const Duration _timeout = Duration(seconds: 15);

  final Map<String, List<MarketplaceAddon>> _cache = {};

  /// Whether the currently-cached community list came from the primary
  /// `stremio-addons.net` API (true) rather than the legacy fallback (false).
  /// Drives the attribution credit — which must name the source actually shown.
  bool _communityFromNet = false;
  bool get communityFromNet => _communityFromNet;

  /// The official/curated collection. Cached for the session; pass
  /// [forceRefresh] to bypass.
  Future<List<MarketplaceAddon>> fetchOfficial({bool forceRefresh = false}) {
    return _fetchCollection(officialCollectionUrl, forceRefresh: forceRefresh);
  }

  /// The community directory: the `stremio-addons.net` API, with an automatic
  /// fallback to the legacy `addon_catalog` if that (experimental) API fails or
  /// returns nothing. Cached for the session; pass [forceRefresh] to bypass.
  Future<List<MarketplaceAddon>> fetchCommunity(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(_communityCacheKey)) {
      return _cache[_communityCacheKey]!;
    }
    try {
      final addons = await _fetchNetCommunity();
      // An empty list means the API answered but gave us nothing usable — treat
      // as a failure and fall through to the legacy catalog rather than caching
      // (and showing) an empty Community tab.
      if (addons.isEmpty) throw Exception('empty result');
      _cache[_communityCacheKey] = addons;
      _communityFromNet = true;
      return addons;
    } catch (e) {
      debugPrint('StremioMarketplace: stremio-addons.net API failed ($e); '
          'falling back to legacy catalog');
      final fallback = await _fetchCollection(
        _legacyCommunityCatalogUrl,
        forceRefresh: forceRefresh,
      );
      _cache[_communityCacheKey] = fallback;
      _communityFromNet = false;
      return fallback;
    }
  }

  /// Fetch every page of the `stremio-addons.net` API and flatten into one
  /// list, sorted (server-side) by stars so popular addons lead. Throws on any
  /// HTTP/parse error so [fetchCommunity] can fall back.
  Future<List<MarketplaceAddon>> _fetchNetCommunity() async {
    final addons = <MarketplaceAddon>[];
    final seen = <String>{};
    var page = 1;
    var totalPages = 1;
    do {
      final uri = Uri.parse(
          '$_netCommunityApiBase?sort_by=stars&order=desc&limit=100&page=$page');
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['addons'] is! List) {
        throw Exception('Unexpected API format');
      }
      for (final entry in decoded['addons'] as List) {
        final addon = MarketplaceAddon._fromNetEntry(entry);
        if (addon == null) continue;
        // Collapse duplicate transport URLs (an addon can be re-listed across
        // categories/pages under the same install URL).
        if (!seen.add(addon.transportUrl)) continue;
        addons.add(addon);
      }
      final pagination = decoded['pagination'];
      totalPages =
          (pagination is Map ? pagination['totalPages'] as int? : null) ?? 1;
      page++;
    } while (page <= totalPages && page <= _netMaxPages);
    debugPrint('StremioMarketplace: loaded ${addons.length} addons from '
        'stremio-addons.net');
    return addons;
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
