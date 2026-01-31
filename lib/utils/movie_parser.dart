import 'dart:core';

/// Result of parsing a movie filename
class MovieInfo {
  final String? title;
  final int? year;
  final String? quality;
  final String? group;
  final bool hasYear;

  const MovieInfo({
    this.title,
    this.year,
    this.quality,
    this.group,
    required this.hasYear,
  });

  @override
  String toString() {
    if (title == null) return 'MovieInfo: (no title)';
    return 'MovieInfo: "$title" (${year ?? "no year"})';
  }
}

/// Parser for extracting movie metadata from filenames
///
/// Handles common movie filename patterns:
/// - Movie.Name.2024.1080p.BluRay.x264.mkv
/// - Movie Name (2024).mkv
/// - Movie.Name.2024.PROPER.1080p.WEB-DL.mkv
class MovieParser {
  // Year pattern: 4 digits starting with 19 or 20
  // Must be preceded by separator (dot, space, underscore, dash, or opening paren)
  static final RegExp _yearPattern = RegExp(
    r'[\.\s_\-\(](19\d{2}|20\d{2})(?:[\.\s_\-\)]|$)',
  );

  // Quality indicators
  static final RegExp _qualityPattern = RegExp(
    r'\b(2160p|1080p|720p|480p|4K|UHD|BluRay|BRRip|BDRip|WEBRip|WEB-DL|HDTV|DVDRip|HDRip)\b',
    caseSensitive: false,
  );

  // Release group pattern (typically at end after dash)
  static final RegExp _groupPattern = RegExp(r'-([A-Za-z0-9]+)(?:\.[a-zA-Z0-9]{3,4})?$');

  // Common quality/codec tags to remove
  static final RegExp _metadataPattern = RegExp(
    r'\b(REPACK|PROPER|INTERNAL|EXTENDED|UNRATED|DIRECTORS?\.?CUT|'
    r'x264|x265|H\.?264|H\.?265|HEVC|AVC|'
    r'AAC|AC3|DTS|Atmos|5\.1|7\.1|10bit|'
    r'AMZN|NF|HMAX|DSNP|ATVP|NETFLIX|AMAZON|'
    r'IMAX|3D|HDR|SDR|'
    r'Multi|Dual|Audio|Subs?|Subtitles?)\b',
    caseSensitive: false,
  );

  /// Parse a movie filename to extract title and year
  ///
  /// Returns MovieInfo with hasYear=true only if a valid year was found
  /// (per user requirement: only do movie lookup if filename has year pattern)
  static MovieInfo parseFilename(String filename) {
    // Remove file extension
    String name = _removeExtension(filename);

    // Try to find year pattern
    final yearMatch = _yearPattern.firstMatch(name);

    if (yearMatch == null) {
      // No year found - don't try to parse as movie
      return const MovieInfo(hasYear: false);
    }

    // Extract year
    final yearStr = yearMatch.group(1);
    final year = int.tryParse(yearStr ?? '');

    // Validate year is reasonable (not in the future, not too old)
    final currentYear = DateTime.now().year;
    if (year == null || year < 1900 || year > currentYear + 1) {
      return const MovieInfo(hasYear: false);
    }

    // Extract title: everything before the year
    final yearStartIndex = yearMatch.start;
    String title = name.substring(0, yearStartIndex);

    // Clean up the title
    title = _cleanTitle(title);

    if (title.isEmpty) {
      return MovieInfo(
        year: year,
        hasYear: true,
      );
    }

    // Extract quality
    final qualityMatch = _qualityPattern.firstMatch(name);
    final quality = qualityMatch?.group(1);

    // Extract release group
    final groupMatch = _groupPattern.firstMatch(name);
    final group = groupMatch?.group(1);

    return MovieInfo(
      title: title,
      year: year,
      quality: quality,
      group: group,
      hasYear: true,
    );
  }

  /// Check if a filename looks like a movie (has year pattern)
  static bool looksLikeMovie(String filename) {
    final name = _removeExtension(filename);
    return _yearPattern.hasMatch(name);
  }

  /// Remove file extension
  static String _removeExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot > 0) {
      final ext = filename.substring(lastDot + 1).toLowerCase();
      // Only remove known video extensions
      if (['mkv', 'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts', 'mpg', 'mpeg'].contains(ext)) {
        return filename.substring(0, lastDot);
      }
    }
    return filename;
  }

  /// Clean up extracted title
  static String _cleanTitle(String title) {
    String cleaned = title;

    // Replace dots and underscores with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[._]'), ' ');

    // Remove metadata tags
    cleaned = cleaned.replaceAll(_metadataPattern, ' ');

    // Remove release group in brackets
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]+\]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\{[^\}]+\}'), ' ');

    // Remove parentheses content that's not a year
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*[a-zA-Z][^)]*\)'), ' ');

    // Remove trailing dashes
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*$'), '');

    // Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Trim
    cleaned = cleaned.trim();

    // Remove trailing separator artifacts
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-_]+$'), '');

    return cleaned;
  }

  /// Clean movie title for search query
  /// More aggressive cleaning for API search
  static String cleanForSearch(String title) {
    String cleaned = title.toLowerCase();

    // Remove common articles for better matching
    cleaned = cleaned.replaceAll(RegExp(r'^(the|a|an)\s+'), '');

    // Remove special characters except spaces
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\s]'), ' ');

    // Collapse spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }
}
