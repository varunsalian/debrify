import 'package:flutter/widgets.dart';

import '../../../models/stremio_addon.dart';

/// Borrowed accepted row references retain live horizontal paging state.
typedef HomeProgressUpdate = ({
  List<CatalogSection> rows,
  bool first,
  int generation,
  Object? scope,
});

/// View-owned publication queue while a route covers Home. Application state
/// already owns accepted rows; this queue only delays their visible application.
class HomeProgressPublication {
  HomeProgressUpdate? _pending;
  bool _scheduled = false;
  bool _disposed = false;

  bool get hasPending => _pending != null;
  bool get isScheduled => _scheduled;

  void defer(HomeProgressUpdate update) {
    if (_disposed) return;
    _pending = (
      rows: update.rows,
      first: _pending?.first ?? update.first,
      generation: update.generation,
      scope: update.scope,
    );
  }

  /// Starting a new load clears old rows, but retains any scheduled frame.
  void clear() => _pending = null;

  /// A timeout retires requests while retaining already accepted presentation.
  void retireGeneration(int previous, int next) {
    final pending = _pending;
    if (pending == null || pending.generation != previous) return;
    _pending = (
      rows: pending.rows,
      first: pending.first,
      generation: next,
      scope: pending.scope,
    );
  }

  void resume({
    required bool Function() isVisible,
    required bool Function(HomeProgressUpdate) isCurrent,
    required void Function(HomeProgressUpdate) publish,
    required VoidCallback onResumed,
  }) {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || !isVisible()) return;
      final pending = _pending;
      _pending = null;
      if (pending != null) {
        if (!isCurrent(pending)) return;
        publish(pending);
      }
      // The caller schedules viewport measurement on the following frame,
      // after the newly published rows have been laid out, even with no update.
      onResumed();
    });
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _scheduled = false;
  }
}
