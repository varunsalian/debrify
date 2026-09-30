import '../models/home_catalog_search_status.dart';
import 'home_continuation_section.dart';
import 'home_continuation_playback.dart';
import 'home_continuation_removal.dart';
import 'home_stage_rows.dart';

typedef HomeContinuationProjectionDeps = ({
  Set<String> Function() disabled,
  void Function(String) openLocal,
  void Function(String) openTrakt,
  void Function(String) openSimkl,
  void Function(String) openMdblist,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() traktAuthenticated,
});

/// Live row-family composition and visibility, including the Trakt loading slot.
class HomeContinuationProjection {
  HomeContinuationProjection(
    this._deps,
    this._section,
    this._playback,
    this._removal,
    this._catalog,
  );
  final HomeContinuationProjectionDeps _deps;
  final HomeContinuationSection _section;
  final HomeContinuationPlayback _playback;
  final HomeContinuationRemoval _removal;
  final HomeCatalogSearchStatus _catalog;

  /// The leading Continue Watching rows to render, in order: local Movies /
  /// Series (when enabled), then Trakt Movies / Shows (when connected). Only
  /// non-empty groups are included. Each row carries its own progress lookup
  /// and open / quick-play handlers so local and Trakt sources coexist.
  List<HomeContinuationRow> get cwRows => [
    ...buildHomeContinuationFamily(
      movieId: 'cw:movies',
      seriesId: 'cw:series',
      title: 'Continue Watching',
      seriesTag: 'Series',
      kind: HomeContinuationKind.local,
      enabled: _section.cwEnabled,
      merged: _section.cwMergeLocal,
      disabled: _deps.disabled(),
      movieItems: _section.cwMergeLocal ? _section.cwAll : _section.cwMovies,
      seriesItems: _section.cwSeries,
      movieNodes: _section.cwMovieNodes,
      seriesNodes: _section.cwSeriesNodes,
      progress: (m) => _section.cwCardProgress(HomeContinuationKind.local, m),
      episode: (m) => _section.cwCardEpisode(HomeContinuationKind.local, m),
      remaining: (m) =>
          _section.cwCardRemainingMinutes(HomeContinuationKind.local, m),
      artwork: (m) => _section.cwEpisodeArtwork[m.imdbId],
      onOpen: _playback.openContinueItem,
      onQuickPlay: _playback.onContinuePlay,
      onRemove: _removal.removeLocalCwItem,
      movieSeeAll: () =>
          _deps.openLocal(_section.cwMergeLocal ? 'all' : 'movie'),
      seriesSeeAll: () => _deps.openLocal('series'),
    ),
    ...buildHomeContinuationFamily(
      movieId: 'trakt:movies',
      seriesId: 'trakt:shows',
      title: 'Trakt Continue Watching',
      seriesTag: 'Shows',
      kind: HomeContinuationKind.trakt,
      enabled: true,
      merged: _section.cwMergeTrakt,
      disabled: _deps.disabled(),
      movieItems: _section.cwMergeTrakt
          ? _section.traktAll
          : _section.traktMovies,
      seriesItems: _section.traktSeries,
      movieNodes: _section.traktMovieNodes,
      seriesNodes: _section.traktSeriesNodes,
      progress: (m) => _section.cwCardProgress(HomeContinuationKind.trakt, m),
      episode: (m) => _section.cwCardEpisode(HomeContinuationKind.trakt, m),
      remaining: (m) =>
          _section.cwCardRemainingMinutes(HomeContinuationKind.trakt, m),
      artwork: (m) => _section.traktEpisodeArtwork[m.imdbId],
      onOpen: _playback.openTraktItem,
      onQuickPlay: _playback.playTraktItem,
      onRemove: _removal.removeTraktCwItem,
      movieSeeAll: () =>
          _deps.openTrakt(_section.cwMergeTrakt ? 'all' : 'movie'),
      seriesSeeAll: () => _deps.openTrakt('series'),
    ),
    ...buildHomeContinuationFamily(
      movieId: 'simkl:movies',
      seriesId: 'simkl:shows',
      title: 'Simkl Continue Watching',
      seriesTag: 'Shows',
      kind: HomeContinuationKind.simkl,
      enabled: true,
      merged: _section.cwMergeSimkl,
      disabled: _deps.disabled(),
      movieItems: _section.cwMergeSimkl
          ? _section.simklAll
          : _section.simklMovies,
      seriesItems: _section.simklSeries,
      movieNodes: _section.simklMovieNodes,
      seriesNodes: _section.simklSeriesNodes,
      progress: (m) => _section.cwCardProgress(HomeContinuationKind.simkl, m),
      episode: (m) => _section.cwCardEpisode(HomeContinuationKind.simkl, m),
      remaining: (m) =>
          _section.cwCardRemainingMinutes(HomeContinuationKind.simkl, m),
      artwork: (m) => _section.simklEpisodeArtwork[m.progressId],
      onOpen: _playback.openSimklCwItem,
      onQuickPlay: _playback.playSimklCwItem,
      onRemove: _removal.removeSimklCwItem,
      movieSeeAll: () =>
          _deps.openSimkl(_section.cwMergeSimkl ? 'all' : 'movie'),
      seriesSeeAll: () => _deps.openSimkl('series'),
    ),
    ...buildHomeContinuationFamily(
      movieId: 'mdblist:movies',
      seriesId: 'mdblist:shows',
      title: 'MDBList Continue Watching',
      seriesTag: 'Shows',
      kind: HomeContinuationKind.mdblist,
      enabled: true,
      merged: _section.cwMergeMdblist,
      disabled: _deps.disabled(),
      movieItems: _section.cwMergeMdblist
          ? _section.mdblistAll
          : _section.mdblistMovies,
      seriesItems: _section.mdblistSeries,
      movieNodes: _section.mdblistMovieNodes,
      seriesNodes: _section.mdblistSeriesNodes,
      progress: (m) => _section.cwCardProgress(HomeContinuationKind.mdblist, m),
      episode: (m) => _section.cwCardEpisode(HomeContinuationKind.mdblist, m),
      remaining: (m) =>
          _section.cwCardRemainingMinutes(HomeContinuationKind.mdblist, m),
      artwork: (m) => null,
      onOpen: _playback.openMdblistCwItem,
      onQuickPlay: _playback.playMdblistCwItem,
      onRemove: _removal.removeMdblistCwItem,
      canRemove: _removal.canRemoveMdblistCwItem,
      movieSeeAll: () =>
          _deps.openMdblist(_section.cwMergeMdblist ? 'all' : 'movie'),
      seriesSeeAll: () => _deps.openMdblist('series'),
    ),
    ...buildHomeContinuationFamily(
      movieId: 'iptv:movies',
      seriesId: 'iptv:series',
      title: 'IPTV Continue Watching',
      seriesTag: 'Series',
      kind: HomeContinuationKind.iptv,
      enabled: true,
      merged: false,
      disabled: _deps.disabled(),
      movieItems: _section.iptvCwMovies,
      seriesItems: _section.iptvCwSeries,
      movieNodes: _section.iptvCwMovieNodes,
      seriesNodes: _section.iptvCwSeriesNodes,
      progress: (m) => _section.iptvCwProgress[m.id],
      episode: (m) => _section.iptvCwEpisode[m.id],
      remaining: (m) => _section.iptvRemainingMinutes(m.id),
      artwork: (m) => _section.iptvCwByKey[m.id]?.posterUrl,
      onOpen: _playback.openIptvCwItem,
      onQuickPlay: _playback.openIptvCwItem,
      onRemove: _removal.removeIptvCwItem,
    ),
  ];

