import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';

typedef DebridDormantFileActionsDeps = ({
  DebridCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String message) showError,
  void Function(String text) copyToClipboard,
});

// New on-demand action handlers
class DebridDormantFileActions {
  DebridDormantFileActions(this._deps);
  final DebridDormantFileActionsDeps _deps;

  Future<void> playFileOnDemand(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _deps.catalogState.apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';
      final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        // Check if it's actually a video using MIME type
        if (FileUtils.isVideoMimeType(mimeType)) {
          if (_deps.mounted()) {
            await VideoPlayerLauncher.push(
              _deps.context(),
              VideoPlayerLaunchArgs(
                videoUrl: downloadLink,
                title: torrent.filename,
                subtitle: 'File ${index + 1}',
                viewMode: PlaylistViewMode.sorted, // Single file - not series
              ),
            );
          }
        } else {
          if (_deps.mounted()) {
            _deps.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } else {
        if (_deps.mounted()) {
          _deps.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to load video: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }

  Future<void> addFileToPlaylist(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
  ) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      // Check if it's a video file before adding to playlist
      final unrestrictResult = await DebridService.unrestrictLink(
        _deps.catalogState.apiKey!,
        torrent.links[index],
      );
      final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

      // Check if it's actually a video using MIME type
      if (FileUtils.isVideoMimeType(mimeType)) {
        final item = {
          'title': FileUtils.cleanPlaylistTitle(torrent.filename),
          'url': '',
          'restrictedLink': torrent.links[index],
          'rdTorrentId': torrent.id,
          'kind': 'single',
        };
        final ok = await PlaylistStorage.addPlaylistItemRaw(item);
        if (!_deps.mounted()) return;
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
          ),
        );
      } else {
        if (_deps.mounted()) {
          _deps.showError('This file is not a video (MIME type: $mimeType)');
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to validate file: ${e.toString()}');
      }
    }
  }

  Future<void> downloadFileOnDemand(
    RDTorrent torrent,
    int index,
    String fileName,
    StateSetter setLocal,
    Set<int> added,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _deps.catalogState.apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        await DownloadService.instance.enqueueDownload(
          credentialKey: 'real_debrid_api_key',
          url: downloadLink,
          // Use RD-provided filename if available to avoid mismatches
          fileName: (unrestrictResult['filename']?.toString() ?? fileName),
          context: _deps.context(),
          torrentName: torrent.filename,
        );
        setLocal(() {
          added.add(index);
        });
      } else {
        if (_deps.mounted()) {
          _deps.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to get download link: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }

  Future<void> copyFileLinkOnDemand(
    RDTorrent torrent,
    int index,
    StateSetter setLocal,
    Map<int, bool> unrestrictingFiles,
  ) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      setLocal(() {
        unrestrictingFiles[index] = true;
      });

      final unrestrictResult = await DebridService.unrestrictLink(
        _deps.catalogState.apiKey!,
        torrent.links[index],
      );
      final downloadLink = unrestrictResult['download']?.toString() ?? '';

      if (downloadLink.isNotEmpty) {
        if (_deps.mounted()) {
          _deps.copyToClipboard(downloadLink);
        }
      } else {
        if (_deps.mounted()) {
          _deps.showError('Failed to get download link');
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to get download link: ${e.toString()}');
      }
    } finally {
      setLocal(() {
        unrestrictingFiles[index] = false;
      });
    }
  }
}
