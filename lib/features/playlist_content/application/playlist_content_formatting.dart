import 'package:debrify/models/webdav_item.dart';

/// Format air date from "YYYY-MM-DD" to "Mon DD, YYYY" (e.g. "Feb 10, 2023")
String formatAirDate(String airDate) {
  try {
    final date = DateTime.parse(airDate);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  } catch (_) {
    return airDate;
  }
}

bool hasWebDavCredentials(WebDavConfig config) {
  return config.username.isNotEmpty || config.password.isNotEmpty;
}

/// Clean Torbox path by removing "TorrentName..." prefix
/// Example: "TorrentName.../Season 1/Episode 1.mkv" -> "Season 1/Episode 1.mkv"
String? cleanTorboxPath(String? path) {
  if (path == null) return null;

  // Step 1: Remove "TorrentName..." prefix
  String cleanedPath = path;
  if (path.contains('.../')) {
    final parts = path.split('.../');
    if (parts.length > 1) {
      cleanedPath = parts.skip(1).join('.../');
    }
  }

  // Step 2: Strip first-level folder for Torbox files
  // Example: "Chapter_1-Introduction/1. Introduction.mp4" -> "1. Introduction.mp4"
  final firstSlash = cleanedPath.indexOf('/');
  if (firstSlash > 0) {
    cleanedPath = cleanedPath.substring(firstSlash + 1);
  }

  return cleanedPath;
}