  /// Whether any Continue Watching row is currently on-screen (drives focus
  /// wiring between it and the first catalog row). Uses allocation-free field
  /// checks (not `cwRows`) since it's read on the per-card build hot path —
  /// keep these conditions in lock-step with the `cwRows` row gates above.
  bool get cwVisible =>
      ((_section.cwEnabled &&
              (((_section.cwMergeLocal ? _section.cwAll : _section.cwMovies)
                          .isNotEmpty &&
                      !_deps.disabled().contains('cw:movies')) ||
                  (!_section.cwMergeLocal &&
                      _section.cwSeries.isNotEmpty &&
                      !_deps.disabled().contains('cw:series')))) ||
          ((_section.cwMergeTrakt ? _section.traktAll : _section.traktMovies)
                  .isNotEmpty &&
              !_deps.disabled().contains('trakt:movies')) ||
          (!_section.cwMergeTrakt &&
              _section.traktSeries.isNotEmpty &&
              !_deps.disabled().contains('trakt:shows')) ||
          ((_section.cwMergeSimkl ? _section.simklAll : _section.simklMovies)
                  .isNotEmpty &&
              !_deps.disabled().contains('simkl:movies')) ||
          (!_section.cwMergeSimkl &&
              _section.simklSeries.isNotEmpty &&
              !_deps.disabled().contains('simkl:shows')) ||
          ((_section.cwMergeMdblist
                      ? _section.mdblistAll
                      : _section.mdblistMovies)
                  .isNotEmpty &&
              !_deps.disabled().contains('mdblist:movies')) ||
          (!_section.cwMergeMdblist &&
              _section.mdblistSeries.isNotEmpty &&
              !_deps.disabled().contains('mdblist:shows')) ||
          (_section.iptvCwMovies.isNotEmpty &&
              !_deps.disabled().contains('iptv:movies')) ||
          (_section.iptvCwSeries.isNotEmpty &&
              !_deps.disabled().contains('iptv:series'))) &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;

  /// Whether the Trakt rows should be held open with skeleton placeholders: the
  /// account is connected, its (slow, network) Continue Watching fetch is in
  /// flight, and there are no real Trakt rows on-screen yet. Reserving the slot
  /// keeps the row count stable so the real rows fill in place — nothing below
  /// reflows, and the auto-focus anchor stays put.
  ///
  /// Shown on every platform (the placeholder header omits the phone/desktop
  /// See-All link, which pops in harmlessly when the real row loads). Only on
  /// the homepage board (not the dedicated Search / Discover tabs, and not while
  /// a catalog search is showing its own results). Requiring the real rows to be
  /// empty means a refresh that already has data updates in place — no skeletons
  /// stacked on top of live rows.
  bool get traktReserving =>
      !_deps.searchMode() &&
      !_deps.discoverMode() &&
      _deps.traktAuthenticated() &&
      traktCwLoading &&
      _section.traktMovies.isEmpty &&
      _section.traktSeries.isEmpty &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;

  /// Whether a Trakt Continue Watching fetch is currently in flight for a
  /// connected account. While true — and there are no real Trakt rows to show
  /// yet — the Trakt slot is held open with skeleton placeholders (see
  /// [traktReserving]) so the real rows fill in place instead of inserting
  /// mid-board and shoving everything below them down. Set at the start of each
  /// load and cleared on every terminal path, so a mid-session connect (which
  /// re-runs the load) reserves the slot again.
  bool get traktCwLoading =>
      _section.traktContinuationController.current.loading;
}
