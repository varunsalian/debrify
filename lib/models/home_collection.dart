import 'dart:convert';

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

/// One addon catalog a folder pulls from.
class CollectionCatalogSource {
  /// Stremio manifest id of the addon (`StremioAddon.id`).
  final String addonId;

  /// `movie` / `series` / … — the catalog's type.
  final String type;

  /// `StremioAddonCatalog.id`.
  final String catalogId;

  /// Optional `genre` extra applied to the catalog request.
  final String? genre;

  const CollectionCatalogSource({
    required this.addonId,
    required this.type,
    required this.catalogId,
    this.genre,
  });

  /// De-duplication identity (a Nuvio file lists each source twice: under
  /// `catalogSources` and again under `sources`).
  String get key => '$addonId|$type|$catalogId|${genre ?? ''}';

  static CollectionCatalogSource? fromJson(Object? json) {
    if (json is! Map) return null;
    // `sources` entries carry a `provider`; a non-addon provider (a future
    // "url"/"trakt" source) is skipped rather than mis-read as an addon.
    final provider = json['provider'];
    if (provider is String && provider.isNotEmpty && provider != 'addon') {
      return null;
    }
    final addonId = _str(json['addonId']) ?? _str(json['addon']);
    final catalogId = _str(json['catalogId']) ?? _str(json['id']);
    if (addonId == null || catalogId == null) return null;
    final type = _str(json['type']) ?? 'movie';
    final genre = _str(json['genre']);
    return CollectionCatalogSource(
      addonId: addonId,
      type: type,
      catalogId: catalogId,
      genre: genre,
    );
  }

  Map<String, dynamic> toJson() => {
    'addonId': addonId,
    'type': type,
    'catalogId': catalogId,
    'genre': genre,
  };
}

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
  final String? titleLogoUrl;
  final String? focusGifUrl;
  final bool focusGifEnabled;
  final CollectionTileShape tileShape;
  final List<CollectionCatalogSource> sources;

  const HomeCollectionFolder({
    required this.id,
    required this.title,
    this.hideTitle = false,
    this.coverImageUrl,
    this.coverEmoji,
    this.heroBackdropUrl,
    this.titleLogoUrl,
    this.focusGifUrl,
    this.focusGifEnabled = false,
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
        titleLogoUrl: titleLogoUrl,
        focusGifUrl: focusGifUrl,
        focusGifEnabled: focusGifEnabled,
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
      for (final raw in list) {
        final s = CollectionCatalogSource.fromJson(raw);
        if (s != null && seen.add(s.key)) sources.add(s);
      }
    }

    // `catalogSources` is canonical; `sources` duplicates it with a
    // `provider` field. Reading both tolerates files that carry only one.
    addAll(json['catalogSources']);
    addAll(json['sources']);

    return HomeCollectionFolder(
      id: id,
      title: title,
      hideTitle: json['hideTitle'] == true,
      coverImageUrl: _str(json['coverImageUrl']) ?? _str(json['cover']),
      coverEmoji: _str(json['coverEmoji']),
      heroBackdropUrl:
          _str(json['heroBackdropUrl']) ?? _str(json['backdropImageUrl']),
      titleLogoUrl: _str(json['titleLogoUrl']),
      focusGifUrl: _str(json['focusGifUrl']),
      focusGifEnabled: json['focusGifEnabled'] == true,
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
    'titleLogoUrl': titleLogoUrl,
    'focusGifUrl': focusGifUrl,
    'focusGifEnabled': focusGifEnabled,
    'tileShape': tileShape.storageValue,
    'catalogSources': [for (final s in sources) s.toJson()],
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

  /// Whether the folder browser offers an "All" view merging every list.
  final bool showAllTab;
  final String? backdropImageUrl;
  final List<HomeCollectionFolder> folders;

  /// Local state (not in the Nuvio file): switched off without deleting.
  final bool enabled;

  /// Local state: when this collection was last imported, epoch ms.
  final int? importedAtMs;

  const HomeCollection({
    required this.id,
    required this.title,
    this.pinToTop = false,
    this.showAllTab = true,
    this.backdropImageUrl,
    this.folders = const [],
    this.enabled = true,
    this.importedAtMs,
  });

  String get rowId => HomeCollectionRowIds.collection(id);

  int get sourceCount => folders.fold(0, (sum, f) => sum + f.sources.length);

  HomeCollection copyWith({bool? enabled, int? importedAtMs}) => HomeCollection(
    id: id,
    title: title,
    pinToTop: pinToTop,
    showAllTab: showAllTab,
    backdropImageUrl: backdropImageUrl,
    folders: folders,
    enabled: enabled ?? this.enabled,
    importedAtMs: importedAtMs ?? this.importedAtMs,
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
      showAllTab: json['showAllTab'] != false,
      backdropImageUrl: _str(json['backdropImageUrl']),
      folders: folders,
      enabled: json['enabled'] != false,
      importedAtMs: importedAt is num ? importedAt.toInt() : null,
    );
  }

  /// Nuvio-compatible shape plus the local `enabled` / `importedAt` fields
  /// (which a Nuvio import ignores).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pinToTop': pinToTop,
    'showAllTab': showAllTab,
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
      decoded = jsonDecode(jsonText);
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
