import '../../../models/torrent.dart';

/// Sort a copy of keyword results, retaining engine order for relevance or an
/// unknown field. Comparisons intentionally have no secondary tie-breaker.
List<Torrent> sortKeywordResults(
  List<Torrent> torrents, {
  required String field,
  required bool ascending,
}) {
  final sorted = [...torrents];
  final direction = ascending ? 1 : -1;
  switch (field) {
    case 'seeders':
      sorted.sort((a, b) => direction * a.seeders.compareTo(b.seeders));
      break;
    case 'size':
      sorted.sort((a, b) => direction * a.sizeBytes.compareTo(b.sizeBytes));
      break;
    case 'date':
      sorted.sort((a, b) => direction * a.createdUnix.compareTo(b.createdUnix));
      break;
    case 'name':
      sorted.sort(
        (a, b) =>
            direction *
            a.displayTitle.toLowerCase().compareTo(
              b.displayTitle.toLowerCase(),
            ),
      );
      break;
    default:
      break;
  }
  return sorted;
}

/// Names read A–Z; seeders, size and date start highest/largest/newest first.
bool keywordSortAscendingByDefault(String field) => field == 'name';
