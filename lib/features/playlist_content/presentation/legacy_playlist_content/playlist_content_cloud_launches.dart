import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/services/webdav_service.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentCloudLaunchesDeps = ({
  PlaylistContentSeriesState seriesState,
  Map<String, dynamic> Function() playlistItem,
  bool Function() mounted,
  VoidCallback? Function() onPlaybackStarted,
  BuildContext Function() context,
  PlaylistViewMode Function(FolderViewMode mode) convertToPlaylistViewMode,
  PlaylistContentNavigationState navigationState,
});

class PlaylistContentCloudLaunches {
  PlaylistContentCloudLaunches(this._deps);
  final PlaylistContentCloudLaunchesDeps _deps;

  /// Play PikPak playlist
  Future<void> playPikPakPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final pikpak = PikPakApiService.instance;

    if (!await pikpak.isAuthenticated()) {
      throw Exception('Please login to PikPak in Settings');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      // Extract PikPak file ID from the path field
      // Format: "pikpak://fileId|fileName"
      String? fileId;
      final path = file.path;
      if (path != null && path.startsWith('pikpak://')) {
        final parts = path.substring(9).split('|');
        if (parts.isNotEmpty) {
          fileId = parts[0];
        }
      }

      if (fileId == null) continue;

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          final fileData = await pikpak.getFileDetails(fileId);
          final streamingUrl = pikpak.getStreamingUrl(fileData);
          entries.add(
            PlaylistEntry(
              url: streamingUrl ?? '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath,
            pikpakFileId: fileId,
            sizeBytes: file.bytes,
            provider: 'pikpak',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _deps.seriesState.seriesPlaylist?.seriesTitle ??
        _deps.playlistItem()['title'] as String? ??
        'Series';

    if (!_deps.mounted()) return;

    // Hide auto-launch overlay before launching player
    _deps.onPlaybackStarted()?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        pikpakCollectionId: _deps.playlistItem()['pikpakFileId'] as String?,
        disableAutoResume: true,
        viewMode: _deps.convertToPlaylistViewMode(
          _deps.navigationState.currentViewMode,
        ),
        // Pass catalog metadata for optimized TVMaze lookup
        contentImdbId: _deps.playlistItem()['imdbId'] as String?,
        contentType: _deps.playlistItem()['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play Premiumize playlist
  Future<void> playPremiumizePlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final infohash = (_deps.playlistItem()['torrent_hash'] as String?)?.trim();
    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Premiumize API key in Settings');
    }

    // Cloud-browser collection: nodes carry cloud item ids in `path`. Resolve
    // only the starting item's link up front; the rest resolve lazily.
    if (infohash == null || infohash.isEmpty) {
      if (videoFiles.isEmpty) throw Exception('No playable files found');
      if (startIndex < 0 || startIndex >= videoFiles.length) startIndex = 0;
      final startId = videoFiles[startIndex].path;
      final startFile = startId != null
          ? await PremiumizeService.resolveItemById(apiKey, startId)
          : null;
      if (startFile == null || startFile.link.isEmpty) {
        throw Exception('Could not get Premiumize streaming URL');
      }
      final List<PlaylistEntry> cloudEntries = [];
      for (int i = 0; i < videoFiles.length; i++) {
        final file = videoFiles[i];
        final id = file.path;
        if (id == null) continue;
        cloudEntries.add(
          PlaylistEntry(
            url: i == startIndex ? startFile.link : '',
            title: file.name,
            relativePath: file.relativePath,
            provider: 'premiumize',
            premiumizeItemId: id,
            sizeBytes: file.bytes,
          ),
        );
      }
      if (cloudEntries.isEmpty) throw Exception('No playable files found');
      final String seriesTitleCloud =
          _deps.seriesState.seriesPlaylist?.seriesTitle ??
          _deps.playlistItem()['title'] as String? ??
          'Series';
      if (!_deps.mounted()) return;
      _deps.onPlaybackStarted()?.call();
      MainPageBridge.notifyPlayerLaunching();
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: cloudEntries[startIndex].url,
          title: seriesTitleCloud,
          subtitle: '${cloudEntries.length} episodes',
          playlist: cloudEntries,
          startIndex: startIndex,
          disableAutoResume: true,
          viewMode: _deps.convertToPlaylistViewMode(
            _deps.navigationState.currentViewMode,
          ),
          contentImdbId: _deps.playlistItem()['imdbId'] as String?,
          contentType: _deps.playlistItem()['contentType'] as String?,
          suppressTraktAutoSync: true,
        ),
      );
      return;
    }

    // Re-resolve fresh direct links and index them by path for matching.
    final resolved = await PremiumizeService.resolveFilesByHash(
      apiKey,
      infohash,
    );
    final linkByPath = <String, String>{
      for (final f in resolved) f.path: f.link,
    };

    final List<PlaylistEntry> entries = [];
    for (final file in videoFiles) {
      final path = file.path;
      if (path == null) continue;
      entries.add(
        PlaylistEntry(
          url: linkByPath[path] ?? '',
          title: file.name,
          relativePath: file.relativePath,
          provider: 'premiumize',
          premiumizeHash: infohash,
          premiumizePath: path,
          torrentHash: infohash,
          sizeBytes: file.bytes,
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }
    if (startIndex < 0 || startIndex >= entries.length) startIndex = 0;

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _deps.seriesState.seriesPlaylist?.seriesTitle ??
        _deps.playlistItem()['title'] as String? ??
        'Series';

    if (!_deps.mounted()) return;

    _deps.onPlaybackStarted()?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        disableAutoResume: true,
        viewMode: _deps.convertToPlaylistViewMode(
          _deps.navigationState.currentViewMode,
        ),
        contentImdbId: _deps.playlistItem()['imdbId'] as String?,
        contentType: _deps.playlistItem()['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play WebDAV playlist
  Future<void> playWebDavPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final config = await resolveWebDavConfig();
    if (config == null) {
      throw Exception('WebDAV server is no longer configured');
    }

    final entries = <PlaylistEntry>[];
    for (final file in videoFiles) {
      final path = file.path;
      if (path == null || path.isEmpty) continue;
      entries.add(
        PlaylistEntry(
          url: WebDavService.directUrl(config, path),
          title: file.name,
          relativePath: file.relativePath ?? path,
          sizeBytes: file.bytes,
          provider: 'webdav',
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }
    if (startIndex < 0 || startIndex >= entries.length) {
      startIndex = 0;
    }

    final seriesTitle =
        _deps.seriesState.seriesPlaylist?.seriesTitle ??
        _deps.playlistItem()['title'] as String? ??
        'Series';

    if (!_deps.mounted()) return;

    _deps.onPlaybackStarted()?.call();
    MainPageBridge.notifyPlayerLaunching();

    final args = VideoPlayerLaunchArgs(
      videoUrl: entries[startIndex].url,
      title: seriesTitle,
      subtitle: '${entries.length} episodes',
      playlist: entries,
      startIndex: startIndex,
      disableAutoResume: true,
      viewMode: _deps.convertToPlaylistViewMode(
        _deps.navigationState.currentViewMode,
      ),
      httpHeaders: WebDavService.authHeaders(config),
      disableExternalPlayer: hasWebDavCredentials(config),
      webDavServerId: (_deps.playlistItem()['webdavServerId'] ?? config.id)
          .toString(),
      webDavBaseUrl: (_deps.playlistItem()['webdavBaseUrl'] ?? config.baseUrl)
          .toString(),
      webDavPath:
          (_deps.playlistItem()['webdavFolderPath'] ??
                  _deps.playlistItem()['webdavPath'] ??
                  '')
              .toString(),
      contentImdbId: _deps.playlistItem()['imdbId'] as String?,
      contentType: _deps.playlistItem()['contentType'] as String?,
      suppressTraktAutoSync: true,
    );

    await VideoPlayerLauncher.push(_deps.context(), args);
  }

  Future<WebDavConfig?> resolveWebDavConfig() async {
    final serverId = (_deps.playlistItem()['webdavServerId'] ?? '').toString();
    final baseUrl = (_deps.playlistItem()['webdavBaseUrl'] ?? '').toString();
    final servers = await WebdavServerStorage.getWebDavServers(
      forSettings: false,
    );
    for (final server in servers) {
      if (serverId.isNotEmpty && server.id == serverId) return server;
    }
    for (final server in servers) {
      if (baseUrl.isNotEmpty && server.baseUrl == baseUrl) return server;
    }
    if (serverId.isEmpty && baseUrl.isEmpty && servers.length == 1) {
      return servers.first;
    }
    return null;
  }
}
