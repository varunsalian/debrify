import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter/foundation.dart';

/// The episode drill-down engine + UI, extracted out of `EpisodesScreen` so it
/// can be hosted both as a standalone route (the existing `EpisodesScreen`
/// wrapper) and inline inside the merged series page — without forking the
/// season-fetch / landing / playback-selection logic.
///
/// This widget is **navigation-agnostic**: it never pushes or pops routes.
/// Terminal actions (episode picked / quick-play / fallback-to-search) build an
/// [AdvancedSearchSelection] and, just before dispatching it, call
/// [onBeforeTerminalDispatch] so the host can tear its route stack down to
/// wherever the result should land. The back affordance calls [onBack].
/// What a custom arrangement should move focus to when the view generation
/// changes. Mirrors what Classic does implicitly.
enum EpisodeFocusIntent {
  /// Nothing should move (a rebuild that isn't a data change).
  none,

  /// A fresh load or deep link resolved — reveal and focus [EpisodesPanelView.landing].
  landing,

  /// The user stepped the season; their attention is on the stepper, so the
  /// layout re-focuses its own season control. Classic does the same thing by
  /// re-requesting `_episodeSeasonDropdownFocusNode`.
  seasonControl,
}

/// Everything a custom episode arrangement needs, so alternate layouts can be
/// drawn without forking the engine (season loading, the Trakt/Simkl watch
/// merge, enrichment, playback dispatch and the options sheet all stay here).
///
/// Handed to [EpisodesPanel.contentBuilder]. Layouts own their own FocusNodes —
/// they must NOT reach for the engine's, which are disposed and rebuilt on
/// every season change.
class EpisodesPanelView {
  final List<TraktSeason> seasons;
  final int selectedSeasonNumber;

  /// Episodes of the selected season. Empty while loading or on failure.
  final List<TraktEpisode> episodes;
  final bool loading;
  final bool unavailable;

  /// Poster fallback for episodes with no still of their own.
  final String? showImageUrl;

  /// Bumped when resolved episodes are PUBLISHED and on every season swap.
  ///
  /// Deliberately not the engine's internal load generation, which bumps when a
  /// load *starts* (and guards enrichment) — a layout first built during
  /// loading would then never see it change when the data actually landed.
  final int generation;

  /// The episode the engine resolved to land on — an explicit deep link, else
  /// Trakt next-up, else local last-played, else the season's first. Validated
  /// as a pair: a stored episode number is only honoured when its season is the
  /// season that was actually selected. Null while loading / when empty.
  final TraktEpisode? landing;

  final EpisodeFocusIntent focusIntent;

  /// 0..100, or null when the episode has no progress.
  final double? Function(TraktEpisode) progressOf;
  final bool Function(TraktEpisode) isNext;
  final void Function(TraktEpisode) play;
  final void Function(TraktEpisode) options;
  final void Function(int delta) stepSeason;
  final void Function(int seasonNumber) selectSeason;
  final void Function(int seasonNumber)? seasonOptions;

  /// Host's stable LEFT-crossing target, when it supplied one.
  final VoidCallback? onLeftEdge;

  /// Failure terminals. [onSearchForSources] is null when the host gave no
  /// `onItemSelected` — direct-source shows have no torrent-search fallback.
  final VoidCallback onRetry;
  final VoidCallback? onSearchForSources;

  const EpisodesPanelView({
    required this.seasons,
    required this.selectedSeasonNumber,
    required this.episodes,
    required this.loading,
    required this.unavailable,
    required this.showImageUrl,
    required this.generation,
    required this.landing,
    required this.focusIntent,
    required this.progressOf,
    required this.isNext,
    required this.play,
    required this.options,
    required this.stepSeason,
    required this.selectSeason,
    this.seasonOptions,
    required this.onLeftEdge,
    required this.onRetry,
    required this.onSearchForSources,
  });
}
