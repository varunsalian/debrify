import 'metadata_preferences.dart';
import 'stremio_addon.dart';

/// Resolves title-card artwork without confusing an episode label with a still.
/// Collection covers are user content and do not use title-provider policies.
({String? primary, String? fallback}) metadataCardArtwork({
  required StremioMeta presented,
  required MetadataPreferences preferences,
  required bool wide,
  String? overrideUrl,
  bool episodeArtwork = false,
  bool collection = false,
}) {
  final category = episodeArtwork
      ? MetadataCategory.episodeArtwork
      : wide
      ? MetadataCategory.backgrounds
      : MetadataCategory.posters;
  final selected =
      preferences.provider(category) != MetadataPreferences.current;
  String? usable(String? value) =>
      value?.trim().isNotEmpty == true ? value : null;
  final primary = collection || episodeArtwork || !selected
      ? overrideUrl ?? presented.poster
      : wide
      ? presented.background
      : presented.poster;
  final fallback = !collection && selected && !preferences.fallback
      ? null
      : usable(presented.poster);
  return (
    primary:
        usable(primary) ??
        (collection || !selected || preferences.fallback
            ? usable(overrideUrl) ?? fallback
            : null),
    fallback: fallback,
  );
}
