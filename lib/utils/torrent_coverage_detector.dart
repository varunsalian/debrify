import 'series_parser.dart';

/// Types of content coverage a torrent can provide
enum CoverageType {
  completeSeries,    // All seasons (S01-S12)
  multiSeasonPack,   // Multiple seasons (S01-S03)
  seasonPack,        // Single season pack
  singleEpisode,     // Individual episode
}

/// Detected coverage information for a torrent
class CoverageInfo {
  final CoverageType coverageType;
  final int? startSeason;
  final int? endSeason;
  final int? seasonNumber;
  final String transformedTitle;
  final String? episodeIdentifier; // e.g., "S01E01" for what's being played

  const CoverageInfo({
    required this.coverageType,
    this.startSeason,
    this.endSeason,
    this.seasonNumber,
    required this.transformedTitle,
    this.episodeIdentifier,
  });

  @override
  String toString() {
    return 'CoverageInfo(type: $coverageType, title: $transformedTitle)';
  }
}

/// Detects torrent coverage type and generates improved titles
class TorrentCoverageDetector {
  /// Detect coverage type from torrent title
  ///
  /// [title] - Raw torrent title (may contain release name + filename separated by \n)
  /// [infohash] - Torrent infohash for logging
  static CoverageInfo detectCoverage({
    required String title,
    String? infohash,
  }) {
    // Split title by newline - format is "release_name\nfilename"
    final parts = title.split('\n');
    final releaseName = parts.isNotEmpty ? parts[0].trim() : title;
    final filename = parts.length > 1 ? parts[1].trim() : '';

    final lowerRelease = releaseName.toLowerCase();
    final lowerFilename = filename.toLowerCase();

    // Detect coverage type from release name patterns
    CoverageType detectedType = CoverageType.singleEpisode; // Default
    int? startSeason;
    int? endSeason;
    int? seasonNumber;

    // Extract season range ONCE upfront to avoid redundant parsing
    final seasonRange = _extractSeasonRange(releaseName);

    // 1. Check for complete series patterns
    if (_isCompleteSeries(lowerRelease, preExtractedRange: seasonRange)) {
      detectedType = CoverageType.completeSeries;
      if (seasonRange != null) {
        startSeason = seasonRange['start'];
        endSeason = seasonRange['end'];
      }
    }
    // 2. Check for multi-season pack (S01-S03)
    else if (_isMultiSeasonPack(lowerRelease, preExtractedRange: seasonRange)) {
      detectedType = CoverageType.multiSeasonPack;
      if (seasonRange != null) {
        startSeason = seasonRange['start'];
        endSeason = seasonRange['end'];
      }
    }
    // 3. Check for single season pack
    else if (_isSeasonPack(lowerRelease, lowerFilename)) {
      detectedType = CoverageType.seasonPack;
      seasonNumber = _extractSingleSeason(releaseName);
    }
    // 4. Otherwise, it's a single episode (default)

    // Generate transformed title
    final transformedTitle = _generateTransformedTitle(
      releaseName: releaseName,
      filename: filename,
      coverageType: detectedType,
      startSeason: startSeason,
      endSeason: endSeason,
      seasonNumber: seasonNumber,
    );

    // Extract episode identifier if applicable (for packs where filename indicates specific episode)
    String? episodeIdentifier;
    if (filename.isNotEmpty &&
        (detectedType == CoverageType.completeSeries ||
         detectedType == CoverageType.multiSeasonPack ||
         detectedType == CoverageType.seasonPack)) {
      episodeIdentifier = _extractEpisodeIdentifier(filename);
    }

    final result = CoverageInfo(
      coverageType: detectedType,
      startSeason: startSeason,
      endSeason: endSeason,
      seasonNumber: seasonNumber,
      transformedTitle: transformedTitle,
      episodeIdentifier: episodeIdentifier,
    );

    return result;
  }

