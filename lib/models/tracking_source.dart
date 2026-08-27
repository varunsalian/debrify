/// Services that can own watched state or playback progress.
enum TrackingSource { local, trakt, simkl, mdblist }

/// The source used for resume, partial progress, and Continue Watching.
enum WatchProgressSource { smart, local, trakt, simkl, mdblist }

extension TrackingSourceStorageName on TrackingSource {
  String get storageName => name;

  static TrackingSource? parse(String value) {
    for (final source in TrackingSource.values) {
      if (source.name == value) return source;
    }
    return null;
  }
}
