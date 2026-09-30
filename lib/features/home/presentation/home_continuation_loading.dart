import 'dart:async';
import 'package:flutter/material.dart';
import '../models/home_episode_artwork.dart';
import 'home_continuation_section.dart';
import 'home_stage_rows.dart';

typedef HomeContinuationLoadingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() searchMode,
  bool Function() discoverMode,
  BuildContext Function() context,
  void Function(List<FocusNode>, int) requestRowFocus,
  VoidCallback autoFocus,
  VoidCallback announceTrakt,
  VoidCallback announceSimkl,
  VoidCallback announceMdblist,
  Future<void> Function() refreshBound,
});

/// Continuation load publication keeps the existing node, artwork and focus order.
class HomeContinuationLoading {
  HomeContinuationLoading(this._deps, this._section, this._mdblistEnabled);
  final HomeContinuationLoadingDeps _deps;
  final HomeContinuationSection _section;
  final bool _mdblistEnabled;

  /// Load the Continue Watching row from the shared local store. Mirrors
  /// Home's join (item list + per-title playback progress) but is read-only —
  /// it never writes, so Home's row is untouched. Safe to call repeatedly
  /// (e.g. after returning from a detail/playback).
  Future<void>
  loadContinueWatching() => _section.localContinuationController.load(
    isCurrent: () => _deps.mounted(),
    onProgressSourceChanged: () => _deps.setState(() {}),
    beforeEnabledRows: _section.ensureCwMergeFlags,
    beforeRows: (next) {
      // Keep the same nodes on refresh. Merged mode uses the movies slot for
      // every item; disabled rows release their nodes before data publication.
      _section.continuationNodes.resize(
        HomeContinuationKind.local,
        movies: _section.cwMergeLocal
            ? next.data.items.length
            : next.movies.length,
        series: _section.cwMergeLocal ? 0 : next.series.length,
        requestFocus: _deps.requestRowFocus,
      );
    },
    onRows: (next, current) {
      _deps.setState(
        () => _section.episodeArtworkController.clear(
          HomeEpisodeArtworkSource.local,
        ),
      );
      if (!next.enabled) return;
      unawaited(
        _section.enrichCwEpisodeArtwork(
          refs: next.data.episodeRefs,
          source: HomeEpisodeArtworkSource.local,
          isCurrent: current,
        ),
      );
      _deps.autoFocus();
    },
  );

  void onLocalCompletionChanged() {
    if (!_deps.mounted() || _deps.searchMode() || _deps.discoverMode()) return;
    unawaited(loadContinueWatching());
  }

  /// Load the IPTV Continue Watching shelves (Xtream VOD movies + series) from
  /// the player's own watch history. Independent of [loadContinueWatching] —
  /// different data source, different (non-IMDb) identity — but follows the same
  /// token-guard + node-sync discipline so a slow reload can't clobber a newer
  /// one or drop the focus node the user is sitting on.
  Future<void> loadIptvContinueWatching() {
    // Dedicated Search does not load IPTV shelves, including playback returns.
    if (_deps.searchMode()) return Future<void>.value();
    return _section.iptvContinuationController.load(
      isCurrent: () => _deps.mounted(),
      beforeRows: (next) {
        _section.continuationNodes.resize(
          HomeContinuationKind.iptv,
          movies: next.movies.length,
          series: next.series.length,
          requestFocus: _deps.requestRowFocus,
        );
      },
      onRows: () {
        _deps.setState(() {});
        _deps.autoFocus();
      },
    );
  }

