/// Utility for robust subtitle language matching and display.
/// Handles ISO 639-1, ISO 639-2, regional variants, and common language names.
class LanguageMapper {
  /// Comprehensive language code mapping.
  /// Maps ISO 639-1 (2-letter) codes to all known variants.
  static const Map<String, Set<String>> _languageVariants = {
    'en': {'en', 'eng', 'english', 'en-us', 'en-gb', 'en-au', 'en-ca', 'en-nz', 'en-ie', 'en-za'},
    'es': {'es', 'spa', 'spanish', 'español', 'espanol', 'es-es', 'es-mx', 'es-ar', 'es-co', 'es-419', 'es-la', 'lat', 'latino'},
    'fr': {'fr', 'fra', 'fre', 'french', 'français', 'francais', 'fr-fr', 'fr-ca', 'fr-be', 'fr-ch'},
    'de': {'de', 'deu', 'ger', 'german', 'deutsch', 'de-de', 'de-at', 'de-ch'},
    'it': {'it', 'ita', 'italian', 'italiano', 'it-it', 'it-ch'},
    'pt': {'pt', 'por', 'portuguese', 'português', 'portugues', 'pt-pt', 'pt-br', 'pb', 'pob'},
    'ru': {'ru', 'rus', 'russian', 'русский', 'russkiy', 'ru-ru'},
    'ja': {'ja', 'jpn', 'japanese', '日本語', 'nihongo', 'ja-jp', 'jp'},
    'ko': {'ko', 'kor', 'korean', '한국어', 'hangugeo', 'ko-kr', 'kr'},
    'zh': {'zh', 'zho', 'chi', 'chinese', '中文', 'zhongwen', 'zh-cn', 'zh-tw', 'zh-hk', 'zh-sg', 'zh-hans', 'zh-hant', 'cmn', 'yue', 'mandarin', 'cantonese'},
    'ar': {'ar', 'ara', 'arabic', 'العربية', 'arabiya', 'ar-sa', 'ar-eg', 'ar-ae'},
    'hi': {'hi', 'hin', 'hindi', 'हिन्दी', 'हिंदी', 'hi-in'},
    'nl': {'nl', 'nld', 'dut', 'dutch', 'nederlands', 'nl-nl', 'nl-be', 'flemish', 'vlaams'},
    'pl': {'pl', 'pol', 'polish', 'polski', 'pl-pl'},
    'tr': {'tr', 'tur', 'turkish', 'türkçe', 'turkce', 'tr-tr'},
    'sv': {'sv', 'swe', 'swedish', 'svenska', 'sv-se'},
    'da': {'da', 'dan', 'danish', 'dansk', 'da-dk'},
    'no': {'no', 'nor', 'nob', 'nno', 'norwegian', 'norsk', 'no-no', 'nb', 'nn', 'nb-no', 'nn-no', 'bokmal', 'bokmål', 'nynorsk'},
    'fi': {'fi', 'fin', 'finnish', 'suomi', 'fi-fi'},
    'el': {'el', 'ell', 'gre', 'greek', 'ελληνικά', 'ellinika', 'el-gr'},
    'he': {'he', 'heb', 'hebrew', 'עברית', 'ivrit', 'he-il', 'iw'},
    'th': {'th', 'tha', 'thai', 'ไทย', 'th-th'},
    'vi': {'vi', 'vie', 'vietnamese', 'tiếng việt', 'tieng viet', 'vi-vn'},
    'id': {'id', 'ind', 'indonesian', 'bahasa indonesia', 'id-id', 'in'},
    'ms': {'ms', 'msa', 'may', 'malay', 'bahasa melayu', 'ms-my'},
    'cs': {'cs', 'ces', 'cze', 'czech', 'čeština', 'cestina', 'cs-cz'},
    'sk': {'sk', 'slk', 'slo', 'slovak', 'slovenčina', 'slovencina', 'sk-sk'},
    'hu': {'hu', 'hun', 'hungarian', 'magyar', 'hu-hu'},
    'ro': {'ro', 'ron', 'rum', 'romanian', 'română', 'romana', 'ro-ro'},
    'bg': {'bg', 'bul', 'bulgarian', 'български', 'balgarski', 'bg-bg'},
    'uk': {'uk', 'ukr', 'ukrainian', 'українська', 'ukrainska', 'uk-ua'},
    'hr': {'hr', 'hrv', 'croatian', 'hrvatski', 'hr-hr'},
    'sr': {'sr', 'srp', 'serbian', 'српски', 'srpski', 'sr-rs', 'sr-latn', 'sr-cyrl'},
    'sl': {'sl', 'slv', 'slovenian', 'slovenščina', 'slovenscina', 'sl-si'},
    'et': {'et', 'est', 'estonian', 'eesti', 'et-ee'},
    'lv': {'lv', 'lav', 'latvian', 'latviešu', 'latviesu', 'lv-lv'},
    'lt': {'lt', 'lit', 'lithuanian', 'lietuvių', 'lietuviu', 'lt-lt'},
    'fa': {'fa', 'fas', 'per', 'persian', 'farsi', 'فارسی', 'fa-ir'},
    'bn': {'bn', 'ben', 'bengali', 'bangla', 'বাংলা', 'bn-bd', 'bn-in'},
    'ta': {'ta', 'tam', 'tamil', 'தமிழ்', 'ta-in', 'ta-lk'},
    'te': {'te', 'tel', 'telugu', 'తెలుగు', 'te-in'},
    'mr': {'mr', 'mar', 'marathi', 'मराठी', 'mr-in'},
    'gu': {'gu', 'guj', 'gujarati', 'ગુજરાતી', 'gu-in'},
    'kn': {'kn', 'kan', 'kannada', 'ಕನ್ನಡ', 'kn-in'},
    'ml': {'ml', 'mal', 'malayalam', 'മലയാളം', 'ml-in'},
    'pa': {'pa', 'pan', 'punjabi', 'ਪੰਜਾਬੀ', 'پنجابی', 'pa-in', 'pa-pk'},
  };

