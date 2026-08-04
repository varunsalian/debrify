import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../widgets/torrent_result_row.dart' show TorrentQualityExtension;
import 'format_tag_detector.dart';

/// Pure, name-based torrent filter matching — a faithful copy of Home's
/// `_buildTorrentMetadataMap` / `_detectQualityTier` / `_detectRipSource` /
/// `_detectAudioLanguage` classification, extracted so the Search tab filters
/// results identically without touching the Home screen.
class TorrentFilterMatcher {
  const TorrentFilterMatcher._();

  /// Returns [torrents] filtered by [filters]. An empty facet matches all.
  static List<Torrent> apply(List<Torrent> torrents, TorrentFilterState filters) {
    if (filters.isEmpty) return torrents;
    return torrents.where((t) => _matches(t, filters)).toList();
  }

  static bool _matches(Torrent t, TorrentFilterState f) {
    if (f.qualities.isNotEmpty) {
      // Use the SAME classifier the result-row badge uses (the qualityTier
      // extension) so a filter can never hide a row that visibly carries that
      // quality badge.
      if (!f.qualities.contains(t.qualityTier)) return false;
    }
    if (f.ripSources.isNotEmpty && !f.ripSources.contains(detectRipSource(t.name))) {
      return false;
    }
    if (f.languages.isNotEmpty) {
      final l = detectAudioLanguage(t.name);
      if (l == null || !f.languages.contains(l)) return false;
    }
    if (f.sizes.isNotEmpty) {
      // Unknown size (bucket == null) matches no bucket, so a size filter
      // hides sizeless results. Callers gate this facet off for series, where
      // pack sizes are per-episode and misleading (see the Search tab).
      final bucket = sizeBucketForBytes(t.sizeBytes);
      if (bucket == null || !f.sizes.contains(bucket)) return false;
    }
    if (f.dynamicRanges.isNotEmpty &&
        !f.dynamicRanges.contains(detectDynamicRange(t.name))) {
      return false;
    }
    return true;
  }

  /// HDR when the name carries any HDR-family tag, SDR otherwise.
  ///
  /// Reads [FormatTagDetector], the same classifier behind the row's badges,
  /// rather than a private token list — so "exclude HDR" can never hide a row
  /// that shows no HDR badge, nor keep one that does. That also means it
  /// inherits the detector's word-boundary rule, which is what stops the very
  /// common `HDRip` from being read as `HDR`.
  static DynamicRange detectDynamicRange(String rawName) {
    for (final tag in FormatTagDetector.detect(rawName)) {
      switch (tag) {
        case FormatTag.dolbyVision:
        case FormatTag.hdr10Plus:
        case FormatTag.hdr10:
        case FormatTag.hlg:
        case FormatTag.hdr:
          return DynamicRange.hdr;
        default:
          continue;
      }
    }
    return DynamicRange.sdr;
  }

  /// Bare "WEB" as its own word — catches dotted scene names like
  /// `Show.S01E01.2160p.WEB.H265-GRP`, which none of the substring tokens
  /// match ('web ' needs a trailing space). Checked LAST, after every other
  /// family, so a name carrying any real rip token keeps its historical
  /// classification (a title word "Web" must not steal
  /// "Charlottes.Web.2006.DVDRip" from dvdrip). Accepted false positive: a
  /// bare title word with NO other rip token reads as web instead of other.
  /// Keep in sync with FormatTagDetector (see the note on `qualityTier`).
  static final RegExp _bareWeb = RegExp(r'\bweb\b');

