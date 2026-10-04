import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';

class EpisodesPanelViewState {
  // Episode drill-down state
  int episodeModeGeneration = 0;

  StremioMeta? selectedShow;

  List<TraktSeason> episodeSeasons = [];

  int selectedSeasonNumber = 1;

  bool isLoadingEpisodes = false;

  /// True when a season fetch yielded no episodes. Instead of auto-diverting to
  /// a whole-series torrent search (which a transient network blip could
  /// trigger, yanking the user out of the drill-down), we show an inline
  /// error+Retry panel — matching old home — with an explicit "Search for
  /// sources" action that preserves the catalog pack-search path on demand.
  bool episodesUnavailable = false;

  /// Bumped when resolved episodes are PUBLISHED and on every season swap —
  /// see [EpisodesPanelView.generation] for why this is not the load
  /// generation. Only read by custom arrangements.
  int viewGeneration = 0;

  TraktEpisode? landing;

  EpisodeFocusIntent focusIntent = EpisodeFocusIntent.none;

  /// The next episode to watch for the current show. Trakt supplies the initial
  /// hint; merged local/Trakt/Simkl/MDBList progress reconciles the final badge.
  ({int season, int episode})? nextEpisode;

  /// The TRACKER's own next-unwatched coordinate, untouched by merges. The
  /// merge's output must never feed back in as the frontier: picking a
  /// partial ahead and completing it would ratchet the fed-back "frontier"
  /// past the tracker's true next, suppressing a genuine session there.
  ({int season, int episode})? trackerNextRaw;
}
