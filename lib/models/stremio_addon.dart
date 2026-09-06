import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/stremio_url.dart';

/// Represents an extra parameter for a catalog (e.g., genre, search, skip)
class StremioExtraParam {
  /// Parameter name (e.g., 'genre', 'search', 'skip')
  final String name;

  /// Whether this parameter is required
  final bool isRequired;

  /// Available options for this parameter (e.g., genre list)
  final List<String>? options;

  /// Options limit (max selections)
  final int? optionsLimit;

  const StremioExtraParam({
    required this.name,
    this.isRequired = false,
    this.options,
    this.optionsLimit,
  });

  factory StremioExtraParam.fromJson(dynamic json) {
    if (json is String) {
      return StremioExtraParam(name: json);
    }
    if (json is Map) {
      return StremioExtraParam(
        name: json['name'] as String? ?? 'unknown',
        isRequired: json['isRequired'] as bool? ?? false,
        options: (json['options'] as List<dynamic>?)?.cast<String>(),
        optionsLimit: json['optionsLimit'] as int?,
      );
    }
    return const StremioExtraParam(name: 'unknown');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (isRequired) 'isRequired': isRequired,
    if (options != null) 'options': options,
    if (optionsLimit != null) 'optionsLimit': optionsLimit,
  };

  @override
  String toString() =>
      'StremioExtraParam(name: $name, options: ${options?.length ?? 0})';
}

/// Represents a catalog definition from a Stremio addon manifest
class StremioAddonCatalog {
  /// Unique ID for this catalog (e.g., 'trending', 'top')
  final String id;

  /// Content type (e.g., 'movie', 'series')
  final String type;

  /// Human-readable name (e.g., 'Trending Movies')
  final String name;

  /// Optional extra parameters supported (e.g., search, genre, skip)
  final List<String>? extraSupported;

  /// Full extra parameter configuration with options
  final List<StremioExtraParam> extras;

  const StremioAddonCatalog({
    required this.id,
    required this.type,
    required this.name,
    this.extraSupported,
    this.extras = const [],
  });

  /// Check if this catalog supports search
  bool get supportsSearch => extraSupported?.contains('search') ?? false;

  /// Check if this catalog supports genre filter
  bool get supportsGenre => extraSupported?.contains('genre') ?? false;

  /// Whether this catalog can be browsed without a required `search` query. A
  /// search-only catalog returns empty when browsed, so browse UIs skip them.
  bool get isBrowsable =>
      !extras.any((e) => e.name == 'search' && e.isRequired);

  /// Get the genre extra param if available (for options)
  StremioExtraParam? get genreParam => extras
      .cast<StremioExtraParam?>()
      .firstWhere((e) => e?.name == 'genre', orElse: () => null);

  /// Get available genre options
  List<String> get genreOptions => genreParam?.options ?? [];

  factory StremioAddonCatalog.fromJson(Map<String, dynamic> json) {
    // Parse extraSupported - can be in 'extraSupported' or derived from 'extra'
    List<String>? extraSupported;
    final List<StremioExtraParam> extras = [];

    // Try extraSupported first
    final extraSupportedRaw = json['extraSupported'] as List<dynamic>?;
    if (extraSupportedRaw != null) {
      extraSupported = extraSupportedRaw.cast<String>();
    }

    // Parse full 'extra' array for names and options
    final extraRaw = json['extra'] as List<dynamic>?;
    if (extraRaw != null) {
      for (final e in extraRaw) {
        extras.add(StremioExtraParam.fromJson(e));
      }
      // Also extract names for extraSupported if not already set
      extraSupported ??= extras.map((e) => e.name).toList();
    }

    return StremioAddonCatalog(
      id: json['id'] as String? ?? 'unknown',
      type: json['type'] as String? ?? 'movie',
      name: json['name'] as String? ?? 'Unknown Catalog',
      extraSupported: extraSupported,
      extras: extras,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    if (extraSupported != null) 'extraSupported': extraSupported,
    if (extras.isNotEmpty) 'extra': extras.map((e) => e.toJson()).toList(),
  };

  @override
  String toString() => 'StremioAddonCatalog(id: $id, type: $type, name: $name)';
}

/// Represents a meta item (movie/series) from a Stremio catalog
class StremioMeta {
  /// Content ID from the addon (e.g., 'tt1234567', 'tmdb:840464', 'trakt:123')
  final String id;

  /// Resolved IMDB ID (e.g., 'tt1234567'), extracted from imdb_id field or links
  final String? imdbId;

  /// Content type ('movie' or 'series')
  final String type;

  /// Title
  final String name;

  /// Poster image URL
  final String? poster;

  /// Background image URL
  final String? background;

  /// Description/overview
  final String? description;

  /// Release year
  final String? year;

  /// IMDb rating
  final double? imdbRating;

