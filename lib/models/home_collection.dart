import 'dart:convert';
import '../utils/canonical_json.dart';

import 'package:crypto/crypto.dart';

/// Row-id grammar for imported collections on the Home board. Kept next to
/// the model so the board, the Home Rows manager and the settings page
/// cannot drift on what an id means.
class HomeCollectionRowIds {
  HomeCollectionRowIds._();

  /// `collection:<collectionId>` — one board row per collection, its folders
  /// as tiles.
  static const String prefix = 'collection:';

  static String collection(String collectionId) => '$prefix$collectionId';

  static bool isCollection(String id) => id.startsWith(prefix);

  /// The `<collectionId>` of a `collection:` id (null for anything else).
  static String? collectionId(String id) =>
      isCollection(id) ? id.substring(prefix.length) : null;

  /// Synthetic meta id for a folder tile on the board (`StremioMeta.id`).
  static String folderMetaId(String collectionId, String folderId) =>
      'collection:$collectionId:$folderId';

  /// `collectionlist:…` — one catalog list inside a folder. Toggleable in the
  /// Home Rows manager (off = present in the disabled set) but never a board
  /// row itself.
  static const String folderListPrefix = 'collectionlist:';

  static String folderList(
    String collectionId,
    String folderId,
    CollectionCatalogSource source,
  ) =>
      '$folderListPrefix$collectionId:$folderId:'
      '${source.addonId}:${source.type}:${source.catalogId}'
      '${source.genre == null ? '' : ':${source.genre}'}';

  static bool isFolderList(String id) => id.startsWith(folderListPrefix);
}

/// How an opened folder presents its lists: stacked horizontal rows, or one
/// list at a time behind a selector. A per-profile preference, not part of
/// the collections file.
enum CollectionFolderLayout {
  rows,
  tabs;

  static CollectionFolderLayout parse(Object? raw) =>
      raw is String && raw.trim().toLowerCase() == 'tabs'
      ? CollectionFolderLayout.tabs
      : CollectionFolderLayout.rows;

  String get storageValue => name;
}

/// How a folder's cover tile is shaped on the Home board.
enum CollectionTileShape {
  landscape(16 / 9),
  portrait(2 / 3),
  square(1);

  const CollectionTileShape(this.aspectRatio);

  /// Width / height.
  final double aspectRatio;

  /// Lenient: unknown or missing values fall back to landscape.
  static CollectionTileShape parse(Object? raw) {
    switch ((raw is String ? raw : '').trim().toUpperCase()) {
      case 'PORTRAIT':
      case 'POSTER':
        return CollectionTileShape.portrait;
      case 'SQUARE':
        return CollectionTileShape.square;
      default:
        return CollectionTileShape.landscape;
    }
  }

  String get storageValue => name.toUpperCase();
}

/// A Nuvio source. Native fields survive import, backup, and sync unchanged.
/// The legacy constructor and addon identity remain stable for existing rows.
class CollectionCatalogSource {
  final String addonId;
  final String type;
  final String catalogId;
  final String? genre;
  final String provider;
  final String? title;
  final String? tmdbSourceType;
  final int? tmdbId;
  final int? traktListId;
  final String? sortBy;
  final String? sortHow;
  final Map<String, dynamic> filters;
  final Map<String, dynamic> extra;

  const CollectionCatalogSource({
    required this.addonId,
    required this.type,
    required this.catalogId,
    this.genre,
    this.provider = 'addon',
    this.title,
    this.tmdbSourceType,
    this.tmdbId,
    this.traktListId,
    this.sortBy,
    this.sortHow,
    this.filters = const {},
    this.extra = const {},
  });

  bool get isAddon => provider == 'addon';
  bool get isNative => provider == 'tmdb' || provider == 'trakt';
  String get mediaType => type == 'series' ? 'tv' : 'movie';
  String get key => isAddon
      ? '$addonId|$type|$catalogId|${genre ?? ''}'
      : '$provider|$catalogId';
  String get label => title ?? (isAddon ? catalogId : provider.toUpperCase());

