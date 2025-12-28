import '../torrent.dart';
import '../torbox_file.dart';
import '../debrify_tv_cache.dart';
import '../../utils/series_parser.dart';

/// Result of checking a window of torrents for Torbox cache availability.
///
/// Contains the list of cached torrents, the cursor for the next batch,
/// and whether the search has been exhausted.
class TorboxCacheWindowResult {
  final List<Torrent> cachedTorrents;
  final int nextCursor;
  final bool exhausted;

  const TorboxCacheWindowResult({
    required this.cachedTorrents,
    required this.nextCursor,
    required this.exhausted,
  });
}

/// Represents a playable file entry from a Torbox torrent.
///
/// Contains the file metadata, display title, and series information
/// parsed from the filename.
class TorboxPlayableEntry {
  final TorboxFile file;
  final String title;
  final SeriesInfo info;

  TorboxPlayableEntry({
    required this.file,
    required this.title,
    required this.info,
  });
}

/// Result of warming a single keyword search.
///
/// Contains the keyword, infohashes that were added to the cache,
/// statistics about the search, and an optional failure message.
class KeywordWarmResult {
  final String keyword;
  final Set<String> addedHashes;
  final KeywordStat stat;
  final String? failureMessage;

  const KeywordWarmResult({
    required this.keyword,
    required this.addedHashes,
    required this.stat,
    this.failureMessage,
  });
}
