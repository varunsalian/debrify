/// Process-local freshness generations for episode tracker snapshots.
///
/// A successful playback/history mutation increments the affected title. The
/// guide coordinator includes this value in its cache identity, so the next
/// guide refresh cannot reuse a pre-mutation snapshot while repeated ordinary
/// opens still share the short-lived cache.
class EpisodeTrackerSnapshotRevision {
  EpisodeTrackerSnapshotRevision._();

  static final Map<String, int> _titleRevisions = <String, int>{};

  static String _provider(String value) => value.trim().toLowerCase();

  static String _titleKey(String provider, String imdbId) =>
      '${_provider(provider)}:${imdbId.trim().toLowerCase()}';

  static int identity(String provider, String imdbId) =>
      _titleRevisions[_titleKey(provider, imdbId)] ?? 0;

  static void invalidateTitle(String provider, String? imdbId) {
    final normalizedImdb = imdbId?.trim().toLowerCase();
    if (normalizedImdb == null || normalizedImdb.isEmpty) return;
    final normalizedProvider = _provider(provider);
    final key = _titleKey(normalizedProvider, normalizedImdb);
    _titleRevisions[key] = (_titleRevisions[key] ?? 0) + 1;
  }

  static void resetForTesting() {
    _titleRevisions.clear();
  }
}
