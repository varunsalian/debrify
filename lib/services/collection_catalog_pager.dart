import 'package:flutter/foundation.dart';

import '../models/stremio_addon.dart';
import 'diagnostic_log.dart';

typedef CatalogFetch =
    Future<List<StremioMeta>> Function(
      StremioAddon addon,
      StremioAddonCatalog catalog, {
      int skip,
      String? genre,
      void Function(int rawCount)? onRawCount,
    });

abstract interface class CollectionPager {
  int get skip;
  bool get exhausted;
  String? get error;
  bool get noProgress;
  void reset();
  Future<List<StremioMeta>> nextPage({int maxWindows = 8});
}

class CollectionSourcePage {
  const CollectionSourcePage({
    required this.items,
    required this.rawCount,
    required this.hasMore,
  });
  final List<StremioMeta> items;
  final int rawCount;
  final bool hasMore;
}

/// Native APIs have numbered pages and explicit end-of-list information.
/// Advance using the raw response, even when watched filtering hides a page.
class NativeCollectionPager implements CollectionPager {
  NativeCollectionPager({required this.fetch, this.hides});
  final Future<CollectionSourcePage> Function(int page) fetch;
  final bool Function(StremioMeta)? hides;
  final Set<String> _seen = {};
  int _page = 1;
  @override
  int skip = 0;
  @override
  bool exhausted = false;
  @override
  String? error;
  @override
  bool noProgress = false;

  @override
  void reset() {
    _page = 1;
    skip = 0;
    exhausted = false;
    error = null;
    noProgress = false;
    _seen.clear();
  }

  @override
  Future<List<StremioMeta>> nextPage({int maxWindows = 8}) async {
    error = null;
    noProgress = false;
    for (var i = 0; i < maxWindows && !exhausted; i++) {
      try {
        final result = await fetch(_page);
        _page++;
        skip += result.rawCount;
        exhausted = !result.hasMore;
        final fresh = [
          for (final item in result.items)
            if (_seen.add(CollectionCatalogPager.itemKey(item)) &&
                !(hides?.call(item) ?? false))
              item,
        ];
        if (fresh.isNotEmpty || exhausted) return fresh;
      } on CollectionSourceException catch (e) {
        error = e.message;
        return const [];
      } catch (failure, stack) {
        DiagnosticLog.instance.recordError(
          source: 'collections',
          event: 'native_page_failed',
          error: failure,
          stackTrace: stack,
          flushImmediately: false,
        );
        if (!kReleaseMode) {
          debugPrint(
            'Native collection failure (${failure.runtimeType}):\n$stack',
          );
        }
        error = 'This list could not load. Retry to continue.';
        return const [];
      }
    }
    if (!exhausted) {
      noProgress = true;
      error = 'This list returned no new titles. Retry to continue.';
    }
    return const [];
  }
}

class CollectionSourceException implements Exception {
  const CollectionSourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A raw catalog cursor, shared by folder rails and the merged view. A valid
/// response with no raw metas is the only proof of exhaustion. Network errors,
/// invalid metas and overlap must not silently truncate the catalog.
class CollectionCatalogPager implements CollectionPager {
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
  @override
  int skip = 0;
  @override
  bool exhausted = false;
  @override
  String? error;
  @override
  bool noProgress = false;

  static String itemKey(StremioMeta m) => '${m.type}\u0000${m.id}';

  @override
  void reset() {
    _seen.clear();
    skip = 0;
    exhausted = false;
    error = null;
    noProgress = false;
  }

  @override
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
