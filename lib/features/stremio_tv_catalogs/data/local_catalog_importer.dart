import 'dart:convert';

import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/storage/stremio_catalog_storage.dart';
import 'package:debrify/services/trakt/trakt_item_transformer.dart';
import 'package:debrify/services/trakt/trakt_service.dart';

// ─── Import helper ──────────────────────────────────────────────────────────

/// Shared validation and save logic for local catalog imports.
/// Supports both the native format and Trakt list JSON.
class LocalCatalogImporter {
  LocalCatalogImporter._();

  static const Set<String> _portableTraktSources = <String>{
    'trending',
    'popular',
    'anticipated',
    'liked',
  };

  /// Generate a unique catalog ID from the name.
  static String generateId(String name) {
    final sanitized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${sanitized}_$ts';
  }

  static Map<String, dynamic> _portableImportMetadata(
    Map<String, dynamic> parsed,
  ) {
    final source = parsed['traktSource'] as String?;
    if (source == null || !_portableTraktSources.contains(source)) {
      return const <String, dynamic>{};
    }

    if (source == 'liked') {
      final slug = parsed['traktSlug'] as String?;
      final owner = parsed['traktOwner'] as String?;
      if (slug == null || slug.isEmpty || owner == null || owner.isEmpty) {
        return const <String, dynamic>{};
      }
      return <String, dynamic>{
        'traktSource': source,
        'traktSlug': slug,
        'traktOwner': owner,
      };
    }

    return <String, dynamic>{'traktSource': source};
  }

  /// Check if parsed JSON looks like a Trakt list export.
  /// Trakt lists are top-level arrays where items have nested movie/show objects.
  static bool isTrakt(dynamic parsed) {
    if (parsed is! List || parsed.isEmpty) return false;
    final first = parsed.first;
    if (first is! Map<String, dynamic>) return false;
    return first.containsKey('movie') || first.containsKey('show');
  }

