import '../models/torrent.dart';

/// One search for a series-source category ("season/series packs" or
/// "individual episodes"), targeting a concrete [season]/[episode]. Returns
/// the curated, ordered results, or null when the search itself failed
/// (transient network etc.).
typedef SeriesSourceSearch =
    Future<List<Torrent>?> Function(int season, int episode);

/// One search for a movie's full source list (no episode targeting).
typedef MovieSourceSearch = Future<List<Torrent>?> Function();

/// The applicable Stremio addons for this play — every one the sheets should
/// show as a group, zero-result ones included.
typedef AddonListing = Future<List<SourceAddonRef>> Function();

/// Enabled torrent engines applicable to this play, including engines whose
/// last search returned no rows.
typedef EngineListing = Future<List<SourceEngineRef>> Function();

/// A targeted fetch for one torrent engine. Null means the engine failed;
/// empty means it completed successfully with no results.
typedef EngineSourceSearch =
    Future<List<Torrent>?> Function(String engineId, int season, int episode);

/// One addon's episode-scoped fetch (movies ignore season/episode). Null =
/// the fetch itself failed; empty = the addon genuinely has nothing.
typedef AddonEpisodeSearch =
    Future<List<Torrent>?> Function(String addonId, int season, int episode);

/// One addon's season-pack probe — the lazy follow-up run only after its
/// episode results contained torrent magnets.
typedef AddonPackSearch =
    Future<List<Torrent>?> Function(String addonId, int season);

/// An applicable addon, as the sheets' rail needs it.
class SourceAddonRef {
  final String id;
  final String name;
  const SourceAddonRef(this.id, this.name);

  /// Matches `Torrent.source` for this addon's converted results — the
  /// sheets' group id, so a placeholder group and the addon's fetched rows
  /// land in the same bucket.
  String get sourceKey => 'stremio:$name'.toLowerCase();
}

class SourceEngineRef {
  final String id;
  final String name;
  final String sourceKey;
  const SourceEngineRef(this.id, this.name, this.sourceKey);
}

/// On-demand fetcher for the in-player "Load more sources" action.
///
/// A bound/pinned play reaches the player with only what was already resolved:
/// a series play carries one category of torrent sources (bound source:
/// nothing searched, pack-first: packs only, episode fallback: episodes only)
/// and a bound movie play carries just the single pinned torrent. This object
/// carries what was already fetched and how to fetch the rest later.
///
/// Deliberately player-agnostic: it holds no channel/UI code, so the Flutter
/// player's sources sheet can reuse it as-is. The search closures are built by
/// `TorrentPlaybackService.seriesFetcherFor` / `movieFetcherFor`, which reuse
/// the exact search + curation + filter-ladder chains the Quick Play flow runs.
class SeriesSourceFetcher {
  /// Series flavor: pack/episode tabs, each independently fetchable.
  SeriesSourceFetcher({
    required SeriesSourceSearch searchPacks,
    required SeriesSourceSearch searchEpisodes,
    required this.season,
    required this.episode,
    this.packsFetched = false,
    this.episodesFetched = false,
    this.listAddons,
    this.listEngines,
    this.fetchAddonEpisodes,
    this.fetchAddonPacks,
    this.fetchEngine,
  }) : _searchPacks = searchPacks,
       _searchEpisodes = searchEpisodes,
       _searchMovie = null,
       movieFetched = true;

  /// Movie flavor: one flat list, one "Load more" (the normal movie search).
  SeriesSourceFetcher.movie({
    required MovieSourceSearch searchMovie,
    this.movieFetched = false,
    this.listAddons,
    this.listEngines,
    this.fetchAddonEpisodes,
    this.fetchEngine,
  }) : _searchMovie = searchMovie,
       _searchPacks = null,
       _searchEpisodes = null,
       fetchAddonPacks = null,
       season = 0,
       episode = 0,
       packsFetched = true,
       episodesFetched = true;

  /// Per-addon fetch, for the sheets' all-addons rail: every applicable
  /// addon shows as a group even with zero results, and an empty/failed
  /// group offers "Fetch results" — episode-scoped first (direct links show
  /// instantly), then the lazy pack probe when magnets appeared. All three
  /// are optional; older launch sites simply don't get the affordance.
  final AddonListing? listAddons;
  final EngineListing? listEngines;
  final AddonEpisodeSearch? fetchAddonEpisodes;
  final AddonPackSearch? fetchAddonPacks;
  final EngineSourceSearch? fetchEngine;

  static const String modePacks = 'packs';
  static const String modeEpisodes = 'episodes';
  static const String modeMovie = 'movie';

  final SeriesSourceSearch? _searchPacks;
  final SeriesSourceSearch? _searchEpisodes;
  final MovieSourceSearch? _searchMovie;

  /// Whether this is the movie flavor (flat list, [modeMovie] only).
  bool get isMovie => _searchMovie != null;

  /// The LAUNCH episode — the fallback search target when the caller doesn't
  /// say what is currently playing. A season-pack playlist can auto-advance
  /// episodes inside one player session, so callers should pass the current
  /// position to [fetch] whenever they know it. Unused (0) for movies.
  final int season;
  final int episode;

  /// Whether the dedicated search for each mode has already run (either
  /// before launch or via a successful [fetch]). While false, the player
  /// offers "Load more sources" for it. The flavors pre-mark each other's
  /// modes fetched so only their own buttons ever show.
  bool packsFetched;
  bool episodesFetched;
  bool movieFetched;

  /// Runs the search for [mode] — for series modes targeting
  /// [season]/[episode] when given (the player's CURRENT position) and the
  /// launch episode otherwise. Returns the fetched (curated, ordered) list —
  /// possibly empty — or null when the search failed or [mode] doesn't apply
  /// to this flavor. The fetched flag flips only on success, so a failed
  /// fetch keeps "Load more" available to retry.
  Future<List<Torrent>?> fetch(String mode, {int? season, int? episode}) async {
    final s = season ?? this.season;
    final e = episode ?? this.episode;
    final List<Torrent>? result;
    switch (mode) {
      case modePacks:
        result = await _searchPacks?.call(s, e);
        break;
      case modeEpisodes:
        result = await _searchEpisodes?.call(s, e);
        break;
      case modeMovie:
        result = await _searchMovie?.call();
        break;
      default:
        return null;
    }
    if (result == null) return null;
    if (mode == modePacks) {
      packsFetched = true;
    } else if (mode == modeEpisodes) {
      episodesFetched = true;
    } else {
      movieFetched = true;
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
