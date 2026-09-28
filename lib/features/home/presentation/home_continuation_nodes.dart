import 'package:flutter/widgets.dart';
import 'home_stage_rows.dart' show HomeContinuationKind;

/// Owns both focus pools for each Continue Watching family. Counts come from
/// accepted rows; merged rows continue to occupy their family's movies slot.
class HomeContinuationNodes {
  static const _order = [
    HomeContinuationKind.local,
    HomeContinuationKind.iptv,
    HomeContinuationKind.trakt,
    HomeContinuationKind.simkl,
    HomeContinuationKind.mdblist,
  ];
  final _movies = {for (final kind in _order) kind: <FocusNode>[]};
  final _series = {for (final kind in _order) kind: <FocusNode>[]};
  List<FocusNode> movies(HomeContinuationKind kind) => _movies[kind]!;
  List<FocusNode> series(HomeContinuationKind kind) => _series[kind]!;

  void resize(
    HomeContinuationKind kind, {
    required int movies,
    required int series,
    required void Function(List<FocusNode>, int) requestFocus,
  }) {
    final (movieTag, seriesTag) = switch (kind) {
      HomeContinuationKind.local => ('movie', 'series'),
      HomeContinuationKind.iptv => ('iptv-movie', 'iptv-series'),
      HomeContinuationKind.trakt => ('tmovie', 'tseries'),
      HomeContinuationKind.simkl => ('smovie', 'sseries'),
      HomeContinuationKind.mdblist => ('mdbmovie', 'mdbseries'),
    };
    _resize(_movies[kind]!, movies, movieTag, requestFocus);
    _resize(_series[kind]!, series, seriesTag, requestFocus);
  }

  /// Resize a Continue Watching row's focus-node list to [count], preserving
  /// the surviving prefix. This used to dispose-and-recreate ALL the row's
  /// nodes on any length change — and these re-sync on every return from
  /// playback/detail (the CW list almost always changes then), so it destroyed
  /// the very node focus was sitting on: primary focus died with it and the
  /// remote went dead until app relaunch. Now only a shrinking tail is
  /// disposed, and if focus sat in that tail it's handed to the nearest
  /// survivor.
  void _resize(
    List<FocusNode> nodes,
    int count,
    String tag,
    void Function(List<FocusNode>, int) requestFocus,
  ) {
    if (nodes.length == count) return;
    if (count < nodes.length) {
      var tailHadFocus = false;
      for (var i = count; i < nodes.length; i++) {
        if (nodes[i].hasFocus) {
          tailHadFocus = true;
          break;
        }
      }
      while (nodes.length > count) {
        nodes.removeLast().dispose();
      }
      // After the disposal so the dying node can't fight the handoff; a row
      // emptied to zero has no survivor — the dead-focus reclaim listener
      // picks that case up. Mounted-aware move: the last survivor's cell may
      // be virtualized out, and requestFocus on a detached node latches a
      // focus-when-reparented that would yank focus when it scrolls back in.
      if (tailHadFocus && count > 0) {
        requestFocus(nodes, count - 1);
      }
    } else {
      for (var i = nodes.length; i < count; i++) {
        nodes.add(FocusNode(debugLabel: 'search_cw_${tag}_$i'));
      }
    }
  }

  // Preserve the separate disposal/clear phases around the favorite pools.
  void disposeNodes() {
    for (final node in [
      for (final kind in _order) ...[..._movies[kind]!, ..._series[kind]!],
    ]) {
      node.dispose();
    }
  }

  void clearNodes() {
    for (final kind in _order) {
      _movies[kind]!.clear();
      _series[kind]!.clear();
    }
  }
}
