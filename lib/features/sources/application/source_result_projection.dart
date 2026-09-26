import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import '../../../services/source_priority.dart';
import '../../../utils/torrent_filter_matcher.dart';

/// Project Sources rows in toolbar order without changing the input or row
/// identities. Filtering precedes provider-priority deduplication; explicit
/// field sorting takes precedence over provider order.
List<Torrent> projectSourceResults(
  List<Torrent> src, {
  required String? sourceFilter,
  required Map<String, String> sourceAliases,
  required bool isSeries,
  required TorrentFilterState filters,
  required List<String> sourcePriority,
  required String sortBy,
  required bool sortAsc,
}) {
  var list = src;
  if (sourceFilter != null) {
    list = list
        .where(
          (t) =>
              SourcePriority.keyForSource(t.source, aliases: sourceAliases) ==
              sourceFilter,
        )
        .toList();
  }
  // Size buckets are meaningless for series: addon packs report a single
  // episode's size, so a size filter would match against a misleading
  // number. Drop the facet before matching when browsing a series.
  final effectiveFilters = isSeries
      ? filters.copyWith(sizes: const <SizeBucket>{})
      : filters;
  list = TorrentFilterMatcher.apply(list, effectiveFilters);
  list = SourcePriority.orderAndDedupe(
    list,
    sourcePriority,
    aliases: sourceAliases,
  );
  if (sortBy != 'source') {
    list = List<Torrent>.from(list);
    int cmp(Torrent a, Torrent b) {
      switch (sortBy) {
        case 'name':
          return a.displayTitle.toLowerCase().compareTo(
            b.displayTitle.toLowerCase(),
          );
        case 'size':
          return a.sizeBytes.compareTo(b.sizeBytes);
        case 'seeders':
          return a.seeders.compareTo(b.seeders);
        case 'date':
          return a.createdUnix.compareTo(b.createdUnix);
        default:
          return 0;
      }
    }

    list.sort((a, b) => sortAsc ? cmp(a, b) : cmp(b, a));
  }
  return List<Torrent>.unmodifiable(list);
}