  /// Display names for ISO 639-1 codes.
  static const Map<String, String> _displayNames = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'nl': 'Dutch',
    'pl': 'Polish',
    'tr': 'Turkish',
    'sv': 'Swedish',
    'da': 'Danish',
    'no': 'Norwegian',
    'fi': 'Finnish',
    'el': 'Greek',
    'he': 'Hebrew',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'ms': 'Malay',
    'cs': 'Czech',
    'sk': 'Slovak',
    'hu': 'Hungarian',
    'ro': 'Romanian',
    'bg': 'Bulgarian',
    'uk': 'Ukrainian',
    'hr': 'Croatian',
    'sr': 'Serbian',
    'sl': 'Slovenian',
    'et': 'Estonian',
    'lv': 'Latvian',
    'lt': 'Lithuanian',
    'fa': 'Persian',
    'bn': 'Bengali',
    'ta': 'Tamil',
    'te': 'Telugu',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'kn': 'Kannada',
    'ml': 'Malayalam',
    'pa': 'Punjabi',
  };

  /// Reverse lookup map (built lazily).
  static Map<String, String>? _reverseLookup;

  static Map<String, String> get _getReverseLookup {
    if (_reverseLookup != null) return _reverseLookup!;

    _reverseLookup = {};
    for (final entry in _languageVariants.entries) {
      final iso6391 = entry.key;
      for (final variant in entry.value) {
        _reverseLookup![variant.toLowerCase()] = iso6391;
      }
    }
    return _reverseLookup!;
  }

  /// Get human-readable language name from any language code/tag.
  static String niceLanguage(String? codeOrTitle) {
    if (codeOrTitle == null || codeOrTitle.isEmpty) return '';

    final v = codeOrTitle.toLowerCase().trim();

    // Try direct lookup in display names
    if (_displayNames.containsKey(v)) {
      return _displayNames[v]!;
    }

    // Try to find canonical code and get display name
    final canonical = _getReverseLookup[v];
    if (canonical != null && _displayNames.containsKey(canonical)) {
      return _displayNames[canonical]!;
    }

    // Try normalized version
    final normalized = _normalizeLanguageTag(v);
    final normalizedCanonical = _getReverseLookup[normalized];
    if (normalizedCanonical != null && _displayNames.containsKey(normalizedCanonical)) {
      return _displayNames[normalizedCanonical]!;
    }

    return '';
  }

  /// Check if a track's language matches the target language.
  ///
  /// [targetLang] - The user's selected language (ISO 639-1, e.g., 'en')
  /// [trackLang] - The track's language tag (could be anything)
  ///
  /// Returns true if they match.
  static bool matchesLanguage(String targetLang, String? trackLang) {
    if (trackLang == null || trackLang.isEmpty) return false;

    final targetLower = targetLang.toLowerCase().trim();
    final trackLower = trackLang.toLowerCase().trim();

    // Direct match
    if (targetLower == trackLower) return true;

    // Get the canonical ISO 639-1 code for target
    final targetCanonical = _getReverseLookup[targetLower] ?? targetLower;

    // Get the variants for the target language
    final targetVariants = _languageVariants[targetCanonical];
    if (targetVariants == null) {
      // Unknown language - fall back to prefix matching
      return _prefixMatch(targetLower, trackLower);
    }

    // Check if track language is in the target's variants
    if (targetVariants.contains(trackLower)) return true;

    // Try to normalize track language and check again
    final trackNormalized = _normalizeLanguageTag(trackLower);
    if (targetVariants.contains(trackNormalized)) return true;

    // Check if track's canonical form matches target
    final trackCanonical = _getReverseLookup[trackLower] ?? _getReverseLookup[trackNormalized];
    if (trackCanonical == targetCanonical) return true;

    // Last resort: prefix matching for regional variants
    return _prefixMatch(targetCanonical, trackLower) ||
           _prefixMatch(targetCanonical, trackNormalized);
  }

  /// Normalize a language tag by removing common suffixes and extracting base.
  static String _normalizeLanguageTag(String tag) {
    // Remove common suffixes like -sdh, -forced, -cc, -full, etc.
    var normalized = tag
        .replaceAll(RegExp(r'[-_](sdh|forced|cc|full|commentary|descriptive|ad|hi)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[-_](sub|subs|subtitle|subtitles)$', caseSensitive: false), '');

    // Extract base language from regional variants (e.g., 'en-us' -> 'en')
    if (normalized.contains('-') || normalized.contains('_')) {
      final parts = normalized.split(RegExp(r'[-_]'));
      if (parts.isNotEmpty && parts[0].length >= 2) {
        // Check if first part is a known language code
        if (_getReverseLookup.containsKey(parts[0]) || _languageVariants.containsKey(parts[0])) {
          return parts[0];
        }
      }
    }

    return normalized;
  }

  /// Check if track language starts with target language code.
  static bool _prefixMatch(String target, String track) {
    if (track.startsWith('$target-') || track.startsWith('${target}_')) {
      return true;
    }
    return false;
  }

  /// Legacy method for track label display.
  static String labelForTrack(dynamic t, int index) {
    // 1. First, check the language property (this is the correct metadata field)
    final language = (t.language as String?)?.trim();
    if (language != null && language.isNotEmpty) {
      final langPretty = niceLanguage(language);
      if (langPretty.isNotEmpty) return langPretty;
      // If language code not in our map, return it as-is (e.g., "jpn" for Japanese)
      return language;
    }

    // 2. Fall back to title
    final title = (t.title as String?)?.trim();
    if (title != null &&
        title.isNotEmpty &&
        title.toLowerCase() != 'no' &&
        title.toLowerCase() != 'auto') {
      final langPretty = niceLanguage(title);
      return langPretty.isNotEmpty ? langPretty : title;
    }

    // 3. Fall back to id (unlikely to help but keep for compatibility)
    final id = (t.id as String?)?.trim();
    if (id != null &&
        id.isNotEmpty &&
        id.toLowerCase() != 'no' &&
        id.toLowerCase() != 'auto') {
      final langPretty = niceLanguage(id);
      if (langPretty.isNotEmpty) return langPretty;
    }

    // 4. Last resort: generic label
    return 'Track ${index + 1}';
  }
}
