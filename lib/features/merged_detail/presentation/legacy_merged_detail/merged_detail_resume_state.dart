import 'package:debrify/utils/episode_progress_merge.dart';

class MergedDetailResumeState {
  /// One playback launch at a time for the whole merged page. Every visual
  /// theme delegates its primary action here, and the hosted episode panel is
  /// wrapped by the same gate below. The modal resolving route usually absorbs
  /// a second tap, but it is presentation rather than synchronization: two OK
  /// events can otherwise enter the async resume/source resolution together.
  bool playLaunching = false;

  /// Primary-button resume state. Until loaded the button keeps its static
  /// label; once resolved it reads "Start Watching" (no progress) or "Resume"
  /// (+ an "S3E4" tag for series). Re-read when the player pops back.
  bool resumeLoaded = false;
  bool resumeStarted = false;
  int? resumeSeason;
  int? resumeEpisode;
  bool hasMergedEpisodeTarget = false;

  /// A resume lookup is in flight and no answer has landed yet (from the
  /// loader OR the mounted episode engine). The primary button shows a
  /// spinner instead of a label so it never flashes "Start Watching" before
  /// flipping to "Resume · S1E7". Errors clear it (static label fallback).
  bool resumePending = false;

  /// Engine emission received BEFORE the loader settled the pill — held back
  /// so the label can't strobe through intermediate merge states; consumed
  /// (or discarded) by [_loadResumeInfo]'s settle arbitration.
  EpisodeResumeTarget? pendingEngineTarget;

  /// The loader is genuinely running right now. Engine emissions stash ONLY
  /// during this window — inferring it from _resumeLoaded left two holes: a
  /// FAILED loader stranded later emissions in the stash forever, and a
  /// not-started settle discarded a later started target (order-dependent
  /// "merged progress beats Start Watching").
  bool resumeLoaderInFlight = false;

  bool seriesDone = false;
  bool rewatchPending = false;
}
