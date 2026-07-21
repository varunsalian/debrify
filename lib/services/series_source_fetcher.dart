import '../models/torrent.dart';

/// One search for a series-source category ("season/series packs" or
/// "individual episodes"), targeting a concrete [season]/[episode]. Returns
/// the curated, ordered results, or null when the search itself failed
/// (transient network etc.).
typedef SeriesSourceSearch = Future<List<Torrent>?> Function(
  int season,
  int episode,
);

/// On-demand fetcher for the in-player series source tabs.
///
/// A series play reaches the player with only ONE category of torrent sources
/// loaded: a bound/pinned source (nothing searched), the pack-first search
/// (packs only) or the episode fallback search (episode results only). This
/// object carries what was already fetched and how to fetch the missing
/// category later — the player's "Load more sources" action.
///
/// Deliberately player-agnostic: it holds no channel/UI code, so the Flutter
/// player's sources sheet can reuse it as-is. The search closures are built by
/// [TorrentPlaybackService.seriesFetcherFor], which reuses the exact search +
/// curation + filter-ladder chains the Quick Play flow runs.
class SeriesSourceFetcher {
  SeriesSourceFetcher({
    required SeriesSourceSearch searchPacks,
    required SeriesSourceSearch searchEpisodes,
    required this.season,
    required this.episode,
    this.packsFetched = false,
    this.episodesFetched = false,
  })  : _searchPacks = searchPacks,
        _searchEpisodes = searchEpisodes;

  static const String modePacks = 'packs';
  static const String modeEpisodes = 'episodes';

  final SeriesSourceSearch _searchPacks;
  final SeriesSourceSearch _searchEpisodes;

  /// The LAUNCH episode — the fallback search target when the caller doesn't
  /// say what is currently playing. A season-pack playlist can auto-advance
  /// episodes inside one player session, so callers should pass the current
  /// position to [fetch] whenever they know it.
  final int season;
  final int episode;

  /// Whether the dedicated search for each tab has already run (either before
  /// launch or via a successful [fetch]). While false, the player offers
  /// "Load more sources" on that tab.
  bool packsFetched;
  bool episodesFetched;

  /// Runs the search for [mode], targeting [season]/[episode] when given
  /// (the player's CURRENT position) and the launch episode otherwise.
  /// Returns the fetched (curated, ordered) list — possibly empty — or null
  /// when the search failed. The fetched flag flips only on success, so a
  /// failed fetch keeps "Load more" available to retry.
  Future<List<Torrent>?> fetch(String mode, {int? season, int? episode}) async {
    if (mode != modePacks && mode != modeEpisodes) return null;
    final s = season ?? this.season;
    final e = episode ?? this.episode;
    final result = await (mode == modePacks
        ? _searchPacks(s, e)
        : _searchEpisodes(s, e));
    if (result == null) return null;
    if (mode == modePacks) {
      packsFetched = true;
    } else {
      episodesFetched = true;
    }
    return result;
  }

  /// Appends [fetched] onto [existing], skipping duplicates. APPEND-ONLY by
  /// design: the players couple a source to its list index (switch requests
  /// travel as a bare index), so existing entries must keep their positions.
  static List<Torrent> mergeSources(
    List<Torrent> existing,
    List<Torrent> fetched,
  ) {
    final seen = existing.map(sourceKey).toSet();
    final merged = List<Torrent>.from(existing);
    for (final t in fetched) {
      if (seen.add(sourceKey(t))) merged.add(t);
    }
    return merged;
  }

  /// Dedupe identity: infohash for torrents, URL for direct streams.
  static String sourceKey(Torrent t) {
    if (t.infohash.isNotEmpty) return 'ih:${t.infohash.toLowerCase()}';
    final url = t.directUrl;
    if (url != null && url.isNotEmpty) return 'url:$url';
    return 'name:${t.name}';
  }
}
