import 'package:flutter/foundation.dart';
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

    // 1. Check for complete series patterns
    if (_isCompleteSeries(lowerRelease)) {
      detectedType = CoverageType.completeSeries;
      final seasonRange = _extractSeasonRange(releaseName);
      if (seasonRange != null) {
        startSeason = seasonRange['start'];
        endSeason = seasonRange['end'];
      }
    }
    // 2. Check for multi-season pack (S01-S03)
    else if (_isMultiSeasonPack(lowerRelease)) {
      detectedType = CoverageType.multiSeasonPack;
      final seasonRange = _extractSeasonRange(releaseName);
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

    // Extract episode identifier if applicable
    String? episodeIdentifier;
    if (filename.isNotEmpty &&
        (detectedType == CoverageType.completeSeries ||
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
  static bool _isCompleteSeries(String lowerName) {
    final patterns = [
      'complete.series',
      'complete series',
      'complete_series',
      'all.seasons',
      'all seasons',
      'all_seasons',
      'the.complete',
      'the complete',
    ];

    for (final pattern in patterns) {
      if (lowerName.contains(pattern)) return true;
    }

    // Check for wide season range (3+ seasons)
    final range = _extractSeasonRange(lowerName);
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
  static bool _isMultiSeasonPack(String lowerName) {
    // Must have season range but not complete series
    final range = _extractSeasonRange(lowerName);
    if (range == null) return false;

    final start = range['start'];
    final end = range['end'];
    if (start == null || end == null) return false;

    // Multi-season is 2+ seasons but not marked as "complete"
    return (end - start) >= 1 && !_isCompleteSeries(lowerName);
  }

  /// Check if release name indicates season pack
  static bool _isSeasonPack(String lowerRelease, String lowerFilename) {
    // Check for season pack keywords
    final patterns = [
      'season.pack',
      'season pack',
      'season_pack',
      RegExp(r's\d{1,2}\.complete'),
      RegExp(r'season\s*\d+\s*complete'),
    ];

    for (final pattern in patterns) {
      if (pattern is String) {
        if (lowerRelease.contains(pattern)) return true;
      } else if (pattern is RegExp) {
        if (pattern.hasMatch(lowerRelease)) return true;
      }
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
    // Match patterns like: S01-S12, S1-S9, S01 - S12
    final pattern = RegExp(r's(\d{1,2})\s*-\s*s(\d{1,2})', caseSensitive: false);
    final match = pattern.firstMatch(text);

    if (match != null) {
      final start = int.tryParse(match.group(1)!);
      final end = int.tryParse(match.group(2)!);
      if (start != null && end != null && end > start) {
        return {'start': start, 'end': end};
      }
    }

    return null;
  }

  /// Extract single season number from release name
  static int? _extractSingleSeason(String text) {
    // Match S01, S1, Season 1, etc.
    final patterns = [
      RegExp(r's(\d{1,2})(?:[^-]|$)', caseSensitive: false),
      RegExp(r'season\s*(\d{1,2})', caseSensitive: false),
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
    final codec = _extractCodec(releaseName);

    String qualityStr = '';
    if (quality != null) qualityStr += quality;
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
    final parts = <String>[cleanedName];
    if (coverageDesc.isNotEmpty) parts.add(coverageDesc);
    if (qualityStr.isNotEmpty) parts.add(qualityStr);

    return parts.join(' - ');
  }

  /// Extract quality from release name
  static String? _extractQuality(String text) {
    final pattern = RegExp(
      r'\b(2160p|1080p|720p|480p|4K|UHD)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }

  /// Extract codec from release name
  static String? _extractCodec(String text) {
    final pattern = RegExp(
      r'\b(x265|x264|HEVC|H\.265|H\.264|AVC)\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    final codec = match?.group(1);

    // Normalize codec names
    if (codec != null) {
      final lower = codec.toLowerCase();
      if (lower == 'hevc' || lower == 'h.265' || lower == 'h265') {
        return 'x265';
      } else if (lower == 'avc' || lower == 'h.264' || lower == 'h264') {
        return 'x264';
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
