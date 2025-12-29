class LanguageMapper {
  static const _languageMap = {
    'en': 'English',
    'eng': 'English',
    'hi': 'Hindi',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fra': 'French',
    'de': 'German',
    'ger': 'German',
    'ru': 'Russian',
    'zh': 'Chinese',
    'zho': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'it': 'Italian',
    'pt': 'Portuguese',
  };

  static String niceLanguage(String? codeOrTitle) {
    final v = (codeOrTitle ?? '').toLowerCase();
    return _languageMap[v] ?? '';
  }

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