  static CollectionCatalogSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = Map<String, dynamic>.from(json);
    final provider = (_str(raw['provider']) ?? 'addon').toLowerCase();
    if (provider == 'addon') {
      final addonId = _str(raw['addonId']) ?? _str(raw['addon']);
      final catalogId = _str(raw['catalogId']) ?? _str(raw['id']);
      if (addonId == null || catalogId == null) return null;
      final genre = _str(raw['genre']);
      return CollectionCatalogSource(
        addonId: addonId,
        catalogId: catalogId,
        type: _str(raw['type']) ?? 'movie',
        genre: genre?.toLowerCase() == 'none' ? null : genre,
        title: _str(raw['title']),
      );
    }
    final media = (_str(raw['mediaType']) ?? 'MOVIE').toUpperCase();
    final identity = <String, dynamic>{
      'provider': provider,
      'sortBy': _str(raw['sortBy']),
      'sortHow': _str(raw['sortHow']),
      'mediaType': media == 'TV' || media == 'SERIES' ? 'TV' : 'MOVIE',
      if (provider == 'tmdb') ...{
        'tmdbSourceType': _str(raw['tmdbSourceType'])?.toUpperCase(),
        'tmdbId': _integer(raw['tmdbId']),
        'filters': raw['filters'] is Map ? raw['filters'] : <String, dynamic>{},
      },
      if (provider == 'trakt') 'traktListId': _integer(raw['traktListId']),
    };
    return CollectionCatalogSource(
      provider: provider,
      addonId: provider,
      catalogId:
          _str(raw['debrifySourceId']) ??
          HomeCollection.stableId(encodeCanonicalJson(identity)),
      type: media == 'TV' || media == 'SERIES' ? 'series' : 'movie',
      title: _str(raw['title']),
      tmdbSourceType: _str(raw['tmdbSourceType'])?.toUpperCase(),
      tmdbId: _integer(raw['tmdbId']),
      traktListId: _integer(raw['traktListId']),
      sortBy: _str(raw['sortBy']),
      sortHow: _str(raw['sortHow']),
      filters: raw['filters'] is Map
          ? Map<String, dynamic>.unmodifiable(raw['filters'] as Map)
          : const {},
      extra: Map<String, dynamic>.unmodifiable(raw),
    );
  }

  Map<String, dynamic> toJson() => isAddon
      ? {
          'addonId': addonId,
          'type': type,
          'catalogId': catalogId,
          'genre': genre,
          if (title != null) 'title': title,
        }
      : {
          ...extra,
          'debrifySourceId': catalogId,
          'provider': provider,
          if (title != null) 'title': title,
          'mediaType': type == 'series' ? 'TV' : 'MOVIE',
          if (provider == 'tmdb') ...{
            'tmdbSourceType': tmdbSourceType,
            'tmdbId': tmdbId,
            'filters': filters,
          },
          if (provider == 'trakt') 'traktListId': traktListId,
          if (sortBy != null) 'sortBy': sortBy,
          if (sortHow != null) 'sortHow': sortHow,
        };
}

int? _integer(Object? value) => value is num
    ? (value.isFinite && value == value.truncateToDouble()
          ? value.toInt()
          : null)
    : int.tryParse('$value');

/// A folder: a titled, cover-art tile whose contents are the merged catalogs
/// in [sources].
class HomeCollectionFolder {
  final String id;
  final String title;

  /// Draw no text over the cover — the art already carries the brand (e.g. a
  /// Netflix logo tile).
  final bool hideTitle;
  final String? coverImageUrl;
  final String? coverEmoji;
  final String? heroBackdropUrl;
  final String? heroVideoUrl;
  final String? titleLogoUrl;
  final String? focusGifUrl;
  final bool focusGifEnabled;
  final String? focusVideoUrl;
  final bool focusVideoEnabled;
  final CollectionTileShape tileShape;
  final List<CollectionCatalogSource> sources;

  const HomeCollectionFolder({
    required this.id,
    required this.title,
    this.hideTitle = false,
    this.coverImageUrl,
    this.coverEmoji,
    this.heroBackdropUrl,
    this.heroVideoUrl,
    this.titleLogoUrl,
    this.focusGifUrl,
    this.focusGifEnabled = true,
    this.focusVideoUrl,
    this.focusVideoEnabled = true,
    this.tileShape = CollectionTileShape.landscape,
    this.sources = const [],
  });

  HomeCollectionFolder copyWith({List<CollectionCatalogSource>? sources}) =>
      HomeCollectionFolder(
        id: id,
        title: title,
        hideTitle: hideTitle,
        coverImageUrl: coverImageUrl,
        coverEmoji: coverEmoji,
        heroBackdropUrl: heroBackdropUrl,
        heroVideoUrl: heroVideoUrl,
        titleLogoUrl: titleLogoUrl,
        focusGifUrl: focusGifUrl,
        focusGifEnabled: focusGifEnabled,
        focusVideoUrl: focusVideoUrl,
        focusVideoEnabled: focusVideoEnabled,
        tileShape: tileShape,
        sources: sources ?? this.sources,
      );