  static RipSourceCategory detectRipSource(String rawName) {
    final lower = rawName.toLowerCase();
    if (_matchesAny(lower, ['bluray', 'blu-ray', 'bdrip', 'brrip', 'remux'])) {
      return RipSourceCategory.bluRay;
    }
    if (_matchesAny(lower, [
      'webrip',
      'web-dl',
      'webdl',
      'webhd',
      'webmux',
      'web ',
      'amzn',
      'nf.web',
    ])) {
      return RipSourceCategory.web;
    }
    if (_matchesAny(lower, ['hdrip', 'hdtv', 'ppv', 'dsr'])) {
      return RipSourceCategory.hdrip;
    }
    if (_matchesAny(lower, ['dvdrip', 'dvd-rip', 'dvdscr', 'dvd'])) {
      return RipSourceCategory.dvdrip;
    }
    if (RegExp(r'\b(cam|hdcam|camrip|telesync|ts|tc)\b').hasMatch(lower)) {
      return RipSourceCategory.cam;
    }
    if (_bareWeb.hasMatch(lower)) {
      return RipSourceCategory.web;
    }
    return RipSourceCategory.other;
  }

  static const List<String> _multiAudioTokens = [
    'multi-audio',
    'multi audio',
    'multiaudio',
    'dual-audio',
    'dual audio',
    'dualaudio',
    'multi-lang',
    'multilang',
  ];

  /// One pattern per language, shared by [detectAudioLanguage] (first match
  /// in [_languageDetectionOrder] wins — a single badge) and
  /// [nameHasLanguage] (per-language membership — the quick-play ladder,
  /// which must accept multi-tag lists like "ENG.LATINO.HINDI" for ANY of
  /// the tagged languages).
  static final Map<AudioLanguage, RegExp> _languagePatterns = {
    AudioLanguage.hindi: RegExp(r'\b(hindi|hin)\b'),
    AudioLanguage.spanish: RegExp(r'\b(spanish|spa|esp|latino|castellano)\b'),
    AudioLanguage.french: RegExp(r'\b(french|fra|fre|vf|vff|vfq)\b'),
    AudioLanguage.german: RegExp(r'\b(german|ger|deu)\b'),
    AudioLanguage.russian: RegExp(r'\b(russian|rus)\b'),
    AudioLanguage.chinese: RegExp(r'\b(chinese|chi|chs|cht|mandarin|cantonese)\b'),
    AudioLanguage.japanese: RegExp(r'\b(japanese|jap|jpn)\b'),
    AudioLanguage.korean: RegExp(r'\b(korean|kor)\b'),
    AudioLanguage.italian: RegExp(r'\b(italian|ita)\b'),
    AudioLanguage.portuguese: RegExp(r'\b(portuguese|por|pt-br)\b'),
    AudioLanguage.arabic: RegExp(r'\b(arabic|ara)\b'),
    AudioLanguage.english: RegExp(r'\b(english|eng)\b'),
  };

  /// Detection order for the single-badge classifier — must stay exactly the
  /// historical if-chain order (english LAST) so badges don't change.
  static const List<AudioLanguage> _languageDetectionOrder = [
    AudioLanguage.hindi,
    AudioLanguage.spanish,
    AudioLanguage.french,
    AudioLanguage.german,
    AudioLanguage.russian,
    AudioLanguage.chinese,
    AudioLanguage.japanese,
    AudioLanguage.korean,
    AudioLanguage.italian,
    AudioLanguage.portuguese,
    AudioLanguage.arabic,
    AudioLanguage.english,
  ];

  /// Whether the name carries an explicit multi/dual-audio tag.
  static bool hasMultiAudioTag(String rawName) =>
      _matchesAny(rawName.toLowerCase(), _multiAudioTokens);

  /// Whether the name carries [language]'s token — independent of what
  /// [detectAudioLanguage] would pick first.
  static bool nameHasLanguage(String rawName, AudioLanguage language) {
    if (language == AudioLanguage.multiAudio) return hasMultiAudioTag(rawName);
    return _languagePatterns[language]!.hasMatch(rawName.toLowerCase());
  }

  static AudioLanguage? detectAudioLanguage(String rawName) {
    final lower = rawName.toLowerCase();
    if (_matchesAny(lower, _multiAudioTokens)) {
      return AudioLanguage.multiAudio;
    }
    for (final language in _languageDetectionOrder) {
      if (_languagePatterns[language]!.hasMatch(lower)) return language;
    }
    return null;
  }

  static bool _matchesAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }
}