  /// Genres
  final List<String>? genres;

  /// Runtime string exactly as the metadata addon provides it — Cinemeta gives
  /// e.g. "167 min". Frequently absent on catalog list items (like the rating),
  /// so it's resolved from the enriched /meta details. See [runtimeDisplay] for
  /// the "2h 47m" form used in the UI.
  final String? runtime;

  /// The addon this result came from (set during aggregated search)
  final StremioAddon? sourceAddon;

  /// YouTube video ID of a trailer, when the metadata addon (Cinemeta) provides
  /// one — parsed from `trailerStreams[].ytId` (preferred) or `trailers[].source`.
  /// Null when the title has no trailer. Played on-device via youtube_explode.
  final String? trailerYtId;

  /// Title-treatment ("logo") artwork URL — the studio's styled title art that
  /// Cinemeta serves on `/meta` (metahub, keyed by IMDb id). Usually absent on
  /// catalog list items, so it's resolved from the enriched details like the
  /// rating/runtime. UIs render it in place of the text title, with the text
  /// as fallback.
  final String? logo;

  /// When the user's tracker row was created — Trakt's `listed_at` /
  /// `collected_at` / `rated_at` / `watched_at`, Simkl's
  /// `added_to_watchlist_at`. Epoch ms, or null for anything that isn't a
  /// personal list row (trending, popular, addon catalogs), which is why the
  /// "Date Added" sort is offered only when the loaded list actually carries
  /// them. NOT a property of the title — the same film has a different value
  /// per user and per list.
  final int? addedAtMs;

  const StremioMeta({
    required this.id,
    this.imdbId,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.description,
    this.year,
    this.imdbRating,
    this.genres,
    this.runtime,
    this.sourceAddon,
    this.trailerYtId,
    this.logo,
    this.addedAtMs,
  });

  /// Create a copy with a source addon attached.
  StremioMeta withSourceAddon(StremioAddon addon) => StremioMeta(
    id: id,
    imdbId: imdbId,
    type: type,
    name: name,
    poster: poster,
    background: background,
    description: description,
    year: year,
    imdbRating: imdbRating,
    genres: genres,
    runtime: runtime,
    sourceAddon: addon,
    trailerYtId: trailerYtId,
    logo: logo,
    addedAtMs: addedAtMs,
  );

  /// Extract a trailer's YouTube ID from a meta JSON. Cinemeta exposes trailers
  /// two ways: `trailerStreams: [{title, ytId}]` (preferred — already a bare id)
  /// and the legacy `trailers: [{source, type}]` where `source` is the id.
  static String? _parseTrailerYtId(Map<String, dynamic> json) {
    final streams = json['trailerStreams'];
    if (streams is List) {
      for (final s in streams) {
        if (s is Map) {
          final ytId = s['ytId'] as String?;
          if (ytId != null && ytId.isNotEmpty) return ytId;
        }
      }
    }
    final trailers = json['trailers'];
    if (trailers is List) {
      // Prefer an entry explicitly typed as a Trailer, else take the first.
      String? firstSource;
      for (final t in trailers) {
        if (t is Map) {
          final source = t['source'] as String?;
          if (source == null || source.isEmpty) continue;
          firstSource ??= source;
          if ((t['type'] as String?)?.toLowerCase() == 'trailer') return source;
        }
      }
      if (firstSource != null) return firstSource;
    }
    return null;
  }

  /// Normalise a raw runtime value to a display string. Cinemeta sends a string
  /// like "167 min"; some addons send a bare minute count. Anything else is
  /// kept verbatim so we never lose information we can't interpret.
  static String? _parseRuntime(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is num && raw > 0) return '${raw.toInt()} min';
    return null;
  }

