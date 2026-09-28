import 'package:flutter/widgets.dart';
import '../models/home_favorite_row_ref.dart';

/// Saved-content node pools retain positional identity on refresh. Watchlist
/// removal restores after layout; Playlist retains its immediate handoff policy.
class HomeFavoriteNodes {
  final _rows = {
    for (final kind in HomeFavoriteKind.values) kind: <FocusNode>[],
  };
  static const _labels = {
    HomeFavoriteKind.debrify: 'search_tvfav',
    HomeFavoriteKind.stremio: 'search_stvfav',
    HomeFavoriteKind.iptv: 'search_iptvfav',
    HomeFavoriteKind.watchlistMovies: 'search_watchlist_movie',
    HomeFavoriteKind.watchlistSeries: 'search_watchlist_series',
    HomeFavoriteKind.playlist: 'search_playlistfav',
  };
  List<FocusNode> nodes(HomeFavoriteKind kind) => _rows[kind]!;

  void sync(
    HomeFavoriteKind kind,
    int count, {
    required bool Function() isCurrent,
    required VoidCallback onEmpty,
  }) {
    final row = nodes(kind);
    while (row.length < count) {
      row.add(FocusNode(debugLabel: '${_labels[kind]}_${row.length}'));
    }
    final watchlist =
        kind == HomeFavoriteKind.watchlistMovies ||
        kind == HomeFavoriteKind.watchlistSeries;
    var removedFocused = false;
    while (row.length > count) {
      final removed = row.removeLast();
      final hadFocus = removed.hasFocus;
      removedFocused = removedFocused || hadFocus;
      removed.dispose();
      if (kind == HomeFavoriteKind.playlist && hadFocus && row.isNotEmpty) {
        row.last.requestFocus();
      }
    }
    if (watchlist && removedFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrent()) return;
        if (row.isNotEmpty) {
          row.last.requestFocus();
        } else {
          onEmpty();
        }
      });
    }
  }

  // Preserve the route's disposal-then-clear phases around continuation pools.
  void disposeNodes() {
    for (final kind in [
      HomeFavoriteKind.debrify,
      HomeFavoriteKind.stremio,
      HomeFavoriteKind.iptv,
      HomeFavoriteKind.watchlistMovies,
      HomeFavoriteKind.watchlistSeries,
      HomeFavoriteKind.playlist,
    ]) {
      for (final node in nodes(kind)) {
        node.dispose();
      }
    }
  }

  void clearNodes() {
    for (final row in _rows.values) {
      row.clear();
    }
  }
}
