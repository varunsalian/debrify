import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter/material.dart';

class MergedDetailResumeActions {
  final MergedDetailDependencies _deps;
  MergedDetailResumeActions(this._deps);
  bool get _isMovie => _deps.isMovie();
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailResumeState get _r => _deps.parts.resumeState;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;

  bool get primaryBusy => _r.resumePending && !_r.resumeLoaded;

  Future<void> loadResumeInfo() async {
    final loader = _deps.resumeInfoLoader();
    if (loader == null) return;
    debugPrint(
      '[SeriesResume] detail-loader-start title="${_item.name}" '
      'id=${_item.effectiveImdbId ?? _item.id} '
      'routeTarget=S${_deps.initialSeason()}E${_deps.initialEpisode()} '
      'loaded=${_r.resumeLoaded} mergedTarget=${_r.hasMergedEpisodeTarget}',
    );
    // setState, not a plain assignment: this runs post-frame (initState
    // schedules it via addPostFrameCallback), and the spinner must actually
    // be scheduled to paint — a bare write only showed it when a sibling
    // loader happened to rebuild.
    if (!_r.resumeLoaded && mounted) {
      setState(() => _r.resumePending = true);
    }
    _r.resumeLoaderInFlight = true;
    try {
      // Time-boxed: the reconciler boxes its tracker fetches but the guide
      // advance can hang on an unbounded body read — and with engine
      // emissions now stashed pre-settle, a hung loader would spin the pill
      // forever. A timeout throws into the catch/finally path, which applies
      // the stashed engine target.
      final info = await loader().timeout(const Duration(seconds: 12));
      if (!mounted) return;
      debugPrint(
        '[SeriesResume] detail-loader-answer title="${_item.name}" '
        'started=${info.started} season=${info.season} episode=${info.episode} '
        'engineAlreadyMerged=${_r.hasMergedEpisodeTarget} '
        'stashedEngine=${_r.pendingEngineTarget == null ? 'none' : 'S${_r.pendingEngineTarget!.season}E${_r.pendingEngineTarget!.episode}/started=${_r.pendingEngineTarget!.started}'}',
      );
      // Once the mounted episode engine has resolved all tracker/local
      // progress, its coordinate is newer and richer than the host loader's
      // cached Continue Watching snapshot. Do not let a slower stale loader
      // overwrite (for example) E7 back to a completed E6. (Pre-settle the
      // engine only stashes, so this guard fires solely on post-settle
      // re-reads — e.g. didPopNext after playback.)
      if (!_isMovie && _r.hasMergedEpisodeTarget) {
        debugPrint(
          '[SeriesResume] detail-loader-discarded title="${_item.name}" '
          'reason=engine-already-authoritative',
        );
        return;
      }
      // Settle arbitration, deterministic where the old code was
      // last-writer-wins. The reconciled loader wins whenever it found a
      // resume: it reads the same trackers + local the engine merges, PLUS
      // recency and the watched frontier — and it is what Play executes, so
      // preferring it keeps the pill and the button provably in lock-step
      // (the engine is frontier-aware but recency-blind: it would call a
      // fresh rewatch "S5" while Play resumes the rewatched episode). The
      // stashed engine target only settles the pill when the loader came
      // back empty-handed — merged in-page progress beats "Start Watching".
      final stash = _r.pendingEngineTarget;
      _r.pendingEngineTarget = null;
      if (!_isMovie && !info.started && stash != null && stash.started) {
        debugPrint(
          '[SeriesResume] detail-loader-arbitration title="${_item.name}" '
          'winner=engine target=S${stash.season}E${stash.episode} '
          'reason=loader-unstarted',
        );
        applyEngineTarget(stash);
        return;
      }
      debugPrint(
        '[SeriesResume] detail-loader-arbitration title="${_item.name}" '
        'winner=loader target=S${info.season}E${info.episode} '
        'engineCandidate=${stash == null ? 'none' : 'S${stash.season}E${stash.episode}/started=${stash.started}'}',
      );
      setState(() {
        _r.resumeLoaded = true;
        _r.resumeStarted = info.started;
        _r.resumeSeason = info.season;
        _r.resumeEpisode = info.episode;
      });
    } catch (error, stackTrace) {
      // Non-critical — leave the static label.
      debugPrint(
        '[SeriesResume] detail-loader-failed title="${_item.name}" '
        'error=$error\n$stackTrace',
      );
    } finally {
      _r.resumeLoaderInFlight = false;
      if (_r.resumePending) {
        if (mounted) {
          setState(() => _r.resumePending = false);
        } else {
          _r.resumePending = false;
        }
      }
      // Loader failed (or bailed) without settling: the stashed engine
      // target is better than a pill stuck on the static label. Emissions
      // arriving after this point direct-write (legacy) — the in-flight
      // window is closed, so nothing can strand in the stash.
      if (mounted && !_r.resumeLoaded) {
        final fallback = _r.pendingEngineTarget;
        _r.pendingEngineTarget = null;
        if (fallback != null) applyEngineTarget(fallback);
      }
    }
  }

