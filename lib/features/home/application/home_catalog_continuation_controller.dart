import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_catalog_session.dart';

final homeCatalogContinuationProvider = NotifierProvider.autoDispose
    .family<HomeCatalogContinuationController, bool, HomeCatalogSession>(
      HomeCatalogContinuationController.new,
      retry: (count, error) => null,
      dependencies: const [],
    );

/// One view's manual paging latch and round-robin cursor. Catalog loaders retain
/// row/request ownership; the view resolves current row positions and focus.
class HomeCatalogContinuationController extends Notifier<bool> {
  HomeCatalogContinuationController(this.session);
  final HomeCatalogSession session;
  int _cursor = 0;
  int _lifetime = 0;

  @override
  bool build() {
    ref.onDispose(() => _lifetime++);
    return false;
  }

  bool get busy => ref.mounted && state;
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  /// Null means rejected synchronously. An accepted future includes latch
  /// release, including failures; the caller can then restore presentation focus.
  Future<void>? start({
    required bool moreCatalogs,
    required bool boardLoading,
    required List<CatalogSection> rows,
    required bool Function() hasMoreCatalogs,
    required bool Function() isCurrent,
    required Future<void> Function() loadMoreCatalogs,
    required Future<void> Function(CatalogSection) resumeRow,
  }) {
    if (!_active || busy || boardLoading || !isCurrent()) return null;
    final pending = rows.where((s) => s.pagingPaused && !s.exhausted).toList();
    if (pending.any((s) => s.loadingMore)) return null;
    final lifetime = _lifetime;
    state = true;
    return _run(
      moreCatalogs: moreCatalogs,
      pending: pending,
      lifetime: lifetime,
      hasMoreCatalogs: hasMoreCatalogs,
      isCurrent: isCurrent,
      loadMoreCatalogs: loadMoreCatalogs,
      resumeRow: resumeRow,
    );
  }

  Future<void> _run({
    required bool moreCatalogs,
    required List<CatalogSection> pending,
    required int lifetime,
    required bool Function() hasMoreCatalogs,
    required bool Function() isCurrent,
    required Future<void> Function() loadMoreCatalogs,
    required Future<void> Function(CatalogSection) resumeRow,
  }) async {
    bool current() => _active && lifetime == _lifetime && isCurrent();
    try {
      if (!current()) return;
      if (moreCatalogs) {
        if (hasMoreCatalogs()) await loadMoreCatalogs();
      } else if (pending.isNotEmpty) {
        final offset = _cursor % pending.length;
        final batch = [
          ...pending.skip(offset),
          ...pending.take(offset),
        ].take(4);
        _cursor = (offset + 4) % pending.length;
        for (final section in batch) {
          if (!current()) return;
          await resumeRow(section);
        }
      }
    } finally {
      // A retired operation cannot clear the latch of a newer provider lifetime.
      if (ref.mounted && lifetime == _lifetime) state = false;
    }
  }
}
