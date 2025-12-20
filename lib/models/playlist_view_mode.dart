import '../utils/series_parser.dart';

/// Defines how a playlist should be displayed and organized in the video player
enum PlaylistViewMode {
  /// Display playlist as-is without sorting or series organization
  /// Files shown in original order as a flat movie collection
  /// Same as 'sorted' mode but preserves original file order
  raw,

  /// Sort files alphabetically but don't organize into series structure
  /// Useful for movie collections or unsorted content
  sorted,

  /// Detect and organize content as a TV series with seasons and episodes
  /// Uses SeriesParser to analyze filenames and create hierarchical structure
  series,
}

extension PlaylistViewModeExtension on PlaylistViewMode {
  /// Convert viewMode to forceSeries parameter for SeriesPlaylist
  /// - raw: false (force non-series - flat movie collection, preserves original order)
  /// - sorted: false (force non-series - sorted movie collection)
  /// - series: true (force series detection)
  bool? toForceSeries() {
    switch (this) {
      case PlaylistViewMode.raw:
        return false; // Force non-series (flat movie collection, preserves original order)
      case PlaylistViewMode.sorted:
        return false; // Force non-series (movie collection mode)
      case PlaylistViewMode.series:
        return true;
    }
  }

  /// Convert viewMode to disableSorting parameter
  /// - raw: true (disable sorting)
  /// - sorted: false (enable sorting)
  /// - series: false (enable sorting)
  bool toDisableSorting() {
    switch (this) {
      case PlaylistViewMode.raw:
        return true;
      case PlaylistViewMode.sorted:
        return false;
      case PlaylistViewMode.series:
        return false;
    }
  }

  /// Get human-readable label for UI display
  String get label {
    switch (this) {
      case PlaylistViewMode.raw:
        return 'Raw';
      case PlaylistViewMode.sorted:
        return 'Sorted';
      case PlaylistViewMode.series:
        return 'Series';
    }
  }

  /// Convert to contentType string for Android TV player
  String toContentType() {
    switch (this) {
      case PlaylistViewMode.series:
        return 'series';
      case PlaylistViewMode.sorted:
        return 'collection';
      case PlaylistViewMode.raw:
        return 'raw';
    }
  }
}

/// Helper function to determine viewMode from isSeries boolean
/// Used for migrating existing code
PlaylistViewMode? viewModeFromIsSeries(bool? isSeries) {
  if (isSeries == null) return null;
  return isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted;
}

/// Helper function to auto-detect viewMode from filenames
PlaylistViewMode autoDetectViewMode(List<String> filenames) {
  final isSeries = SeriesParser.isSeriesPlaylist(filenames);
  return isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted;
}
