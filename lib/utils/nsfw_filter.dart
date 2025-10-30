/// NSFW content filter for torrent results
/// Provides category-based and name-based filtering
class NsfwFilter {
  // Pre-compiled regex patterns for performance
  static final List<RegExp> _nsfwPatterns = [
    // Explicit NSFW keywords with word boundaries
    RegExp(r'\b(xxx|porn|sex|adult|nsfw|18\+)\b', caseSensitive: false),
    
    // NSFW in brackets or special formatting
    RegExp(r'[\[\(](xxx|adult|18\+|nsfw|porn|sex)[\]\)]', caseSensitive: false),
    
    // Known adult content sites/brands
    RegExp(r'\b(brazzers|pornhub|xvideos|onlyfans|playboy|penthouse|hustler)\b', caseSensitive: false),
    
    // Asian adult content patterns (specific enough to avoid false positives)
    RegExp(r'\b(javhd|jav-hd|fc2-ppv|fc2 ppv|tokyo-hot|caribbeancom)\b', caseSensitive: false),
    
    // File naming patterns (requires delimiters to avoid false positives)
    RegExp(r'[-_\.](xxx|porn|adult|sex|nsfw)[-_\.]', caseSensitive: false),
    
    // Resolution + adult keyword combinations (high confidence)
    RegExp(r'(1080p|720p|4k|2160p|uhd).*\b(xxx|porn|adult)\b', caseSensitive: false),
    RegExp(r'\b(xxx|porn|adult)\b.*(1080p|720p|4k|2160p|uhd)', caseSensitive: false),
    
    // Hentai/anime adult content (specific terms)
    RegExp(r'\b(hentai|ecchi|r18|r-18|doujin|ero-anime)\b', caseSensitive: false),
    
    // Scene group patterns (adult release groups)
    RegExp(r'\b(x-art|sexart|metart|nubilefilms)\b', caseSensitive: false),
    
    // Site rip pattern (common for adult content collections)
    RegExp(r'\b(siterip|site-rip|site rip)\b', caseSensitive: false),
    
    // AV/JAV patterns (require additional context to avoid false positives)
    RegExp(r'\b(av|jav)\b.*\b(uncensored|censored|1080p|720p)\b', caseSensitive: false),
    RegExp(r'\[(av|jav)\]', caseSensitive: false),
    
    // Adult content descriptors
    RegExp(r'\b(erotic|softcore|hardcore)\b.*\b(collection|pack|bundle)\b', caseSensitive: false),
    
    // Specific NSFW patterns with context
    RegExp(r'\b(nude|naked)\b.*(collection|pack|photos|videos)', caseSensitive: false),
  ];

  /// Check if category indicates NSFW content
  /// PirateBay uses 5xx categories for adult content
  /// Returns false if category is null
  static bool isNsfwByCategory(String? category) {
    if (category == null || category.isEmpty) {
      return false;
    }
    
    // PirateBay adult categories start with "5"
    // 500-599 are all adult/NSFW categories
    return category.startsWith('5');
  }

  /// Check if torrent name indicates NSFW content using regex patterns
  /// Returns true if any pattern matches
  /// 
  /// Note: This is a best-effort approach and cannot guarantee 100% accuracy.
  /// It aims to minimize false positives while catching common NSFW patterns.
  static bool isNsfwByName(String name) {
    if (name.isEmpty) {
      return false;
    }
    
    // Check against all pre-compiled patterns
    for (final pattern in _nsfwPatterns) {
      if (pattern.hasMatch(name)) {
        return true;
      }
    }
    
    return false;
  }

  /// Main filter method that checks both category and name
  /// Returns true if content should be filtered out
  static bool shouldFilter(String? category, String name) {
    // Category-based filtering (most reliable for PirateBay)
    if (isNsfwByCategory(category)) {
      return true;
    }
    
    // Name-based filtering (for TorrentsCsv and extra safety)
    if (isNsfwByName(name)) {
      return true;
    }
    
    return false;
  }
}

