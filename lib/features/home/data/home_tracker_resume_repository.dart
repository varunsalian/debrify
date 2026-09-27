import '../../../models/mdblist_continue_watching.dart';
import '../../../models/media_identity.dart';
import '../../../services/mdblist/mdblist_models.dart';

/// Catalog tracker positions for one mounted view/profile session.
/// Tracker services retain their own authentication, retries and feed caches.
class HomeTrackerResumeRepository {
  HomeTrackerResumeRepository({
    required this.readTraktMovie,
    required this.readSimklMovie,
    required this.readMdblist,
    required this.isOwnerCurrent,
    required this.now,
  });

  final Future<double?> Function(String id) readTraktMovie;
  final Future<double?> Function(String id) readSimklMovie;
  final Future<MdblistResult<MdblistContinueWatchingSnapshot>> Function()
  readMdblist;
  final bool Function() isOwnerCurrent;
  final DateTime Function() now;
  // A long-lived view must not retain every movie it has ever inspected.
  // Recency affects eviction only; reading an entry never extends its TTL.
  static const _maxTraktMemoEntries = 512;
  final Map<String, (double?, DateTime)> _traktMemo = {};
  bool _disposed = false;

  bool _current(bool Function() isCurrent) =>
      !_disposed && isOwnerCurrent() && isCurrent();

  /// Label and Play share this memo because Trakt's selection resolver does
  /// not cache its movie read. Cache nulls too; timestamp successful completion,
  /// preserve independent overlapping requests and the strict 30-second TTL.
  Future<double?> traktMovie(
    String id, {
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent) || id.isEmpty || !id.startsWith('tt')) return null;
    final memo = _traktMemo[id];
    if (memo != null &&
        now().difference(memo.$2) < const Duration(seconds: 30)) {
      _traktMemo.remove(id);
      _traktMemo[id] = memo;
      return memo.$1;
    }
    final value = await readTraktMovie(id);
    if (!_current(isCurrent)) return null;
    final percent = _resumableMovie(value);
    _traktMemo.remove(id);
    _traktMemo[id] = (percent, now());
    if (_traktMemo.length > _maxTraktMemoEntries) {
      _traktMemo.remove(_traktMemo.keys.first);
    }
    return percent;
  }

  Future<double?> simklMovie(
    String id, {
    required bool Function() isCurrent,
  }) async {
    if (!_current(isCurrent) ||
        id.isEmpty ||
        (!MediaIdentity.isImdb(id) && !MediaIdentity.isNative(id))) {
      return null;
    }
    final value = await readSimklMovie(id);
    return _current(isCurrent) ? _resumableMovie(value) : null;
  }

  /// Shared with the series reconciler: preserve case folding, movies-before-
  /// shows order, and first-match behavior even for partial usable snapshots.
  Future<MdblistContinueWatchingItem?> mdblistItem(
    String id, {
    required bool Function() isCurrent,
  }) async {
    id = id.toLowerCase();
    if (!_current(isCurrent) || !id.startsWith('tt')) return null;
    final result = await readMdblist();
    if (!_current(isCurrent) || !result.isUsable) return null;
    for (final candidate in [...result.data!.movies, ...result.data!.shows]) {
      if (candidate.selection.imdbId.toLowerCase() == id) return candidate;
    }
    return null;
  }

  Future<double?> mdblistMovie(
    String id, {
    required bool Function() isCurrent,
  }) async {
    final candidate = await mdblistItem(id, isCurrent: isCurrent);
    if (!_current(isCurrent) ||
        candidate == null ||
        !candidate.paused ||
        candidate.selection.isSeries) {
      return null;
    }
    final percent = candidate.selection.mdblistProgressPercent;
    if (percent == null || percent < 1 || percent >= 80) return null;
    return percent;
  }

  /// Match the existing player seek window: at least 1%, below 90%. The lower
  /// percent is conservative because catalog metadata has no movie duration;
  /// for a normal-length movie it exceeds the player's two-second minimum.
  static double? _resumableMovie(double? percent) {
    if (percent == null || percent < 1 || percent >= 90) return null;
    return percent;
  }

  void dispose() {
    _disposed = true;
    _traktMemo.clear();
  }
}
