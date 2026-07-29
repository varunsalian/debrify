import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_catalog_db.dart';

/// A `List<IptvChannel>` facade over one filtered view of a [CatalogSnapshot].
///
/// This is what lets the results view go query-driven without rewriting every
/// consumer: `_allChannels` / `_filteredChannels` keep their `List` type,
/// `.length` is a cached SQL COUNT, and `[index]` faults in a fixed-size page
/// (sub-millisecond synchronous read) held in a small LRU. Only the rows near
/// the viewport are ever materialized — RAM no longer scales with catalog
/// size.
///
/// Instance semantics: a cached page returns the SAME [IptvChannel] instances
/// on every access, so `ObjectKey(channel)` and the identity-keyed focus-node
/// map behave exactly as they do for a plain list. An evicted-and-refaulted
/// page mints new instances — [onEvicted] lets the owner retire the old
/// instances' focus nodes.
///
/// Iterating the whole facade works (it pages), and the favorites-URL
/// reconcile relies on that — but treat full iteration as a deliberate,
/// yielding walk, never something to do per frame.
class DbChannelList extends ListBase<IptvChannel> {
  DbChannelList(
    this.snapshot, {
    this.group,
    this.search,
    this.onPageLoaded,
    this.onEvicted,
    this.instanceCache,
  }) : _length = snapshot.count(group: group, search: search);

  static const int pageSize = 60;

  /// ~16 resident pages ≈ under a thousand live channel objects, regardless
  /// of whether the catalog has 5k or 500k rows.
  static const int maxResidentPages = 16;

  /// Cap on the shared cross-facade instance cache (see [instanceCache]).
  /// Only needs to cover what's on screen across a filter recompute, plus
  /// margin — a few pages. Bounds memory to a few hundred channel objects no
  /// matter the catalog size.
  static const int maxCachedInstances = 300;

  final CatalogSnapshot snapshot;
  final String? group;
  final String? search;

  /// Shared across every facade the view builds for one catalog generation
  /// (unfiltered, and each filter/search recompute), keyed by catalog
  /// position. Reusing the same [IptvChannel] instance for a given position
  /// across recomputes keeps its ObjectKey stable, so a row that survives a
  /// filter change is NOT torn down and rebuilt (no EPG re-resolve, no focus
  /// node / image churn) — the cost that made search feel laggy on a big
  /// catalog. Positions are unique within a generation, so distinct rows
  /// never collide (duplicate-URL rows keep distinct instances). Null = no
  /// caching (fresh instances every fault).
  final LinkedHashMap<int, IptvChannel>? instanceCache;

  /// Fired (synchronously, during a fault) with each freshly loaded page —
  /// the view uses it to kick off the async progress-bar lookup for those
  /// URLs. Do NOT setState inside; schedule instead.
  final void Function(List<IptvChannel> page)? onPageLoaded;

  /// Fired with the instances of an evicted page so their focus nodes can be
  /// retired (skip any that are attached or focused).
  final void Function(List<IptvChannel> evicted)? onEvicted;

  final int _length;

  /// Insertion-ordered so the eldest entry is the LRU victim; touched pages
  /// are re-inserted on access.
  final LinkedHashMap<int, List<IptvChannel>> _pages = LinkedHashMap();
  final HashMap<IptvChannel, int> _indexOfInstance = HashMap.identity();

  /// Kept alive by rows whose page got evicted while they were still built —
  /// see the fallback in [operator []].
  static final IptvChannel _missingRow = IptvChannel(name: '…', url: '');

  @override
  int get length => _length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('DbChannelList is read-only');

  @override
  void operator []=(int index, IptvChannel value) =>
      throw UnsupportedError('DbChannelList is read-only');

  @override
  IptvChannel operator [](int index) {
    final pageIndex = index ~/ pageSize;
    var page = _pages.remove(pageIndex);
    if (page == null) {
      final entries = _effective.pageEntries(
        offset: pageIndex * pageSize,
        limit: pageSize,
        group: group,
        search: search,
      );
      final cache = instanceCache;
      page = [
        for (final e in entries)
          if (cache == null) e.channel else _cachedInstance(cache, e),
      ];
      for (var i = 0; i < page.length; i++) {
        _indexOfInstance[page[i]] = pageIndex * pageSize + i;
      }
      onPageLoaded?.call(page);
      while (_pages.length >= maxResidentPages) {
        final evicted = _pages.remove(_pages.keys.first)!;
        for (final channel in evicted) {
          _indexOfInstance.remove(channel);
        }
        onEvicted?.call(evicted);
      }
    }
    _pages[pageIndex] = page; // (re-)insert = most recently used
    final offsetInPage = index - pageIndex * pageSize;
    if (offsetInPage >= page.length) {
      // Only reachable if this snapshot's generation was finally swept while
      // the view somehow never re-pinned (two refreshes without a present) —
      // render a placeholder row instead of throwing mid-build.
      debugPrint(
        'DbChannelList: page ${pageIndex} short '
        '(${page.length} rows, wanted #$offsetInPage) — stale generation?',
      );
      return _missingRow;
    }
    return page[offsetInPage];
  }

  /// Reuse the cached instance for this catalog position, or cache the fresh
  /// one. LRU: a hit moves to the most-recent end; overflow evicts the
  /// eldest. Within one generation a position always maps to identical row
  /// data, so a hit is always safe to reuse.
  static IptvChannel _cachedInstance(
    LinkedHashMap<int, IptvChannel> cache,
    ({int position, IptvChannel channel}) entry,
  ) {
    final hit = cache.remove(entry.position);
    if (hit != null) {
      cache[entry.position] = hit; // touch
      return hit;
    }
    cache[entry.position] = entry.channel;
    while (cache.length > maxCachedInstances) {
      cache.remove(cache.keys.first);
    }
    return entry.channel;
  }

  /// The filtered index of a currently-resident instance, or null if its
  /// page has been evicted (or it never came from this facade).
  int? indexOfInstance(IptvChannel channel) => _indexOfInstance[channel];

  /// O(1) identity check against resident instances — shadows ListBase's
  /// full-iteration contains, which would page through the entire catalog.
  @override
  bool contains(Object? element) =>
      element is IptvChannel && _indexOfInstance.containsKey(element);

  /// Adopt a newer snapshot whose content digest is IDENTICAL to this one's:
  /// the resident pages stay valid verbatim (same data ⇒ same rows), so the
  /// grid keeps its instances, focus and scroll with zero rebuilds — only
  /// the generation pin moves forward.
  void repin(CatalogSnapshot fresh) {
    assert(fresh.contentDigest == snapshot.contentDigest,
        'repin is only sound for identical content');
    _repinned = fresh;
  }

  CatalogSnapshot? _repinned;

  /// The snapshot new page faults should read from.
  CatalogSnapshot get _effective => _repinned ?? snapshot;

  /// Same as [_effective], for callers that need to run their own queries
  /// against this facade's current generation (e.g. the player-launch
  /// window).
  CatalogSnapshot get effectiveSnapshot => _effective;

  /// Every instance currently resident in the page cache — the rows that can
  /// be on screen right now.
  List<IptvChannel> residentChannels() =>
      [for (final page in _pages.values) ...page];
}
