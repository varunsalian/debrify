import 'dart:async';
import 'package:flutter/material.dart';
import '../application/home_post_playback_refresh_controller.dart';
import 'home_continuation_section.dart';
import 'home_continuation_loading.dart';
import 'home_saved_content_section.dart';

typedef HomeContinuationReturnDeps = ({
  HomePostPlaybackRefreshController Function() controller,
  bool Function() mounted,
  bool Function() searchMode,
  BuildContext Function() context,
  bool Function() traktAuthenticated,
  VoidCallback clearResume,
  Future<void> Function() refreshBound,
});

/// Coordinates the existing post-playback refresh latch and resume throttling.
class HomeContinuationReturn {
  HomeContinuationReturn(this._deps, this._section, this._loading, this._saved);
  final HomeContinuationReturnDeps _deps;
  final HomeContinuationSection _section;
  final HomeContinuationLoading _loading;
  final HomeSavedContentSection _saved;

  /// Set when a real content player launches (any path — in-app route, native
  /// TV activity, external app; never trailers), consumed by
  /// [refreshAfterPlayback].
  ///
  /// This is what keeps the post-playback refresh from becoming a tax on plain
  /// browsing: Trakt and Simkl each still require multiple paged calls, and
  /// [refreshAfterPlayback] runs on EVERY detail-page close — so without this
  /// latch, opening a title and pressing Back would hit both tracker APIs. Only
  /// a session that actually played something can have moved a tracker's
  /// position. Tracker rows changed by menu actions (mark watched, remove from
  /// Continue Watching) are refreshed by those handlers directly.
  HomePostPlaybackRefreshController get postPlaybackRefreshController =>
      _deps.controller();
  bool get playedSinceRefresh =>
      postPlaybackRefreshController.playedSinceRefresh;

  /// Last Trakt CW network attempt. The row is refreshed when the app returns
  /// from the background (where the user may have changed Trakt in another app
  /// or browser), but lifecycle noise within this window is coalesced.
  DateTime? get lastTraktCwRefreshAttemptAt =>
      _section.traktContinuationController.lastAttemptAt;
  static const Duration traktCwResumeRefreshInterval = Duration(seconds: 30);

  /// A real content player launched — see [playedSinceRefresh].
  void markPlaybackStarted() =>
      postPlaybackRefreshController.markPlaybackStarted();

  /// Re-read everything a finished playback (or a detail/See-All visit) can
  /// change: local Continue Watching, then — when something actually played —
  /// the Trakt and Simkl rows, then the bound-source badges.
  ///
  /// The tracker rows matter because they're SEPARATE rows ([_continuationProjection.cwRows]):
  /// reloading only the local list left a tracker user staring at the episode
  /// they'd just finished. They're gated on [playedSinceRefresh] (or an
  /// explicit [trackers]) so plain browsing doesn't hit two APIs per Back press.
  ///
  /// Bound sources go LAST: _deps.refreshBound scans the CW lists the loaders
  /// replace, so running them concurrently would count the pre-reload set.
  ///
  /// Fire-and-forget from route callbacks and the playback-return listener, so
  /// a transient storage/network error must not become an unhandled async
  /// exception (a stale row is recoverable; a crash-log isn't warranted).
  Future<void> refreshAfterPlayback({bool trackers = false}) =>
      postPlaybackRefreshController.refresh(
        searchMode: _deps.searchMode(),
        trackers: trackers,
        isCurrent: () => _deps.mounted(),
        clearResume: _deps.clearResume,
        watchlist: _saved.loadMyWatchlist,
        local: _loading.loadContinueWatching,
        iptv: _loading.loadIptvContinueWatching,
        trakt: () => _loading.loadTraktContinueWatching(refreshBound: false),
        simkl: () => _loading.loadSimklContinueWatching(refreshBound: false),
        shouldRefreshMdblist: () => _section.mdblistContinuationController
            .shouldRefreshAfterPlayback(DateTime.now()),
        mdblist: () => _loading.loadMdblistContinueWatching(
          refreshBound: false,
          force: true,
        ),
        boundSources: _deps.refreshBound,
        onError: (error) =>
            debugPrint('SearchScreen: post-playback refresh failed: $error'),
      );

  /// Playback ran in a separate ACTIVITY and the app just came back (see
  /// [MainPageBridge.notifyPlaybackReturned]). Only refresh when the board is
  /// the top route: with a detail page or See-All open on top, THAT screen owns
  /// the refresh and the board re-reads through the covering route's `.then`
  /// when it pops — so this can't double up with it. The latch survives until
  /// then, so the deferred refresh still knows playback happened.
  void onPlaybackReturned() {
    if (!_deps.mounted()) return;
    if (!(ModalRoute.of(_deps.context())?.isCurrent ?? false)) return;
    unawaited(refreshAfterPlayback());
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_deps.mounted() ||
        _deps.searchMode() ||
        !_deps.traktAuthenticated() ||
        playedSinceRefresh ||
        !(ModalRoute.of(_deps.context())?.isCurrent ?? false)) {
      return;
    }
    final lastAttempt = lastTraktCwRefreshAttemptAt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < traktCwResumeRefreshInterval) {
      return;
    }
    unawaited(_loading.loadTraktContinueWatching());
  }

  /// Refresh state that a See-All screen may have changed (Continue Watching
  /// progress/removal, bound sources) when it pops back to the board — plus the
  /// tracker rows when the user played something from the grid.
  Future<void> afterSeeAllReturn() => refreshAfterPlayback();
}
