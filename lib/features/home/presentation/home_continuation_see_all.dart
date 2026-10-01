import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import 'home_continuation_loading.dart';
import 'home_continuation_playback.dart';
import 'home_continuation_return.dart';
import 'home_continuation_section.dart';
import 'home_see_all_navigation.dart';
import 'home_stage_rows.dart';

typedef HomeContinuationSeeAllDeps = ({
  BuildContext Function() context,
  HomeSeeAllNavigation Function() navigation,
  bool Function() pikpakOnly,
});

/// Continuation grids retain their distinct reload and return policies.
class HomeContinuationSeeAll {
  HomeContinuationSeeAll(
    this._deps,
    this._section,
    this._playback,
    this._loading,
    this._returns,
  );
  final HomeContinuationSeeAllDeps _deps;
  final HomeContinuationSection _section;
  final HomeContinuationPlayback _playback;
  final HomeContinuationLoading _loading;
  final HomeContinuationReturn _returns;

  /// Desktop "See All" for the Simkl Continue Watching rows — reuses the generic
  /// Continue Watching grid, seeded with the paused-order list + progress.
  void openSimklCwSeeAll([String initialCategory = 'all']) {
    pushCwSeeAll(
      title: 'Simkl Continue Watching',
      initialCategory: initialCategory,
      items: _section.simklAll,
      progressOf: (m) => _section.cwCardProgress(HomeContinuationKind.simkl, m),
      onOpen: _playback.openSimklCwItem,
      onQuickPlay: _deps.pikpakOnly() ? null : _playback.playSimklCwItem,
      // One uniform pass instead of an explicit Simkl fetch followed by
      // _returns.afterSeeAllReturn: `trackers: true` because this grid renders Simkl's
      // own list and must refetch whether or not anything was played here, and
      // folding it in stops the two from fetching Simkl twice after a playback.
      onReload: () async {
        await _returns.refreshAfterPlayback(trackers: true);
        return List<StremioMeta>.of(_section.simklAll);
      },
    );
  }

  void openMdblistCwSeeAll([String initialCategory = 'all']) {
    pushCwSeeAll(
      title: 'MDBList Continue Watching',
      initialCategory: initialCategory,
      items: _section.mdblistAll,
      progressOf: (m) =>
          _section.cwCardProgress(HomeContinuationKind.mdblist, m),
      onOpen: _playback.openMdblistCwItem,
      onQuickPlay: _deps.pikpakOnly() ? null : _playback.playMdblistCwItem,
      onReload: () async {
        await _loading.loadMdblistContinueWatching();
        return List<StremioMeta>.of(_section.mdblistAll);
      },
    );
  }

  void pushCwSeeAll({
    required String title,
    required String initialCategory,
    required List<StremioMeta> items,
    required double? Function(StremioMeta) progressOf,
    required void Function(StremioMeta) onOpen,
    required void Function(StremioMeta)? onQuickPlay,
    required Future<List<StremioMeta>> Function()? onReload,
    VoidCallback? onReturn,
  }) => _deps.navigation().pushContinuation(
    _deps.context(),
    title: title,
    initialCategory: initialCategory,
    items: items,
    progressOf: progressOf,
    onOpen: onOpen,
    onQuickPlay: onQuickPlay,
    onReload: onReload,
    onReturn: onReturn,
  );

  /// Local Continue Watching "See All", pre-filtered to [initialCategory]
  /// ('movie' / 'series') of the row the user came from. Re-fetches (via
  /// onReload) whenever a detail/player route pops back onto it, so finished
  /// titles drop out and progress stays fresh.
  void openContinueWatchingSeeAll([String initialCategory = 'all']) {
    pushCwSeeAll(
      title: 'Continue Watching',
      initialCategory: initialCategory,
      items: _section.cwAll,
      progressOf: (m) => _section.cwCardProgress(HomeContinuationKind.local, m),
      onOpen: _playback.openContinueItem,
      onQuickPlay: _deps.pikpakOnly() ? null : _playback.onContinuePlay,
      // Reload CW + refresh bound sources (sequenced), then hand the grid the
      // fresh list. This runs on every detail/player return AND keeps the board
      // beneath fresh, so no separate onReturn is needed (it would double the
      // reload when a detail-close is immediately followed by a board-return).
      onReload: () async {
        await _returns.afterSeeAllReturn();
        return List<StremioMeta>.of(_section.cwAll);
      },
    );
  }

  void openTraktSeeAll([String initialCategory = 'all']) =>
      _deps.navigation().openTrakt(_deps.context(), initialCategory);
}
