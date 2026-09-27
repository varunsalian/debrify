import '../../../models/mdblist_continue_watching.dart';
import '../../../services/mdblist/mdblist_models.dart';

/// Coordinates existing invalidation and feed services without owning caches.
class HomeMdblistContinuationRepository {
  const HomeMdblistContinuationRepository({
    required void Function() invalidate,
    required Future<bool> Function() synchronizeInvalidations,
    required Future<MdblistResult<MdblistContinueWatchingSnapshot>> Function({
      required bool force,
    })
    fetch,
  }) : _invalidate = invalidate,
       _synchronizeInvalidations = synchronizeInvalidations,
       _fetch = fetch;

  final void Function() _invalidate;
  void invalidate() => _invalidate();

  final Future<bool> Function() _synchronizeInvalidations;
  final Future<MdblistResult<MdblistContinueWatchingSnapshot>> Function({
    required bool force,
  })
  _fetch;

  /// Null means retirement before fetch. Once fetched, the caller retains the
  /// result kind for its existing layout wait and discarded-result diagnostic.
  Future<MdblistResult<MdblistContinueWatchingSnapshot>?> read({
    required bool force,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    // A false poll result still permits the existing cached/partial feed path.
    await _synchronizeInvalidations();
    if (!isCurrent()) return null;
    return _fetch(force: force);
  }
}
