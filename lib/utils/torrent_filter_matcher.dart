import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../widgets/torrent_result_row.dart' show TorrentQualityExtension;

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
    return true;
  }

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
    return RipSourceCategory.other;
  }

  static AudioLanguage? detectAudioLanguage(String rawName) {
    final lower = rawName.toLowerCase();
    if (_matchesAny(lower, [
      'multi-audio',
      'multi audio',
      'multiaudio',
      'dual-audio',
      'dual audio',
      'dualaudio',
      'multi-lang',
      'multilang',
    ])) {
      return AudioLanguage.multiAudio;
    }
    if (RegExp(r'\b(hindi|hin)\b').hasMatch(lower)) return AudioLanguage.hindi;
    if (RegExp(r'\b(spanish|spa|esp|latino|castellano)\b').hasMatch(lower)) {
      return AudioLanguage.spanish;
    }
    if (RegExp(r'\b(french|fra|fre|vf|vff|vfq)\b').hasMatch(lower)) {
      return AudioLanguage.french;
    }
    if (RegExp(r'\b(german|ger|deu)\b').hasMatch(lower)) {
      return AudioLanguage.german;
    }
    if (RegExp(r'\b(russian|rus)\b').hasMatch(lower)) return AudioLanguage.russian;
    if (RegExp(r'\b(chinese|chi|chs|cht|mandarin|cantonese)\b').hasMatch(lower)) {
      return AudioLanguage.chinese;
    }
    if (RegExp(r'\b(japanese|jap|jpn)\b').hasMatch(lower)) {
      return AudioLanguage.japanese;
    }
    if (RegExp(r'\b(korean|kor)\b').hasMatch(lower)) return AudioLanguage.korean;
    if (RegExp(r'\b(italian|ita)\b').hasMatch(lower)) return AudioLanguage.italian;
    if (RegExp(r'\b(portuguese|por|pt-br)\b').hasMatch(lower)) {
      return AudioLanguage.portuguese;
    }
    if (RegExp(r'\b(arabic|ara)\b').hasMatch(lower)) return AudioLanguage.arabic;
    if (RegExp(r'\b(english|eng)\b').hasMatch(lower)) return AudioLanguage.english;
    return null;
  }

  static bool _matchesAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }
}
