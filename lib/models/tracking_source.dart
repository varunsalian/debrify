/// Services that can own watched state or playback progress.
/// `ledger` is Debrify's own tracker (placeholder name, see
/// lib/features/ledger/models/ledger_brand.dart). The case NAME is persisted.
enum TrackingSource { local, trakt, simkl, mdblist, ledger }

/// The source used for resume, partial progress, and Continue Watching.
enum WatchProgressSource { smart, local, trakt, simkl, mdblist, ledger }

extension TrackingSourceStorageName on TrackingSource {
  String get storageName => name;

  static TrackingSource? parse(String value) {
    for (final source in TrackingSource.values) {
      if (source.name == value) return source;
    }
    return null;
  }
}