  /// Check if release name indicates complete series
  static bool _isCompleteSeries(String lowerName, {Map<String, int>? preExtractedRange}) {
    // FIRST: Check if this is actually a season pack (takes priority)
    // "The Complete Season X" or "Complete Season X" is a SEASON pack, not complete series
    // But "Complete Season 1,2,3,4,5" or "Complete Seasons 1-8" IS complete series
    if (RegExp(r'complete\s+season\s+\d+\s*[\[\(]', caseSensitive: false).hasMatch(lowerName)) {
      return false; // "Complete Season 3 [HDTV]" - single season
    }
    if (RegExp(r'complete\s+season\s+\d+\s*$', caseSensitive: false).hasMatch(lowerName)) {
      return false; // "Complete Season 3" at end - single season
    }

    // String patterns to check
    final stringPatterns = [
      'complete.series',
      'complete series',
      'complete_series',
      'complete.collection',
      'complete collection',
      'all.seasons',
      'all seasons',
      'all_seasons',
      'the.complete.series',
      'the complete series',
      'the.complete.collection',
      'the complete collection',
      'full.series',
      'full series',
      'entire.series',
      'entire series',
      'box.set',
      'box set',
      'boxset',
      'anthology',
      'saga',
      // Non-English - Spanish
      'serie completa',
      'series completa',
      'todas las temporadas',
      // Non-English - Italian
      'serie completa',
      'tutta la serie',
      'tutte le stagioni',
      // Non-English - German
      'komplette serie',
      'serien komplett',
      'alle staffeln',
      // Non-English - French
      'integrale',
      'série complète',
      'serie complete',
      'toutes les saisons',
      // Non-English - Dutch
      'complete serie',
      'alle seizoenen',
      // Non-English - Portuguese
      'serie completa',
      'todas as temporadas',
    ];

    for (final pattern in stringPatterns) {
      if (lowerName.contains(pattern)) return true;
    }

    // Check for standalone "COMPLETE" but NOT if it's a single season pack
    // e.g., "Game of Thrones (2011) Complete [2160p]" = complete series
    // e.g., "Game of Thrones S01 Complete" = season pack (NOT complete series)
    // e.g., "Game of Thrones S01-S08 Complete" = complete series (has range)
    if (RegExp(r'\bcomplete\b', caseSensitive: false).hasMatch(lowerName)) {
      // First check if there's a season RANGE - if so, it's complete series
      final hasSeasonRange =
          RegExp(r's\d{1,2}\s*-\s*s?\d{1,2}', caseSensitive: false).hasMatch(lowerName) ||
          RegExp(r'seasons?\s*\d{1,2}\s*-\s*\d{1,2}', caseSensitive: false).hasMatch(lowerName) ||
          RegExp(r'seasons?\s*\d{1,2}\s*(?:to|thru|through)\s*\d{1,2}', caseSensitive: false).hasMatch(lowerName);

      if (hasSeasonRange) {
        return true; // Has season range + complete = complete series
      }

      // Check if this is actually a single season pack (has single season indicator, no range)
      // Patterns like "S01 Complete", "Season 1 Complete"
      final hasSingleSeasonIndicator =
          RegExp(r'\bs\d{1,2}\b', caseSensitive: false).hasMatch(lowerName) ||
          RegExp(r'\bseason\s*\d{1,2}\b', caseSensitive: false).hasMatch(lowerName);

      // Only return true if NO single season indicator (pure "complete" like "Show (2011) Complete")
      if (!hasSingleSeasonIndicator) {
        return true;
      }
    }

    // Check for wide season range (3+ seasons = definitely complete)
    // Use pre-extracted range if available to avoid redundant parsing
    final range = preExtractedRange ?? _extractSeasonRange(lowerName);
    if (range != null) {
      final start = range['start'];
      final end = range['end'];
      if (start != null && end != null && (end - start) >= 2) {
        return true;
      }
    }

    return false;
  }

  /// Check if release name indicates multi-season pack
  static bool _isMultiSeasonPack(String lowerName, {Map<String, int>? preExtractedRange}) {
    // Must have season range but not complete series
    final range = preExtractedRange ?? _extractSeasonRange(lowerName);
    if (range == null) return false;

    final start = range['start'];
    final end = range['end'];
    if (start == null || end == null) return false;

    // Multi-season is 2+ seasons (end - start >= 1 means at least 2 seasons)
    // But not marked as "complete" via keywords
    // Pass pre-extracted range to avoid redundant parsing
    return (end - start) >= 1 && !_isCompleteSeries(lowerName, preExtractedRange: range);
  }

