import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import 'local_playback_resume_resolver.dart';
import 'media_server_service.dart';
import 'video_player_launcher.dart';

/// Keep library playback on the same revocable native-source path as search.
class MediaServerLibraryPlayback {
  static VideoPlayerLaunchArgs arguments(
    List<Torrent> sources,
    int index, {
    required String title,
  }) {
    final source = sources[index];
    final target = MediaServerService.watchTargetFor(source);
    if (target == null) {
      throw StateError('Media server source is no longer authorized');
    }
    return VideoPlayerLaunchArgs(
      videoUrl: source.directUrl!,
      title: source.displayTitle,
      httpHeaders: source.httpHeaders,
      disableExternalPlayer: true,
      suppressTrackerAutoSync: true,
      contentImdbId: target.contentId,
      contentType: target.isMovie ? 'movie' : 'series',
      contentTitle: title,
      contentSeason: target.season,
      contentEpisode: target.episode,
      resumePolicy: PlaybackResumePolicy.catalogCanonical,
      stremioSources: sources,
      stremioCurrentSourceIndex: index,
      resolveSourceToPlaylist: (candidate) async {
        if (!sources.contains(candidate)) {
          throw StateError('Unknown server source');
        }
        await MediaServerService.authorize(candidate);
        return [
          PlaylistEntry(
            url: candidate.directUrl!,
            title: candidate.displayTitle,
            httpHeaders: candidate.httpHeaders,
          ),
        ];
      },
    );
  }
}