  /// Transform a Trakt list array into the native catalog format.
  /// Returns the catalog map with 'name', 'type', and 'items'.
  static Map<String, dynamic> transformTrakt(List items, String catalogName) {
    final metas = TraktItemTransformer.transformList(items);

    int movieCount = 0;
    int seriesCount = 0;
    final transformed = <Map<String, dynamic>>[];

    for (final meta in metas) {
      if (meta.type == 'series') {
        seriesCount++;
      } else {
        movieCount++;
      }
      transformed.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final catalogType = seriesCount > movieCount ? 'series' : 'movie';

    return {'name': catalogName, 'type': catalogType, 'items': transformed};
  }

  /// Validate JSON catalog content. Returns error message or null if valid.
  static String? validate(String content) {
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }
    if (parsed is! Map<String, dynamic>) return 'Expected a JSON object';
    final name = parsed['name'] as String?;
    if (name == null || name.trim().isEmpty) return 'Missing "name" field';
    final items = parsed['items'] as List<dynamic>?;
    if (items == null || items.isEmpty) return '"items" is missing or empty';
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map<String, dynamic>) return 'Item $i: not an object';
      if ((item['id'] as String?)?.isEmpty ?? true) {
        return 'Item $i: missing "id"';
      }
      if ((item['name'] as String?)?.isEmpty ?? true) {
        return 'Item $i: missing "name"';
      }
    }
    return null;
  }

  /// Refresh a Trakt-sourced catalog by re-fetching its items.
  /// Returns error message or null on success.
  static Future<String?> refreshTraktCatalog(
    Map<String, dynamic> catalog,
  ) async {
    final source = catalog['traktSource'] as String?;
    final slug = catalog['traktSlug'] as String?;
    final owner = catalog['traktOwner'] as String?;
    final ownerSlug = catalog['traktOwnerSlug'] as String?;
    final listId = catalog['traktListId']?.toString();
    if (source == null) return 'Not a Trakt catalog';

    final traktService = TraktService.instance;
    final List<dynamic> rawItems;

    // Direct sources (watchlist, trending, etc.)
    const directSources = [
      'watchlist',
      'history',
      'collection',
      'ratings',
      'trending',
      'popular',
      'anticipated',
      'recommendations',
    ];
    if (directSources.contains(source)) {
      final movies = await traktService.fetchList(source, 'movies');
      final shows = await traktService.fetchList(source, 'shows');
      rawItems = [...movies, ...shows];
    } else if (source == 'custom') {
      if (slug == null || slug.isEmpty) return 'Missing list slug';
      final movies = await traktService.fetchCustomListItems(slug, 'movies');
      final shows = await traktService.fetchCustomListItems(slug, 'shows');
      rawItems = [...movies, ...shows];
    } else if (source == 'liked' &&
        ((listId != null && listId.isNotEmpty) ||
            (owner != null && owner.isNotEmpty))) {
      if (slug == null || slug.isEmpty) return 'Missing list slug';
      final list = <String, dynamic>{
        'ids': {
          if (listId != null && listId.isNotEmpty) 'trakt': listId,
          'slug': slug,
        },
        'user': {
          if (owner != null && owner.isNotEmpty) 'username': owner,
          'ids': {
            if (ownerSlug != null && ownerSlug.isNotEmpty)
              'slug': ownerSlug
            else if (owner != null && owner.isNotEmpty)
              'slug': owner,
          },
        },
      };
      final movies = await traktService.fetchLikedListItemsFromList(
        list,
        'movies',
      );
      final shows = await traktService.fetchLikedListItemsFromList(
        list,
        'shows',
      );
      rawItems = [...movies, ...shows];
    } else {
      return 'Unknown Trakt source: $source';
    }

    final metas = TraktItemTransformer.transformList(rawItems);
    if (metas.isEmpty) return 'No items found in list';

    final catalogType = catalog['type'] as String? ?? 'movie';
    final items = <Map<String, dynamic>>[];
    for (final meta in metas) {
      // Filter by catalog type (movie catalogs only get movies, series only get series)
      if (catalogType == 'series' && meta.type != 'series') continue;
      if (catalogType == 'movie' && meta.type == 'series') continue;
      items.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final updated = Map<String, dynamic>.from(catalog);
    updated['items'] = items;
    updated['addedAt'] = DateTime.now().toIso8601String();
    if (items.isEmpty) return 'No matching items after filtering by type';
    final ok = await StremioCatalogStorage.updateStremioTvLocalCatalog(updated);
    if (!ok) return 'Catalog not found — it may have been deleted';
    return null;
  }

  /// Refresh an MDBList-sourced catalog by re-fetching its items (bypassing the
  /// service cache so newly-added titles show). Filters by the catalog's own
  /// type, so a split "X — Movies"/"X — Series" pair each refreshes to its side.
  /// Returns error message or null on success.
  static Future<String?> refreshMdblistCatalog(
    Map<String, dynamic> catalog,
  ) async {
    if (!kMdblistEnabled) return 'MDBList integration is disabled';
    final listId = (catalog['mdblistListId'] as num?)?.toInt();
    if (listId == null) return 'Not an MDBList catalog';

    final loaded = await MdblistListSource.instance.loadListItems(
      MdblistListChoice(id: listId, name: ''),
      forceRefresh: true,
    );
    if (loaded.failed || !loaded.complete) {
      return 'Failed to refresh from MDBList';
    }

    final catalogType = catalog['type'] as String? ?? 'movie';
    final items = <Map<String, dynamic>>[];
    for (final meta in loaded.items) {
      // Filter by catalog type (movie catalogs only get movies, series only series).
      if (catalogType == 'series' && meta.type != 'series') continue;
      if (catalogType == 'movie' && meta.type == 'series') continue;
      items.add({
        'id': meta.id,
        'name': meta.name,
        'type': meta.type,
        if (meta.year != null) 'year': int.tryParse(meta.year!) ?? meta.year,
        if (meta.description != null) 'overview': meta.description,
        if (meta.imdbRating != null) 'rating': meta.imdbRating,
        if (meta.poster != null) 'poster': meta.poster,
        if (meta.background != null) 'fanart': meta.background,
        if (meta.genres != null && meta.genres!.isNotEmpty)
          'genres': meta.genres,
      });
    }

    final updated = Map<String, dynamic>.from(catalog);
    updated['items'] = items;
    updated['addedAt'] = DateTime.now().toIso8601String();
    if (items.isEmpty) return 'No matching items after filtering by type';
    final ok = await StremioCatalogStorage.updateStremioTvLocalCatalog(updated);
    if (!ok) return 'Catalog not found — it may have been deleted';
    return null;
  }

  /// Validate and save JSON content as a local catalog.
  /// Pass [catalogName] for Trakt lists (which lack a root name).
  /// Returns error message or null on success.
  static Future<String?> import(String content, {String? catalogName}) async {
    // Detect and transform Trakt format before validation
    dynamic raw;
    try {
      raw = jsonDecode(content);
    } catch (e) {
      return 'Invalid JSON: $e';
    }

    if (isTrakt(raw)) {
      final name = catalogName?.trim() ?? '';
      if (name.isEmpty) {
        return 'Trakt list detected — please enter a catalog name';
      }
      final transformed = transformTrakt(raw as List, name);
      final allItems = transformed['items'] as List<Map<String, dynamic>>;
      if (allItems.isEmpty) {
        return 'No items with IMDB IDs found in Trakt list';
      }

      // Split mixed lists into separate movie and series catalogs
      final movies = allItems.where((i) => i['type'] != 'series').toList();
      final series = allItems.where((i) => i['type'] == 'series').toList();
      final existing = await StremioCatalogStorage.getStremioTvLocalCatalogs();

      if (movies.isNotEmpty && series.isNotEmpty) {
        // Mixed list — create two catalogs
        for (final entry in [
          (items: movies, type: 'movie', suffix: 'Movies'),
          (items: series, type: 'series', suffix: 'Series'),
        ]) {
          final catName = '$name — ${entry.suffix}';
          if (existing.any((c) => c['name'] == catName)) continue;
          await StremioCatalogStorage.addStremioTvLocalCatalog({
            'id': generateId(catName),
            'name': catName,
            'type': entry.type,
            'addedAt': DateTime.now().toIso8601String(),
            'items': entry.items,
          });
        }
        return null;
      }

      // Single-type list — use as-is
      content = jsonEncode(transformed);
    }

    final err = validate(content);
    if (err != null) return err;

    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final name = (parsed['name'] as String).trim();

    final existing = await StremioCatalogStorage.getStremioTvLocalCatalogs();
    if (existing.any((c) => c['name'] == name)) {
      return 'Catalog "$name" already exists';
    }

    final catalog = <String, dynamic>{
      'id': generateId(name),
      'name': name,
      'type': parsed['type'] as String? ?? 'movie',
      'addedAt': DateTime.now().toIso8601String(),
      'items': parsed['items'],
      ..._portableImportMetadata(parsed),
    };

    await StremioCatalogStorage.addStremioTvLocalCatalog(catalog);
    return null;
  }
}
