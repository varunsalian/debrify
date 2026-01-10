import 'dart:core';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Classification of playlist content type
enum PlaylistClassification {
  SERIES,     // High confidence it's a TV series
  MOVIES,     // High confidence it's a movie collection
  AMBIGUOUS,  // Could be either
}

/// Analysis result for playlist content
class PlaylistAnalysis {
  final double confidenceScore;      // 0-100
  final PlaylistClassification classification;
  final String detectionMethod;      // Primary method used for detection
  final Map<String, double> scores;  // Individual score breakdown

  const PlaylistAnalysis({
    required this.confidenceScore,
    required this.classification,
    required this.detectionMethod,
    required this.scores,
  });
}

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
  final double? confidence;  // Confidence score for series detection
  final int? fileSize;        // File size in bytes for duplicate resolution

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
    this.confidence,
    this.fileSize,
  });

  @override
  String toString() {
    if (!isSeries) return 'Movie: $title';
    return 'Series: $title S${season?.toString().padLeft(2, '0')}E${episode?.toString().padLeft(2, '0')} - $episodeTitle';
  }

  /// Create a copy with updated fields
  SeriesInfo copyWith({
    String? title,
    int? season,
    int? episode,
    String? episodeTitle,
    int? year,
    String? quality,
    String? audioCodec,
    String? videoCodec,
    String? group,
    bool? isSeries,
    double? confidence,
    int? fileSize,
  }) {
    return SeriesInfo(
      title: title ?? this.title,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      year: year ?? this.year,
      quality: quality ?? this.quality,
      audioCodec: audioCodec ?? this.audioCodec,
      videoCodec: videoCodec ?? this.videoCodec,
      group: group ?? this.group,
      isSeries: isSeries ?? this.isSeries,
      confidence: confidence ?? this.confidence,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}

class SeriesParser {
  // Special content keywords for Season 0 detection
  static const DELETED_KEYWORDS = ['deleted', 'deletedscenes', 'deleted.scenes', 'deleted_scenes'];
  static const BEHIND_KEYWORDS = ['behind', 'behindthescenes', 'behind.the.scenes',
                                   'making.of', 'makingof', 'making_of', 'bts'];
  // Note: 'extended' removed - it's commonly used in movie names like "Extended Edition"
  // and would cause false positives. Only standalone "Extras" folders/files should match.
  static const EXTRAS_KEYWORDS = ['extras', 'bonus', 'special', 'feature'];
  static const INTERVIEW_KEYWORDS = ['interview', 'featurette', 'interviews'];
  static const BLOOPER_KEYWORDS = ['bloopers', 'gag.reel', 'gagreel', 'outtakes', 'mistakes'];
  static const COMMENTARY_KEYWORDS = ['commentary', 'directors.cut', 'directors_cut'];
  static const SAMPLE_KEYWORDS = ['sample', 'trailer', 'preview'];

  // Movie false positive patterns
  static const MOVIE_EPISODE_PATTERNS = [
    'star.wars.episode', 'star_wars_episode',
    'episode.i', 'episode.ii', 'episode.iii', 'episode.iv', 'episode.v',
    'episode.vi', 'episode.vii', 'episode.viii', 'episode.ix',
    'part.i', 'part.ii', 'part.iii', 'part.iv', 'part.v',
    'chapter.1', 'chapter.2', 'chapter.3', 'chapter.4',
  ];

  // Movie collection indicators - patterns that suggest a movie collection
  static const MOVIE_COLLECTION_KEYWORDS = [
    'collection', 'complete.collection', 'box.set', 'boxset',
    'trilogy', 'quadrilogy', 'saga', 'anthology',
    'part.1', 'part.2', 'part.one', 'part.two',
    'vol.1', 'vol.2', 'volume.1', 'volume.2',
  ];

  // Year pattern for detecting movies (movies typically have years, episodes don't)
  static final RegExp _movieYearPattern = RegExp(r'[\.\s_\-\(](?:19|20)\d{2}[\.\s_\-\)]');

  static final List<RegExp> _seasonEpisodePatterns = [
    // Bracket notation: [S.E] or [S.E.E] (MUST BE FIRST for priority)
    RegExp(r'^\[(\d{1,2})\.(\d{1,2})(?:\.(\d{1,2}))?\]'),
    // S01EP02, S1EP2, S01.EP02, S1.EP2 (EP variant - MUST BE BEFORE standard E pattern)
    RegExp(r'[Ss](\d{1,2})[Ee][Pp](\d{1,3})'),
    // S01E02, S1E2, S01.E02, S1.E2
    RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})'),
    // 1x02, 01x02, 1.02, 01.02
    RegExp(r'(\d{1,2})[xX](\d{1,3})'),
    RegExp(r'(\d{1,2})\.(\d{1,3})'),
    // Season 1 Episode 2, Season 01 Episode 02
    RegExp(r'[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,3})'),
    // Episode 2, Ep 2, E02
    RegExp(r'[Ee]pisode\s*(\d{1,3})'),
    RegExp(r'[Ee]p\s*(\d{1,3})'),
    RegExp(r'[Ee](\d{1,3})'),
  ];

  // Anime-specific patterns
  static final List<RegExp> _animePatterns = [
    // Anime.001.mkv, Show.123.mkv
    RegExp(r'^.*?[\s._-](\d{3})(?:[\s._-]|$)'),
    // EP001, E001
    RegExp(r'EP?(\d{3})', caseSensitive: false),
    // Episode 001, Episode.001
    RegExp(r'Episode[\s._-]?(\d{3})', caseSensitive: false),
    // [001], (001)
    RegExp(r'[\[\(](\d{3})[\]\)]'),
  ];

  static final List<RegExp> _titlePatterns = [
    // Common series title patterns
    // S01EP02 variant (MUST BE BEFORE standard S01E02 pattern)
    RegExp(r'^(.+?)\s*[Ss](\d{1,2})[Ee][Pp](\d{1,3})'),
    RegExp(r'^(.+?)\s*[Ss](\d{1,2})[Ee](\d{1,3})'),
    RegExp(r'^(.+?)\s*(\d{1,2})[xX](\d{1,3})'),
    RegExp(r'^(.+?)\s*(\d{1,2})\.(\d{1,3})'),
    // Anime patterns for title extraction
    RegExp(r'^(.+?)[\s._-]\d{3}(?:[\s._-]|$)'),
    RegExp(r'^(.+?)[\s._-]EP?\d{3}', caseSensitive: false),
  ];

  static final RegExp _yearPattern = RegExp(r'\((\d{4})\)');
  static final RegExp _qualityPattern = RegExp(r'(1080p|720p|480p|2160p|4K|HDRip|BRRip|WEBRip|BluRay|HDTV|DVDRip)');
  static final RegExp _audioCodecPattern = RegExp(r'(AAC|AC3|DTS|FLAC|MP3|OGG)');
  static final RegExp _videoCodecPattern = RegExp(r'(H\.264|H\.265|HEVC|AVC|XVID|DIVX)');
  static final RegExp _groupPattern = RegExp(r'-([A-Za-z0-9]+)$');

  /// Validate if a series title is valid and usable
  static bool isValidSeriesTitle(String? title) {
    if (title == null || title.isEmpty) return false;
    if (title.length == 1) return false; // Reject single characters
    if (title == '[' || title == ']') return false; // Reject brackets
    if (title.trim().isEmpty) return false; // Reject whitespace-only

    // Reject if title is just special characters
    if (RegExp(r'^[\[\]\.\_\-\s]+$').hasMatch(title)) return false;

    // Reject titles starting with season/episode patterns
    if (RegExp(r'^[Ss]\d{1,2}[\s\-]*[Ee]\d{1,3}').hasMatch(title)) return false;
    if (RegExp(r'^[Ss]\d{1,2}[\s\-]+[Ee]pisode', caseSensitive: false).hasMatch(title)) return false;
    if (RegExp(r'^\d{1,2}[xX]\d{1,3}').hasMatch(title)) return false;
    if (RegExp(r'^[Ss]eason\s+\d', caseSensitive: false).hasMatch(title)) return false;
    if (RegExp(r'^[Ee]pisode\s+\d', caseSensitive: false).hasMatch(title)) return false;

    // Reject titles that are mostly quality/codec tags
    final qualityTagCount = RegExp(
      r'\b(1080p|720p|480p|2160p|4K|BluRay|WEBRip|HDTV|x264|x265|HEVC|AAC|AC3|DTS)\b',
      caseSensitive: false
    ).allMatches(title).length;
    final wordCount = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount > 0 && qualityTagCount > wordCount / 2) return false;

    return true;
  }

  /// Extract common series title from ALL filenames
  /// Returns null if no consistent pattern found
  static String? extractCommonSeriesTitle(List<String> filenames) {
    if (filenames.isEmpty) return null;

    // Parse all filenames and extract titles
    final titles = <String>[];
    for (final filename in filenames.take(10)) { // Limit to first 10 for performance
      final info = parseFilename(filename);
      if (info.title != null && info.title!.isNotEmpty) {
        // Clean up trailing separators from extracted titles
        final cleanedTitle = info.title!.toLowerCase().trim().replaceAll(RegExp(r'[\s\-_\+]+$'), '');
        if (cleanedTitle.isNotEmpty) {
          titles.add(cleanedTitle);
        }
      }
    }

    if (titles.isEmpty) return null;

    // Check if all titles are the same (most common case)
    final uniqueTitles = titles.toSet();
    if (uniqueTitles.length == 1) {
      final commonTitle = titles.first;
      if (isValidSeriesTitle(commonTitle)) {
        debugPrint('SeriesParser: Found common title (all same): "$commonTitle"');
        return commonTitle;
      }
    }

    // If titles differ slightly, find longest common prefix
    if (uniqueTitles.length > 1 && uniqueTitles.length <= 3) {
      final sortedTitles = titles.toList()..sort();
      String prefix = _longestCommonPrefix(sortedTitles);

      // Clean prefix - remove trailing separators
      prefix = prefix.trim().replaceAll(RegExp(r'[\s\-_\+]+$'), '');

      if (prefix.length >= 3 && isValidSeriesTitle(prefix)) {
        debugPrint('SeriesParser: Found common prefix: "$prefix"');
        return prefix;
      }
    }

    debugPrint('SeriesParser: No common title found (${uniqueTitles.length} unique titles)');
    return null;
  }

  /// Find longest common prefix among strings
  static String _longestCommonPrefix(List<String> strings) {
    if (strings.isEmpty) return '';
    if (strings.length == 1) return strings[0];

    String prefix = strings[0];
    for (int i = 1; i < strings.length; i++) {
      while (!strings[i].startsWith(prefix)) {
        prefix = prefix.substring(0, prefix.length - 1);
        if (prefix.isEmpty) return '';
      }
    }
    return prefix;
  }

  /// Clean a collection/torrent title to extract the actual series name
  /// Removes season info, quality tags, release groups, etc.
  ///
  /// Examples:
  /// - "The Office - Complete Season 1-9 [F4S7]" → "The Office"
  /// - "Breaking Bad S01-S05 COMPLETE [x265]" → "Breaking Bad"
  /// - "Game of Thrones - Complete Series (2011-2019) [1080p]" → "Game of Thrones"
  /// - "The Office [US] - Complete Series" → "The Office US"
  /// - "Beverly Hills 90210" → "Beverly Hills 90210" (preserves numbers in title)
  /// - "The Walking Dead - The Complete Collection (2010-2022) BDRip 1080p [Part 2]" → "The Walking Dead"
  /// - "Breaking Bad - Complete Series [Vol 1]" → "Breaking Bad"
  /// - "Game of Thrones S01-S08 [Disc 2]" → "Game of Thrones"
  static String cleanCollectionTitle(String title) {
    if (title.isEmpty) return title;

    final originalTitle = title;
    String cleaned = title;

    // PRE-PROCESSING: Handle multi-line titles and file metadata
    // 1. Take only the first line (before any newline)
    if (cleaned.contains('\n')) {
      cleaned = cleaned.split('\n').first.trim();
    }

    // 2. Remove emoji metadata (👤 💾 ⚙️ and similar) - do this BEFORE other cleaning
    // Remove common file metadata emojis and everything after them
    cleaned = cleaned.replaceAll(RegExp(r'[👤💾⚙️📁📂🎬🎥🎞️📽️🎦]+.*$'), '');
    // Remove any remaining emoji characters
    cleaned = cleaned.replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '');
    // Remove emoji variation selectors and other unicode symbols
    cleaned = cleaned.replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '');

    // 3. Remove file paths (anything with forward/back slashes)
    // Match patterns like "Season 1/file.mkv" or " /folder/file"
    cleaned = cleaned.replaceAll(RegExp(r'[/\\][^/\\]+\.(mkv|mp4|avi|mov|wmv|flv|webm|m4v).*$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*[/\\].+$'), '');

    // 4. Trim and remove trailing numbers that are leftovers (like "HEVC 1" → "1")
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+\d+\s*$'), '');

    // PHASE 1: NORMALIZATION
    // 1. Normalize separators - replace dots and underscores with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[._]'), ' ');

    // 2. Normalize country codes [US]/[UK] to just US/UK (BEFORE removing release groups)
    //    This preserves country codes while removing other bracketed content
    cleaned = _normalizeCountryCodes(cleaned);

    // PHASE 2: REMOVE METADATA (Order matters!)
    // 3. Remove regional/language tags (BEFORE release groups to avoid conflicts)
    cleaned = _removeRegionalTags(cleaned);

    // 4. Remove collection part indicators BEFORE release group tags
    //    This ensures [Part 2], [Vol 1], [Disc 3] are removed for TVMaze search
    cleaned = _removeCollectionPartIndicators(cleaned);

    // 5. Remove release group tags in brackets
    //    Match [UPPERCASE] or [ALPHANUMERIC] patterns (greedy)
    cleaned = _removeReleaseGroupTags(cleaned);

    // 6. Remove scene release metadata tags (PROPER, REPACK, etc.)
    cleaned = _removeSceneTags(cleaned);

    // 7. Remove quality/format/platform tags
    //    Includes multi-word tags (WEB DL) and platform tags (AMZN, NETFLIX)
    cleaned = _removeQualityTags(cleaned);

    // 8. Remove season/series metadata
    //    Includes extended keywords (Full Series, Box Set) and alternative formats
    cleaned = _removeSeasonMetadata(cleaned);

    // 9. Remove date formats (for daily shows like talk shows, news)
    cleaned = _removeDateFormats(cleaned);

    // 10. Remove year ranges - ALL variations
    //    (2005-2013), (2011 2019), [2011-2019], {2011-2019}
    cleaned = _removeYearRanges(cleaned);

    // 11. Remove trailing single year (2005) at end only - preserve years in middle
    cleaned = _removeTrailingYear(cleaned);

    // 12. Remove edition tags (Extended, Unrated, Director's Cut)
    cleaned = _removeEditionTags(cleaned);

    // PHASE 3: CLEANUP
    // 13. Clean up remaining artifacts - separators, empty brackets
    cleaned = _cleanupSeparators(cleaned);

    // 14. Remove orphaned punctuation (leftover from bracket/paren content removal)
    // This handles cases where content inside brackets was removed but brackets remain
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(\s*$'), ''); // trailing "("
    cleaned = cleaned.replaceAll(RegExp(r'\s*\[\s*$'), ''); // trailing "["
    cleaned = cleaned.replaceAll(RegExp(r'\s*\)\s*$'), ''); // trailing ")"
    cleaned = cleaned.replaceAll(RegExp(r'\s*\]\s*$'), ''); // trailing "]"

    // 15. Final trim
    cleaned = cleaned.trim();

    // VALIDATION
    // If result is empty or too short (likely all metadata), return original
    if (cleaned.isEmpty || cleaned.length < 2) {
      return originalTitle;
    }

    return cleaned;
  }

  /// Remove release group tags like [YIFY], {RARBG}, etc.
  static String _removeReleaseGroupTags(String text) {
    // Remove square brackets with uppercase/alphanumeric content
    // Examples: [F4S7], [YIFY], [RARBG], [PublicHD]
    // Note: Collection part indicators like [Part 2] are now handled by _removeCollectionPartIndicators
    text = text.replaceAll(RegExp(r'\[[A-Z0-9]+\]', caseSensitive: false), ' ');

    // Remove curly braces with uppercase/alphanumeric content
    // Examples: {RARBG}, {YIFY}
    text = text.replaceAll(RegExp(r'\{[A-Z0-9]+\}', caseSensitive: false), ' ');

    // Remove parentheses with only uppercase letters/numbers (but be careful not to remove years)
    // Only remove if it's clearly a release group (all uppercase, 3-10 chars)
    text = text.replaceAll(RegExp(r'\([A-Z0-9]{3,10}\)'), ' ');

    return text;
  }

  /// Remove scene release metadata tags
  /// Scene releases use specific tags to indicate version/fix status
  static String _removeSceneTags(String text) {
    // Scene metadata tags:
    // PROPER - Correct version by different group
    // REPACK - Fixed by same group
    // INTERNAL - Internal release (not widespread)
    // DIRFIX - Directory name fix
    // NFOFIX - NFO file fix
    // SUBFIX - Subtitle fix
    // READNFO - Read NFO for important info
    // REAL - Verified authentic
    // RETAIL - Retail source
    // DUBBED/SUBBED - Audio/subtitle variants
    final scenePattern = RegExp(
      r'\b(?:REPACK|PROPER|INTERNAL|DIRFIX|NFOFIX|SUBFIX|READNFO|REAL|'
      r'RETAIL|DUBBED|SUBBED|UNRATED|UNCUT|LIMITED)\b',
      caseSensitive: false,
    );

    text = text.replaceAll(scenePattern, ' ');

    return text;
  }

  /// Remove quality and format tags
  static String _removeQualityTags(String text) {
    // PHASE 2: Remove multi-word quality tags FIRST (before hyphenated versions)
    // WEB DL, Blu Ray, DVD Rip, HD TV (sometimes not hyphenated)
    text = text.replaceAll(RegExp(r'\bWEB\s+DL\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bBlu\s+Ray\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bDVD\s+Rip\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bHD\s+TV\b', caseSensitive: false), ' ');

    // PHASE 1: Platform/Service tags (streaming platforms and abbreviations)
    // Full names: NETFLIX, AMAZON, HULU, DISNEY, HBO, APPLE
    // Abbreviations: AMZN, NF, HMAX, DSNP, ATVP
    final platformPattern = RegExp(
      r'\b(?:AMZN|NF|HMAX|DSNP|ATVP|NETFLIX|AMAZON|HULU|DISNEY|HBO|APPLE)\b',
      caseSensitive: false,
    );
    text = text.replaceAll(platformPattern, ' ');

    // Quality tags: 1080p, 720p, 480p, 2160p, 4K, UHD, FHD, HD, HDR
    // Format tags: BluRay, BRRip, BDRip, WEBRip, WEB-DL, HDTV, DVDRip
    // Codec tags: x264, x265, H264, H265, HEVC, AVC
    // Audio tags: AAC, AC3, DTS, Atmos, 5.1, 7.1
    final qualityPattern = RegExp(
      r'\b(?:1080p|720p|480p|2160p|4K|UHD|FHD|HD|HDR|'
      r'BluRay|BRRip|BDRip|WEBRip|WEB-DL|HDTV|DVDRip|HDRip|'
      r'x264|x265|H\.?264|H\.?265|HEVC|AVC|'
      r'AAC|AC3|DTS|Atmos|5\.1|7\.1|10bit|8bit)\b',
      caseSensitive: false,
    );

    text = text.replaceAll(qualityPattern, ' ');

    // Remove orphaned audio channel numbers (from 5.1, 7.1 after separator normalization)
    text = text.replaceAll(RegExp(r'\b[57]\s+1\b'), ' ');

    // Also remove common quality indicators in brackets
    text = text.replaceAll(RegExp(r'\[(?:1080p|720p|480p|2160p|4K|BluRay|WEB-DL|x264|x265|HEVC|HDR)\]', caseSensitive: false), ' ');

    // Remove file size indicators: "59GB", "1.5GB", "100MB", etc.
    text = text.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\s*(?:GB|MB|TB)\b', caseSensitive: false), ' ');

    // Remove percentage indicators: "100%", "50% English", etc.
    text = text.replaceAll(RegExp(r'\b\d+%\b'), ' ');

    // Remove audio/subtitle metadata
    text = text.replaceAll(RegExp(r'\b(?:English|Multi|Dual)\s+(?:Audio|Subs?|Subtitles?)\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\b\d+%\s+(?:English|Multi|Dual)\s+(?:Audio|Subs?)\b', caseSensitive: false), ' ');

    // Remove standalone release group names at end (all caps, 2-5 chars)
    // But DON'T remove country codes (US, UK, AU, CA, NZ)
    text = text.replaceAll(RegExp(r'\b(?!US|UK|AU|CA|NZ)[A-Z]{2,5}\s*$'), ' ');

    return text;
  }

  /// Remove season/series metadata
  static String _removeSeasonMetadata(String text) {
    // CRITICAL: Handle "The Complete Series/Collection" FIRST before other patterns
    // Remove with optional preceding space/paren
    text = text.replaceAll(RegExp(r'[\s\)]+The\s+Complete\s+(?:Series|Collection)', caseSensitive: false), ' ');

    // PHASE 2: Extended season keywords (Full, Entire, Box Set)
    // "Full Series", "Entire Series", "Complete Box Set", "Full Collection"
    text = text.replaceAll(RegExp(r'\b(?:Full|Entire|Complete)\s+(?:Series|Collection)\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bBox\s+Set\b', caseSensitive: false), ' ');

    // PHASE 2: Alternative season range formats
    // "Seasons 1 to 9", "Seasons 1 through 9", "Seasons 1 thru 9"
    // Note: Using looser word boundary to handle edge cases
    text = text.replaceAll(RegExp(r'\bSeasons?\s+\d+\s+(?:to|through|thru)\s+\d+(?:\s|$)', caseSensitive: false), ' ');

    // Space-separated season list: "S01 S02 S03" (at least 2 instances)
    text = text.replaceAll(RegExp(r'(?:S\d{1,2}\s+){2,}', caseSensitive: false), ' ');

    // "Complete Season 1-9", "Complete Series", "All Seasons", "All Episodes"
    text = text.replaceAll(RegExp(r'\b(?:Complete\s+)?(?:Season|Series|Collection)s?\s*\d*\s*-?\s*\d*\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bAll\s+(?:Seasons?|Episodes?)\b', caseSensitive: false), ' ');

    // "S01-S09", "S1-S9", "S01 - S09"
    text = text.replaceAll(RegExp(r'\bS\d{1,2}\s*-\s*S\d{1,2}\b', caseSensitive: false), ' ');

    // "Season 1-9", "Seasons 1-9", "Series 1-9"
    text = text.replaceAll(RegExp(r'\b(?:Season|Series)s?\s+\d+\s*-\s*\d+\b', caseSensitive: false), ' ');

    // Handle "Complete" followed by "+" - remove "Complete" in this context
    text = text.replaceAll(RegExp(r'\bComplete\s+\+', caseSensitive: false), ' +');

    // Remove everything from first "+" to end (simplest approach)
    // This handles "+ Movies + Specials + STAR WARS + Special Features" etc.
    text = text.replaceAll(RegExp(r'\+.*$', caseSensitive: false), ' ');

    // Standalone "COMPLETE" as a keyword (but not when it's part of a title like "Complete Saga")
    // Remove if at the end OR followed by year/punctuation (like "Complete (2011)")
    text = text.replaceAll(RegExp(r'\bComplete\s*(?=\(|\[|$)', caseSensitive: false), ' ');

    return text;
  }

  /// Normalize country codes - convert [US]/[UK] to US/UK
  static String _normalizeCountryCodes(String text) {
    // PHASE 3: Support ALL bracket types for country codes
    // [US], (US), {US}, <US> → " US "
    // Supports: US, UK, AU, CA, NZ, IN, BR, FR, DE, JP, KR
    text = text.replaceAllMapped(
      RegExp(r'[\[{(<](US|UK|AU|CA|NZ|IN|BR|FR|DE|JP|KR)[\]}>)]', caseSensitive: false),
      (match) => ' ${match.group(1)!.toUpperCase()} ',
    );

    return text;
  }

  /// PHASE 3: Remove date formats for daily shows
  /// Daily/weekly shows often use date formats in filenames
  static String _removeDateFormats(String text) {
    // Date formats: YYYY.MM.DD, YYYY-MM-DD (ISO format)
    // Examples: 2024.01.15, 2024-01-15
    // NOTE: Dots may have been converted to spaces by separator normalization
    text = text.replaceAll(RegExp(r'\b\d{4}[\.\-\s]\d{2}[\.\-\s]\d{2}\b'), ' ');

    // Alternative date formats: MM.DD.YYYY, DD.MM.YYYY
    // Examples: 01.15.2024, 15.01.2024
    // NOTE: Dots may have been converted to spaces by separator normalization
    text = text.replaceAll(RegExp(r'\b\d{2}[\.\-\s]\d{2}[\.\-\s]\d{4}\b'), ' ');

    return text;
  }

  /// PHASE 3: Remove regional/language tags
  /// Remove language and regional variant tags
  static String _removeRegionalTags(String text) {
    // Language tags in brackets
    // [HINDI], [SPANISH], [FRENCH], [Multi-Audio], [Dual-Audio]
    final regionalPattern = RegExp(
      r'\[(?:HINDI|SPANISH|FRENCH|GERMAN|CHINESE|JAPANESE|KOREAN|ITALIAN|'
      r'PORTUGUESE|RUSSIAN|ARABIC|Multi-?Audio|Dual-?Audio)\]',
      caseSensitive: false,
    );
    text = text.replaceAll(regionalPattern, ' ');

    // Remove platform tags in brackets (also covers regional variants)
    // [NETFLIX], [AMAZON], [HULU], [DISNEY+], [HBO]
    text = text.replaceAll(
      RegExp(r'\[(?:NETFLIX|AMAZON|HULU|DISNEY\+?|HBO|APPLE)\]', caseSensitive: false),
      ' ',
    );

    return text;
  }

  /// Remove year ranges like (2005-2013) or 2005-2013
  static String _removeYearRanges(String text) {
    // Remove year ranges in parentheses or standalone WITH DASH
    // (2005-2013), (2005 - 2013), 2005-2013, 2005 - 2013
    text = text.replaceAll(RegExp(r'\(?\d{4}\s*-\s*\d{4}\)?'), ' ');

    // CRITICAL FIX: Remove year ranges with SPACE ONLY (no dash)
    // (2011 2019), 2011 2019 - common in many torrents
    text = text.replaceAll(RegExp(r'\(?\d{4}\s+\d{4}\)?'), ' ');

    // Remove year ranges in SQUARE or CURLY brackets
    // [2011-2019], {2011-2019}, [2011 2019], {2011 2019}
    text = text.replaceAll(RegExp(r'[\[{]\d{4}\s*-?\s*\d{4}[\]}]'), ' ');

    return text;
  }

  /// Remove trailing single year (YYYY) at the end only
  /// Preserves years in the middle like "Beverly Hills 90210" and "The 4400"
  static String _removeTrailingYear(String text) {
    // Only remove (YYYY) at the very end after trimming
    text = text.trim();
    text = text.replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '');

    // Remove standalone year at the end ONLY if it's clearly a release year
    // Match patterns like " 2013" or "- 2013" but NOT "The 4400" or "90210"
    // We look for a year that's preceded by whitespace/dash AND is 19xx or 20xx
    text = text.replaceAll(RegExp(r'[\s\-](19\d{2}|20[0-2]\d)\s*$'), '');

    return text;
  }

  /// Remove edition tags like Extended, Unrated, Director's Cut
  static String _removeEditionTags(String text) {
    final editionPattern = RegExp(
      r'\b(?:Extended\s+Edition|Extended|Unrated|Directors?\s*Cut|Theatrical|'
      r'Remastered|Special\s+Edition|Ultimate\s+Edition|'
      r'Anniversary\s+Edition|Collectors?\s*Edition)\b',
      caseSensitive: false,
    );

    text = text.replaceAll(editionPattern, ' ');

    return text;
  }

  /// Clean up separators, multiple spaces, empty brackets
  static String _cleanupSeparators(String text) {
    // Remove empty brackets
    text = text.replaceAll(RegExp(r'\[\s*\]'), ' ');
    text = text.replaceAll(RegExp(r'\(\s*\)'), ' ');
    text = text.replaceAll(RegExp(r'\{\s*\}'), ' ');

    // Remove orphaned plus signs (from "+ MOVIES" removal)
    text = text.replaceAll(RegExp(r'\s+\+\s*'), ' ');
    text = text.replaceAll(RegExp(r'\+\s+'), ' ');

    // Replace multiple spaces with single space
    text = text.replaceAll(RegExp(r'\s+'), ' ');

    // Remove leading/trailing dashes, dots, underscores, plus signs after spaces
    text = text.replaceAll(RegExp(r'^\s*[\-\._\+]+\s*'), '');
    text = text.replaceAll(RegExp(r'\s*[\-\._\+]+\s*$'), '');

    // Clean up "- -" patterns that might remain
    text = text.replaceAll(RegExp(r'\s*-\s*-\s*'), ' - ');

    // Clean up standalone dashes with trailing words that look like leftovers
    // Pattern: " - Word" at the end where Word is short (likely metadata fragment)
    text = text.replaceAll(RegExp(r'\s+-\s+\w{1,4}\s*$'), '');

    // Clean up standalone dashes
    text = text.replaceAll(RegExp(r'\s+-\s+$'), '');
    text = text.replaceAll(RegExp(r'^\s*-\s+'), '');

    return text;
  }

  /// Remove collection part indicators like [Part 1], [Vol 2], [Disc 3]
  /// These are metadata used in collections and should be removed for TVMaze search
  static String _removeCollectionPartIndicators(String text) {
    // Remove collection part indicators in square brackets
    // [Part X], [Part 1], [Part One], etc.
    text = text.replaceAll(RegExp(r'\[Part\s+(?:\d+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|I{1,3}|IV|V|VI{1,3}|IX|X)\]', caseSensitive: false), ' ');

    // Remove volume indicators
    // [Vol X], [Vol. X], [Volume X], etc.
    text = text.replaceAll(RegExp(r'\[Vol(?:ume)?\.?\s+\d+\]', caseSensitive: false), ' ');

    // Remove disc/disk indicators
    // [Disc X], [Disk X], [DVD X], [CD X]
    text = text.replaceAll(RegExp(r'\[(?:Disc|Disk|DVD|CD)\s+\d+\]', caseSensitive: false), ' ');

    // Also remove these patterns in parentheses
    text = text.replaceAll(RegExp(r'\(Part\s+(?:\d+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|I{1,3}|IV|V|VI{1,3}|IX|X)\)', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\(Vol(?:ume)?\.?\s+\d+\)', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\((?:Disc|Disk|DVD|CD)\s+\d+\)', caseSensitive: false), ' ');

    // Remove these patterns without brackets too (at word boundaries)
    text = text.replaceAll(RegExp(r'\bPart\s+(?:\d+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|I{1,3}|IV|V|VI{1,3}|IX|X)\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\bVol(?:ume)?\.?\s+\d+\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\b(?:Disc|Disk|DVD|CD)\s+\d+\b', caseSensitive: false), ' ');

    return text;
  }

  static SeriesInfo parseFilename(String filename, {int? fileSize}) {
    // Removed verbose per-file logging

    // Remove file extension
    final nameWithoutExt = _removeExtension(filename);
    final lowerName = nameWithoutExt.toLowerCase();

    // Check for movie false positives first
    bool isMoviePattern = false;
    for (final pattern in MOVIE_EPISODE_PATTERNS) {
      if (lowerName.contains(pattern)) {
        debugPrint('SeriesParser: Detected movie pattern: $pattern');
        isMoviePattern = true;
        break;
      }
    }

    // Check if it's a sample file
    bool isSample = false;
    for (final keyword in SAMPLE_KEYWORDS) {
      if (lowerName.contains(keyword)) {
        debugPrint('SeriesParser: Detected sample file: $keyword');
        isSample = true;
        break;
      }
    }

    // Try to extract season and episode
    int? season;
    int? episode;
    bool isAnime = false;
    bool isBracketNotation = false;
    String? episodeTitle;

    // Try standard patterns first unless it's a movie pattern
    if (!isMoviePattern) {
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

            // Check if this is the bracket notation pattern (first in list)
            if (pattern == _seasonEpisodePatterns[0]) {
              isBracketNotation = true;

              // Extract episode title from after the closing bracket FIRST
              final bracketEnd = match.end;
              String? extractedTitle;
              if (bracketEnd < nameWithoutExt.length) {
                final afterBracket = nameWithoutExt.substring(bracketEnd).trim();
                if (afterBracket.isNotEmpty) {
                  // Clean up the title
                  extractedTitle = afterBracket.replaceAll(RegExp(r'[._]'), ' ').trim();
                  extractedTitle = extractedTitle.replaceAll(RegExp(r'\s+'), ' ');
                  if (extractedTitle.isEmpty) {
                    extractedTitle = null;
                  }
                }
              }

              // Check for multi-episode format [S.E.E]
              if (match.groupCount >= 3 && match.group(3) != null) {
                final endEpisode = int.tryParse(match.group(3) ?? '');
                if (endEpisode != null) {
                  // For multi-episode, append the range to the title
                  if (extractedTitle != null) {
                    episodeTitle = '$extractedTitle (Episodes $episode-$endEpisode)';
                  } else {
                    episodeTitle = 'Episodes $episode-$endEpisode';
                  }
                  // Multi-episode detected
                } else {
                  episodeTitle = extractedTitle;
                }
              } else {
                episodeTitle = extractedTitle;
              }

              debugPrint('SeriesParser: Bracket notation [$season.$episode${match.group(3) != null ? ".${match.group(3)}" : ""}] → title: "${episodeTitle ?? "none"}"');
            }
          } else if (match.groupCount >= 1) {
            // For patterns like "Episode 2" or "E02", we need to infer season
            episode = int.tryParse(match.group(1) ?? '');
            // Try to find season from other patterns
            final seasonMatch = RegExp(r'[Ss](\d{1,2})').firstMatch(nameWithoutExt);
            if (seasonMatch != null) {
              season = int.tryParse(seasonMatch.group(1) ?? '');
            }
          }
          if (season != null || episode != null) {
            // Found standard pattern - no log needed
            break;
          }
        }
      }

      // Try anime patterns if no standard pattern found
      if (season == null && episode == null) {
        for (final pattern in _animePatterns) {
          final match = pattern.firstMatch(nameWithoutExt);
          if (match != null && match.groupCount >= 1) {
            episode = int.tryParse(match.group(1) ?? '');
            if (episode != null) {
              season = 1; // Default to season 1 for anime
              isAnime = true;
              // Found anime pattern - no log needed
              break;
            }
          }
        }
      }
    }

    // Check for special content (Season 0)
    bool isSpecialContent = false;
    if (!isSample) {
      isSpecialContent = _isSpecialContent(lowerName);
      if (isSpecialContent) {
        debugPrint('SeriesParser: Detected special content');
        // Assign to Season 0 if not already assigned
        if (season == null && episode == null) {
          season = 0;
          episode = 1; // Will be properly numbered later
        }
      }
    }

    // Determine if it's a series with confidence
    final isSeries = (season != null || episode != null) && !isMoviePattern;
    double confidence = 50.0; // Base confidence

    if (isSeries) {
      if (season != null && episode != null) {
        confidence = isAnime ? 85.0 : 90.0;
      } else {
        confidence = 70.0;
      }
    } else if (isMoviePattern) {
      confidence = 20.0; // Low confidence for series
    }

    // Extract title
    String? title;

    // For bracket notation, don't extract series title from filename
    // Return null to allow collection title to be used as fallback
    if (isBracketNotation) {
      // Title will be null, which signals to use collection title
      // (already logged above)
    } else {
      // Standard title extraction for other formats
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

      // If no title found and it's a series, don't try to extract from split
      // This prevents extracting episode names as series titles (like "S01 - E01 - Winter Is Coming")
      // Return null to signal that collection title should be used as fallback
      if (title == null && isSeries) {
        // Don't try to extract title from split - unreliable
        title = null;
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

    // Clean up title - replace dots and underscores with spaces
    if (title != null) {
      title = title.replaceAll(RegExp(r'[._]'), ' ').trim();
      // Remove duplicate spaces
      title = title.replaceAll(RegExp(r'\s+'), ' ');
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
      episodeTitle: episodeTitle,
      year: year,
      quality: quality,
      audioCodec: audioCodec,
      videoCodec: videoCodec,
      group: group,
      isSeries: isSeries,
      confidence: confidence,
      fileSize: fileSize,
    );
  }

  /// Conservative series parser optimized for streaming contexts (Magic TV).
  ///
  /// This variant is MORE STRICT about identifying series to reduce false positives
  /// where movies are incorrectly tagged as TV series. Key improvements:
  ///
  /// - Rejects patterns where numbers follow years (e.g., "2009.1080p")
  /// - Excludes multi-part movie indicators (CD1, Disc2, Part 1)
  /// - Validates season/episode numbers are in reasonable ranges
  /// - Detects movie sequels with Roman numerals (II, III, IV)
  /// - Requires stronger evidence before marking content as series
  ///
  /// Use this for Magic TV and other streaming/browsing contexts where
  /// conservative classification is preferred. Use the standard parseFilename()
  /// for playlist management and progress tracking.
  static SeriesInfo parseFilenameConservative(String filename, {int? fileSize}) {
    // Remove file extension
    final nameWithoutExt = _removeExtension(filename);
    final lowerName = nameWithoutExt.toLowerCase();

    // PHASE 1: PRE-FILTERING - Detect strong movie indicators
    bool isLikelyMovie = false;
    String? movieReason;

    // Check for existing movie patterns
    for (final pattern in MOVIE_EPISODE_PATTERNS) {
      if (lowerName.contains(pattern)) {
        debugPrint('SeriesParser (Conservative): Movie pattern detected: $pattern');
        isLikelyMovie = true;
        movieReason = 'movie episode pattern';
        break;
      }
    }

    // Check for multi-part movie indicators (CD/Disc/Part)
    if (!isLikelyMovie) {
      final multiPartPattern = RegExp(
        r'\b(?:CD|Disc|Disk|DVD|Part)[\s\._-]?(?:\d+|One|Two|Three|I{1,3}|IV|V)\b',
        caseSensitive: false,
      );
      if (multiPartPattern.hasMatch(nameWithoutExt)) {
        debugPrint('SeriesParser (Conservative): Multi-part movie detected');
        isLikelyMovie = true;
        movieReason = 'multi-part indicator';
      }
    }

    // Check for Roman numeral sequels (II, III, IV, etc.)
    if (!isLikelyMovie) {
      final romanNumeralPattern = RegExp(
        r'\b(?:II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)\b(?!\s*[Ee]pisode)',
        caseSensitive: false,
      );
      if (romanNumeralPattern.hasMatch(nameWithoutExt)) {
        debugPrint('SeriesParser (Conservative): Roman numeral sequel detected');
        isLikelyMovie = true;
        movieReason = 'roman numeral sequel';
      }
    }

    // Check for year followed by quality pattern (common in movies)
    if (!isLikelyMovie) {
      final yearQualityPattern = RegExp(
        r'(?:19|20)\d{2}[\s\._-]*(?:\d{3,4}p|720|1080|2160|BluRay|WEBRip|BRRip)',
        caseSensitive: false,
      );
      if (yearQualityPattern.hasMatch(nameWithoutExt)) {
        debugPrint('SeriesParser (Conservative): Year-quality pattern detected (movie)');
        isLikelyMovie = true;
        movieReason = 'year-quality pattern';
      }
    }

    // Check for sample files
    bool isSample = false;
    for (final keyword in SAMPLE_KEYWORDS) {
      if (lowerName.contains(keyword)) {
        debugPrint('SeriesParser (Conservative): Sample file detected');
        isSample = true;
        isLikelyMovie = true;
        movieReason = 'sample file';
        break;
      }
    }

    // PHASE 2: EPISODE PATTERN MATCHING (only if not likely a movie)
    int? season;
    int? episode;
    bool isAnime = false;
    bool isBracketNotation = false;
    String? episodeTitle;
    bool foundValidPattern = false;

    if (!isLikelyMovie) {
      // Try standard patterns with strict validation
      for (final pattern in _seasonEpisodePatterns) {
        final match = pattern.firstMatch(nameWithoutExt);
        if (match != null) {
          // Check if this looks like a resolution pattern
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
            final potentialSeason = int.tryParse(match.group(1) ?? '');
            final potentialEpisode = int.tryParse(match.group(2) ?? '');

            // CONSERVATIVE VALIDATION: Reject unreasonable numbers
            // Reject if season > 50 (unless explicit S##E## format)
            // Reject if episode > 500
            if (potentialSeason != null && potentialSeason > 50) {
              // Check if this is explicit S##E## format
              final isExplicitFormat = nameWithoutExt.contains(RegExp(r'[Ss]\d+[Ee]\d+'));
              if (!isExplicitFormat) {
                debugPrint('SeriesParser (Conservative): Rejected season=$potentialSeason (too high)');
                continue;
              }
            }
            if (potentialEpisode != null && potentialEpisode > 500) {
              debugPrint('SeriesParser (Conservative): Rejected episode=$potentialEpisode (too high)');
              continue;
            }

            // Additional check: If pattern is just digits.digits, check for year context
            if (pattern == _seasonEpisodePatterns[5]) { // The (\d{1,2})\.(\d{1,3}) pattern
              // Check if there's a 4-digit year before this pattern
              final yearBeforePattern = RegExp(r'(?:19|20)\d{2}[\s\._-]*$');
              final textBeforeMatch = nameWithoutExt.substring(0, match.start);
              if (yearBeforePattern.hasMatch(textBeforeMatch)) {
                debugPrint('SeriesParser (Conservative): Rejected pattern after year (likely quality)');
                continue;
              }
            }

            season = potentialSeason;
            episode = potentialEpisode;
            foundValidPattern = true;

            // Handle bracket notation
            if (pattern == _seasonEpisodePatterns[0]) {
              isBracketNotation = true;
              final bracketEnd = match.end;
              String? extractedTitle;
              if (bracketEnd < nameWithoutExt.length) {
                final afterBracket = nameWithoutExt.substring(bracketEnd).trim();
                if (afterBracket.isNotEmpty) {
                  extractedTitle = afterBracket.replaceAll(RegExp(r'[._]'), ' ').trim();
                  extractedTitle = extractedTitle.replaceAll(RegExp(r'\s+'), ' ');
                  if (extractedTitle.isEmpty) {
                    extractedTitle = null;
                  }
                }
              }

              if (match.groupCount >= 3 && match.group(3) != null) {
                final endEpisode = int.tryParse(match.group(3) ?? '');
                if (endEpisode != null) {
                  if (extractedTitle != null) {
                    episodeTitle = '$extractedTitle (Episodes $episode-$endEpisode)';
                  } else {
                    episodeTitle = 'Episodes $episode-$endEpisode';
                  }
                } else {
                  episodeTitle = extractedTitle;
                }
              } else {
                episodeTitle = extractedTitle;
              }
            }
          } else if (match.groupCount >= 1) {
            // For patterns like "Episode 2" or "E02"
            episode = int.tryParse(match.group(1) ?? '');
            if (episode != null && episode <= 500) {
              final seasonMatch = RegExp(r'[Ss](\d{1,2})').firstMatch(nameWithoutExt);
              if (seasonMatch != null) {
                season = int.tryParse(seasonMatch.group(1) ?? '');
                foundValidPattern = true;
              }
            }
          }

          if (foundValidPattern && (season != null || episode != null)) {
            break;
          }
        }
      }

      // Try anime patterns if no standard pattern found
      if (!foundValidPattern && season == null && episode == null) {
        for (final pattern in _animePatterns) {
          final match = pattern.firstMatch(nameWithoutExt);
          if (match != null && match.groupCount >= 1) {
            episode = int.tryParse(match.group(1) ?? '');
            if (episode != null && episode <= 999) {
              season = 1; // Default to season 1 for anime
              isAnime = true;
              foundValidPattern = true;
              break;
            }
          }
        }
      }
    }

    // PHASE 3: SPECIAL CONTENT DETECTION
    bool isSpecialContent = false;
    if (!isSample && foundValidPattern) {
      isSpecialContent = _isSpecialContent(lowerName);
      if (isSpecialContent) {
        if (season == null && episode == null) {
          season = 0;
          episode = 1;
        }
      }
    }

    // PHASE 4: SERIES CLASSIFICATION WITH CONSERVATIVE LOGIC
    // Only mark as series if we have STRONG evidence AND no movie indicators
    final isSeries = foundValidPattern &&
                     (season != null || episode != null) &&
                     !isLikelyMovie;

    double confidence = 50.0;
    if (isSeries) {
      if (season != null && episode != null) {
        // High confidence only for explicit patterns
        confidence = isAnime ? 85.0 : 90.0;
      } else {
        confidence = 70.0;
      }
    } else if (isLikelyMovie) {
      confidence = 10.0; // Very low confidence for series
    }

    // PHASE 5: TITLE EXTRACTION
    String? title;

    if (isBracketNotation) {
      title = null; // Use collection title as fallback
    } else {
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

      if (title == null && isSeries) {
        title = null; // Use collection title
      }
    }

    // Extract title before "Season" keyword
    if (title != null && title.contains('Season')) {
      final seasonIndex = title.indexOf('Season');
      if (seasonIndex > 0) {
        title = title.substring(0, seasonIndex).trim();
      }
    }

    // For non-series, extract title before year
    if (title == null && !isSeries) {
      final yearMatch = _yearPattern.firstMatch(nameWithoutExt);
      if (yearMatch != null) {
        final yearIndex = nameWithoutExt.indexOf(yearMatch.group(0)!);
        if (yearIndex > 0) {
          title = nameWithoutExt.substring(0, yearIndex).trim();
        }
      }
    }

    // Clean up title
    if (title != null) {
      title = title.replaceAll(RegExp(r'[._]'), ' ').trim();
      title = title.replaceAll(RegExp(r'\s+'), ' ');
    }

    // Extract metadata
    final year = _extractYear(nameWithoutExt);
    final quality = _extractQuality(nameWithoutExt);
    final audioCodec = _extractAudioCodec(nameWithoutExt);
    final videoCodec = _extractVideoCodec(nameWithoutExt);
    final group = _extractGroup(nameWithoutExt);

    if (isLikelyMovie && movieReason != null) {
      debugPrint('SeriesParser (Conservative): Classified as MOVIE ($movieReason): $filename');
    }

    return SeriesInfo(
      title: title,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      year: year,
      quality: quality,
      audioCodec: audioCodec,
      videoCodec: videoCodec,
      group: group,
      isSeries: isSeries,
      confidence: confidence,
      fileSize: fileSize,
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

  static List<SeriesInfo> parsePlaylist(List<String> filenames, {List<int>? fileSizes}) {
    return filenames.asMap().entries.map((entry) {
      final index = entry.key;
      final filename = entry.value;
      final fileSize = fileSizes != null && index < fileSizes.length ? fileSizes[index] : null;
      return parseFilename(filename, fileSize: fileSize);
    }).toList();
  }

  static bool isSeriesPlaylist(List<String> filenames) {
    final analysis = analyzePlaylistConfidence(filenames);
    // Analysis details already logged in analyzePlaylistConfidence
    return analysis.classification == PlaylistClassification.SERIES;
  }

  /// Analyze a playlist to determine confidence it's a series vs movie collection
  static PlaylistAnalysis analyzePlaylistConfidence(List<String> filenames) {

    if (filenames.isEmpty) {
      return const PlaylistAnalysis(
        confidenceScore: 0,
        classification: PlaylistClassification.AMBIGUOUS,
        detectionMethod: 'Empty playlist',
        scores: {},
      );
    }

    final scores = <String, double>{};

    // Parse all filenames
    final parsedFiles = parsePlaylist(filenames);

    // 1. Pattern matching score (40 points max)
    int seriesPatternCount = 0;
    int animePatternCount = 0;
    int moviePatternCount = 0;
    int yearPatternCount = 0;
    bool hasConsistentSeasonEpisode = false;
    Map<int, Set<int>> seasonEpisodeMap = {};

    for (int i = 0; i < parsedFiles.length; i++) {
      final info = parsedFiles[i];
      final filename = filenames[i];
      final lowerName = filename.toLowerCase();

      if (info.isSeries) {
        seriesPatternCount++;
        if (info.season != null && info.episode != null) {
          seasonEpisodeMap.putIfAbsent(info.season!, () => {});
          seasonEpisodeMap[info.season!]!.add(info.episode!);
          hasConsistentSeasonEpisode = true;
        }
      } else {
        // Check if it's a movie pattern
        for (final pattern in MOVIE_EPISODE_PATTERNS) {
          if (lowerName.contains(pattern)) {
            moviePatternCount++;
            break;
          }
        }
      }

      // Check for year patterns (strong movie indicator)
      if (_movieYearPattern.hasMatch(filename)) {
        yearPatternCount++;
      }

      // Check for anime patterns
      for (final pattern in _animePatterns) {
        if (pattern.hasMatch(filename)) {
          animePatternCount++;
          break;
        }
      }
    }

    double patternScore = 0;
    if (seriesPatternCount > 0) {
      patternScore = (seriesPatternCount / filenames.length) * 40;
      if (hasConsistentSeasonEpisode) {
        patternScore = math.min(40, patternScore + 10);
      }
    } else if (animePatternCount > filenames.length / 2) {
      patternScore = 35; // High score for anime
    }

    // Penalize if most files have movie patterns
    if (moviePatternCount > filenames.length / 3) {
      patternScore = math.max(0, patternScore - 20);
    }

    // Strong penalty if most files have year patterns but no S##E## patterns
    // Movies like "Movie.Name.2020.1080p" have years, series episodes typically don't
    if (yearPatternCount > filenames.length * 0.6 && seriesPatternCount == 0) {
      patternScore = math.max(0, patternScore - 15);
    }

    scores['pattern_match'] = patternScore;

    // 2. File count heuristics (30 points max)
    // BUT only give full points if we also have series patterns
    double fileCountScore = 0;
    if (filenames.length >= 3) {
      if (filenames.length >= 6 && filenames.length <= 26) {
        // Typical series season size - but reduce if no series patterns found
        if (seriesPatternCount > 0) {
          fileCountScore = 30;
        } else {
          // Could be a movie collection (Harry Potter has 8 movies)
          fileCountScore = 15;
        }
      } else if (filenames.length > 26) {
        // Likely multiple seasons or anime
        fileCountScore = 25;
      } else {
        // 3-5 files could be either
        fileCountScore = 15;
      }
    } else {
      // 1-2 files likely movies
      fileCountScore = 5;
    }

    scores['file_count'] = fileCountScore;

    // 3. Naming consistency (30 points max)
    double consistencyScore = 0;
    if (parsedFiles.isNotEmpty) {
      // Check if all files have the same series title
      final titles = parsedFiles
          .where((info) => info.title != null)
          .map((info) => info.title!.toLowerCase())
          .toSet();

      if (titles.length == 1 && titles.first.isNotEmpty) {
        consistencyScore = 25;
      } else if (titles.length <= 2 && filenames.length > 3) {
        consistencyScore = 15;
      } else {
        consistencyScore = 5;
      }

      // Bonus for sequential episodes
      if (seasonEpisodeMap.isNotEmpty) {
        bool hasSequential = false;
        for (final episodes in seasonEpisodeMap.values) {
          final sortedEps = episodes.toList()..sort();
          bool isSequential = true;
          for (int i = 1; i < sortedEps.length; i++) {
            if (sortedEps[i] - sortedEps[i - 1] > 2) {
              isSequential = false;
              break;
            }
          }
          if (isSequential && sortedEps.length > 2) {
            hasSequential = true;
            break;
          }
        }
        if (hasSequential) {
          consistencyScore = math.min(30, consistencyScore + 5);
        }
      }
    }

    scores['naming_consistency'] = consistencyScore;

    // Calculate total confidence
    final totalScore = patternScore + fileCountScore + consistencyScore;

    // Determine classification
    PlaylistClassification classification;
    String detectionMethod = 'Mixed analysis';

    if (totalScore >= 60) {
      classification = PlaylistClassification.SERIES;
      if (animePatternCount > filenames.length / 2) {
        detectionMethod = 'Anime pattern detection';
      } else if (hasConsistentSeasonEpisode) {
        detectionMethod = 'Season/Episode pattern';
      } else {
        detectionMethod = 'Series pattern matching';
      }
    } else if (totalScore <= 30) {
      classification = PlaylistClassification.MOVIES;
      detectionMethod = 'Movie collection pattern';
    } else {
      classification = PlaylistClassification.AMBIGUOUS;
      detectionMethod = 'Ambiguous content';
    }

    // Single consolidated log with all important info
    debugPrint('SeriesParser: ${filenames.length} files → Score: ${totalScore.toStringAsFixed(0)}/100 (Pattern:${patternScore.toStringAsFixed(0)} Count:${fileCountScore.toStringAsFixed(0)} Consistency:${consistencyScore.toStringAsFixed(0)}) → $classification');

    return PlaylistAnalysis(
      confidenceScore: totalScore,
      classification: classification,
      detectionMethod: detectionMethod,
      scores: scores,
    );
  }

  /// Check if filename contains special content keywords
  static bool _isSpecialContent(String filename) {
    final lower = filename.toLowerCase();

    // Check all special content keywords
    final allKeywords = [
      ...DELETED_KEYWORDS,
      ...BEHIND_KEYWORDS,
      ...EXTRAS_KEYWORDS,
      ...INTERVIEW_KEYWORDS,
      ...BLOOPER_KEYWORDS,
      ...COMMENTARY_KEYWORDS,
    ];

    for (final keyword in allKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  /// Check if filename is a sample file
  static bool isSampleFile(String filename) {
    final lower = filename.toLowerCase();
    for (final keyword in SAMPLE_KEYWORDS) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// Get special content type for Season 0 organization
  /// IMPORTANT: Only detects special content for files WITHOUT valid S##E## patterns
  /// This prevents moving actual episodes like "S01E15 Special Operations Squad" to Season 0
  static String? getSpecialContentType(String filename, {SeriesInfo? parsedInfo}) {
    final lower = filename.toLowerCase();

    // CRITICAL: If file has a valid season AND episode number (and it's NOT Season 0),
    // it's a regular episode - DON'T treat it as special content even if it has keywords
    if (parsedInfo != null &&
        parsedInfo.season != null &&
        parsedInfo.episode != null &&
        parsedInfo.season != 0) {
      // This is a regular episode (S01E15, S04E29, etc.)
      // Keywords like "special" are part of the episode TITLE, not special content markers
      return null;
    }

    for (final keyword in DELETED_KEYWORDS) {
      if (lower.contains(keyword)) return 'Deleted Scenes';
    }
    for (final keyword in BEHIND_KEYWORDS) {
      if (lower.contains(keyword)) return 'Behind The Scenes';
    }
    for (final keyword in INTERVIEW_KEYWORDS) {
      if (lower.contains(keyword)) return 'Interviews';
    }
    for (final keyword in BLOOPER_KEYWORDS) {
      if (lower.contains(keyword)) return 'Bloopers';
    }
    for (final keyword in COMMENTARY_KEYWORDS) {
      if (lower.contains(keyword)) return 'Commentary';
    }
    for (final keyword in EXTRAS_KEYWORDS) {
      if (lower.contains(keyword)) return 'Extras';
    }

    return null;
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
