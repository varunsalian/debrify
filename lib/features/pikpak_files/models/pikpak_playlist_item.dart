import 'package:debrify/utils/series_parser.dart';

/// Helper class for building PikPak playlists
class PikPakPlaylistItem {
  final Map<String, dynamic> file;
  final int originalIndex;
  final SeriesInfo seriesInfo;
  final String displayName;

  const PikPakPlaylistItem({
    required this.file,
    required this.originalIndex,
    required this.seriesInfo,
    required this.displayName,
  });
}
