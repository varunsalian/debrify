import '../../../models/series_source.dart';
import '../../../models/torrent.dart';

/// Matches a row to its first saved binding without storage or UI dependencies.
class SourceBindingMatcher {
  const SourceBindingMatcher({
    required this.mediaServerKeyFor,
    required this.isIptv,
  });

  final String? Function(Torrent) mediaServerKeyFor;
  final bool Function(Torrent) isIptv;

  SeriesSource? match(List<SeriesSource> saved, Torrent torrent) {
    for (final source in saved) {
      if (source.isMediaServer &&
          mediaServerKeyFor(torrent) == source.bindingKey) {
        return source;
      }
      if (isIptv(torrent) &&
          source.isIptvDirect &&
          source.iptvPlaylistId == torrent.iptvPlaylistId &&
          source.iptvCatalogType == torrent.iptvCatalogType &&
          source.iptvEntryKey == torrent.iptvEntryKey) {
        return source;
      }
      if (torrent.isDirectStream &&
          source.matchesAddonDirect(
            candidateAddonKey: torrent.stremioAddonKey,
            candidateStreamKey: torrent.stremioStreamKey,
            candidateBingeGroup: torrent.stremioBingeGroup,
          )) {
        return source;
      }
      if (torrent.streamType == StreamType.torrent &&
          source.torrentHash.isNotEmpty &&
          source.torrentHash == torrent.infohash) {
        return source;
      }
    }
    return null;
  }
}
