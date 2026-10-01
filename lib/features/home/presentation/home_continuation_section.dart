import 'package:flutter/material.dart';

import '../../../models/custom_series_identity.dart';
import '../../../models/iptv_cw_entry.dart';
import '../../../models/mdblist_continue_watching.dart';
import '../../../models/simkl_continue_watching_item.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/tracking_source.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../application/home_continuation_layout_controller.dart';
import '../application/home_episode_artwork_controller.dart';
import '../application/home_iptv_continuation_controller.dart';
import '../application/home_local_continuation_controller.dart';
import '../application/home_mdblist_continuation_controller.dart';
import '../application/home_simkl_continuation_controller.dart';
import '../application/home_trakt_continuation_controller.dart';
import '../models/home_episode_artwork.dart';
import '../models/home_iptv_continuation_state.dart';
import '../models/home_local_continuation_state.dart';
import '../models/home_mdblist_continuation.dart';
import '../models/home_simkl_continuation.dart';
import '../models/home_trakt_continuation.dart';
import 'home_continuation_bindings.dart';
import 'home_continuation_nodes.dart';
import 'home_stage_rows.dart';

typedef HomeContinuationDeps = ({
  HomeContinuationBindings Function() bindings,
  HomeEpisodeArtworkController Function() artwork,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

/// Route-owned continuation focus pools and live projections of provider state.
class HomeContinuationSection {
  HomeContinuationSection(this._deps);
  final HomeContinuationDeps _deps;

  // LOCAL Continue Watching rows. Reads the SAME local store Home writes to
  // (StorageService `continue_watching_v1`) — read-only here, so Home is never
  // affected. Split into two recency-ordered rows (Movies, then Series), each
  // shown as a leading board row when non-empty. Removal happens only from the
  // detail screen's action.
  HomeLocalContinuationController get localContinuationController =>
      _deps.bindings().local;
  HomeLocalContinuationState get localContinuation =>
      localContinuationController.current;
  bool get cwEnabled => localContinuation.enabled;
  List<StremioMeta> get cwMovies => localContinuation.movies;
  List<StremioMeta> get cwSeries => localContinuation.series;
  List<StremioMeta> get cwAll => localContinuation.data.items;
  Map<String, double> get cwProgress => _deps.bindings().localProgress;
  Map<String, String> get cwEpisode => localContinuation.data.episode;
  Map<String, int> get cwRemainingMinutes =>
      localContinuation.data.remainingMinutes;
  Set<String> get cwIds => localContinuation.data.ids;
  Map<String, String?> get cwAddonId => localContinuation.data.addonIds;
  Map<String, String> get cwEpisodeArtwork =>
      episodeArtworkController.current[HomeEpisodeArtworkSource.local] ??
      const {};

  final continuationNodes = HomeContinuationNodes();
  List<FocusNode> get cwMovieNodes =>
      continuationNodes.movies(HomeContinuationKind.local);
  List<FocusNode> get cwSeriesNodes =>
      continuationNodes.series(HomeContinuationKind.local);

  // Per-provider "one Continue Watching row" preferences. When a provider is
  // merged, its MOVIES slot carries the combined recency-ordered list (the
  // same `_xxxAll` the See-All grid uses) on the movies node list, and its
  // Series row is suppressed — so row ids, saved Home order, and the
  // hide-rows page keep working off the existing `<provider>:movies` id.
  // Loaded once before the first node sync (each CW loader awaits
  // [ensureCwMergeFlags]); [_reloadForHomeSettings] re-reads and re-syncs
  // node counts when a toggle changes.
  HomeContinuationLayoutController get continuationLayoutController =>
      _deps.bindings().layout;
  bool get cwMergeLocal => continuationLayoutController.current.local;
  bool get cwMergeTrakt => continuationLayoutController.current.trakt;
  bool get cwMergeSimkl => continuationLayoutController.current.simkl;
  bool get cwMergeMdblist => continuationLayoutController.current.mdblist;

  Future<void> ensureCwMergeFlags() => continuationLayoutController
      .ensureLoaded(isCurrent: () => _deps.mounted());

  // IPTV Continue Watching (Xtream VOD movies + series), sourced from the
  // player's own watch history via [IptvCwRouter] — kept separate from the
  // metadata-addon rows above because IPTV items aren't IMDb-keyed, so their
  // progress/episode lookups and routing key off the router's routeKey (stored
  // as the synthetic meta id) instead of an imdbId.
  HomeIptvContinuationController get iptvContinuationController =>
      _deps.bindings().iptv;
  HomeIptvContinuationState get iptvContinuation =>
      iptvContinuationController.current;
  List<StremioMeta> get iptvCwMovies => iptvContinuation.movies;
  List<StremioMeta> get iptvCwSeries => iptvContinuation.series;
  Map<String, double> get iptvCwProgress => iptvContinuation.progress;
  Map<String, String> get iptvCwEpisode => iptvContinuation.episode;
  Map<String, IptvCwEntry> get iptvCwByKey => iptvContinuation.byKey;
  List<FocusNode> get iptvCwMovieNodes =>
      continuationNodes.movies(HomeContinuationKind.iptv);
  List<FocusNode> get iptvCwSeriesNodes =>
      continuationNodes.series(HomeContinuationKind.iptv);

  // TRAKT Continue Watching rows ("Trakt Movies" / "Trakt Shows"), fetched live
  // from the Trakt account (no local store). Shown after the local rows when
  // connected + non-empty. Network-loaded on init / integration change,
  // post-playback, and throttled app resume, then cached in memory.
  HomeTraktContinuationController get traktContinuationController =>
      _deps.bindings().trakt;
  HomeTraktContinuation get traktContinuation =>
      traktContinuationController.current.data;
  List<StremioMeta> get traktMovies => traktContinuation.movies;
  List<StremioMeta> get traktSeries => traktContinuation.series;
  List<StremioMeta> get traktAll => traktContinuation.all;
  Map<String, double> get traktProgress => _deps.bindings().traktProgress;
  Map<String, String> get traktEpisode => traktContinuation.episode;
  Map<String, int> get traktRemainingMinutes =>
      traktContinuation.remainingMinutes;
  Map<String, TraktContinueWatchingItem> get traktByImdb =>
      traktContinuation.byImdb;
  Map<String, String> get traktEpisodeArtwork =>
      episodeArtworkController.current[HomeEpisodeArtworkSource.trakt] ??
      const {};
  List<FocusNode> get traktMovieNodes =>
      continuationNodes.movies(HomeContinuationKind.trakt);
  List<FocusNode> get traktSeriesNodes =>
      continuationNodes.series(HomeContinuationKind.trakt);

  // SIMKL Continue Watching rows ("Simkl Movies" / "Simkl Shows") — a parallel
  // strip below the Trakt rows, built from the account's paused playback
  // sessions (same `/sync/playback` lists the scrobble resume already fetches).
  // Independent of the Trakt block above so neither can regress the other.
  HomeSimklContinuationController get simklContinuationController =>
      _deps.bindings().simkl;
  HomeSimklContinuation get simklContinuation =>
      simklContinuationController.current;
  List<StremioMeta> get simklMovies => simklContinuation.movies;
  List<StremioMeta> get simklSeries => simklContinuation.series;
  List<StremioMeta> get simklAll => simklContinuation.all;
  Map<String, double> get simklProgress => _deps.bindings().simklProgress;
  Map<String, String> get simklEpisode => simklContinuation.episode;
  Map<String, SimklContinueWatchingItem> get simklByImdb =>
      simklContinuation.byImdb;
  Map<String, String> get simklEpisodeArtwork =>
      episodeArtworkController.current[HomeEpisodeArtworkSource.simkl] ??
      const {};

  List<FocusNode> get simklMovieNodes =>
      continuationNodes.movies(HomeContinuationKind.simkl);
  List<FocusNode> get simklSeriesNodes =>
      continuationNodes.series(HomeContinuationKind.simkl);
  HomeMdblistContinuationController get mdblistContinuationController =>
      _deps.bindings().mdblist;
  HomeMdblistContinuation get mdblistContinuation =>
      mdblistContinuationController.current;
  List<StremioMeta> get mdblistMovies => mdblistContinuation.movies;
  List<StremioMeta> get mdblistSeries => mdblistContinuation.series;
  List<StremioMeta> get mdblistAll => mdblistContinuation.all;
  Map<String, double> get mdblistProgress => _deps.bindings().mdblistProgress;
  Map<String, String> get mdblistEpisode => mdblistContinuation.episode;
  Map<String, MdblistContinueWatchingItem> get mdblistByImdb =>
      mdblistContinuation.byImdb;
  List<FocusNode> get mdblistMovieNodes =>
      continuationNodes.movies(HomeContinuationKind.mdblist);
  List<FocusNode> get mdblistSeriesNodes =>
      continuationNodes.series(HomeContinuationKind.mdblist);

  /// The Progress source, mirrored for the CW card lookups below. Smart until
  /// the first load resolves it (Smart = every row keeps its own numbers,
  /// which is also the pre-Tracking behaviour).
  WatchProgressSource get cwProgressSource => localContinuation.progressSource;

  /// Continue Watching cards show the title from whichever row owns it, but
  /// the PROGRESS comes from the selected Progress source — so a card can
  /// never advertise a resume point the detail page and Play button refuse to
  /// honour. In Smart mode each row keeps its own numbers (legacy behaviour);
  /// in a dedicated mode a title the chosen source doesn't know simply renders
  /// as a plain poster. IPTV rows are exempt: they are routeKey-keyed player
  /// history that no tracker can describe.
  String? simklCardKey(StremioMeta item) => HomeSimklContinuation.cardKey(item);

  String? cwCardKey(HomeContinuationKind kind, StremioMeta item) =>
      cwProgressSource == WatchProgressSource.simkl ||
          (cwProgressSource == WatchProgressSource.smart &&
              kind == HomeContinuationKind.simkl)
      ? simklCardKey(item)
      : item.progressId;

  double? cwCardProgress(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId)
      ? cwProgress[item.imdbId]
      : cwCardMaps(kind).progress[cwCardKey(kind, item)];

  String? cwCardEpisode(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId)
      ? cwEpisode[item.imdbId]
      : cwCardMaps(kind).episode[cwCardKey(kind, item)];

  int? cwCardRemainingMinutes(HomeContinuationKind kind, StremioMeta item) =>
      CustomSeriesIdentity.isCustom(item.imdbId)
      ? cwRemainingMinutes[item.imdbId]
      : cwCardMaps(kind).remaining?[item.progressId];

  ({
    Map<String, double> progress,
    Map<String, String> episode,
    Map<String, int>? remaining,
  })
  cwCardMaps(HomeContinuationKind kind) {
    final effective = kind == HomeContinuationKind.iptv
        ? kind
        : switch (cwProgressSource) {
            WatchProgressSource.smart => kind,
            WatchProgressSource.local => HomeContinuationKind.local,
            WatchProgressSource.trakt => HomeContinuationKind.trakt,
            WatchProgressSource.simkl => HomeContinuationKind.simkl,
            WatchProgressSource.mdblist => HomeContinuationKind.mdblist,
          };
    return switch (effective) {
      HomeContinuationKind.local => (
        progress: cwProgress,
        episode: cwEpisode,
        remaining: cwRemainingMinutes,
      ),
      HomeContinuationKind.trakt => (
        progress: traktProgress,
        episode: traktEpisode,
        remaining: traktRemainingMinutes,
      ),
      HomeContinuationKind.simkl => (
        progress: simklProgress,
        episode: simklEpisode,
        remaining: null,
      ),
      HomeContinuationKind.mdblist => (
        progress: mdblistProgress,
        episode: mdblistEpisode,
        remaining: null,
      ),
      HomeContinuationKind.iptv => (
        progress: iptvCwProgress,
        episode: iptvCwEpisode,
        remaining: null,
      ),
    };
  }

  int? iptvRemainingMinutes(String routeKey) =>
      iptvContinuation.remainingMinutes[routeKey];

  HomeEpisodeArtworkController get episodeArtworkController => _deps.artwork();

  Future<void> enrichCwEpisodeArtwork({
    required Map<String, HomeEpisodeReference> refs,
    required HomeEpisodeArtworkSource source,
    required bool Function() isCurrent,
  }) => episodeArtworkController.load(
    source: source,
    refs: refs,
    isCurrent: () => _deps.mounted() && isCurrent(),
    onChanged: () => _deps.setState(() {}),
  );
}
