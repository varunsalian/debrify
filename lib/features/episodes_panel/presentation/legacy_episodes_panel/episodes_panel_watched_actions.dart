import 'dart:async';
import 'package:debrify/features/episodes_panel/application/earlier_episodes.dart';
import 'package:debrify/features/episodes_panel/application/episodes_panel_policies.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/season_watched_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/watched_action_coordinator.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class EpisodesPanelWatchedActions {
  final EpisodesPanelDeps _deps;
  EpisodesPanelWatchedActions(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelProgress get _p => _deps.parts.progress;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  /// One earlier-episodes batch at a time (the season retry coordinator keeps
  /// its own re-entrancy guard; this one covers the whole multi-provider run).
  bool earlierActionBusy = false;

  /// "Mark earlier episodes watched": batch-mark every aired episode before
  /// this one on this device plus every tracker a single watched-write would
  /// touch. The ticks are re-read (not painted) afterwards, so failed trackers
  /// never show a false tick.
  Future<void> markEarlierWatched(TraktEpisode episode) async {
    if (earlierActionBusy) return;
    final show = _s.selectedShow;
    if (show == null) return;
    final imdbId = show.progressId ?? show.id;
    final refs = earlierEpisodes(
      _s.episodeSeasons,
      season: episode.season,
      episode: episode.number,
      now: DateTime.now(),
    );
    if (refs.isEmpty) return;
    final messenger = ScaffoldMessenger.of(_deps.context());
    final confirmed = await showDialog<bool>(
      useRootNavigator: true,
      context: _deps.context(),
      builder: (ctx) => AlertDialog(
        title: const Text('Mark earlier episodes watched?'),
        content: Text(
          'Marks ${refs.length} earlier episodes of ${show.name} as watched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark watched'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    earlierActionBusy = true;
    // Capture the originating profile: a switch mid-batch must stop writes.
    final scope = ProfileRuntime.scope.value;
    messenger.showSnackBar(
      SnackBar(content: Text('Marking ${refs.length} episodes watched…')),
    );
    try {
      final providers = await WatchedActionCoordinator.episodeWriteProviders(
        imdbId,
      );
      final result = await markEarlierEpisodesWatched(
        imdbId: imdbId,
        seriesTitle: show.name,
        episodes: refs,
        providers: providers,
        canContinue: () => ProfileRuntime.scope.value == scope && mounted,
        mark: (id, season, eps, provider, {seriesTitle}) =>
            SeasonWatchedService.mark(
              id,
              season,
              eps,
              provider,
              seriesTitle: seriesTitle,
            ),
      );
      if (!mounted || result.cancelled) return;
      MdblistContinueWatchingService.instance.invalidate();
      // Re-read the real ticks instead of painting them: a tracker whose
      // write failed must not keep a fake tick.
      await _deps.refreshWatchProgress();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailures
                ? 'Marked ${refs.length} episodes; some trackers failed. '
                      'Try again to retry them.'
                : 'Marked ${refs.length} episodes watched',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not mark earlier episodes. Please retry.'),
          ),
        );
      }
    } finally {
      earlierActionBusy = false;
    }
  }

  /// Everywhere a watched-state change will be written: the connected
  /// trackers, plus this device's own playback storage — always on unwatch
  /// (local completion is a tick source only the app can clear), on watch only
  /// when it is the sole store available. Shared by the action itself and the
  /// menu row's subtitle, so what the row promises IS what the action does.
  List<String> watchedSyncTargets({required bool watched}) {
    final show = _s.selectedShow;
    final imdb = show == null ? '' : (show.progressId ?? show.id);
    final targets = <String>[
      if (_a.isTraktAuthenticated &&
          _p.trackingPolicy.scrobbles(TrackingSource.trakt))
        'Trakt',
      if (_a.isSimklAuthenticated &&
          _p.trackingPolicy.scrobbles(TrackingSource.simkl))
        'Simkl',
      if (_a.isMdblistAuthenticated &&
          (MediaIdentity.isImdb(imdb) || MediaIdentity.isNative(imdb)) &&
          _p.trackingPolicy.scrobbles(TrackingSource.mdblist))
        'MDBList',
      'this device',
    ];
    return targets;
  }

  /// Set an episode's watched state everywhere at once: local playback
  /// storage plus every connected tracker. The ticks this panel paints are an
  /// OR-union of all of those sources (see [_loadEpisodeWatchProgress]), so a
  /// per-provider action can never make an unwatch stick — whichever source
  /// wasn't cleared resurrects the tick when the union is re-merged on the
  /// next panel open (2026-08-24 report: episodes unwatched on Trakt AND
  /// Simkl kept re-ticking on detail re-entry).
  Future<void> setEpisodeWatchedEverywhere(
    TraktEpisode episode, {
    required bool watched,
  }) async {
    final show = _s.selectedShow;
    if (show == null) return;
    final showImdbId = show.progressId ?? show.id;
    final key = '${episode.season}-${episode.number}';
    final targets = watchedSyncTargets(watched: watched);
    final result = await WatchedActionCoordinator.setEpisodeWatched(
      imdbId: showImdbId,
      seriesTitle: show.name,
      season: episode.season,
      episode: episode.number,
      watched: watched,
    );
    final failed = result.failedTargets;

    if (!mounted) return;
    MdblistContinueWatchingService.instance.invalidate();
    // Only move the tick if some store actually changed — when every write
    // failed, an optimistic update would paint a state that silently reverts
    // on the next re-merge. (Unwatch always changes at least local storage.)
    final done = targets.where((t) => !failed.contains(t)).toList();
    // Guide ticks follow the Progress source, so the optimistic update only
    // sticks when this action reached a source the guide actually renders —
    // otherwise the next re-merge would silently revert it.
    final rendersHere =
        _p.trackingPolicy.isSmart ||
        (_p.trackingPolicy.progressFrom(TrackingSource.local) &&
            done.contains('this device')) ||
        (_p.trackingPolicy.progressFrom(TrackingSource.trakt) &&
            done.contains('Trakt')) ||
        (_p.trackingPolicy.progressFrom(TrackingSource.simkl) &&
            done.contains('Simkl')) ||
        (_p.trackingPolicy.progressFrom(TrackingSource.mdblist) &&
            done.contains('MDBList'));
    if (done.isNotEmpty && rendersHere) {
      _deps.setState(() {
        if (watched) {
          _p.episodeWatchProgress[key] = 100.0;
        } else {
          _p.episodeWatchProgress.remove(key);
        }
        _s.nextEpisode = _p.mergedUpNext(
          _p.episodeWatchProgress,
          _s.trackerNextRaw,
        );
      });
      final next = _s.nextEpisode;
      if (next != null) _p.publishNextEpisode(next, mutation: true);
      _p.publishSeriesCompletion();
    }
    final label =
        'Marked as ${watched ? 'Watched' : 'Unwatched'}'
        '${done.isEmpty ? '' : ' on ${EpisodesPanelPolicies.joinNames(done)}'}';
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty ? label : '$label — failed on ${failed.join(', ')}',
        ),
        backgroundColor: failed.isEmpty
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Handle the episode quick-strip / long-press menu against Trakt. The
  /// watched-state actions route through [_setEpisodeWatchedEverywhere] — the
  /// tick is a multi-source union, so they must never act on Trakt alone.
  Future<void> onEpisodeMenuAction(
    TraktEpisode episode,
    TraktEpisodeMenuAction action,
  ) async {
    final show = _s.selectedShow;
    if (show == null) return;
    final showImdbId = show.progressId ?? show.id;
    bool success = false;
    String actionLabel = '';

    switch (action) {
      case TraktEpisodeMenuAction.markWatched:
        return setEpisodeWatchedEverywhere(episode, watched: true);
      case TraktEpisodeMenuAction.markUnwatched:
        return setEpisodeWatchedEverywhere(episode, watched: false);
      case TraktEpisodeMenuAction.rate:
        if (!mounted) return;
        final rating = await showTraktRatingDialog(_deps.context());
        if (rating == null) return;
        actionLabel = 'Rated $rating/10';
        success = await _sv.traktService.rateEpisode(
          showImdbId,
          episode.season,
          episode.number,
          rating,
        );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(success ? actionLabel : 'Failed: $actionLabel'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> onEpisodeMdblistMenuAction(
    TraktEpisode episode,
    MdblistEpisodeMenuAction action,
  ) async {
    final show = _s.selectedShow;
    if (show == null) return;
    final imdb = show.progressId ?? show.id;
    if (!MediaIdentity.isImdb(imdb) && !MediaIdentity.isNative(imdb)) return;
    final ids = MdblistMediaIds.forContent(imdb);
    final key = '${episode.season}-${episode.number}';
    bool success;
    String label;
    switch (action) {
      case MdblistEpisodeMenuAction.markWatched:
        return setEpisodeWatchedEverywhere(episode, watched: true);
      case MdblistEpisodeMenuAction.markUnwatched:
        return setEpisodeWatchedEverywhere(episode, watched: false);
      case MdblistEpisodeMenuAction.rate:
        if (!mounted) return;
        final rating = await showMdblistRatingDialog(_deps.context());
        if (rating == null) return;
        success = await _sv.mdblistService.rateTitle(
          ids,
          'episode',
          rating,
          season: episode.season,
          episode: episode.number,
        );
        label = 'Rated $rating/10 on MDBList';
        if (success && mounted) {
          _deps.setState(() => _p.episodeMdblistRatings[key] = rating);
        }
      case MdblistEpisodeMenuAction.removeRating:
        success = await _sv.mdblistService.removeRating(
          ids,
          'episode',
          season: episode.season,
          episode: episode.number,
        );
        label = 'Removed rating from MDBList';
        if (success && mounted) {
          _deps.setState(() => _p.episodeMdblistRatings.remove(key));
        }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(success ? label : 'Failed: $label'),
        backgroundColor: success
            ? const Color(0xFF34D399)
            : const Color(0xFFEF4444),
      ),
    );
  }
}