  /// Check if release name indicates season pack
  static bool _isSeasonPack(String lowerRelease, String lowerFilename) {
    // String patterns - English
    final stringPatterns = [
      'season.pack',
      'season pack',
      'season_pack',
      'full.season',
      'full season',
      'complete.season',
      'complete season',
      'entire.season',
      'entire season',
      // Non-English - Spanish
      'temporada completa',
      'temporada.completa',
      // Non-English - German
      'staffel komplett',
      'staffel.komplett',
      'komplette staffel',
      // Non-English - French
      'saison complete',
      'saison.complete',
      'saison complète',
      // Non-English - Italian
      'stagione completa',
      'stagione.completa',
      // Non-English - Portuguese
      'temporada completa',
      // Non-English - Dutch
      'seizoen compleet',
      'volledig seizoen',
    ];

    for (final pattern in stringPatterns) {
      if (lowerRelease.contains(pattern)) return true;
    }

    // Regex patterns
    final regexPatterns = [
      RegExp(r's\d{1,2}\.complete', caseSensitive: false),
      RegExp(r's\d{1,2}\s+complete', caseSensitive: false),
      RegExp(r'season\s*\d+\s*complete', caseSensitive: false),
      RegExp(r'season\s*\d+\s*full', caseSensitive: false),
      // Non-English season patterns
      RegExp(r'temporada\s*\d+\s*completa', caseSensitive: false), // Spanish
      RegExp(r'staffel\s*\d+\s*komplett', caseSensitive: false),   // German
      RegExp(r'saison\s*\d+\s*compl[eè]te', caseSensitive: false), // French
      RegExp(r'stagione\s*\d+\s*completa', caseSensitive: false),  // Italian
      // "S01 [1080p]" without episode number often indicates pack
      // But exclude if it's part of a range like "S01-S03" or "S01-03"
      RegExp(r'\bs\d{1,2}\b(?!\s*-\s*s?\d)(?!\s*e\d)', caseSensitive: false),
    ];

    for (final pattern in regexPatterns) {
      if (pattern.hasMatch(lowerRelease)) return true;
    }

    // Check if filename has folder structure (e.g., "Show.S01/Show.S01E01.mkv")
    if (lowerFilename.contains('/')) {
      // Has folder structure - likely a pack
      return true;
    }

    return false;
  }

  /// Extract season range from release name (e.g., S01-S12 → {start: 1, end: 12})
  static Map<String, int>? _extractSeasonRange(String text) {
    final lowerText = text.toLowerCase();

    // List of patterns to try in order of specificity
    final patterns = [
      // S01-S12, S1-S9, S01 - S12 (MUST have S before both numbers)
      RegExp(r's(\d{1,2})\s*-\s*s(\d{1,2})', caseSensitive: false),
      // [S01-S08] or [S01-08] with brackets
      RegExp(r'\[s(\d{1,2})\s*-\s*s?(\d{1,2})\]', caseSensitive: false),
      // S01-08 format (second S optional) - but NOT followed by more digits (avoid 720p)
      // Must be followed by word boundary, space, or end
      RegExp(r's(\d{1,2})\s*-\s*(\d{1,2})(?:\s|$|\.|\]|\))', caseSensitive: false),
      // S01 to S12, S1 to S9 (with "to" keyword)
      RegExp(r's(\d{1,2})\s+to\s+s(\d{1,2})', caseSensitive: false),
      // Seasons 1-8, Season 1-8
      RegExp(r'seasons?\s*(\d{1,2})\s*-\s*(\d{1,2})', caseSensitive: false),
      // Season.1-8 (dot separated)
      RegExp(r'season\.(\d{1,2})\s*-\s*(\d{1,2})', caseSensitive: false),
      // Seasons 1 to 8, Seasons 1 thru 8, Seasons 1 through 8
      RegExp(r'seasons?\s*(\d{1,2})\s*(?:to|thru|through)\s*(\d{1,2})', caseSensitive: false),
      // Seasons 1 & 2, Seasons 1 and 2 (for 2-season packs)
      RegExp(r'seasons?\s*(\d{1,2})\s*(?:&|and)\s*(\d{1,2})', caseSensitive: false),
      // Series 1-8
      RegExp(r'series\s*(\d{1,2})\s*-\s*(\d{1,2})', caseSensitive: false),
      // 1ª a 8ª Temporada (ordinal format - Portuguese/Spanish)
      RegExp(r'(\d{1,2})ª?\s*a\s*(\d{1,2})ª?\s*temporada', caseSensitive: false),
      // Non-English - Spanish: Temporadas 1-8, Temporada 1 a 8
      RegExp(r'temporadas?\s*(\d{1,2})\s*(?:-|a)\s*(\d{1,2})', caseSensitive: false),
      // Non-English - German: Staffeln 1-8, Staffel 1 bis 8
      RegExp(r'staffeln?\s*(\d{1,2})\s*(?:-|bis)\s*(\d{1,2})', caseSensitive: false),
      // Non-English - French: Saisons 1-8, Saison 1 à 8
      RegExp(r'saisons?\s*(\d{1,2})\s*(?:-|[àa])\s*(\d{1,2})', caseSensitive: false),
      // Non-English - Italian: Stagioni 1-8, Stagione 1 a 8
      RegExp(r'stagion[ei]\s*(\d{1,2})\s*(?:-|a)\s*(\d{1,2})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        final start = int.tryParse(match.group(1)!);
        final end = int.tryParse(match.group(2)!);
        // Validate: end > start, and reasonable season numbers (max 50)
        // This prevents matching "720p" as season 72
        if (start != null && end != null && end > start && end <= 50) {
          return {'start': start, 'end': end};
        }
      }
    }

    return null;
  }

