/// Chooses the start offset for a native-player IPTV zap page.
///
/// Anchored pages keep the selected channel near the middle where possible.
/// Explicit offsets may point at the final item because they are used for
/// forward/backward page requests, while [fromEnd] always returns a full final
/// page when the catalog is larger than [limit].
int iptvPlayerZapPageOffset({
  required int total,
  required int limit,
  int requestedOffset = 0,
  int? anchorIndex,
  bool fromEnd = false,
}) {
  if (total <= 0) return 0;

  final safeLimit = limit.clamp(1, 1 << 30);
  final lastFullPage = (total - safeLimit).clamp(0, 1 << 30);
  if (fromEnd) return lastFullPage;
  if (anchorIndex != null) {
    return (anchorIndex - safeLimit ~/ 2).clamp(0, lastFullPage);
  }
  return requestedOffset.clamp(0, total - 1);
}

/// The category [attempt] steps away from [current] in [delta]'s direction,
/// wrapping past either end of [categories].
///
/// Zapping past the last channel of a category lands in the next one; past the
/// last channel of the last category it wraps to the first. Attempts beyond one
/// exist to skip categories that come back empty, so the walk is bounded by the
/// number of distinct categories — asking for more returns null rather than
/// circling forever.
String? iptvAdjacentZapCategory({
  required List<String> categories,
  required String? current,
  required int delta,
  int attempt = 1,
}) {
  if (current == null || delta == 0) return null;
  final unique = <String>[];
  for (final category in categories) {
    if (category.isNotEmpty && !unique.contains(category)) unique.add(category);
  }
  if (unique.isEmpty || attempt < 1 || attempt > unique.length) return null;
  // A category that isn't in the list (a stale or renamed group) still has to
  // lead somewhere, so treat it as sitting at the front.
  var index = unique.indexOf(current);
  if (index < 0) index = 0;
  final step = delta > 0 ? attempt : -attempt;
  return unique[(index + step + unique.length * 2) % unique.length];
}

/// A loaded window of channels and where it starts in the catalog.
class IptvZapWindow<T> {
  final List<T> channels;
  final int offset;

  const IptvZapWindow({required this.channels, required this.offset});
}

/// Splices [page] into [window] by absolute catalog position, growing the
/// window rather than replacing it.
///
/// Returns null when the two don't touch: with a gap between them the merged
/// list would claim positions it doesn't hold, and every later paging and
/// category-boundary decision is read off those positions. Where they overlap,
/// the page wins — it is the fresher copy.
IptvZapWindow<T>? iptvMergeZapWindow<T>({
  required List<T> window,
  required int windowOffset,
  required List<T> page,
  required int pageOffset,
}) {
  if (page.isEmpty) return null;
  if (window.isEmpty) {
    return IptvZapWindow(channels: List<T>.from(page), offset: pageOffset);
  }
  final windowEnd = windowOffset + window.length;
  final pageEnd = pageOffset + page.length;
  if (pageOffset > windowEnd || pageEnd < windowOffset) return null;

  final start = windowOffset < pageOffset ? windowOffset : pageOffset;
  final end = windowEnd > pageEnd ? windowEnd : pageEnd;
  return IptvZapWindow(
    channels: [
      for (var absolute = start; absolute < end; absolute++)
        (absolute >= pageOffset && absolute < pageEnd)
            ? page[absolute - pageOffset]
            : window[absolute - windowOffset],
    ],
    offset: start,
  );
}
