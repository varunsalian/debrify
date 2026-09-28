import 'dart:async';
import '../models/home_row_refresh.dart';

/// Coalesces row invalidations for one mounted Home view. Accepted refresh
/// actions remain host-owned; this queue owns only pending events and timing.
class HomeRefreshQueue {
  HomeRefreshQueue({
    required this.isCurrent,
    required this.isVisible,
    required this.refreshRow,
    required this.refreshAddons,
  });

  final bool Function() isCurrent;
  final bool Function() isVisible;
  final void Function(HomeRowRefresh) refreshRow;
  final void Function() refreshAddons;
  final _pending = <HomeRowRefresh>{};
  Timer? _timer;
  bool _addonsPending = false;

  void addonsChanged() {
    _addonsPending = true;
    enqueue({HomeRowRefresh.stremioTvFavorites});
  }

  void enqueue(Set<HomeRowRefresh> rows) {
    if (!isCurrent()) return;
    // Visible Home receives the separate playback-data bridge already.
    _pending.addAll(
      rows.where((row) => row != HomeRowRefresh.playback || !isVisible()),
    );
    _timer ??= Timer(const Duration(milliseconds: 100), () {
      _timer = null;
      if (!isCurrent()) return;
      final pending = Set<HomeRowRefresh>.of(_pending);
      _pending.clear();
      for (final row in pending) {
        refreshRow(row);
      }
      if (_addonsPending) {
        _addonsPending = false;
        refreshAddons();
      }
    });
  }

  void dispose() => _timer?.cancel();
}
