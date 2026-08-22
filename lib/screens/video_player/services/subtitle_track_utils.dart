import 'package:media_kit/media_kit.dart' as mk;

const _addonSubtitleFilenamePrefix = 'stremio_sub_';

/// Whether [track] points at a temporary subtitle downloaded by this app.
///
/// libmpv also marks automatically discovered sidecar files as external, so
/// `track.external` alone cannot distinguish addon tracks from local sidecars.
bool isAppManagedAddonSubtitleTrack(mk.SubtitleTrack track) {
  if (!track.external) return false;

  final source = track.externalFilename ?? (track.uri ? track.id : null);
  if (source == null || source.isEmpty) return false;

  final parsedPath = Uri.tryParse(source)?.path;
  final normalizedPath =
      (parsedPath == null || parsedPath.isEmpty ? source : parsedPath)
          .replaceAll('\\', '/');
  final filename = normalizedPath.substring(
    normalizedPath.lastIndexOf('/') + 1,
  );
  return filename.startsWith(_addonSubtitleFilenamePrefix);
}

List<mk.SubtitleTrack> embeddedSubtitleTracks(
  Iterable<mk.SubtitleTrack> tracks,
) => tracks
    .where(
      (track) =>
          !isAppManagedAddonSubtitleTrack(track) &&
          track.id.toLowerCase() != 'auto' &&
          track.id.toLowerCase() != 'no',
    )
    .toList(growable: false);
