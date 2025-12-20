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
    final title = (t.title as String?)?.trim();
    if (title != null &&
        title.isNotEmpty &&
        title.toLowerCase() != 'no' &&
        title.toLowerCase() != 'auto') {
      final langPretty = niceLanguage(title);
      return langPretty.isNotEmpty ? langPretty : title;
    }
    final id = (t.id as String?)?.trim();
    if (id != null &&
        id.isNotEmpty &&
        id.toLowerCase() != 'no' &&
        id.toLowerCase() != 'auto') {
      final langPretty = niceLanguage(id);
      if (langPretty.isNotEmpty) return langPretty;
    }
    return 'Track ${index + 1}';
  }
}