  static HomeCollectionFolder? fromJson(
    Object? json, {
    required String collectionId,
  }) {
    if (json is! Map) return null;
    final title = _str(json['title']) ?? _str(json['name']) ?? '';
    final id =
        _str(json['id']) ?? HomeCollection.stableId('$collectionId/$title');

    final seen = <String>{};
    final sources = <CollectionCatalogSource>[];
    void addAll(Object? list) {
      if (list is! List) return;
      final localSeen = <String>{};
      for (final raw in list) {
        final parsed = CollectionCatalogSource.fromJson(raw);
        if (parsed == null) continue;
        var s = parsed;
        if (!s.isAddon) {
          final baseId = s.catalogId;
          var ordinal = 0;
          while (!localSeen.add(s.key)) {
            s = CollectionCatalogSource.fromJson({
              ...s.toJson(),
              'debrifySourceId': '$baseId-${++ordinal}',
            })!;
          }
        }
        if (seen.add(s.key)) sources.add(s);
      }
    }

    // Modern sources preserve the author's mixed-provider order. Legacy
    // catalogs are appended only when they are not already represented.
    addAll(json['sources']);
    addAll(json['catalogSources']);

    return HomeCollectionFolder(
      id: id,
      title: title,
      hideTitle: json['hideTitle'] == true,
      coverImageUrl: _str(json['coverImageUrl']) ?? _str(json['cover']),
      coverEmoji: _str(json['coverEmoji']),
      heroBackdropUrl:
          _str(json['heroBackdropUrl']) ?? _str(json['backdropImageUrl']),
      heroVideoUrl: _str(json['heroVideoUrl']),
      titleLogoUrl: _str(json['titleLogoUrl']),
      focusGifUrl: _str(json['focusGifUrl']),
      focusGifEnabled: json['focusGifEnabled'] != false,
      focusVideoUrl: _str(json['focusVideoUrl']),
      focusVideoEnabled: json['focusVideoEnabled'] != false,
      tileShape: CollectionTileShape.parse(json['tileShape']),
      sources: sources,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'hideTitle': hideTitle,
    'coverImageUrl': coverImageUrl,
    'coverEmoji': coverEmoji,
    'heroBackdropUrl': heroBackdropUrl,
    'heroVideoUrl': heroVideoUrl,
    'titleLogoUrl': titleLogoUrl,
    'focusGifUrl': focusGifUrl,
    'focusGifEnabled': focusGifEnabled,
    'focusVideoUrl': focusVideoUrl,
    'focusVideoEnabled': focusVideoEnabled,
    'tileShape': tileShape.storageValue,
    'catalogSources': [
      for (final s in sources)
        if (s.isAddon) s.toJson(),
    ],
    if (sources.any((s) => !s.isAddon))
      'sources': [
        for (final s in sources) {...s.toJson(), 'provider': s.provider},
      ],
  };
}

/// A collection: a titled group of folders that becomes one Home row.
///
/// Storage and import share the Nuvio / Xperience JSON shape, so a backup
/// round-trips and a third-party file parses without conversion. Every field
/// is optional — third-party files drift, and a folder with no art is still
/// a folder.
class HomeCollection {
  final String id;
  final String title;

  /// The row leads the board, ahead of the tracker list rows.
  final bool pinToTop;

  /// Artwork-colored halo around the focused folder tile (Nuvio default: on).
  final bool focusGlowEnabled;

  /// Whether the folder browser offers an "All" view merging every list.
  final bool showAllTab;

  /// Imported Nuvio layout; absent values use the profile preference.
  final String? viewMode;
  final String? backdropImageUrl;
  final List<HomeCollectionFolder> folders;

  /// Local state (not in the Nuvio file): switched off without deleting.
  final bool enabled;

  /// Local state: when this collection was last imported, epoch ms.
  final int? importedAtMs;
  // Storage provenance for migration only; sync conflicts use normal LWW.
  final int serializationVersion;

  const HomeCollection({
    required this.id,
    required this.title,
    this.pinToTop = false,
    this.focusGlowEnabled = true,
    this.showAllTab = true,
    this.viewMode,
    this.backdropImageUrl,
    this.folders = const [],
    this.enabled = true,
    this.importedAtMs,
    this.serializationVersion = 2,
  });

  String get rowId => HomeCollectionRowIds.collection(id);

  int get sourceCount => folders.fold(0, (sum, f) => sum + f.sources.length);

