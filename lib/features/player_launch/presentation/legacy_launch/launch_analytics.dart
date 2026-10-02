import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/models/playlist_entry.dart';

final class LaunchAnalytics {
  static String analyticsProviderLabel(VideoPlayerLaunchArgs args) {
    if (args.rdTorrentId != null && args.rdTorrentId!.isNotEmpty) {
      return 'real_debrid';
    }
    if (args.torboxTorrentId != null && args.torboxTorrentId!.isNotEmpty) {
      return 'torbox';
    }
    if (args.pikpakCollectionId != null && args.pikpakCollectionId!.isNotEmpty) {
      return 'pikpak';
    }
    if (args.stremioTvChannels != null) {
      return 'stremio_tv';
    }
    if (args.iptvChannels != null) {
      return 'iptv';
    }
    if (args.stremioSources != null && args.stremioSources!.isNotEmpty) {
      return 'stremio';
    }
    final playlistProvider = LaunchAnalytics.analyticsPlaylistProviderLabel(args.playlist);
    if (playlistProvider != null) {
      return playlistProvider;
    }
    final urlProvider = LaunchAnalytics.analyticsUrlProviderLabel(args.videoUrl);
    if (urlProvider != null) {
      return urlProvider;
    }
    return 'direct';
  }

  static String? analyticsPlaylistProviderLabel(
    List<PlaylistEntry>? playlist,
  ) {
    if (playlist == null || playlist.isEmpty) return null;

    for (final entry in playlist) {
      final explicitProvider = entry.provider?.trim().toLowerCase();
      if (explicitProvider == 'torbox') return 'torbox';
      if (explicitProvider == 'pikpak') return 'pikpak';
      if (explicitProvider == 'realdebrid' ||
          explicitProvider == 'real_debrid' ||
          explicitProvider == 'real debrid') {
        return 'real_debrid';
      }

      if (entry.torboxTorrentId != null ||
          entry.torboxWebDownloadId != null ||
          entry.torboxFileId != null) {
        return 'torbox';
      }
      if (entry.pikpakFileId != null) {
        return 'pikpak';
      }
      if (entry.rdTorrentId != null && entry.rdTorrentId!.isNotEmpty) {
        return 'real_debrid';
      }
    }

    return null;
  }

  static String? analyticsUrlProviderLabel(String videoUrl) {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;

    if (host.contains('real-debrid')) {
      return 'real_debrid';
    }
    if (host.contains('mypikpak') || host.contains('pikpak')) {
      return 'pikpak';
    }
    if (host.contains('torbox') || host.contains('tb-cdn.')) {
      return 'torbox';
    }

    return null;
  }
}