  static StremioAddon? _parseSourceAddon(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final json = Map<String, dynamic>.from(raw);
      if (json.containsKey('manifest_url') && json.containsKey('base_url')) {
        return StremioAddon.fromJson(json);
      }
      final id = json['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return StremioAddon(
        id: id,
        name: json['name'] as String? ?? id,
        manifestUrl: '',
        baseUrl: '',
        enabled: json['enabled'] as bool? ?? true,
        types: (json['types'] as List<dynamic>?)?.cast<String>() ?? const [],
        resources:
            (json['resources'] as List<dynamic>?)?.cast<String>() ?? const [],
        idPrefixes: (json['id_prefixes'] as List<dynamic>?)?.cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _sourceAddonToJson(StremioAddon? addon) {
    if (addon == null) return null;
    return {'id': addon.id, 'name': addon.name};
  }

  factory StremioMeta.fromJson(Map<String, dynamic> json) {
    // Handle rating - can be string or number
    double? rating;
    final ratingRaw = json['imdbRating'] ?? json['rating'];
    if (ratingRaw is num) {
      rating = ratingRaw.toDouble();
    } else if (ratingRaw is String) {
      rating = double.tryParse(ratingRaw);
    }

    // Handle year - can be string or number
    String? year;
    final yearRaw = json['year'] ?? json['releaseInfo'];
    if (yearRaw is int) {
      year = yearRaw.toString();
    } else if (yearRaw is String) {
      year = yearRaw;
    }

    final id = json['id'] as String? ?? json['imdb_id'] as String? ?? '';

    // Resolve IMDB ID: if id is already IMDB, use it directly.
    // Otherwise try imdb_id field, then extract from links array.
    String? imdbId;
    if (id.startsWith('tt') && id.length >= 9) {
      imdbId = id;
    } else {
      final rawImdbId = json['imdb_id'] as String?;
      if (rawImdbId != null && rawImdbId.startsWith('tt')) {
        imdbId = rawImdbId;
      } else {
        // Try extracting from links: [{category: "imdb", url: "https://imdb.com/title/tt..."}]
        final links = json['links'] as List<dynamic>?;
        if (links != null) {
          for (final link in links) {
            if (link is Map<String, dynamic> && link['category'] == 'imdb') {
              final url = link['url'] as String?;
              if (url != null) {
                final match = RegExp(r'(tt\d{7,10})').firstMatch(url);
                if (match != null) {
                  imdbId = match.group(1);
                  break;
                }
              }
            }
          }
        }
      }
    }

    return StremioMeta(
      id: id,
      imdbId: imdbId,
      type: json['type'] as String? ?? 'movie',
      name: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      poster: json['poster'] as String?,
      background: json['background'] as String? ?? json['fanart'] as String?,
      description:
          json['description'] as String? ?? json['overview'] as String?,
      year: year,
      imdbRating: rating,
      genres: (json['genres'] as List<dynamic>?)?.cast<String>(),
      runtime: _parseRuntime(json['runtime']),
      sourceAddon: _parseSourceAddon(
        json['source_addon'] ?? json['sourceAddon'],
      ),
      trailerYtId: json['trailer_yt_id'] as String? ?? _parseTrailerYtId(json),
      logo: json['logo'] as String?,
    );
  }

  /// Human "2h 47m" form of [runtime]. Parses the leading minute count from
  /// Cinemeta's "167 min"; falls back to the raw string when it isn't
  /// minute-shaped, and null when there's no runtime at all.
  String? get runtimeDisplay {
    final raw = runtime?.trim();
    if (raw == null || raw.isEmpty) return null;
    // Already carries an hour marker (e.g. "2h 47m") — trust it rather than
    // mis-reading the leading "2" as a minute count.
    if (raw.contains('h') || raw.contains('H')) return raw;
    final m = RegExp(r'^(\d+)').firstMatch(raw);
    if (m == null) return raw;
    final mins = int.parse(m.group(1)!);
    if (mins <= 0) return null;
    final h = mins ~/ 60, mm = mins % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h ${mm}m';
  }

  /// Check if this has a resolved IMDB ID (either from id or imdb_id/links)
  bool get hasValidImdbId => imdbId != null;

  /// The effective IMDB ID for torrent search — resolved from imdb_id/links fields
  String? get effectiveImdbId => imdbId;

  /// Check if this has a valid ID (any non-empty ID, not just IMDB)
  bool get hasValidId => id.isNotEmpty;

  /// Check if this is a non-IMDB content type (TV channel, etc.)
  bool get isNonImdb => !hasValidImdbId && hasValidId;

  /// Convert to a storage-friendly JSON map for local catalogs.
  Map<String, dynamic> toJson() {
    final sourceAddonJson = _sourceAddonToJson(sourceAddon);
    return {
      'id': id,
      if (imdbId != null) 'imdb_id': imdbId,
      'type': type,
      'name': name,
      if (poster != null) 'poster': poster,
      if (background != null) 'background': background,
      if (description != null) 'description': description,
      if (year != null) 'year': year,
      if (imdbRating != null) 'rating': imdbRating,
      if (genres != null && genres!.isNotEmpty) 'genres': genres,
      if (runtime != null) 'runtime': runtime,
      if (sourceAddonJson != null) 'source_addon': sourceAddonJson,
      if (trailerYtId != null) 'trailer_yt_id': trailerYtId,
      if (logo != null) 'logo': logo,
    };
  }

  @override
  String toString() =>
      'StremioMeta(id: $id, imdbId: $imdbId, name: $name, year: $year)';
}

/// Represents a section of catalog content for homepage display
class CatalogSection {
  /// Display title (e.g., "Popular Movies" — see [rowTitle]; the addon rides
  /// separately as the row's provenance tag)
  final String title;

  /// The addon this section is from
  final StremioAddon addon;

  /// The specific catalog
  final StremioAddonCatalog catalog;

  /// Items in this section. Grows in place as more pages lazy-load, so this
  /// must be a growable list.
  final List<StremioMeta> items;

  /// Offset (`skip`) for the next page fetch. Advances by the raw page size
  /// returned so it stays aligned with however the addon paginates.
  int nextSkip;

  /// True while a page fetch is in flight (re-entrancy guard).
  bool loadingMore;

  /// True once the catalog has ended, so we stop asking.
  bool exhausted;

  /// A bounded fetch found no visible titles; the cursor can be resumed.
  bool pagingPaused;

  /// The search query that produced these items, when this section is a
  /// per-catalog SEARCH result (Search tab) rather than a browsed catalog
  /// (home board). Null/empty for browse sections. Lets "See all" keep
  /// *searching* the catalog instead of falling back to a plain browse (which
  /// would mix in non-matching catalog items).
  final String? query;

  CatalogSection({
    required this.title,
    required this.addon,
    required this.catalog,
    required this.items,
    int? nextSkip,
    this.loadingMore = false,
    this.exhausted = false,
    this.pagingPaused = false,
    this.query,
  }) : nextSkip = nextSkip ?? items.length;

  /// The row heading for a catalog: catalog name + content type — "Popular"
  /// of type movie becomes "Popular Movies". The addon's name is NOT baked
  /// in any more (it rides separately as the row's provenance tag), which is
  /// also what un-duplicates rows: the old "Cinemeta: Popular" appeared
  /// twice — movies and series — with nothing on screen telling them apart.
  ///
  /// Catalogs whose name already carries the type word ("New Movies", "MTV")
  /// keep it un-doubled. A contains() guard rather than endsWith, on
  /// purpose: skipping the suffix is always safe, doubling never is.
  ///
  /// Row-order persistence is untouched by any of this — saved orders key on
  /// `addon.id:type:id`, never on the display title.
  static String rowTitle(StremioAddonCatalog catalog) {
    final name = catalog.name.trim();
    final type = switch (catalog.type.toLowerCase()) {
      'movie' => 'Movies',
      'series' => 'Series',
      'tv' => 'TV',
      'channel' => 'Channels',
      _ => null,
    };
    if (type == null) return name;
    // Nameless catalogs exist in the wild; the type alone beats " Movies".
    if (name.isEmpty) return type;
    // Matched on the SINGULAR stem so "Movie Night" and a catalog literally
    // named "movie" both count as already-typed — "movie Movies" is exactly
    // the doubling this guard exists to prevent.
    final stem = type.toLowerCase().replaceFirst(RegExp(r's$'), '');
    if (name.toLowerCase().contains(stem)) return name;
    return '$name $type';
  }
}

/// Represents a Stremio addon that can be used for torrent search.
///
/// Stremio addons follow a standard protocol where:
/// - `/manifest.json` describes the addon capabilities
/// - `/stream/{type}/{id}.json` returns torrent streams for content
/// - `/catalog/{type}/{id}.json` returns content catalogs for discovery
///
/// The manifest URL contains all configuration (debrid keys, filters, etc.)
/// already embedded, so we just store and use the full URL.
class StremioAddon {
  /// Unique identifier for this addon (derived from manifest id)
  final String id;

  /// Provider identity used by portable collection catalog references.
  /// Separate from the profile-local configuration identity in [id].
  final String? manifestId;

  /// Human-readable name from manifest
  final String name;

  /// The full manifest URL (includes any configuration)
  final String manifestUrl;

  /// Base URL derived from manifest URL (without /manifest.json)
  final String baseUrl;

  /// Profile resource provenance. These fields are deliberately carried by
  /// compatibility models so a decrypted, borrowed addon can never be
  /// mistaken for caller-owned input and cloned on the next collection save.
  final String? connectionResourceId;
  final int? connectionResourceRevision;
  final bool connectionResourceReadOnly;
  final bool connectionResourceCredentialsRedacted;

  /// Optional description from manifest
  final String? description;

  /// Optional version from manifest
  final String? version;

  /// Whether this addon is enabled for searches
  final bool enabled;

  /// Content types this addon supports (e.g., 'movie', 'series')
  final List<String> types;

  /// Resources this addon provides (e.g., 'stream', 'catalog')
  final List<String> resources;

  /// Optional ID prefixes this addon handles (e.g., 'tt' for IMDB)
  final List<String>? idPrefixes;

  /// Catalogs provided by this addon (for content discovery)
  final List<StremioAddonCatalog> catalogs;

  /// When this addon was added
  final DateTime addedAt;

  /// Last time the manifest was fetched/validated
  final DateTime? lastChecked;

  StremioAddon({
    required this.id,
    this.manifestId,
    required this.name,
    required this.manifestUrl,
    required this.baseUrl,
    this.connectionResourceId,
    this.connectionResourceRevision,
    this.connectionResourceReadOnly = false,
    this.connectionResourceCredentialsRedacted = false,
    this.description,
    this.version,
    this.enabled = true,
    this.types = const [],
    this.resources = const [],
    this.idPrefixes,
    this.catalogs = const [],
    DateTime? addedAt,
    this.lastChecked,
  }) : addedAt = addedAt ?? DateTime.now();

  String get storageKey => connectionResourceId ?? manifestUrl;

  /// Opaque, secret-free identity for persisted references to this exact addon
  /// configuration. Configured Stremio URLs can contain API keys, so bound
  /// sources store this digest instead of copying [manifestUrl]/[baseUrl].
  String get sourceBindingKey =>
      sha256.convert(utf8.encode(storageKey)).toString();

  /// Stable, secret-free identity for preferences that must survive profile
  /// backup and restore. Connection-resource IDs are device-local, while the
  /// normalized manifest URL identifies the same configured addon after its
  /// resource is recreated with a new ID.
  String get portableConfigurationKey {
    final normalized = manifestUrl.isEmpty
        ? ''
        : normalizeStremioManifestUri(manifestUrl).toString();
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  bool get canManage => !connectionResourceReadOnly;
  bool get canRevealManifestUrl =>
      !connectionResourceCredentialsRedacted && manifestUrl.isNotEmpty;

  /// Whether this addon supports streaming (has 'stream' resource)
  bool get supportsStreams => resources.contains('stream');

  /// Whether this addon supports catalogs (has 'catalog' resource)
  bool get supportsCatalogs =>
      resources.contains('catalog') && catalogs.isNotEmpty;

  /// Whether this addon supports meta (has 'meta' resource)
  bool get supportsMeta => resources.contains('meta');

  /// Whether this addon supports movies
  bool get supportsMovies => types.contains('movie');

  /// Whether this addon supports series/TV shows
  bool get supportsSeries => types.contains('series');

  /// Whether this addon has any catalogs that support search
  bool get hasSearchableCatalogs => catalogs.any((c) => c.supportsSearch);

  /// Whether this addon handles IMDB IDs
  bool get handlesImdbIds =>
      idPrefixes == null ||
      idPrefixes!.isEmpty ||
      idPrefixes!.any((p) => p == 'tt' || p.startsWith('tt'));

  /// Extract the prefix from a content ID dynamically.
  ///
  /// Handles various ID formats:
  /// - Colon-separated: "kitsu:1234" → "kitsu", "mal:5678" → "mal"
  /// - IMDB format: "tt1234567" → "tt"
  /// - Unknown: returns null if no recognizable prefix
  static String? extractIdPrefix(String contentId) {
    if (contentId.isEmpty) return null;

    // Check for colon-separated format (kitsu:1234, mal:5678, etc.)
    final colonIndex = contentId.indexOf(':');
    if (colonIndex > 0) {
      return contentId.substring(0, colonIndex);
    }

    // Check for IMDB format (tt followed by digits)
    if (contentId.startsWith('tt') && contentId.length > 2) {
      return 'tt';
    }

    // Try to extract alphabetic prefix before digits
    final prefixMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(contentId);
    if (prefixMatch != null) {
      return prefixMatch.group(1);
    }

    return null;
  }

  /// Check if this addon supports a given content ID.
  ///
  /// Returns true if:
  /// - The addon has no idPrefixes restriction (null or empty), OR
  /// - The contentId starts with any of the addon's idPrefixes, OR
  /// - The extracted prefix matches any of the addon's idPrefixes
  bool supportsContentId(String contentId) {
    // No restriction means addon accepts all IDs
    if (idPrefixes == null || idPrefixes!.isEmpty) {
      return true;
    }

    // Check if contentId starts with any of the declared prefixes
    // This handles complex IDs like "vavoo_SKY%20ARTE|group:it" where the
    // prefix is "vavoo_" but colon-based extraction would fail
    for (final p in idPrefixes!) {
      if (contentId.startsWith(p)) {
        return true;
      }
    }

    // Fallback to extracted prefix matching
    final prefix = extractIdPrefix(contentId);
    if (prefix == null) {
      // Can't determine prefix - let addon try anyway
      return true;
    }

    // Check if any of the addon's idPrefixes match (exact match only)
    return idPrefixes!.any((p) => p == prefix);
  }

  /// Create from manifest JSON response
  factory StremioAddon.fromManifest(
    Map<String, dynamic> manifest,
    String manifestUrl,
  ) {
    final id = manifest['id'] as String? ?? 'unknown';
    final name = manifest['name'] as String? ?? 'Unknown Addon';
    final description = manifest['description'] as String?;
    final version = manifest['version'] as String?;

    // Parse types
    final typesRaw = manifest['types'];
    final types = <String>[];
    if (typesRaw is List) {
      for (final t in typesRaw) {
        if (t is String) types.add(t);
      }
    }

    // Parse resources - can be list of strings or list of objects
    //
    // The object form also carries per-resource `types`/`idPrefixes`, and
    // manifests using it commonly leave the top-level `types` empty — StremThru
    // Torz ships exactly that:
    //   "resources":[{"name":"stream","types":["movie","series","anime"],...}]
    //   "types":[]
    // Those are deliberately NOT hoisted into [types]. The query filters
    // (searchStreams, recommendations, meta candidates) read empty types as
    // "unrestricted", so filling them in would NARROW addons that are queried
    // permissively today — e.g. a `tv`-type channel search against an addon
    // that never declared `tv`. searchStreams treats empty as unrestricted
    // instead, which fixes the reported case without taking anything away.
    final resourcesRaw = manifest['resources'];
    final resources = <String>[];
    if (resourcesRaw is List) {
      for (final r in resourcesRaw) {
        if (r is String) {
          resources.add(r);
        } else if (r is Map) {
          final name = r['name'] as String?;
          if (name != null) resources.add(name);
        }
      }
    }

    // Parse idPrefixes
    final idPrefixesRaw = manifest['idPrefixes'];
    List<String>? idPrefixes;
    if (idPrefixesRaw is List) {
      idPrefixes = [];
      for (final p in idPrefixesRaw) {
        if (p is String) idPrefixes.add(p);
      }
    }

    // Parse catalogs
    final catalogsRaw = manifest['catalogs'];
    final catalogs = <StremioAddonCatalog>[];
    if (catalogsRaw is List) {
      for (final c in catalogsRaw) {
        if (c is Map<String, dynamic>) {
          catalogs.add(StremioAddonCatalog.fromJson(c));
        }
      }
    }

    // Derive base URL from manifest URL
    final baseUrl = stremioBaseUriFromManifest(manifestUrl).toString();

    return StremioAddon(
      id: id,
      manifestId: id,
      name: name,
      manifestUrl: manifestUrl,
      baseUrl: baseUrl,
      description: description,
      version: version,
      types: types,
      resources: resources,
      idPrefixes: idPrefixes,
      catalogs: catalogs,
      lastChecked: DateTime.now(),
    );
  }

  /// Create from stored JSON
  factory StremioAddon.fromJson(Map<String, dynamic> json) {
    // Parse catalogs
    final catalogsRaw = json['catalogs'] as List<dynamic>?;
    final catalogs = <StremioAddonCatalog>[];
    if (catalogsRaw != null) {
      for (final c in catalogsRaw) {
        if (c is Map<String, dynamic>) {
          catalogs.add(StremioAddonCatalog.fromJson(c));
        }
      }
    }

    return StremioAddon(
      id: json['id'] as String,
      manifestId: json['manifest_id'] as String?,
      name: json['name'] as String,
      manifestUrl: json['manifest_url'] as String,
      baseUrl: json['base_url'] as String,
      connectionResourceId: json['_connectionResourceId'] as String?,
      connectionResourceRevision: json['_connectionResourceRevision'] as int?,
      connectionResourceReadOnly:
          json['_connectionResourceReadOnly'] as bool? ?? false,
      connectionResourceCredentialsRedacted:
          json['_connectionResourceCredentialsRedacted'] as bool? ?? false,
      description: json['description'] as String?,
      version: json['version'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      types: (json['types'] as List<dynamic>?)?.cast<String>() ?? [],
      resources: (json['resources'] as List<dynamic>?)?.cast<String>() ?? [],
      idPrefixes: (json['id_prefixes'] as List<dynamic>?)?.cast<String>(),
      catalogs: catalogs,
      addedAt: json['added_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['added_at'] as int)
          : DateTime.now(),
      lastChecked: json['last_checked'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_checked'] as int)
          : null,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (manifestId != null) 'manifest_id': manifestId,
      'name': name,
      'manifest_url': manifestUrl,
      'base_url': baseUrl,
      if (connectionResourceId != null)
        '_connectionResourceId': connectionResourceId,
      if (connectionResourceRevision != null)
        '_connectionResourceRevision': connectionResourceRevision,
      if (connectionResourceReadOnly)
        '_connectionResourceReadOnly': connectionResourceReadOnly,
      if (connectionResourceCredentialsRedacted)
        '_connectionResourceCredentialsRedacted':
            connectionResourceCredentialsRedacted,
      if (description != null) 'description': description,
      if (version != null) 'version': version,
      'enabled': enabled,
      'types': types,
      'resources': resources,
      if (idPrefixes != null) 'id_prefixes': idPrefixes,
      if (catalogs.isNotEmpty)
        'catalogs': catalogs.map((c) => c.toJson()).toList(),
      'added_at': addedAt.millisecondsSinceEpoch,
      if (lastChecked != null)
        'last_checked': lastChecked!.millisecondsSinceEpoch,
    };
  }

  /// Create a copy with updated fields
  StremioAddon copyWith({
    String? id,
    String? manifestId,
    String? name,
    String? manifestUrl,
    String? baseUrl,
    String? connectionResourceId,
    int? connectionResourceRevision,
    bool? connectionResourceReadOnly,
    bool? connectionResourceCredentialsRedacted,
    String? description,
    String? version,
    bool? enabled,
    List<String>? types,
    List<String>? resources,
    List<String>? idPrefixes,
    List<StremioAddonCatalog>? catalogs,
    DateTime? addedAt,
    DateTime? lastChecked,
  }) {
    return StremioAddon(
      id: id ?? this.id,
      manifestId: manifestId ?? this.manifestId,
      name: name ?? this.name,
      manifestUrl: manifestUrl ?? this.manifestUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      connectionResourceId: connectionResourceId ?? this.connectionResourceId,
      connectionResourceRevision:
          connectionResourceRevision ?? this.connectionResourceRevision,
      connectionResourceReadOnly:
          connectionResourceReadOnly ?? this.connectionResourceReadOnly,
      connectionResourceCredentialsRedacted:
          connectionResourceCredentialsRedacted ??
          this.connectionResourceCredentialsRedacted,
      description: description ?? this.description,
      version: version ?? this.version,
      enabled: enabled ?? this.enabled,
      types: types ?? this.types,
      resources: resources ?? this.resources,
      idPrefixes: idPrefixes ?? this.idPrefixes,
      catalogs: catalogs ?? this.catalogs,
      addedAt: addedAt ?? this.addedAt,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  @override
  String toString() {
    return 'StremioAddon(id: $id, name: $name, enabled: $enabled, '
        'types: $types, resources: $resources)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StremioAddon &&
        other.id == id &&
        other.manifestUrl == manifestUrl;
  }

  @override
  int get hashCode => id.hashCode ^ manifestUrl.hashCode;
}

/// Represents a stream result from a Stremio addon
class StremioStream {
  /// Torrent info hash (if available)
  final String? infoHash;

  /// Magnet URI (if available)
  final String? magnetUri;

  /// Direct URL (for non-torrent streams - playable URLs)
  final String? url;

  /// External URL (opens in browser/external app - e.g., Netflix link)
  final String? externalUrl;

  /// Stream title/name
  final String? title;

  /// The addon's raw short `name` label (kept distinct from [title], which
  /// prefers the longer `description`). Used as the display title for
  /// recommendation ("Watch Next") entries.
  final String? name;

  /// File index within the torrent (for multi-file torrents)
  final int? fileIdx;

  /// Optional behavior hints
  final Map<String, dynamic>? behaviorHints;

  /// Source addon name
  final String source;

  /// Provenance needed to re-fetch a fresh URL for an addon-backed pin. The
  /// key is an opaque digest of the installed addon configuration; it never
  /// contains the addon's configured URL or credentials.
  final String? addonId;
  final String? addonKey;

  /// Stable-ish stream profile plus its original response position. The
  /// profile deliberately excludes the URL (often signed/expiring) and
  /// normalizes episode tokens, while the position disambiguates equal labels.
  final String? streamKey;
  final int streamIndex;

  StremioStream({
    this.infoHash,
    this.magnetUri,
    this.url,
    this.externalUrl,
    this.title,
    this.name,
    this.fileIdx,
    this.behaviorHints,
    required this.source,
    this.addonId,
    this.addonKey,
    this.streamKey,
    this.streamIndex = 0,
  });

  /// Whether this is a torrent stream (has infoHash)
  bool get isTorrent => infoHash != null && infoHash!.isNotEmpty;

  /// Whether this is a direct URL stream (has url but no infoHash)
  bool get isDirectUrl => !isTorrent && url != null && url!.isNotEmpty;

  /// Whether this is an external URL stream (opens in browser)
  bool get isExternalUrl => externalUrl != null && externalUrl!.isNotEmpty;

  /// Whether this stream is usable (has any playable source)
  bool get isUsable => isTorrent || isDirectUrl || isExternalUrl;

  /// Matches the Stremio in-app navigation deep link some addons (e.g.
  /// "Watch Next") return as fake streams: `stremio:///detail/<type>/<id>`.
  /// Two or three slashes after the scheme are both accepted; only the
  /// leading title id is captured (trailing season/episode segments — e.g.
  /// `.../series/tt123/tt123:1:1` — are ignored).
  static final RegExp _recommendationLinkRe = RegExp(
    r'^stremio:/{2,3}detail/([a-z]+)/(tt\d{7,10})',
    caseSensitive: false,
  );

  /// The `(type, imdbId)` this stream navigates to when it is a Stremio
  /// detail deep link, or null when it is a normal/playable stream.
  ///
  /// These entries are *not* playable media — they are recommendations
  /// meant to be opened inside the app, so they are kept out of the
  /// torrent/sources pipeline and surfaced as a "Watch Next" rail instead.
  ({String type, String imdbId})? get recommendationTarget {
    final ext = externalUrl;
    if (ext == null || ext.isEmpty) return null;
    final m = _recommendationLinkRe.firstMatch(ext);
    if (m == null) return null;
    return (type: m.group(1)!.toLowerCase(), imdbId: m.group(2)!);
  }

  /// Whether this "stream" is actually a Stremio detail deep link
  /// (a recommendation), not a playable source.
  bool get isRecommendationLink => recommendationTarget != null;

  /// Extract seeders from title if available (common pattern: "seeders: 123")
  int? get seedersFromTitle {
    if (title == null) return null;
    // Common patterns: "👤 123", "S: 123", "seeders: 123"
    final patterns = [
      RegExp(r'👤\s*(\d+)'),
      RegExp(r'\bS:\s*(\d+)'),
      RegExp(r'seeders?:\s*(\d+)', caseSensitive: false),
      RegExp(r'\[(\d+)\s*seeds?\]', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(title!);
      if (match != null) {
        return int.tryParse(match.group(1) ?? '');
      }
    }
    return null;
  }

  /// Extract size from title if available
  String? get sizeFromTitle {
    if (title == null) return null;
    // Common patterns: "💾 1.5 GB", "Size: 1.5GB"
    final pattern = RegExp(
      r'(?:💾|size:?)\s*([\d.]+\s*(?:GB|MB|TB|KB))',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(title!);
    return match?.group(1)?.trim();
  }

  factory StremioStream.fromJson(
    Map<String, dynamic> json,
    String source, {
    String? addonId,
    String? addonKey,
    int streamIndex = 0,
  }) {
    String? infoHash = json['infoHash'] as String?;
    final behaviorHints = json['behaviorHints'] as Map<String, dynamic>?;

    // Try to extract infoHash from behaviorHints.bingeGroup
    // Formats: "addon|hash" or "addon|debrid|hash" (e.g., "addon|realdebrid|58b0e410...")
    if (infoHash == null && behaviorHints != null) {
      final bingeGroup = behaviorHints['bingeGroup'] as String?;
      if (bingeGroup != null && bingeGroup.contains('|')) {
        final parts = bingeGroup.split('|');
        // Check each part for a valid SHA1 hash (40 hex chars)
        for (final part in parts) {
          if (part.length == 40 && RegExp(r'^[a-fA-F0-9]+$').hasMatch(part)) {
            infoHash = part;
            break;
          }
        }
      }
    }

    // Get title - try description first, then title (detailed info
    // with torrent name/size/seeders), then name (short addon label).
    String? title =
        json['description'] as String? ??
        json['title'] as String? ??
        json['name'] as String?;

    return StremioStream(
      infoHash: infoHash,
      magnetUri: json['magnetUri'] as String? ?? json['magnet'] as String?,
      url: json['url'] as String?,
      externalUrl: json['externalUrl'] as String?,
      title: title,
      name: json['name'] as String?,
      fileIdx: json['fileIdx'] as int?,
      behaviorHints: behaviorHints,
      source: source,
      addonId: addonId,
      addonKey: addonKey,
      streamKey: _directStreamProfileKey(json),
      streamIndex: streamIndex,
    );
  }

  /// Fingerprint the user-visible stream choice without retaining its URL.
  /// Episode numbers, torrent hashes and file sizes commonly change between
  /// episodes, so they are normalized out; quality/provider labels remain.
  static String _directStreamProfileKey(Map<String, dynamic> json) {
    final hints = json['behaviorHints'] as Map<String, dynamic>?;
    String normalize(Object? raw) {
      var value = raw?.toString().trim().toLowerCase() ?? '';
      value = value
          .replaceAll(RegExp(r'\b[a-f0-9]{40,64}\b'), '{hash}')
          .replaceAll(RegExp(r'\bs\d{1,2}\s*e\d{1,3}\b'), '{episode}')
          .replaceAll(RegExp(r'\b\d{1,2}x\d{1,3}\b'), '{episode}')
          .replaceAll(RegExp(r'\bepisode\s*\d{1,3}\b'), '{episode}')
          .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\s*(?:kb|mb|gb|tb)\b'), '{size}')
          .replaceAll(RegExp(r'\s+'), ' ');
      return value;
    }

    final identity = <String>[
      normalize(json['name']),
      normalize(json['description'] ?? json['title']),
      normalize(hints?['filename']),
      normalize(hints?['bingeGroup']),
      normalize(json['fileIdx']),
    ].join('|');
    return sha256.convert(utf8.encode(identity)).toString();
  }

  @override
  String toString() {
    return 'StremioStream(infoHash: $infoHash, title: $title, source: $source)';
  }
}
