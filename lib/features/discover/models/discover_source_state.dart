import '../../../models/media_server.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';

abstract final class DiscoverSources {
  static const cw = 'cw';
  static const trakt = 'trakt';
  static const simkl = 'simkl';
  static const tmdb = 'tmdb';
  static const jellyfin = 'jellyfin';
  static const emby = 'emby';
  static const plex = 'plex';
  static const mdblist = 'mdblist';
  static const addonPrefix = 'a:';

  /// The media-server kind a source browses, or null for other sources.
  static MediaServerKind? mediaServerKind(String source) => switch (source) {
    jellyfin => MediaServerKind.jellyfin,
    emby => MediaServerKind.emby,
    plex => MediaServerKind.plex,
    _ => null,
  };
}

typedef DiscoverSourceSession = ({
  ProfileSessionOwner owner,
  Object viewIdentity,
  String initialSource,
  bool hasHandoff,
});

class DiscoverSourceState {
  const DiscoverSourceState({required this.source, this.addons = const []});
  final String source;
  final List<StremioAddon> addons;
}

bool discoverLandingLoadIsCurrent({
  required int capturedRevision,
  required int currentRevision,
  required bool hasPendingHandoff,
}) => !hasPendingHandoff && capturedRevision == currentRevision;
