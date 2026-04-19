import 'series_parser.dart';

class StremioEpisodeSelector {
  static final RegExp _seasonFolderPattern = RegExp(
    r'\bseason[\s._-]*(\d{1,2})\b',
    caseSensitive: false,
  );
  static final RegExp _shortSeasonFolderPattern = RegExp(r'^[sS](\d{1,2})$');
  static final RegExp _episodeFilePattern = RegExp(
    r'\b(?:episode|ep|e)[\s._-]*(\d{1,3})\b',
    caseSensitive: false,
  );
  static final RegExp _numericEpisodeFilePattern = RegExp(
    r'^(\d{1,3})(?:[\s._-]|$)',
  );

  static int? findEpisodeFileIndex(
    List<String> filenames, {
    required int season,
    required int episode,
  }) {
    final parsed = SeriesParser.parsePlaylist(filenames);
    for (int i = 0; i < parsed.length; i++) {
      if (parsed[i].season == season && parsed[i].episode == episode) {
        return i;
      }
    }

    for (int i = 0; i < filenames.length; i++) {
      final pathMatch = _matchEpisodeFromPath(filenames[i]);
      if (pathMatch == null) continue;
      if (pathMatch.$1 == season && pathMatch.$2 == episode) {
        return i;
      }
    }

    return null;
  }

  static int findLargestFileIndex(List<int?> sizes) {
    int largestIndex = 0;
    int largestSize = -1;

    for (int i = 0; i < sizes.length; i++) {
      final size = sizes[i] ?? 0;
      if (size > largestSize) {
        largestSize = size;
        largestIndex = i;
      }
    }

    return largestIndex;
  }

  static (int, int)? _matchEpisodeFromPath(String filename) {
    final normalized = filename.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.isEmpty) return null;

    int? extractedSeason;
    int? extractedEpisode;

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      extractedSeason ??= _extractSeason(segment);
      extractedEpisode ??= _extractEpisode(segment);
    }

    if (extractedEpisode == null && extractedSeason != null) {
      extractedEpisode = _extractNumericEpisodeFromFile(segments.last);
    }

    if (extractedSeason == null || extractedEpisode == null) {
      return null;
    }

    return (extractedSeason, extractedEpisode);
  }

  static int? _extractSeason(String value) {
    final match = _seasonFolderPattern.firstMatch(value);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }

    final shortMatch = _shortSeasonFolderPattern.firstMatch(value.trim());
    return int.tryParse(shortMatch?.group(1) ?? '');
  }

  static int? _extractEpisode(String value) {
    final match = _episodeFilePattern.firstMatch(value);
    return int.tryParse(match?.group(1) ?? '');
  }

  static int? _extractNumericEpisodeFromFile(String value) {
    final basename = value.split('/').last;
    final dotIndex = basename.lastIndexOf('.');
    final stem = dotIndex > 0 ? basename.substring(0, dotIndex) : basename;
    final match = _numericEpisodeFilePattern.firstMatch(stem.trim());
    return int.tryParse(match?.group(1) ?? '');
  }
}
