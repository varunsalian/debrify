import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/widgets/detail/detail_primary_sources.dart';
import 'package:debrify/widgets/rewatch_progress_dialog.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class MergedDetailPlaybackActions {
  final MergedDetailDependencies _deps;
  MergedDetailPlaybackActions(this._deps);
  List<TraktMenuOption> get _appMenuOptions => _deps.appMenuOptions();
  bool get _isMovie => _deps.isMovie();
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailResumeActions get _ra => _deps.parts.resumeActions;
  MergedDetailResumeState get _r => _deps.parts.resumeState;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;

  Future<void> guardPlay(Future<void> Function() launch) async {
    if (_r.playLaunching || !mounted) return;
    // Rebuild immediately so HeroTrailerBackdrop disables and tears down its
    // engine at the button press. The resolving loader is a RawDialogRoute,
    // which the app's PageRoute observer deliberately does not see; waiting
    // for the eventual player-handoff signal lets the delayed trailer start
    // (or keep playing) behind source resolution.
    setState(() => _r.playLaunching = true);
    try {
      await launch();
    } finally {
      if (mounted) {
        // A cancelled/failed resolve may resume autoplay after its normal
        // delay. A successful launch remains off because the backdrop's
        // content-player signal has independently latched _canPlay false.
        setState(() => _r.playLaunching = false);
      } else {
        _r.playLaunching = false;
      }
    }
  }

  /// The engine-only episode promise shared by primary Play and primary hold.
  /// See [_playPrimary] for why loader-derived coordinates are intentionally
  /// left for the host to resolve again.
  ({bool started, int season, int episode})? get primaryEpisodePromise {
    // Promise ONLY an engine-derived target ([_hasMergedEpisodeTarget]), and
    // only a started one.
    //
    // The engine is the sole reason the label can disagree with the host: it
    // advances off watched state, which the host's reconciler never reads. A
    // label that came from the loader instead already equals what the host
    // would work out for itself, so promising it buys nothing — and costs
    // freshness, because these coordinates are only re-read at page open and on
    // return from playback. Promising a loader echo would let a page left open
    // while an episode was finished elsewhere override a fresher reconcile with
    // the episode the user already watched.
    //
    // This also covers the post-playback window for free:
    // [_refreshAfterPlayback] clears the flag before re-reading, so a press
    // during the refresh promises nothing and the host decides — without having
    // to block the button, which stays pressable throughout. An untouched show
    // resolves to S01E01 with no evidence behind it, hence the started gate.
    final season = _r.resumeSeason;
    final episode = _r.resumeEpisode;
    return (!_isMovie &&
            _r.resumeStarted &&
            _r.hasMergedEpisodeTarget &&
            season != null &&
            episode != null)
        ? (started: true, season: season, episode: episode)
        : null;
  }

  void playPrimary() {
    if (_ra.primaryLabel == 'Rewatch') {
      unawaited(guardPlay(rewatchTitle));
      return;
    }
    final promised = primaryEpisodePromise;
    debugPrint(
      '[SeriesResume] detail-primary-pressed title="${_item.name}" '
      'label="${_ra.primaryLabel}" loaded=${_r.resumeLoaded} started=${_r.resumeStarted} '
      'labelTarget=S${_r.resumeSeason}E${_r.resumeEpisode} '
      'routeTarget=S${_deps.initialSeason()}E${_deps.initialEpisode()} '
      'mergedEngineTarget=${_r.hasMergedEpisodeTarget} '
      'loaderInFlight=${_r.resumeLoaderInFlight} '
      'promised=${promised == null ? 'none' : 'S${promised.season}E${promised.episode}'}',
    );
    unawaited(guardPlay(() => _deps.onResume()(promised)));
  }

  Future<void> rewatchTitle() async {
    final restart = _deps.onRewatch();
    if (restart == null) return;
    final cleared = await resetProgressForRewatch(
      _deps.context(),
      id: _item.imdbId ?? _item.id,
      title: _item.name,
      isMovie: _isMovie,
      onConfirmed: () => setState(() => _r.rewatchPending = true),
    );
    if (!mounted) return;
    _f.episodesPanelKey.currentState?.refreshWatchProgress();
    if (!cleared) return;
    ++_k.movieCompletionGeneration; // Discard reads started before the reset.
    setState(() {
      _r.seriesDone = false;
      _r.rewatchPending = false;
      _k.localMovieFinished = false;
      _k.simklStatus = null;
      _r.resumeStarted = false;
      _r.resumeSeason = 1;
      _r.resumeEpisode = 1;
      _r.hasMergedEpisodeTarget = false;
    });
    await restart();
  }

  void browsePrimarySources() {
    unawaited(browsePrimarySourcesAsync());
  }

  Future<void> browsePrimarySourcesAsync() async {
    if (_isMovie) {
      _deps.onBrowse()?.call();
      return;
    }

    final openEpisode = _deps.onBrowsePrimaryEpisodeSources();
    if (openEpisode == null) return;

    final rules = await QuickPlayStorage.getQuickPlayRules(isMovie: false);
    if (!mounted) return;

    final canBrowsePacks =
        _deps.onTraktAction() != null &&
        _appMenuOptions.any(
          (option) => option.action == TraktItemMenuAction.searchPacks,
        );
    if (!rules.preferSeriesPacks || !canBrowsePacks) {
      await openEpisode(primaryEpisodePromise);
      return;
    }

    final season = _r.resumeSeason;
    final episode = _r.resumeEpisode;
    final choice = await showDetailPrimarySourcesSheet(
      _deps.context(),
      title: _item.name,
      isTelevision: _deps.isTelevision(),
      episodeLabel: season == null || episode == null
          ? null
          : 'S${season}E$episode',
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case DetailPrimarySourceChoice.seasonPacks:
        await _deps.onTraktAction()?.call(TraktItemMenuAction.searchPacks);
        return;
      case DetailPrimarySourceChoice.episode:
        await openEpisode(primaryEpisodePromise);
        return;
    }
  }

  void quickPlayEpisode(AdvancedSearchSelection selection) {
    final play = _deps.onQuickPlay();
    if (play == null) return;
    unawaited(guardPlay(() => play(selection)));
  }

  void playDirectEpisode(TraktEpisode episode) {
    final play = _deps.onPlayEpisode();
    if (play == null) return;
    unawaited(guardPlay(() => play(episode)));
  }
}