  void onNextEpisodeChanged(EpisodeResumeTarget next, {bool mutation = false}) {
    if (!mounted || _isMovie) return;
    debugPrint(
      '[SeriesResume] detail-engine-emission title="${_item.name}" '
      'target=S${next.season}E${next.episode} started=${next.started} '
      'mutation=$mutation loaderInFlight=${_r.resumeLoaderInFlight} '
      'labelLoaded=${_r.resumeLoaded} current=S${_r.resumeSeason}E${_r.resumeEpisode} '
      'currentStarted=${_r.resumeStarted}',
    );
    // While the loader is IN FLIGHT: stash, never write. The episodes engine
    // re-emits as each tracker fetch lands, and letting every emission write
    // the pill strobed it through wrong states ("Start Watching" → S2E8 →
    // S1E7) and killed the busy spinner. The loader's reconciled answer
    // settles the pill exactly ONCE, arbitrating against this stash. A
    // failed/absent loader closes the window, so emissions never strand.
    // Mutations are deliberate single user actions, not strobe — they write
    // through even mid-loader (stashing dropped their tag and let a stale
    // settle discard them); the applied target arms the loader guard, so a
    // later-settling loader cannot overwrite the user's mark.
    if (_r.resumeLoaderInFlight && !_r.resumeLoaded && !mutation) {
      _r.pendingEngineTarget = next;
      debugPrint(
        '[SeriesResume] detail-engine-stashed title="${_item.name}" '
        'target=S${next.season}E${next.episode}',
      );
      return;
    }
    // Settled STARTED: the loader is authoritative (it is literally what
    // Play executes) — only explicit in-page MUTATIONS (mark watched/
    // unwatched) move the pill; a slower engine initial-merge landing after
    // settle must not late-flip it (the loader-vs-engine finish order is a
    // network race). A settle that found NO resume is different: a later
    // started engine target upgrades it — "merged progress beats Start
    // Watching" must not depend on which fetch finished first.
    if (_r.resumeLoaded &&
        _r.resumeStarted &&
        !mutation &&
        _deps.resumeInfoLoader() != null) {
      debugPrint(
        '[SeriesResume] detail-engine-discarded title="${_item.name}" '
        'target=S${next.season}E${next.episode} '
        'reason=started-loader-authoritative',
      );
      return;
    }
    if (_r.resumeLoaded &&
        _r.resumeStarted == next.started &&
        _r.resumeSeason == next.season &&
        _r.resumeEpisode == next.episode) {
      return;
    }
    applyEngineTarget(next);
  }

  /// Write an engine target into the pill state (the legacy
  /// [_onNextEpisodeChanged] body): merged playback progress outranks the
  /// host's snapshot, so a started target also arms the loader-overwrite
  /// guard.
  void applyEngineTarget(EpisodeResumeTarget next) {
    debugPrint(
      '[SeriesResume] detail-engine-applied title="${_item.name}" '
      'target=S${next.season}E${next.episode} started=${next.started}',
    );
    setState(() {
      // A coordinate alone is not resume evidence: an untouched show also
      // resolves to its first episode. Only merged playback progress outranks
      // the host's independently loaded Continue Watching snapshot.
      _r.hasMergedEpisodeTarget = next.started;
      _r.resumeLoaded = true;
      _r.resumeStarted = next.started;
      _r.resumeSeason = next.season;
      _r.resumeEpisode = next.episode;
    });
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static Play/Resume label until the resume state resolves.
  String get primaryLabel =>
      _deps.onRewatch() == null && resolvedPrimaryLabel == 'Rewatch'
      ? 'Play'
      : resolvedPrimaryLabel;

  String get resolvedPrimaryLabel {
    if (_r.rewatchPending || (!_isMovie && _r.seriesDone)) return 'Rewatch';
    // Completion is available independently of the optional resume loader.
    // Keep the rewatch affordance visible for movie routes that omit one.
    if (!_r.resumeLoaded) {
      if (_isMovie && _k.localMovieFinished) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Resume';
    }
    if (!_r.resumeStarted) {
      // A movie already finished on Simkl (status `completed`) has no resume
      // session; its Play un-marks it watched so the rewatch re-enters
      // Continue Watching — surface that intent as "Rewatch".
      if (_isMovie && _k.localMovieFinished) {
        return 'Rewatch';
      }
      return _isMovie ? 'Play' : 'Start Watching';
    }
    if (_isMovie || _r.resumeSeason == null || _r.resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_r.resumeSeason}E${_r.resumeEpisode}';
  }
}
