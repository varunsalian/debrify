import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import 'torrent_filter_matcher.dart';

/// Audio-language source policy used by Stremio TV.
///
/// The policy is intentionally conservative:
/// - a source is blocked only when its detected languages are known and ALL
///   of them are blocked;
/// - mixed-language sources survive if they contain any allowed language;
/// - unknown and ambiguous multi-audio sources survive as fallbacks;
/// - a preferred language changes ordering, not eligibility.
class StremioTvAudioPolicy {
  const StremioTvAudioPolicy._();

  static String _searchableText(Torrent source) {
    final description = source.badgeDescription;
    return description == null || description.isEmpty
        ? source.name
        : '${source.name}\n$description';
  }

  /// Explicitly known languages for this source.
  ///
  /// Authoritative track metadata wins when available. Otherwise we inspect
  /// the release/addon text using Debrify's existing language detector.
  static Set<AudioLanguage> explicitLanguages(Torrent source) {
    final metadata = source.audioLanguages;

    if (metadata != null && metadata.isNotEmpty) {
      final result = <AudioLanguage>{};

      for (final raw in metadata) {
        final language = TorrentFilterMatcher.audioLanguageForCode(raw);
        if (language != null && language != AudioLanguage.multiAudio) {
          result.add(language);
        }
      }

      return result;
    }

    final text = _searchableText(source);
    final result = <AudioLanguage>{};

    for (final language in AudioLanguage.values) {
      if (language == AudioLanguage.multiAudio) continue;

      if (TorrentFilterMatcher.nameHasLanguage(text, language)) {
        result.add(language);
      }
    }

    return result;
  }

  static bool _metadataHasUnknownLanguage(Torrent source) {
    final metadata = source.audioLanguages;
    if (metadata == null || metadata.isEmpty) return false;

    for (final raw in metadata) {
      if (raw.trim().isEmpty) continue;

      if (TorrentFilterMatcher.audioLanguageForCode(raw) == null) {
        return true;
      }
    }

    return false;
  }

  static bool isMultiAudio(Torrent source) {
    final metadata = source.audioLanguages;

    if (metadata != null && metadata.isNotEmpty) {
      final languages = <AudioLanguage>{};

      for (final raw in metadata) {
        final language = TorrentFilterMatcher.audioLanguageForCode(raw);
        if (language != null && language != AudioLanguage.multiAudio) {
          languages.add(language);
        }
      }

      if (languages.length > 1) return true;
    }

    return TorrentFilterMatcher.hasMultiAudioTag(_searchableText(source));
  }

  static bool hasLanguage(Torrent source, AudioLanguage language) {
    if (language == AudioLanguage.multiAudio) {
      return isMultiAudio(source);
    }

    final metadata = source.audioLanguages;

    if (metadata != null && metadata.isNotEmpty) {
      for (final raw in metadata) {
        if (TorrentFilterMatcher.audioLanguageForCode(raw) == language) {
          return true;
        }
      }
      return false;
    }

    return TorrentFilterMatcher.nameHasLanguage(
      _searchableText(source),
      language,
    );
  }

  /// Returns true only when we can safely say the source contains no allowed
  /// detected language.
  static bool shouldBlock(
    Torrent source,
    Set<AudioLanguage> blockedLanguages,
  ) {
    if (blockedLanguages.isEmpty) return false;

    final languages = explicitLanguages(source);

    // No language evidence: keep it as a fallback.
    if (languages.isEmpty) return false;

    // Metadata contains an unrecognised track language. We cannot safely say
    // that every track is blocked.
    if (_metadataHasUnknownLanguage(source)) return false;

    // A release tagged only "Multi-Audio RUS", for example, may contain an
    // unlabelled second language. Avoid destructive guessing.
    if (source.audioLanguages == null &&
        isMultiAudio(source) &&
        languages.every(blockedLanguages.contains)) {
      return false;
    }

    return languages.every(blockedLanguages.contains);
  }

  /// Lower rank = higher priority.
  ///
  /// Preferred language:
  ///   0 explicit preferred language
  ///   1 ambiguous/multi-audio
  ///   2 unknown language
  ///   3 explicitly known non-preferred language
  static int preferenceRank(
    Torrent source,
    AudioLanguage? preferredLanguage,
  ) {
    if (preferredLanguage == null) return 0;

    if (hasLanguage(source, preferredLanguage)) return 0;

    if (isMultiAudio(source)) return 1;

    if (explicitLanguages(source).isEmpty) return 2;

    return 3;
  }

  static List<Torrent> filterBlocked(
    Iterable<Torrent> sources,
    Set<AudioLanguage> blockedLanguages,
  ) {
    if (blockedLanguages.isEmpty) return sources.toList();

    return sources
        .where((source) => !shouldBlock(source, blockedLanguages))
        .toList();
  }
}
