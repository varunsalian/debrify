import '../models/stremio_addon.dart';

/// Fetches one raw window of a paged catalog starting at `skip`. The addon's
/// RAW item count (before anything was dropped upstream) must be reported
/// through [onRawCount] so `skip` can advance in step with the addon's own
/// paging.
typedef PageFetch =
    Future<List<StremioMeta>> Function(
      int skip,
      void Function(int rawCount) onRawCount,
    );

/// The result of [fetchFilteredPage].
class FilteredPage {
  /// Surviving items in addon order, de-duplicated against `seenIds`.
  final List<StremioMeta> items;

  /// Where the next page starts: the sum of the raw windows consumed.
  final int nextSkip;

  /// True only when the addon served a RAW-empty window, i.e. the catalog is
  /// genuinely at its end. A window that was entirely filtered away is not
  /// exhaustion.
  final bool exhausted;

  /// Number of windows pulled. Tests only.
  final int fetches;

  const FilteredPage({
    required this.items,
    required this.nextSkip,
    required this.exhausted,
    required this.fetches,
  });
}

/// Fetch from [skip], drop items [hides] rejects, and keep pulling windows
/// until at least [minItems] survive, the addon serves a raw-empty window, or
/// [maxFetches] windows were consumed.
///
/// With [hides] null this is exactly one fetch, so surfaces that don't filter
/// behave as before. With a predicate, a page that happened to be all watched
/// no longer looks like an empty catalog: [FilteredPage.exhausted] is defined
/// by the addon running dry, never by the filter. [seenIds], when given,
/// collects every id encountered — filtered or not — so the caller's
/// de-duplication and paging stay aligned across calls.
Future<FilteredPage> fetchFilteredPage(
  PageFetch fetch, {
  required int skip,
  bool Function(StremioMeta item)? hides,
  int minItems = 12,
  int maxFetches = 4,
  Set<String>? seenIds,
}) async {
  var cursor = skip;
  var fetches = 0;
  var exhausted = false;
  final out = <StremioMeta>[];
  while (true) {
    var rawCount = 0;
    final page = await fetch(cursor, (c) => rawCount = c);
    fetches++;
    if (page.isEmpty) {
      exhausted = true;
      break;
    }
    // Raw window, not the post-filter count: keeps skip aligned with what
    // the addon actually served.
    cursor += rawCount > 0 ? rawCount : page.length;
    for (final m in page) {
      if (seenIds != null && !seenIds.add(m.id)) continue;
      if (hides != null && hides(m)) continue;
      out.add(m);
    }
    if (hides == null) break;
    if (out.length >= minItems || fetches >= maxFetches) break;
  }
  return FilteredPage(
    items: out,
    nextSkip: cursor,
    exhausted: exhausted,
    fetches: fetches,
  );
}
