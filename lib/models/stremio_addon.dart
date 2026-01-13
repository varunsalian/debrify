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

  /// Get the genre extra param if available (for options)
  StremioExtraParam? get genreParam =>
      extras.cast<StremioExtraParam?>().firstWhere(
            (e) => e?.name == 'genre',
            orElse: () => null,
          );

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
      if (extraSupported == null) {
        extraSupported = extras.map((e) => e.name).toList();
      }
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
  /// IMDB ID (e.g., 'tt1234567')
  final String id;

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

  const StremioMeta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.description,
    this.year,
    this.imdbRating,
    this.genres,
  });

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

    return StremioMeta(
      id: json['id'] as String? ?? json['imdb_id'] as String? ?? '',
      type: json['type'] as String? ?? 'movie',
      name: json['name'] as String? ?? json['title'] as String? ?? 'Unknown',
      poster: json['poster'] as String?,
      background: json['background'] as String? ?? json['fanart'] as String?,
      description: json['description'] as String? ?? json['overview'] as String?,
      year: year,
      imdbRating: rating,
      genres: (json['genres'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Check if this is a valid IMDB ID
  bool get hasValidImdbId => id.startsWith('tt') && id.length >= 9;

  /// Check if this has a valid ID (any non-empty ID, not just IMDB)
  bool get hasValidId => id.isNotEmpty;

  /// Check if this is a non-IMDB content type (TV channel, etc.)
  bool get isNonImdb => !hasValidImdbId && hasValidId;

  @override
  String toString() => 'StremioMeta(id: $id, name: $name, year: $year)';
}

/// Represents a section of catalog content for homepage display
class CatalogSection {
  /// Display title (e.g., "Cinemeta: Popular Movies")
  final String title;

  /// The addon this section is from
  final StremioAddon addon;

  /// The specific catalog
  final StremioAddonCatalog catalog;

  /// Items in this section
  final List<StremioMeta> items;

  const CatalogSection({
    required this.title,
    required this.addon,
    required this.catalog,
    required this.items,
  });
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

  /// Human-readable name from manifest
  final String name;

  /// The full manifest URL (includes any configuration)
  final String manifestUrl;

  /// Base URL derived from manifest URL (without /manifest.json)
  final String baseUrl;

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
    required this.name,
    required this.manifestUrl,
    required this.baseUrl,
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

  /// Whether this addon supports streaming (has 'stream' resource)
  bool get supportsStreams => resources.contains('stream');

  /// Whether this addon supports catalogs (has 'catalog' resource)
  bool get supportsCatalogs =>
      resources.contains('catalog') && catalogs.isNotEmpty;

  /// Whether this addon supports movies
  bool get supportsMovies => types.contains('movie');

  /// Whether this addon supports series/TV shows
  bool get supportsSeries => types.contains('series');

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
  /// - The addon's idPrefixes contains the prefix extracted from contentId
  bool supportsContentId(String contentId) {
    // No restriction means addon accepts all IDs
    if (idPrefixes == null || idPrefixes!.isEmpty) {
      return true;
    }

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
    String baseUrl = manifestUrl;
    if (baseUrl.endsWith('/manifest.json')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - '/manifest.json'.length);
    }

    return StremioAddon(
      id: id,
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
      name: json['name'] as String,
      manifestUrl: json['manifest_url'] as String,
      baseUrl: json['base_url'] as String,
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
      'name': name,
      'manifest_url': manifestUrl,
      'base_url': baseUrl,
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
    String? name,
    String? manifestUrl,
    String? baseUrl,
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
      name: name ?? this.name,
      manifestUrl: manifestUrl ?? this.manifestUrl,
      baseUrl: baseUrl ?? this.baseUrl,
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

  /// File index within the torrent (for multi-file torrents)
  final int? fileIdx;

  /// Optional behavior hints
  final Map<String, dynamic>? behaviorHints;

  /// Source addon name
  final String source;

  StremioStream({
    this.infoHash,
    this.magnetUri,
    this.url,
    this.externalUrl,
    this.title,
    this.fileIdx,
    this.behaviorHints,
    required this.source,
  });

  /// Whether this is a torrent stream (has infoHash)
  bool get isTorrent => infoHash != null && infoHash!.isNotEmpty;

  /// Whether this is a direct URL stream (has url but no infoHash)
  bool get isDirectUrl =>
      !isTorrent && url != null && url!.isNotEmpty;

  /// Whether this is an external URL stream (opens in browser)
  bool get isExternalUrl => externalUrl != null && externalUrl!.isNotEmpty;

  /// Whether this stream is usable (has any playable source)
  bool get isUsable => isTorrent || isDirectUrl || isExternalUrl;

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

  factory StremioStream.fromJson(Map<String, dynamic> json, String source) {
    String? infoHash = json['infoHash'] as String?;
    final behaviorHints = json['behaviorHints'] as Map<String, dynamic>?;

    // Try to extract infoHash from behaviorHints.bingeGroup (format: "addon|hash")
    if (infoHash == null && behaviorHints != null) {
      final bingeGroup = behaviorHints['bingeGroup'] as String?;
      if (bingeGroup != null && bingeGroup.contains('|')) {
        final parts = bingeGroup.split('|');
        if (parts.length >= 2) {
          final potentialHash = parts[1];
          // Validate it looks like a hash (40 hex chars for SHA1)
          if (potentialHash.length == 40 &&
              RegExp(r'^[a-fA-F0-9]+$').hasMatch(potentialHash)) {
            infoHash = potentialHash;
          }
        }
      }
    }

    // Get title - try description first (Comet uses this), then name, then title
    String? title = json['description'] as String? ??
        json['name'] as String? ??
        json['title'] as String?;

    return StremioStream(
      infoHash: infoHash,
      magnetUri: json['magnetUri'] as String? ?? json['magnet'] as String?,
      url: json['url'] as String?,
      externalUrl: json['externalUrl'] as String?,
      title: title,
      fileIdx: json['fileIdx'] as int?,
      behaviorHints: behaviorHints,
      source: source,
    );
  }

  @override
  String toString() {
    return 'StremioStream(infoHash: $infoHash, title: $title, source: $source)';
  }
}
