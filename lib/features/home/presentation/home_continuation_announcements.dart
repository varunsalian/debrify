import 'package:flutter/material.dart';
import 'home_continuation_section.dart';
import 'home_saved_content_section.dart';

typedef HomeContinuationAnnouncementsDeps = ({
  bool Function() mounted,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() loading,
  bool Function() activeTab,
  BuildContext Function() context,
  Set<String> Function() disabled,
  List<List<FocusNode>> Function() rowNodes,
});

/// Announces newly visible tracker rows relative to the user's current focus.
class HomeContinuationAnnouncements {
  HomeContinuationAnnouncements(this._deps, this._section, this._saved);
  final HomeContinuationAnnouncementsDeps _deps;
  final HomeContinuationSection _section;
  final HomeSavedContentSection _saved;

  /// The Trakt rows just landed (skeleton → content), usually seconds after
  /// the rest of the board. Local Continue Watching renders above them; Simkl,
  /// IPTV, favourites and catalog rows below.
  void maybeAnnounceTraktRows() => maybeAnnounceCwRows(
    label: 'Trakt',
    // Same merge-aware gates as _cwRows / _cwVisible, so a notice fires
    // exactly when a row actually rendered.
    visible:
        ((_section.cwMergeTrakt ? _section.traktAll : _section.traktMovies)
                .isNotEmpty &&
            !_deps.disabled().contains('trakt:movies')) ||
        (!_section.cwMergeTrakt &&
            _section.traktSeries.isNotEmpty &&
            !_deps.disabled().contains('trakt:shows')),
    ownNodes: [_section.traktMovieNodes, _section.traktSeriesNodes],
    aboveNodes: [_section.cwMovieNodes, _section.cwSeriesNodes],
    belowNodes: [
      _section.simklMovieNodes,
      _section.simklSeriesNodes,
      _section.mdblistMovieNodes,
      _section.mdblistSeriesNodes,
      _section.iptvCwMovieNodes,
      _section.iptvCwSeriesNodes,
    ],
  );

  /// Same for the Simkl rows, which land on their own schedule (and without a
  /// reserved skeleton slot, so they push the board when they arrive). Local
  /// Continue Watching and the Trakt rows render above them, IPTV below.
  void maybeAnnounceSimklRows() => maybeAnnounceCwRows(
    label: 'Simkl',
    visible:
        ((_section.cwMergeSimkl ? _section.simklAll : _section.simklMovies)
                .isNotEmpty &&
            !_deps.disabled().contains('simkl:movies')) ||
        (!_section.cwMergeSimkl &&
            _section.simklSeries.isNotEmpty &&
            !_deps.disabled().contains('simkl:shows')),
    ownNodes: [_section.simklMovieNodes, _section.simklSeriesNodes],
    aboveNodes: [
      _section.cwMovieNodes,
      _section.cwSeriesNodes,
      _section.traktMovieNodes,
      _section.traktSeriesNodes,
    ],
    belowNodes: [
      _section.mdblistMovieNodes,
      _section.mdblistSeriesNodes,
      _section.iptvCwMovieNodes,
      _section.iptvCwSeriesNodes,
    ],
  );

  void maybeAnnounceMdblistRows() => maybeAnnounceCwRows(
    label: 'MDBList',
    visible:
        ((_section.cwMergeMdblist
                    ? _section.mdblistAll
                    : _section.mdblistMovies)
                .isNotEmpty &&
            !_deps.disabled().contains('mdblist:movies')) ||
        (!_section.cwMergeMdblist &&
            _section.mdblistSeries.isNotEmpty &&
            !_deps.disabled().contains('mdblist:shows')),
    ownNodes: [_section.mdblistMovieNodes, _section.mdblistSeriesNodes],
    aboveNodes: [
      _section.cwMovieNodes,
      _section.cwSeriesNodes,
      _section.traktMovieNodes,
      _section.traktSeriesNodes,
      _section.simklMovieNodes,
      _section.simklSeriesNodes,
    ],
    belowNodes: [_section.iptvCwMovieNodes, _section.iptvCwSeriesNodes],
  );

  /// A tracker's Continue Watching rows just appeared on the board — if the
  /// user is already browsing elsewhere, point them at the new rows with a
  /// small toast, with the direction worked out from where DPAD focus currently
  /// sits. [ownNodes] are the new rows themselves (focus already there → stay
  /// quiet), [aboveNodes] / [belowNodes] the other Continue Watching rows they
  /// slot between; favourites and catalog rows always render below.
  void maybeAnnounceCwRows({
    required String label,
    required bool visible,
    required List<List<FocusNode>> ownNodes,
    required List<List<FocusNode>> aboveNodes,
    required List<List<FocusNode>> belowNodes,
  }) {
    if (!_deps.mounted() || !_deps.isTelevision()) return;
    if (_deps.searchMode() || _deps.discoverMode()) return;
    // Still on the brand loading stage: the rows will simply be there when the
    // board first paints — nothing to announce.
    if (_deps.loading()) return;
    // Only the board the user is actually looking at announces (not one
    // reloading under a detail page/player or on an inactive tab).
    if (!_deps.activeTab()) return;
    final context = _deps.context();
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    // Rows hidden by the Home Rows manager never reached the screen.
    if (!visible) return;
    final primary = FocusManager.instance.primaryFocus;
    bool onRow(List<FocusNode> nodes) =>
        primary != null && nodes.contains(primary);
    bool onAny(List<List<FocusNode>> rows) => rows.any(onRow);
    if (onAny(ownNodes)) return; // already looking at them
    String? dir;
    if (onAny(aboveNodes)) {
      dir = 'down';
    } else if (onAny(belowNodes)) {
      dir = 'up';
    } else {
      for (final kind in _saved.favRowKinds) {
        if (onRow(_saved.favNodesFor(kind))) {
          dir = 'up';
          break;
        }
      }
      if (dir == null) {
        for (final row in _deps.rowNodes()) {
          if (onRow(row)) {
            dir = 'up';
            break;
          }
        }
      }
    }
    final msg = dir == null
        ? '$label Continue Watching loaded'
        : '$label loaded — scroll $dir to view';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
    );
  }
}
