import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../../../models/series_source.dart';
import '../../../services/source_priority.dart';
import '../../../services/pinned_direct_stream_match.dart';
import 'source_seasons.dart';

/// Prepare a batch before it is displayed or parked as pending results.
/// Row identities remain intact for focus, saved-source and IPTV ownership.
({List<Torrent> torrents, bool cachedEpisodeInserted}) prepareSourceResults(
  List<Torrent> raw, {
  required AdvancedSearchSelection selection,
  required bool bindMode,
  required bool Function(Torrent) isIptvSource,
  required bool searching,
  required Torrent? cachedEpisodeSource,
  required List<SeriesSource> bound,
}) {
  var cachedEpisodeInserted = false;
  final sel = selection;
  // Ready-to-play addon URLs are the most useful first choice on the Sources
  // page. Keep the service's shared ranking untouched (Quick Play also uses
  // it), and invert the transport order only for this view. Explicit toolbar
  // sorts are applied later and therefore still win.
  final sourceOrdered = SourcePriority.directAddonLinksFirst(raw);
  // Series pack/bind post-processing — ported from the old Home
  // (torrent_search_screen) so this list matches. For a specific episode
  // (episode drill-down), show EVERYTHING the episode-scoped query returned
  // — engines + addon streams, torrents and direct links alike, in standard
  // merge order. No curateEpisodeCandidates here: that filter serves the
  // auto-play probe path; on this page it dropped direct links lacking an
  // S/E token in the name and floated season packs, hiding exactly the
  // per-episode sources the user drilled down for. Pack-NAMED rows the
  // episode query genuinely returned stay visible by design. Otherwise
  // (whole series/season, no episode) drop direct-link singles and apply the
  // requested season scope while retaining provider order. The Sources
  // browser does not apply an implicit relevance sort.
  List<Torrent> torrents;
  if (sel.isSeries && sel.season != null && sel.episode != null) {
    torrents = sourceOrdered;
  } else {
    torrents = filterSourceSeasonPacks(
      sourceOrdered,
      selection: sel,
      bindMode: bindMode,
      isIptvSource: isIptvSource,
    );
  }
  // Include the fallback before buffering so it counts as a pending row even
  // when the final engine response adds no other sources.
  if (!searching &&
      cachedEpisodeSource != null &&
      bound.isNotEmpty &&
      bound.first.isAddonDirect) {
    final pin = bound.first;
    final candidates =
        torrents
            .where((t) => t.isDirectStream && t.stremioAddonKey == pin.addonKey)
            .toList()
          ..sort(
            (a, b) => (a.stremioStreamIndex ?? 0).compareTo(
              b.stremioStreamIndex ?? 0,
            ),
          );
    if (matchPinnedDirectStream(
          candidates,
          streamKey: pin.streamKey ?? '',
          streamIndex: pin.streamIndex ?? 0,
          bingeGroup: pin.bingeGroup,
        ) ==
        null) {
      torrents = [cachedEpisodeSource, ...torrents];
      cachedEpisodeInserted = true;
    }
  }
  return (
    torrents: List<Torrent>.unmodifiable(torrents),
    cachedEpisodeInserted: cachedEpisodeInserted,
  );
}