  /// Fetch the Trakt "Continue Watching" rows (in-progress movies + up-next
  /// episodes) from the connected account. Uses Trakt's intent-aware Up Next
  /// feed plus paged playback checkpoints. Runs on init / integration change,
  /// post-playback, and a throttled app resume — never on every rebuild.
  /// Token-guarded against overlap; hides the rows when Trakt isn't connected.
  /// [refreshBound] runs a bound-source refresh at the end; pass false when the
  /// caller already refreshes bound sources itself (avoids a double pass).
  Future<void> loadTraktContinueWatching({
    bool refreshBound = true,
  }) => _section.traktContinuationController.load(
    attemptedAt: DateTime.now(),
    isCurrent: () => _deps.mounted(),
    beforeConnectedRows: _section.ensureCwMergeFlags,
    beforeRows: (next) {
      _section.continuationNodes.resize(
        HomeContinuationKind.trakt,
        movies: _section.cwMergeTrakt ? next.all.length : next.movies.length,
        series: _section.cwMergeTrakt ? 0 : next.series.length,
        requestFocus: _deps.requestRowFocus,
      );
    },
    onRows: (next, connected, hadRows, current) {
      _deps.setState(
        () => _section.episodeArtworkController.clear(
          HomeEpisodeArtworkSource.trakt,
        ),
      );
      if (!connected) return;
      unawaited(
        _section.enrichCwEpisodeArtwork(
          refs: next.episodeRefs,
          source: HomeEpisodeArtworkSource.trakt,
          isCurrent: current,
        ),
      );
      _deps.autoFocus();
      if (!hadRows) _deps.announceTrakt();
      if (refreshBound) unawaited(_deps.refreshBound());
    },
    onFailure: (error, accepted) {
      debugPrint('SearchScreen: Trakt continue-watching load failed: $error');
      if (accepted) _deps.setState(() {});
    },
  );

  /// Fetch the Simkl "Continue Watching" rows (paused movies + paused episodes)
  /// from the connected account's playback sessions — the same `/sync/playback`
  /// lists the scrobble resume already fetches + caches, so this is cheap. Runs
  /// once on init / integration change and caches in memory. Token-guarded
  /// against overlap; hides the rows when Simkl isn't connected. [refreshBound]
  /// runs a bound-source refresh at the end (skip when the caller already does).
  Future<void> loadSimklContinueWatching({bool refreshBound = true}) =>
      _section.simklContinuationController.load(
        isCurrent: () => _deps.mounted(),
        ensureLayout: _section.ensureCwMergeFlags,
        beforeRows: (next) {
          _section.continuationNodes.resize(
            HomeContinuationKind.simkl,
            movies: _section.cwMergeSimkl
                ? next.all.length
                : next.movies.length,
            series: _section.cwMergeSimkl ? 0 : next.series.length,
            requestFocus: _deps.requestRowFocus,
          );
        },
        onRows: (next, hadRows, current) {
          _deps.setState(
            () => _section.episodeArtworkController.clear(
              HomeEpisodeArtworkSource.simkl,
            ),
          );
          unawaited(
            _section.enrichCwEpisodeArtwork(
              refs: next.episodeRefs,
              source: HomeEpisodeArtworkSource.simkl,
              isCurrent: current,
            ),
          );
          _deps.autoFocus();
          if (!hadRows) _deps.announceSimkl();
          if (refreshBound) unawaited(_deps.refreshBound());
        },
      );

  Future<void> loadMdblistContinueWatching({
    bool refreshBound = true,
    bool force = false,
  }) => _section.mdblistContinuationController.load(
    enabled: _mdblistEnabled,
    force: force,
    refreshBound: refreshBound,
    isCurrent: () => _deps.mounted(),
    ensureLayout: _section.ensureCwMergeFlags,
    now: DateTime.now,
    trace: debugPrint,
    onDisabled: () => _deps.setState(() {}),
    beforeRows: (next) {
      _section.continuationNodes.resize(
        HomeContinuationKind.mdblist,
        movies: _section.cwMergeMdblist ? next.all.length : next.movies.length,
        series: _section.cwMergeMdblist ? 0 : next.series.length,
        requestFocus: _deps.requestRowFocus,
      );
    },
    onRows: (next, hadRows) {
      _deps.setState(() {});
      _deps.autoFocus();
      if (!hadRows) _deps.announceMdblist();
      if (refreshBound) unawaited(_deps.refreshBound());
    },
  );

  void onMdblistPlaybackRevision() {
    if (_deps.searchMode() || _deps.discoverMode()) return;
    unawaited(
      _section.mdblistContinuationController.refreshAfterRevision(
        isCurrent: () => _deps.mounted(),
        isVisible: () => ModalRoute.of(_deps.context())?.isCurrent ?? true,
        wait: (duration) => Future<void>.delayed(duration),
        reload: () =>
            loadMdblistContinueWatching(refreshBound: false, force: true),
      ),
    );
  }
}
