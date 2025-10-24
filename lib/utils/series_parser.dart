import 'dart:core';

class SeriesInfo {
  final String? title;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final int? year;
  final String? quality;
  final String? audioCodec;
  final String? videoCodec;
  final String? group;
  final bool isSeries;

  const SeriesInfo({
    this.title,
    this.season,
    this.episode,
    this.episodeTitle,
    this.year,
    this.quality,
    this.audioCodec,
    this.videoCodec,
    this.group,
    required this.isSeries,
  });

  @override
  String toString() {
    if (!isSeries) return 'Movie: $title';
    return 'Series: $title S${season?.toString().padLeft(2, '0')}E${episode?.toString().padLeft(2, '0')} - $episodeTitle';
  }
}

class SeriesParser {
  static final List<RegExp> _seasonEpisodePatterns = [
    // S01E02, S1E2, S01.E02, S1.E2
    RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})'),
    // 1x02, 01x02, 1.02, 01.02
    RegExp(r'(\d{1,2})[xX](\d{1,2})'),
    RegExp(r'(\d{1,2})\.(\d{1,2})'),
    // Season 1 Episode 2, Season 01 Episode 02
    RegExp(r'[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,2})'),
    // Episode 2, Ep 2, E02
    RegExp(r'[Ee]pisode\s*(\d{1,2})'),
    RegExp(r'[Ee]p\s*(\d{1,2})'),
    RegExp(r'[Ee](\d{1,2})'),
  ];

  static final List<RegExp> _titlePatterns = [
    // Common series title patterns
    RegExp(r'^(.+?)\s*[Ss](\d{1,2})[Ee](\d{1,2})'),
    RegExp(r'^(.+?)\s*(\d{1,2})[xX](\d{1,2})'),
    RegExp(r'^(.+?)\s*(\d{1,2})\.(\d{1,2})'),
  ];

  static final RegExp _yearPattern = RegExp(r'\((\d{4})\)');
  static final RegExp _qualityPattern = RegExp(r'(1080p|720p|480p|2160p|4K|HDRip|BRRip|WEBRip|BluRay|HDTV|DVDRip)');
  static final RegExp _audioCodecPattern = RegExp(r'(AAC|AC3|DTS|FLAC|MP3|OGG)');
  static final RegExp _videoCodecPattern = RegExp(r'(H\.264|H\.265|HEVC|AVC|XVID|DIVX)');
  static final RegExp _groupPattern = RegExp(r'-([A-Za-z0-9]+)$');

  static SeriesInfo parseFilename(String filename) {
    // Remove file extension
    final nameWithoutExt = _removeExtension(filename);
    
    // Try to extract season and episode
    int? season;
    int? episode;
    
    for (final pattern in _seasonEpisodePatterns) {
      final match = pattern.firstMatch(nameWithoutExt);
      if (match != null) {
        if (match.groupCount >= 2 &&
            _looksLikeResolutionMatch(
              nameWithoutExt,
              match,
              seasonGroupIndex: 1,
              episodeGroupIndex: 2,
            )) {
          continue;
        }
        if (match.groupCount >= 2) {
          season = int.tryParse(match.group(1) ?? '');
          episode = int.tryParse(match.group(2) ?? '');
        } else if (match.groupCount >= 1) {
          // For patterns like "Episode 2" or "E02", we need to infer season
          episode = int.tryParse(match.group(1) ?? '');
          // Try to find season from other patterns
          final seasonMatch = RegExp(r'[Ss](\d{1,2})').firstMatch(nameWithoutExt);
          if (seasonMatch != null) {
            season = int.tryParse(seasonMatch.group(1) ?? '');
          }
        }
        break;
      }
    }

    // Determine if it's a series early
    final isSeries = season != null || episode != null;

    // Extract title
    String? title;
    for (final pattern in _titlePatterns) {
      final match = pattern.firstMatch(nameWithoutExt);
      if (match != null) {
        if (match.groupCount >= 3 &&
            _looksLikeResolutionMatch(
              nameWithoutExt,
              match,
              seasonGroupIndex: 2,
              episodeGroupIndex: 3,
            )) {
          continue;
        }
        title = match.group(1)?.trim();
        break;
      }
    }

    // If no title found and it's a series, try to extract from the beginning
    if (title == null && isSeries) {
      final parts = nameWithoutExt.split(
        RegExp(r'[Ss]\d{1,2}[Ee]\d{1,2}|\d{1,2}[xX]\d{1,2}|\d{1,2}\.\d{1,2}'),
      );
      if (parts.isNotEmpty) {
        title = parts.first.trim();
      }
    }

    // For "Season X Episode Y" format, extract title before "Season"
    if (title != null && title.contains('Season')) {
      final seasonIndex = title.indexOf('Season');
      if (seasonIndex > 0) {
        title = title.substring(0, seasonIndex).trim();
      }
    }

    // For non-series files, try to extract title before year
    if (title == null && !isSeries) {
      final yearMatch = _yearPattern.firstMatch(nameWithoutExt);
      if (yearMatch != null) {
        final yearIndex = nameWithoutExt.indexOf(yearMatch.group(0)!);
        if (yearIndex > 0) {
          title = nameWithoutExt.substring(0, yearIndex).trim();
        }
      }
    }

    // Extract other metadata
    final year = _extractYear(nameWithoutExt);
    final quality = _extractQuality(nameWithoutExt);
    final audioCodec = _extractAudioCodec(nameWithoutExt);
    final videoCodec = _extractVideoCodec(nameWithoutExt);
    final group = _extractGroup(nameWithoutExt);

    return SeriesInfo(
      title: title,
      season: season,
      episode: episode,
      year: year,
      quality: quality,
      audioCodec: audioCodec,
      videoCodec: videoCodec,
      group: group,
      isSeries: isSeries,
    );
  }

  static String _removeExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot > 0) {
      return filename.substring(0, lastDot);
    }
    return filename;
  }

  static int? _extractYear(String text) {
    final match = _yearPattern.firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  static String? _extractQuality(String text) {
    final match = _qualityPattern.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractAudioCodec(String text) {
    final match = _audioCodecPattern.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractVideoCodec(String text) {
    final match = _videoCodecPattern.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractGroup(String text) {
    final match = _groupPattern.firstMatch(text);
    return match?.group(1);
  }

  static List<SeriesInfo> parsePlaylist(List<String> filenames) {
    return filenames.map((filename) => parseFilename(filename)).toList();
  }

  static bool isSeriesPlaylist(List<String> filenames) {
    final seriesCount = filenames.where((filename) {
      final info = parseFilename(filename);
      return info.isSeries;
    }).length;

    // Consider it a series if more than 50% of files are series episodes
    return seriesCount > filenames.length / 2;
  }

  static bool _looksLikeResolutionMatch(
    String source,
    RegExpMatch match, {
    required int seasonGroupIndex,
    required int episodeGroupIndex,
  }) {
    final text = match.group(0) ?? '';
    if (!text.contains(RegExp(r'[xX\.]'))) {
      return false;
    }

    bool isDigitAt(int index) {
      if (index < 0 || index >= source.length) return false;
      final codeUnit = source.codeUnitAt(index);
      return codeUnit >= 48 && codeUnit <= 57; // '0'..'9'
    }

    if (isDigitAt(match.start - 1) || isDigitAt(match.end)) {
      return true;
    }

    final seasonValue = int.tryParse(match.group(seasonGroupIndex) ?? '');
    final episodeValue = int.tryParse(match.group(episodeGroupIndex) ?? '');
    if (seasonValue != null && episodeValue != null) {
      if (seasonValue >= 60 || episodeValue >= 200) {
        return true;
      }
    }

    return false;
  }
}
