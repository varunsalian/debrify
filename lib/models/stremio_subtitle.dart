/// Represents a subtitle track from a Stremio addon.
///
/// Stremio subtitle addons return subtitles via:
/// `GET {baseUrl}/subtitles/{type}/{id}.json`
///
/// Response format:
/// ```json
/// {
///   "subtitles": [
///     {"id": "...", "url": "...", "lang": "eng", "label": "English"}
///   ]
/// }
/// ```
class StremioSubtitle {
  /// Unique identifier for this subtitle
  final String id;

  /// Direct URL to the subtitle file (SRT, VTT, etc.)
  final String url;

  /// Language code (e.g., 'eng', 'spa', 'por')
  final String lang;

  /// Human-readable label (e.g., 'English', 'Spanish')
  final String? label;

  /// Source addon name
  final String source;

  const StremioSubtitle({
    required this.id,
    required this.url,
    required this.lang,
    this.label,
    required this.source,
  });

  /// Display name for UI (label or formatted language)
  String get displayName {
    if (label != null && label!.isNotEmpty) {
      return label!;
    }
    return _formatLanguageCode(lang);
  }

  /// Full display name including source addon
  String get displayNameWithSource => '$displayName ($source)';

  /// Format language code to readable name
  static String _formatLanguageCode(String code) {
    const languageNames = {
      'eng': 'English',
      'spa': 'Spanish',
      'por': 'Portuguese',
      'fra': 'French',
      'deu': 'German',
      'ita': 'Italian',
      'rus': 'Russian',
      'jpn': 'Japanese',
      'kor': 'Korean',
      'zho': 'Chinese',
      'chi': 'Chinese',
      'ara': 'Arabic',
      'hin': 'Hindi',
      'tur': 'Turkish',
      'pol': 'Polish',
      'nld': 'Dutch',
      'swe': 'Swedish',
      'nor': 'Norwegian',
      'dan': 'Danish',
      'fin': 'Finnish',
      'ces': 'Czech',
      'hun': 'Hungarian',
      'ron': 'Romanian',
      'ell': 'Greek',
      'heb': 'Hebrew',
      'tha': 'Thai',
      'vie': 'Vietnamese',
      'ind': 'Indonesian',
      'msa': 'Malay',
      'fil': 'Filipino',
      'ukr': 'Ukrainian',
      'bul': 'Bulgarian',
      'hrv': 'Croatian',
      'srp': 'Serbian',
      'slk': 'Slovak',
      'slv': 'Slovenian',
      'est': 'Estonian',
      'lav': 'Latvian',
      'lit': 'Lithuanian',
      // 2-letter codes (ISO 639-1)
      'en': 'English',
      'es': 'Spanish',
      'pt': 'Portuguese',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'ru': 'Russian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'tr': 'Turkish',
      'pl': 'Polish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'no': 'Norwegian',
      'da': 'Danish',
      'fi': 'Finnish',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'el': 'Greek',
      'he': 'Hebrew',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'id': 'Indonesian',
      'ms': 'Malay',
      'uk': 'Ukrainian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sr': 'Serbian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'et': 'Estonian',
      'lv': 'Latvian',
      'lt': 'Lithuanian',
    };

    final lowerCode = code.toLowerCase();
    return languageNames[lowerCode] ?? code.toUpperCase();
  }

  factory StremioSubtitle.fromJson(
    Map<String, dynamic> json,
    String source,
  ) {
    // Generate ID if not provided
    final id = json['id'] as String? ??
        '${source}_${json['lang'] ?? 'unknown'}_${json['url'].hashCode}';

    return StremioSubtitle(
      id: id,
      url: json['url'] as String,
      lang: json['lang'] as String? ?? 'unknown',
      label: json['label'] as String?,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'lang': lang,
        if (label != null) 'label': label,
        'source': source,
      };

  @override
  String toString() =>
      'StremioSubtitle(lang: $lang, label: $label, source: $source)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StremioSubtitle && other.id == id && other.url == url;
  }

  @override
  int get hashCode => id.hashCode ^ url.hashCode;
}

/// Result of fetching subtitles from multiple addons
class StremioSubtitleResult {
  /// All subtitles fetched successfully
  final List<StremioSubtitle> subtitles;

  /// Addons that failed to respond
  final List<String> failedAddons;

  const StremioSubtitleResult({
    required this.subtitles,
    this.failedAddons = const [],
  });

  /// Check if any subtitles were found
  bool get hasSubtitles => subtitles.isNotEmpty;

  /// Get subtitles grouped by language
  Map<String, List<StremioSubtitle>> get byLanguage {
    final map = <String, List<StremioSubtitle>>{};
    for (final sub in subtitles) {
      map.putIfAbsent(sub.lang, () => []).add(sub);
    }
    return map;
  }

  /// Get subtitles grouped by source addon
  Map<String, List<StremioSubtitle>> get bySource {
    final map = <String, List<StremioSubtitle>>{};
    for (final sub in subtitles) {
      map.putIfAbsent(sub.source, () => []).add(sub);
    }
    return map;
  }
}
