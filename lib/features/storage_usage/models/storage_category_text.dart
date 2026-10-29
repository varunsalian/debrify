// Names and explanations for the storage categories, plus byte formatting.
// Shared by the page and by the copied text report.
import 'storage_usage_models.dart';

extension StorageCategoryText on StorageCategory {
  String get label => switch (this) {
    StorageCategory.iptvCatalogs => 'IPTV catalogs & guide',
    StorageCategory.debrifyTv => 'Debrify TV channels',
    StorageCategory.imageCache => 'Image cache',
    StorageCategory.guideDownloads => 'Guide downloads in progress',
    StorageCategory.guideCache => 'Guide cache',
    StorageCategory.recordings => 'Recordings',
    StorageCategory.downloads => 'Downloads',
    StorageCategory.logs => 'Diagnostic logs',
    StorageCategory.preferences => 'Settings',
    StorageCategory.otherDatabases => 'Other databases',
    StorageCategory.other => 'Other app files',
  };

  /// What the files are and what makes them grow.
  String get explanation => switch (this) {
    StorageCategory.iptvCatalogs =>
      'Every IPTV playlist\'s channels, movies, series and TV guide, saved '
          'so lists open instantly. Each profile keeps its own copy, so '
          'several profiles using the same playlist store it several times.',
    StorageCategory.debrifyTv =>
      'Your Debrify TV channels and the items cached for them.',
    StorageCategory.imageCache =>
      'Posters, backdrops and channel logos kept so they load without '
          'downloading again. Capped in size and cleaned up automatically.',
    StorageCategory.guideDownloads =>
      'TV guide files being downloaded. They are deleted when the download '
          'finishes; files left here come from a download that was '
          'interrupted. On Android the app removes them when it starts, once '
          'they are a day old.',
    StorageCategory.guideCache =>
      'Recently loaded TV guide data. Files unused for a week are removed '
          'the next time a guide loads.',
    StorageCategory.recordings =>
      'Recordings saved inside the app\'s own storage. Recordings saved to '
          'a folder you picked are not counted here.',
    StorageCategory.downloads =>
      'Downloaded files kept inside the app\'s own storage.',
    StorageCategory.logs =>
      'Diagnostic logs for bug reports: the last two hours, and important '
          'events from the last day.',
    StorageCategory.preferences =>
      'Your settings and preferences for every profile.',
    StorageCategory.otherDatabases =>
      'Smaller databases, such as the profile list and the download queue.',
    StorageCategory.other =>
      'App files that fit none of the groups above, such as search engines '
          'and the app\'s working files.',
  };
}

/// "0 B", "512 KB", "1.4 MB", "2.31 GB".
String formatStorageBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  if (bytes >= mb) {
    final value = bytes / mb;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
  }
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes B';
}
