import 'language_mapping.dart';

/// The opt-in rule uses the selected audio, never the movie's original language
/// or the existence of another matching audio track.
bool allowsAutomaticSubtitles({
  required bool onlyForeignAudio,
  required String? preferredAudio,
  required String? selectedAudio,
}) {
  if (!onlyForeignAudio) return true;
  final preferred = LanguageMapper.canonicalLanguage(preferredAudio);
  final selected = LanguageMapper.canonicalLanguage(selectedAudio);
  return preferred != null && selected != null && preferred != selected;
}

/// mpv exposes forced disposition on track-list entries, not media_kit tracks.
/// Read scalar properties so selection does not depend on node serialization.
Future<String?> findForcedSubtitleId({
  required Future<String> Function(String) readProperty,
  required String? preferredSubtitle,
  required bool Function() isCurrent,
}) async {
  if (preferredSubtitle == 'off' || !isCurrent()) return null;
  Future<String> read(String key) async {
    try {
      return await readProperty(key);
    } catch (_) {
      return ''; // Missing metadata cannot establish forced disposition/language.
    }
  }

  final language = preferredSubtitle ?? 'en';
  final count = int.tryParse(await read('track-list/count')) ?? 0;
  for (var i = 0; i < count; i++) {
    if (!isCurrent()) return null;
    final prefix = 'track-list/$i';
    if (await read('$prefix/type') != 'sub') continue;
    if (await read('$prefix/forced') != 'yes') continue;
    if (await read('$prefix/external') == 'yes') continue;
    final tag = await read('$prefix/lang');
    if (!LanguageMapper.matchesLanguage(language, tag)) continue;
    final id = await read('$prefix/id');
    if (!isCurrent()) return null;
    if (int.tryParse(id) != null) return id;
  }
  return null;
}