  /// Extract single season number from release name
  static int? _extractSingleSeason(String text) {
    // Match S01, S1, Season 1, etc. in multiple languages
    final patterns = [
      RegExp(r's(\d{1,2})(?:[^-]|$)', caseSensitive: false),
      RegExp(r'season\s*(\d{1,2})', caseSensitive: false),
      // Non-English
      RegExp(r'temporada\s*(\d{1,2})', caseSensitive: false),  // Spanish/Portuguese
      RegExp(r'staffel\s*(\d{1,2})', caseSensitive: false),    // German
      RegExp(r'saison\s*(\d{1,2})', caseSensitive: false),     // French
      RegExp(r'stagione\s*(\d{1,2})', caseSensitive: false),   // Italian
      RegExp(r'seizoen\s*(\d{1,2})', caseSensitive: false),    // Dutch
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }

    return null;
  }

  /// Extract episode identifier from filename (e.g., S01E01)
  static String? _extractEpisodeIdentifier(String filename) {
    // Match S01E01, S1E1, etc.
    final pattern = RegExp(r's(\d{1,2})e(\d{1,3})', caseSensitive: false);
    final match = pattern.firstMatch(filename);

    if (match != null) {
      final season = match.group(1)!.padLeft(2, '0');
      final episode = match.group(2)!.padLeft(2, '0');
      return 'S${season}E$episode';
    }

    return null;
  }

  /// Generate transformed title based on coverage type
  static String _generateTransformedTitle({
    required String releaseName,
    required String filename,
    required CoverageType coverageType,
    int? startSeason,
    int? endSeason,
    int? seasonNumber,
  }) {
    // Extract series name using existing parser
    final cleanedName = SeriesParser.cleanCollectionTitle(releaseName);

    // Extract quality info
    final quality = _extractQuality(releaseName);
    final hdr = _extractHdr(releaseName);
    final codec = _extractCodec(releaseName);

    String qualityStr = '';
    if (quality != null) qualityStr += quality;
    if (hdr != null) {
      qualityStr += qualityStr.isEmpty ? hdr : ' $hdr';
    }
    if (codec != null) {
      qualityStr += qualityStr.isEmpty ? codec : ' $codec';
    }

    // Build coverage description
    String coverageDesc = '';

    switch (coverageType) {
      case CoverageType.completeSeries:
        if (startSeason != null && endSeason != null) {
          coverageDesc = 'Complete Series S${startSeason.toString().padLeft(2, '0')}-S${endSeason.toString().padLeft(2, '0')}';
        } else {
          coverageDesc = 'Complete Series';
        }
        break;

      case CoverageType.multiSeasonPack:
        if (startSeason != null && endSeason != null) {
          coverageDesc = 'Seasons $startSeason-$endSeason';
        } else {
          coverageDesc = 'Multi-Season Pack';
        }
        break;

      case CoverageType.seasonPack:
        if (seasonNumber != null) {
          coverageDesc = 'Season $seasonNumber Complete';
        } else {
          coverageDesc = 'Season Pack';
        }
        break;

      case CoverageType.singleEpisode:
        // For single episodes, extract S01E01 from release name
        final episodeId = _extractEpisodeIdentifier(releaseName);
        if (episodeId != null) {
          coverageDesc = episodeId;
        } else {
          // Fallback to original name
          return releaseName;
        }
        break;
    }

    // Assemble final title
    // Clean up cleanedName - remove trailing dashes/separators and orphan words
    String trimmedName = cleanedName
        .replaceAll(RegExp(r'\s*-\s*$'), '')           // Remove trailing " - "
        .replaceAll(RegExp(r'\s+The\s*$', caseSensitive: false), '')  // Remove trailing orphan "The"
        .replaceAll(RegExp(r'\s+'), ' ')               // Normalize spaces
        .trim();

    // Also remove common orphan words at the end (from partial metadata removal)
    trimmedName = trimmedName
        .replaceAll(RegExp(r'\s+(?:The|A|An)\s*$', caseSensitive: false), '')
        .trim();

    final parts = <String>[];
    if (trimmedName.isNotEmpty) parts.add(trimmedName);
    if (coverageDesc.isNotEmpty) parts.add(coverageDesc);
    if (qualityStr.isNotEmpty) parts.add(qualityStr);

    // Join and clean up any double dashes that might remain
    return parts.join(' - ').replaceAll(RegExp(r'\s*-\s*-\s*'), ' - ');
  }

