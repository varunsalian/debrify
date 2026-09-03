import '../models/home_collection.dart';
import '../models/stremio_addon.dart';
import 'home_collections_store.dart';
import 'stremio_service.dart';

/// Signature of [StremioService.fetchCatalog]; injectable for tests.
typedef CatalogFetch =
    Future<List<StremioMeta>> Function(
      StremioAddon addon,
      StremioAddonCatalog catalog, {
      int skip,
      String? genre,
      void Function(int rawCount)? onRawCount,
    });

/// Pages a folder's catalogs as one merged, de-duplicated list.
///
/// Each source keeps its own `skip` cursor; [nextPage] pulls the next window
/// from every source that still has items (bounded fan-out) and interleaves
/// them round-robin, so "Netflix movies + Netflix series + Top 10" reads as
/// a mix rather than one catalog after another. Items are de-duplicated by
/// meta id across sources (the same title routinely appears in "Popular" and
/// "Top Rated").
///
/// Fetch errors are swallowed per source: one dead addon must not blank the
/// whole folder.
class CollectionFolderLoader {
  CollectionFolderLoader({
    required this.folder,
    required List<StremioAddon> installedAddons,
    StremioService? stremio,
    CatalogFetch? fetch,
  }) : _fetch =
           fetch ??
           ((addon, catalog, {skip = 0, genre, onRawCount}) =>
               (stremio ?? StremioService.instance).fetchCatalog(
                 addon,
                 catalog,
                 skip: skip,
                 genre: genre,
                 onRawCount: onRawCount,
               )) {
    for (final source in folder.sources) {
      final addon = HomeCollectionsStore.resolveAddon(source, installedAddons);
      if (addon == null) {
        _unresolved.add(source.addonId);
        continue;
      }
      final catalog = HomeCollectionsStore.resolveCatalog(source, addon);
      if (catalog == null) {
        _unresolved.add(
          '${source.addonId} → ${source.type}/${source.catalogId}',
        );
        continue;
      }
      _sources.add(_Source(addon, catalog, source.genre));
    }
  }

  final HomeCollectionFolder folder;
  final CatalogFetch _fetch;

  final List<_Source> _sources = [];
  final List<String> _unresolved = [];
  final Set<String> _seen = {};

  /// Catalog requests in flight per page, so a many-source folder pages in a
  /// few rounds instead of hammering the addon.
  static const int maxConcurrent = 4;

  /// Sources that resolved to an installed addon and catalog.
  int get resolvedSourceCount => _sources.length;

  /// Human-readable descriptions of the sources that did not resolve.
  List<String> get unresolved => List.unmodifiable(_unresolved);

  /// True once every resolved source has run dry.
  bool get exhausted => _sources.every((s) => s.exhausted);

  /// Forget paging state so the next [nextPage] starts from the top.
  void reset() {
    _seen.clear();
    for (final s in _sources) {
      s.skip = 0;
      s.exhausted = false;
    }
  }

  /// Fetch the next window from every live source and return the merged,
  /// interleaved, de-duplicated additions. Empty means [exhausted].
  Future<List<StremioMeta>> nextPage() async {
    final live = [
      for (final s in _sources)
        if (!s.exhausted) s,
    ];
    if (live.isEmpty) return const [];

    final pages = List<List<StremioMeta>>.filled(live.length, const []);
    for (var start = 0; start < live.length; start += maxConcurrent) {
      final slice = live.sublist(
        start,
        (start + maxConcurrent).clamp(0, live.length),
      );
      await Future.wait(
        slice.indexed.map((entry) async {
          final (offset, s) = entry;
          final index = start + offset;
          try {
            var rawCount = 0;
            final items = await _fetch(
              s.addon,
              s.catalog,
              skip: s.skip,
              genre: s.genre,
              onRawCount: (c) => rawCount = c,
            );
            if (items.isEmpty) {
              s.exhausted = true;
              return;
            }
            // Advance past the addon's raw window (not the post-filter count)
            // so paging stays aligned with what the addon actually served.
            s.skip += rawCount > 0 ? rawCount : items.length;
            pages[index] = [
              for (final m in items)
                m.sourceAddon == null ? m.withSourceAddon(s.addon) : m,
            ];
          } catch (_) {
            s.exhausted = true;
          }
        }),
      );
    }

    final merged = interleave(pages);
    final fresh = <StremioMeta>[];
    for (final m in merged) {
      if (_seen.add(m.id)) fresh.add(m);
    }
    // A page that added nothing new means every source repeated itself
    // (addons that ignore `skip` do this); stop rather than loop forever.
    if (fresh.isEmpty) {
      for (final s in live) {
        s.exhausted = true;
      }
    }
    return fresh;
  }

  /// Round-robin merge: first of each list, then second of each, and so on.
  /// Lists that run out drop out of the rotation.
  static List<StremioMeta> interleave(List<List<StremioMeta>> pages) {
    final out = <StremioMeta>[];
    var index = 0;
    var any = true;
    while (any) {
      any = false;
      for (final page in pages) {
        if (index < page.length) {
          out.add(page[index]);
          any = true;
        }
      }
      index++;
    }
    return out;
  }
}

class _Source {
  _Source(this.addon, this.catalog, this.genre);
  final StremioAddon addon;
  final StremioAddonCatalog catalog;
  final String? genre;
  int skip = 0;
  bool exhausted = false;
}
