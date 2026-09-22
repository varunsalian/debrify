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