  /// Extract quality from release name
  static String? _extractQuality(String text) {
    // Prioritize specific resolutions over generic terms
    // Check for specific resolutions first (most reliable)
    final specificPattern = RegExp(
      r'\b(2160p|1080p|720p|480p|360p)\b',
      caseSensitive: false,
    );
    final specificMatch = specificPattern.firstMatch(text);
    if (specificMatch != null) {
      return specificMatch.group(1);
    }

    // Then check for quality keywords
    final qualityPattern = RegExp(
      r'\b(4K|UHD|FHD|Remux)\b',
      caseSensitive: false,
    );
    final qualityMatch = qualityPattern.firstMatch(text);
    final quality = qualityMatch?.group(1);

    // Normalize quality names
    if (quality != null) {
      final lower = quality.toLowerCase();
      if (lower == '4k' || lower == 'uhd') {
        return '2160p';
      } else if (lower == 'fhd') {
        return '1080p';
      } else if (lower == 'remux') {
        return 'Remux';
      }
      return quality;
    }
    return null;
  }

  /// Extract HDR format from release name
  static String? _extractHdr(String text) {
    final pattern = RegExp(
      r'\b(HDR10\+?|HDR|DV|Dolby\.?Vision|DoVi)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    final hdr = match?.group(1);

    // Normalize HDR names
    if (hdr != null) {
      final lower = hdr.toLowerCase().replaceAll('.', '');
      if (lower == 'dv' || lower == 'dolbyvision' || lower == 'dovi') {
        return 'DV';
      } else if (lower == 'hdr10+' || lower == 'hdr10plus') {
        return 'HDR10+';
      } else if (lower == 'hdr10') {
        return 'HDR10';
      } else if (lower == 'hdr') {
        return 'HDR';
      }
      return hdr;
    }
    return null;
  }

  /// Extract codec from release name
  static String? _extractCodec(String text) {
    final pattern = RegExp(
      r'\b(x265|x264|HEVC|H\.?265|H\.?264|AVC|AV1|VP9)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    final codec = match?.group(1);

    // Normalize codec names
    if (codec != null) {
      final lower = codec.toLowerCase().replaceAll('.', '');
      if (lower == 'hevc' || lower == 'h265') {
        return 'x265';
      } else if (lower == 'avc' || lower == 'h264') {
        return 'x264';
      } else if (lower == 'av1') {
        return 'AV1';
      } else if (lower == 'vp9') {
        return 'VP9';
      }
      return codec;
    }

    return null;
  }

  /// Get sort priority for coverage type (lower = better)
  static int getSortPriority(CoverageType type) {
    switch (type) {
      case CoverageType.completeSeries:
        return 0;
      case CoverageType.multiSeasonPack:
        return 1;
      case CoverageType.seasonPack:
        return 2;
      case CoverageType.singleEpisode:
        return 3;
    }
  }
}
