import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../utils/stremio_url.dart';

import 'stremio_subtitle.dart';
import '../screens/video_player/utils/language_mapping.dart';

/// Configuration digests survive restored addons receiving new resource IDs.
abstract final class SubtitleSourcePriority {
  static const preferenceKey = 'subtitle_source_priority_v1';
  static const embedded = 'embedded';
  static String addon(String id) => 'addon:$id';
  static String configurationId(String manifestUrl) => sha256
      .convert(
        utf8.encode(
          manifestUrl.isEmpty
              ? ''
              : normalizeStremioManifestUri(manifestUrl).toString(),
        ),
      )
      .toString();

  static List<String> normalize(Iterable<Object?> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value is String &&
            (value == embedded ||
                (value.startsWith('addon:') && value.length > 6)) &&
            seen.add(value))
          value,
      if (!seen.contains(embedded)) embedded,
    ];
  }

  static List<String> decode(String? value) {
    try {
      final decoded = jsonDecode(value ?? '[]');
      return normalize(decoded is List ? decoded : const []);
    } catch (_) {
      return [embedded];
    }
  }

  /// Removed/disabled sources do not delay fallback. New addons join at the end.
  static List<String> effective(
    Iterable<String> saved,
    Iterable<String> addonIds,
  ) {
    final available = {embedded, ...addonIds.map(addon)};
    final normalized = normalize(saved);
    return [
      ...normalized.where(available.contains),
      ...available.where((id) => !normalized.contains(id)),
    ];
  }

  static List<StremioSubtitle> matching(
    Iterable<StremioSubtitle> subtitles,
    String? language,
  ) {
    if (language == 'off') return [];
    final tracks = subtitles.where((s) => s.url.isNotEmpty).toList();
    final preferred = tracks.where(
      (s) => LanguageMapper.matchesLanguage(language ?? 'en', s.lang),
    );
    return [
      ...preferred,
      if (language == null)
        ...tracks.where((s) => !LanguageMapper.matchesLanguage('en', s.lang)),
    ];
  }
}
