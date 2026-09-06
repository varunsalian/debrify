import '../models/stremio_addon.dart';

typedef CatalogFetch =
    Future<List<StremioMeta>> Function(
      StremioAddon addon,
      StremioAddonCatalog catalog, {
      int skip,
      String? genre,
      void Function(int rawCount)? onRawCount,
    });

/// A raw catalog cursor, shared by folder rails and the merged view. A valid
/// response with no raw metas is the only proof of exhaustion. Network errors,
/// invalid metas and overlap must not silently truncate the catalog.
class CollectionCatalogPager {
  CollectionCatalogPager({
    required this.addon,
    required this.catalog,
    required this.fetch,
    this.genre,
    this.hides,
  });
  static const int maxEmptyWindows = 8;
  final StremioAddon addon;
  final StremioAddonCatalog catalog;
  final CatalogFetch fetch;
  final String? genre;
  final bool Function(StremioMeta)? hides;
  final Set<String> _seen = {};
  int skip = 0;
  bool exhausted = false;
  String? error;
  bool noProgress = false;

  static String itemKey(StremioMeta m) => '${m.type}\u0000${m.id}';

  void reset() {
    _seen.clear();
    skip = 0;
    exhausted = false;
    error = null;
    noProgress = false;
  }

  Future<List<StremioMeta>> nextPage({int maxWindows = maxEmptyWindows}) async {
    error = null;
    noProgress = false;
    if (exhausted) return const [];
    for (var attempt = 0; attempt < maxWindows; attempt++) {
      int? rawCount;
      try {
        final items = await fetch(
          addon,
          catalog,
          skip: skip,
          genre: genre,
          onRawCount: (count) => rawCount = count,
        );
        // StremioService returns [] without reporting a count on HTTP failure.
        if (items.isEmpty && rawCount == null) {
          error = 'This list could not load. Retry to continue.';
          return const [];
        }
        final count = rawCount ?? items.length;
        if (count == 0) {
          exhausted = true;
          return const [];
        }
        skip += count;
        final fresh = [
          for (final m in items)
            if (_seen.add(itemKey(m)) && !(hides?.call(m) ?? false))
              m.sourceAddon == null ? m.withSourceAddon(addon) : m,
        ];
        if (fresh.isNotEmpty) return fresh;
      } catch (_) {
        error = 'This list could not load. Retry to continue.';
        return const [];
      }
    }
    // Bound faulty addons that ignore skip. The cursor remains resumable.
    noProgress = true;
    error = 'This list returned no new titles. Retry to continue.';
    return const [];
  }
}
