import '../../../models/torrent.dart';
import '../models/keyword_providers.dart';

export '../models/keyword_providers.dart';

/// Source tabs and provider groups must agree on the empty-source bucket.
String keywordSourceOf(Torrent torrent) =>
    torrent.source.isNotEmpty ? torrent.source : 'unknown';

bool isDirectKeywordResult(Torrent torrent) =>
    torrent.isDirectStream || torrent.isExternalStream;

/// New providers start selected, while providers unticked by the user stay
/// unticked across streaming batches. A vanished provider is forgotten so it
/// starts selected if deduplication later reintroduces it.
KeywordProviders reconcileKeywordProviders(
  List<Torrent> torrents, {
  required Set<String> selectedDirect,
  required Set<String> selectedTorrent,
  required Set<String> seen,
}) {
  final direct = <String, int>{};
  final torrent = <String, int>{};
  for (final item in torrents) {
    final source = keywordSourceOf(item);
    final bucket = isDirectKeywordResult(item) ? direct : torrent;
    bucket[source] = (bucket[source] ?? 0) + 1;
  }
  final nextDirect = {...selectedDirect};
  final nextTorrent = {...selectedTorrent};
  final nextSeen = {...seen};
  for (final source in direct.keys) {
    if (nextSeen.add('d:$source')) nextDirect.add(source);
  }
  for (final source in torrent.keys) {
    if (nextSeen.add('t:$source')) nextTorrent.add(source);
  }
  nextDirect.removeWhere((source) => !direct.containsKey(source));
  nextTorrent.removeWhere((source) => !torrent.containsKey(source));
  nextSeen.removeWhere(
    (key) => key.startsWith('d:')
        ? !direct.containsKey(key.substring(2))
        : !torrent.containsKey(key.substring(2)),
  );
  return KeywordProviders(
    directCounts: direct,
    torrentCounts: torrent,
    selectedDirect: nextDirect,
    selectedTorrent: nextTorrent,
    seen: nextSeen,
  );
}
