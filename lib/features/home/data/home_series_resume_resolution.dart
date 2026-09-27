import '../../../models/advanced_search_selection.dart';
import '../../../models/mdblist_continue_watching.dart';
import '../../../utils/episode_progress_merge.dart';
import '../models/home_series_resume_result.dart';

/// Reconcile already-read resume signals without owning storage or UI state.
/// The originating workflow supplies its guide lookup and retains cache/lifetime
/// ownership. Only a completed winner invokes the lookup, with the existing 4s
/// timeout and direct-successor fallback; errors continue to propagate.
Future<HomeSeriesResumeResult> resolveHomeSeriesResume({
  ({AdvancedSearchSelection sel, int? tsMs})? trakt,
  ({int season, int episode, double? progress, DateTime? pausedAt})? simkl,
  MdblistContinueWatchingItem? mdb,
  ({int season, int episode, double? pct, int? tsMs, bool finished})? local,
  EpisodeCoordinate? simklNext,
  required Future<EpisodeCoordinate?> Function(int season, int episode)
  findNextEpisode,
  void Function(
    HomeSeriesResumeCandidate winner, {
    required bool trackerFrontierAhead,
    required bool willAdvance,
  })?
  onWinner,
  void Function(
    EpisodeCoordinate from,
    EpisodeCoordinate? guide,
    EpisodeCoordinate? adjacentTracker,
    EpisodeCoordinate? target,
  )?
  onAdvance,
}) async {
  final candidates = <HomeSeriesResumeCandidate>[];
  if (trakt != null && trakt.sel.season != null && trakt.sel.episode != null) {
    candidates.add((
      sourcePriority: 0,
      // Trakt's own activity timestamp.
      timestampMs: trakt.tsMs,
      season: trakt.sel.season!,
      episode: trakt.sel.episode!,
      progress: trakt.sel.traktProgressPercent,
      finished: false,
      selection: trakt.sel,
    ));
  }
  if (simkl != null) {
    candidates.add((
      sourcePriority: 1,
      timestampMs: simkl.pausedAt?.millisecondsSinceEpoch,
      season: simkl.season,
      episode: simkl.episode,
      progress: simkl.progress,
      finished: false,
      selection: null,
    ));
  }
  final mdbSel = mdb?.selection;
  if (mdb != null &&
      mdb.paused &&
      mdbSel!.season != null &&
      mdbSel.episode != null) {
    candidates.add((
      sourcePriority: 2,
      timestampMs: mdb.updatedAt?.millisecondsSinceEpoch,
      season: mdbSel.season!,
      episode: mdbSel.episode!,
      progress: mdbSel.mdblistProgressPercent,
      // The winner's ORIGINAL selection so a launch keeps its progress
      // percent (a rebuilt coordinate would restart at the local offset).
      finished: false,
      selection: mdbSel,
    ));
  }
  if (local != null) {
    candidates.add((
      sourcePriority: 3,
      timestampMs: local.tsMs,
      season: local.season,
      episode: local.episode,
      progress: local.pct,
      finished: local.finished,
      selection: null,
    ));
  }

  HomeSeriesResumeResult result;
  if (candidates.isEmpty) {
    // Fresh device / nothing anywhere. next_to_watch matches the home card;
    // the MDBList CW coordinate is the weaker backup (same as the old tail).
    if (simklNext != null) {
      result = (
        started: true,
        season: simklNext.season,
        episode: simklNext.episode,
        simklProgress: null,
        selection: null,
        sourcePrio: null,
      );
    } else if (mdbSel?.season != null && mdbSel?.episode != null) {
      result = (
        started: true,
        season: mdbSel!.season!,
        episode: mdbSel.episode!,
        simklProgress: null,
        selection: null,
        sourcePrio: null,
      );
    } else {
      result = (
        started: false,
        season: 1,
        episode: 1,
        simklProgress: null,
        selection: null,
        sourcePrio: null,
      );
    }
  } else {
    candidates.sort((a, b) {
      final at = a.timestampMs;
      final bt = b.timestampMs;
      if (at != null && bt != null) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.sourcePriority.compareTo(b.sourcePriority);
    });
    final w = candidates.first;
    var season = w.season;
    var episode = w.episode;
    var selection = w.selection;
    var simklProgress = w.sourcePriority == 1 ? w.progress : null;
    final isTracker = w.sourcePriority <= 2;
    final sourcePrio = w.sourcePriority;
    // Advance rules. Tracker sessions at ≥80% are the orphan pattern the
    // trackers themselves treat as watched — advance. A LOCAL position at
    // ≥80% only advances when the player marked it finished OR a tracker's
    // resume/up-next frontier confirms the episode is behind it. A local-only
    // pause in the last stretch stays resumable in place.
    final trackerFrontiers = <EpisodeCoordinate>[
      for (final candidate in candidates)
        if (candidate.sourcePriority <= 2)
          (season: candidate.season, episode: candidate.episode),
      if (simklNext != null)
        (season: simklNext.season, episode: simklNext.episode),
    ];
    final trackerFrontierAhead = trackerFrontiers.any(
      (frontier) =>
          frontier.season > season ||
          (frontier.season == season && frontier.episode > episode),
    );
    final done = shouldAdvanceEpisodeResume(
      candidate: (season: season, episode: episode),
      finished: w.finished,
      progress: w.progress,
      isTracker: isTracker,
      trackerFrontiers: trackerFrontiers,
    );
    onWinner?.call(
      w,
      trackerFrontierAhead: trackerFrontierAhead,
      willAdvance: done,
    );
    if (done) {
      // 4s-boxed like every other network hop here: the guide fetch's body
      // read is otherwise unbounded, and the PLAY path has no outer box —
      // a stalled read would hang the press. Timeout → null → the defined
      // "keep the winner / adjacent tracker frontier" fallback.
      final next = await findNextEpisode(
        season,
        episode,
      ).timeout(const Duration(seconds: 4), onTimeout: () => null);
      // A tracker-frontier backup is safe ONLY when it is the winner's direct
      // successor. A frontier can be seasons ahead during a rewatch; trusting
      // that blindly when the guide flakes would teleport the rewatch.
      EpisodeCoordinate? adjacentTrackerFrontier;
      for (final frontier in trackerFrontiers) {
        final isDirectSuccessor =
            (frontier.season == season && frontier.episode == episode + 1) ||
            (frontier.season == season + 1 && frontier.episode == 1);
        if (isDirectSuccessor) {
          adjacentTrackerFrontier = frontier;
          break;
        }
      }
      final target = next ?? adjacentTrackerFrontier;
      onAdvance?.call(
        (season: w.season, episode: w.episode),
        next,
        adjacentTrackerFrontier,
        target,
      );
      if (target != null) {
        season = target.season;
        episode = target.episode;
        selection = null;
        simklProgress = null;
      }
      // Both unknown (finale / no guide): keep the winner — playing its tail
      // is still truer than inventing an episode.
    }
    result = (
      started: true,
      season: season,
      episode: episode,
      simklProgress: simklProgress,
      selection: selection,
      // The BASE winner's provider survives an advance on purpose — the
      // next episode should scrobble to the tracker that owned the resume.
      sourcePrio: sourcePrio,
    );
  }
  return result;
}
