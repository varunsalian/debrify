import 'dart:convert';

import '../models/home_collection.dart';
import '../models/stremio_addon.dart';
import 'collection_catalog_pager.dart';
import 'home_collections_store.dart';
import 'stremio_service.dart';
import 'watched_filter.dart';
export 'collection_catalog_pager.dart' show CatalogFetch;

/// Pages every catalog with bounded concurrency and retains per-source raw
/// cursors. Deduplication is presentation only, never proof of exhaustion.
class CollectionFolderLoader {
  CollectionFolderLoader({
    required this.folder,
    required List<StremioAddon> installedAddons,
    StremioService? stremio,
    CatalogFetch? fetch,
    bool forceRefresh = false,
    bool Function(StremioMeta)? hides,
  }) {
    final load =
        fetch ??
        ((
          StremioAddon addon,
          StremioAddonCatalog catalog, {
          int skip = 0,
          String? genre,
          void Function(int)? onRawCount,
        }) => (stremio ?? StremioService.instance).fetchCatalog(
          addon,
          catalog,
          skip: skip,
          genre: genre,
          onRawCount: onRawCount,
          forceRefresh: forceRefresh,
        ));
    final resolved = <String>{};
    for (final source in folder.sources) {
      final addon = HomeCollectionsStore.resolveAddon(source, installedAddons);
      final catalog = addon == null
          ? null
          : HomeCollectionsStore.resolveCatalog(source, addon);
      if (addon == null || catalog == null) {
        _unresolved.add(source.addonId);
        continue;
      }
      final key = jsonEncode([
        addon.manifestUrl,
        catalog.type,
        catalog.id,
        source.genre,
      ]);
      if (!resolved.add(key)) continue;
      _sources.add(
        CollectionCatalogPager(
          addon: addon,
          catalog: catalog,
          genre: source.genre,
          fetch: load,
          hides: hides ?? WatchedFilter.predicate,
        ),
      );
    }
  }
  final HomeCollectionFolder folder;
  static const int maxConcurrent = 4;
  final List<CollectionCatalogPager> _sources = [];
  final List<String> _unresolved = [];
  final Set<String> _seen = {};
  bool _stalled = false;
  bool _loading = false;
  int get resolvedSourceCount => _sources.length;
  List<String> get unresolved => List.unmodifiable(_unresolved);
  bool get exhausted => _sources.every((s) => s.exhausted);
  // A source can have an empty/overlapping window while its siblings advance.
  // Only the shared budget exhausting makes no-progress an All-view error.
  bool get hasLoadFailures =>
      _sources.any((s) => s.error != null && !s.noProgress);
  bool get hasErrors => _stalled || hasLoadFailures;

  void reset() {
    _seen.clear();
    _stalled = false;
    for (final s in _sources) {
      s.reset();
    }
  }

  Future<List<StremioMeta>> nextPage() async {
    if (_loading) return const [];
    _loading = true;
    _stalled = false;
    try {
      // Each source is tried once after failure per user/request, not once for
      // every overlap window of the remaining successful sources.
      final failed = <CollectionCatalogPager>{};
      for (
        var attempt = 0;
        attempt < CollectionCatalogPager.maxEmptyWindows;
        attempt++
      ) {
        final live = [
          for (final s in _sources)
            if (!s.exhausted && !failed.contains(s)) s,
        ];
        if (live.isEmpty) return const [];
        final pages = <List<StremioMeta>>[];
        for (var start = 0; start < live.length; start += maxConcurrent) {
          final batch = live.skip(start).take(maxConcurrent).toList();
          pages.addAll(
            await Future.wait(batch.map((s) => s.nextPage(maxWindows: 1))),
          );
          failed.addAll(batch.where((s) => s.error != null && !s.noProgress));
        }
        final fresh = [
          for (final m in interleave(pages))
            if (_seen.add(CollectionCatalogPager.itemKey(m))) m,
        ];
        if (fresh.isNotEmpty) return fresh;
        if (exhausted) return const [];
      }
      _stalled = true;
      return const [];
    } finally {
      _loading = false;
    }
  }

  static List<StremioMeta> interleave(List<List<StremioMeta>> pages) {
    final out = <StremioMeta>[];
    for (var i = 0; pages.any((p) => i < p.length); i++) {
      for (final page in pages) {
        if (i < page.length) out.add(page[i]);
      }
    }
    return out;
  }
}
