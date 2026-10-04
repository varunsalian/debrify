import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_content_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentDebridLaunchesDeps = ({
  Map<String, dynamic> Function() playlistItem,
  PlaylistContentSeriesState seriesState,
  bool Function() mounted,
  VoidCallback? Function() onPlaybackStarted,
  BuildContext Function() context,
  PlaylistViewMode Function(FolderViewMode mode) convertToPlaylistViewMode,
  PlaylistContentNavigationState navigationState,
  PlaylistContentCatalogState catalogState,
  Future<void> Function() loadAllDebridContent,
});

class PlaylistContentDebridLaunches {
  PlaylistContentDebridLaunches(this._deps);
  final PlaylistContentDebridLaunchesDeps _deps;

  /// Play Real-Debrid playlist
  Future<void> playRealDebridPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final String? apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Real-Debrid API key in Settings');
    }

    final rdTorrentId = _deps.playlistItem()['rdTorrentId'] as String?;
    if (rdTorrentId == null) {
      throw Exception('No Real-Debrid torrent ID found');
    }

    final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
    final links = (info['links'] as List<dynamic>?) ?? [];

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final linkIndex = file.linkIndex ?? i;

      if (linkIndex >= links.length) continue;

      if (i == startIndex) {
        // Unrestrict the first file
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[linkIndex],
          );
          final url = unrestrictResult['download']?.toString() ?? '';
          entries.add(
            PlaylistEntry(
              url: url,
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              restrictedLink: links[linkIndex],
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath ?? file.path,
            restrictedLink: links[linkIndex],
            rdTorrentId: rdTorrentId,
            rdLinkIndex: linkIndex,
            sizeBytes: file.bytes,
            provider: 'realdebrid',
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
        rdTorrentId: rdTorrentId,
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

  /// Play AllDebrid playlist. Each node's linkIndex maps to its locked link in
  /// [PlaylistContentCatalogState.allDebridFiles] (populated by [PlaylistContentContentLoading.loadAllDebridContent]); the start file is
  /// unlocked, the rest carry their locked link for lazy unlock by the player.
  Future<void> playAllDebridPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your AllDebrid API key in Settings');
    }
    final torrentHash = _deps.playlistItem()['torrent_hash'] as String?;

    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final linkIndex = file.linkIndex;
      if (linkIndex < 0 ||
          linkIndex >= _deps.catalogState.allDebridFiles.length) {
        continue;
      }
      final lockedLink = _deps.catalogState.allDebridFiles[linkIndex].link;

      String url = '';
      if (i == startIndex) {
        try {
          url = await AllDebridService.unlockLink(apiKey, lockedLink);
        } catch (_) {}
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: file.name,
          relativePath: file.relativePath ?? file.path,
          provider: 'alldebrid',
          allDebridLink: lockedLink,
          torrentHash: torrentHash,
          sizeBytes: file.bytes,
        ),
      );
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

  /// Play Torbox playlist
  Future<void> playTorboxPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final String? apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Torbox API key in Settings');
    }

    final torboxTorrentId = _deps.playlistItem()['torboxTorrentId'] as int?;
    if (torboxTorrentId == null) {
      throw Exception('No Torbox torrent ID found');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          if (file.fileId != null) {
            final url = await TorboxService.requestFileDownloadLink(
              apiKey: apiKey,
              torrentId: torboxTorrentId,
              fileId: file.fileId!,
            );
            entries.add(
              PlaylistEntry(
                url: url,
                title: file.name,
                relativePath: cleanTorboxPath(file.path),
                torboxTorrentId: torboxTorrentId,
                torboxFileId: file.fileId,
                sizeBytes: file.bytes,
                provider: 'torbox',
              ),
            );
          }
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: cleanTorboxPath(file.path),
              torboxTorrentId: torboxTorrentId,
              torboxFileId: file.fileId,
              sizeBytes: file.bytes,
              provider: 'torbox',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: cleanTorboxPath(file.path),
            torboxTorrentId: torboxTorrentId,
            torboxFileId: file.fileId,
            sizeBytes: file.bytes,
            provider: 'torbox',
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
        torboxTorrentId: torboxTorrentId.toString(),
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
}
