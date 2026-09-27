import '../../../services/hide_watched_prefs.dart';
import '../../../services/home_return_cache.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/watched_status_service.dart';
import '../models/home_return_snapshot.dart';

/// Adapters borrow one process-lifetime cache and invalidation subscription pair.
/// Retain this plain adapter for disposal; it never needs a WidgetRef then.
class HomeReturnRepository {
  const HomeReturnRepository({required this.owner});
  final ProfileSessionOwner owner;
  static final _cache = HomeReturnCache<HomeReturnSnapshot>();
  static bool _observing = false;

  int get revision => HomeReturnCache.revision;

  HomeReturnSnapshot? take({DateTime? now}) =>
      owner == ProfileSessionMemory.captureOwner()
      ? _cache.take(owner, now: now)
      : null;

  void store(HomeReturnSnapshot snapshot, {required int revision}) => _cache
      .store(owner, snapshot, revision: revision, loadedAt: snapshot.loadedAt);

  /// Called only by Home, at the same first-mount point as the legacy view.
  void observeInvalidation() {
    if (_observing) return;
    _observing = true;
    MetadataPreferencesService.revision.addListener(HomeReturnCache.invalidate);
    WatchedStatusService.instance.addListener(_watchedChanged);
  }

  static void _watchedChanged() {
    if (HideWatchedPrefs.enabled) HomeReturnCache.invalidate();
  }
}
