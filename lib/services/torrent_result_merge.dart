import '../models/torrent.dart';

/// Merge search results for both provisional and awaited result sets.
///
/// Normally deduplicates by infohash and sorts by seeders descending. With
/// [preserveSourceOrder], batches are concatenated unchanged so a Sources UI
/// can apply provider priority and stable dedupe without losing the order
/// returned by each provider.
List<Torrent> mergeTorrentResults(
  List<List<Torrent>> batches, {
  bool preserveSourceOrder = false,
}) {
  if (preserveSourceOrder) {
    return [for (final batch in batches) ...batch];
  }
  return _deduplicateAndSort(batches);
}

/// Total order used for dedupe tie-breaks and sort tie-breaks, so the merge
/// is deterministic and INDEPENDENT of batch arrival order — a streaming
/// provisional merge and the awaited (nested) final merge can never pick
/// different representatives or row orders for the same inputs.
int _mergeTieBreak(Torrent a, Torrent b) {
  final n = a.name.compareTo(b.name);
  if (n != 0) return n;
  return a.source.compareTo(b.source);
}

List<Torrent> _deduplicateAndSort(List<List<Torrent>> allResults) {
  final Map<String, Torrent> uniqueTorrents = {};

  for (final torrentList in allResults) {
    for (final torrent in torrentList) {
      // Keep the higher-seeded copy of a shared infohash; on equal seeders
      // pick deterministically (NOT first-seen — that would depend on which
      // engine happened to answer first).
      final existing = uniqueTorrents[torrent.infohash];
      if (existing == null ||
          torrent.seeders > existing.seeders ||
          (torrent.seeders == existing.seeders &&
              _mergeTieBreak(torrent, existing) < 0)) {
        uniqueTorrents[torrent.infohash] = torrent;
      }
    }
  }

  // Sort by seeders descending with a total-order tiebreak, so equal-seeder
  // runs (e.g. addon direct streams, all seeders == 0) can't reorder
  // arbitrarily between two merges of the same inputs.
  final deduplicatedResults = uniqueTorrents.values.toList();
  deduplicatedResults.sort((a, b) {
    final s = b.seeders.compareTo(a.seeders);
    if (s != 0) return s;
    final h = a.infohash.compareTo(b.infohash);
    if (h != 0) return h;
    return _mergeTieBreak(a, b);
  });

  return deduplicatedResults;
}