  HomeCollection copyWith({bool? enabled, int? importedAtMs}) => HomeCollection(
    id: id,
    title: title,
    pinToTop: pinToTop,
    focusGlowEnabled: focusGlowEnabled,
    showAllTab: showAllTab,
    viewMode: viewMode,
    backdropImageUrl: backdropImageUrl,
    folders: folders,
    enabled: enabled ?? this.enabled,
    importedAtMs: importedAtMs ?? this.importedAtMs,
    serializationVersion: serializationVersion,
  );

  static HomeCollection? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = _str(json['title']) ?? _str(json['name']) ?? '';
    final rawFolders = json['folders'];
    if (title.isEmpty && rawFolders is! List) return null;
    final id = _str(json['id']) ?? stableId(title);
    final folders = <HomeCollectionFolder>[];
    final seen = <String>{};
    if (rawFolders is List) {
      for (final raw in rawFolders) {
        final f = HomeCollectionFolder.fromJson(raw, collectionId: id);
        if (f != null && seen.add(f.id)) folders.add(f);
      }
    }
    final importedAt = json['importedAt'];
    return HomeCollection(
      id: id,
      title: title.isEmpty ? 'Collection' : title,
      pinToTop: json['pinToTop'] == true,
      focusGlowEnabled: json['focusGlowEnabled'] != false,
      showAllTab: json['showAllTab'] != false,
      viewMode: _str(json['viewMode']),
      backdropImageUrl: _str(json['backdropImageUrl']),
      folders: folders,
      enabled: json['enabled'] != false,
      importedAtMs: importedAt is num ? importedAt.toInt() : null,
      serializationVersion: json['debrifyCollectionVersion'] == 1 ? 1 : 2,
    );
  }

  /// Nuvio-compatible shape plus the local `enabled` / `importedAt` fields
  /// (which a Nuvio import ignores).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'debrifyCollectionVersion': serializationVersion,
    'debrifyVisualVersion': 2,
    'pinToTop': pinToTop,
    'focusGlowEnabled': focusGlowEnabled,
    'showAllTab': showAllTab,
    if (viewMode != null) 'viewMode': viewMode,
    'backdropImageUrl': backdropImageUrl,
    'folders': [for (final f in folders) f.toJson()],
    'enabled': enabled,
    if (importedAtMs != null) 'importedAt': importedAtMs,
  };

  /// Deterministic id for a record that came without one, so re-importing
  /// the same file replaces rather than duplicates.
  static String stableId(String seed) =>
      sha1.convert(utf8.encode(seed)).toString().substring(0, 16);
}

/// Parses a collections JSON document into [HomeCollection]s.
///
/// Accepts:
///   - a bare list of collections (the Nuvio / Xperience export),
///   - `{ "collections": [ … ] }` (a wrapped export or a Debrify backup),
///   - a single collection object,
///   - a bare list of folders (wrapped into one "Imported" collection).
///
/// Throws [FormatException] with a user-readable message when the text is
/// not JSON or holds no collection.
class HomeCollectionParser {
  HomeCollectionParser._();

  static List<HomeCollection> parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(
        jsonText.trimLeft().replaceFirst(RegExp(r'^\uFEFF'), ''),
      );
    } catch (_) {
      throw const FormatException('The file is not valid JSON.');
    }
    return parseDecoded(decoded);
  }

  static List<HomeCollection> parseDecoded(Object? decoded) {
    Object? root = decoded;
    if (root is Map) {
      final wrapped =
          root['collections'] ?? root['homeCollections'] ?? root['data'];
      if (wrapped is List) {
        root = wrapped;
      } else if (root.containsKey('folders') ||
          root.containsKey('title') ||
          root.containsKey('name')) {
        root = [root];
      } else {
        throw const FormatException(
          'No collections found — expected a list of collections '
          'with "title" and "folders".',
        );
      }
    }
    if (root is! List) {
      throw const FormatException(
        'Unexpected JSON shape — expected a list of collections.',
      );
    }
    if (root.isEmpty) {
      throw const FormatException('The file contains no collections.');
    }

    // A bare list of folders (catalog sources but no `folders`) imports as
    // one collection.
    final looksLikeFolders = root.every(
      (e) =>
          e is Map &&
          !e.containsKey('folders') &&
          (e.containsKey('catalogSources') || e.containsKey('sources')),
    );
    if (looksLikeFolders) {
      root = [
        {'title': 'Imported', 'folders': root},
      ];
    }

    final out = <HomeCollection>[];
    final seen = <String>{};
    for (final raw in root) {
      final c = HomeCollection.fromJson(raw);
      if (c == null || !seen.add(c.id)) continue;
      out.add(c);
    }
    if (out.isEmpty) {
      throw const FormatException(
        'No collections found — expected a list of collections '
        'with "title" and "folders".',
      );
    }
    return out;
  }
}

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
