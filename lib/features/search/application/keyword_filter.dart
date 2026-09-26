import '../../../models/torrent.dart';
import '../../../models/torrent_filter_state.dart';
import '../../../utils/torrent_filter_matcher.dart';
import 'keyword_providers.dart';

/// Match the cache badge's key exactly: lowercase, without trimming. Hashless
/// torrent download links are retained because they cannot be cache-checked.
bool isKeywordTorboxCached(Torrent torrent, Map<String, List<String>> cache) {
  if (!torrent.hasRealInfoHash && torrent.torrentUrl != null) return true;
  final labels = cache[torrent.infohash.toLowerCase()];
  return labels != null && labels.contains('TB');
}

/// Filter in existing priority order without modifying the input or taking
/// ownership of focus, cache checks, source settings or user selections.
List<Torrent> filterKeywordResults(
  List<Torrent> torrents, {
  required bool cachedOnly,
  required Map<String, List<String>> cache,
  required Map<String, int> directCounts,
  required Map<String, int> torrentCounts,
  required Set<String> selectedDirect,
  required Set<String> selectedTorrent,
  required String? sourceTab,
  required TorrentFilterState filters,
}) {
  Iterable<Torrent> base = torrents;
  if (cachedOnly) {
    base = base.where((torrent) => isKeywordTorboxCached(torrent, cache));
  }
  if (directCounts.isNotEmpty || torrentCounts.isNotEmpty) {
    base = base.where((torrent) {
      final source = keywordSourceOf(torrent);
      if (isDirectKeywordResult(torrent)) {
        return directCounts.isEmpty || selectedDirect.contains(source);
      }
      return torrentCounts.isEmpty || selectedTorrent.contains(source);
    });
  }
  if (sourceTab != null) {
    base = base.where((torrent) => keywordSourceOf(torrent) == sourceTab);
  }
  return TorrentFilterMatcher.apply(base.toList(), filters);
}
