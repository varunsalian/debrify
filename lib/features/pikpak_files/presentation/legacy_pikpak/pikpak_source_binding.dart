import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

typedef PikpakSourceBindingDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
});

class PikpakSourceBinding {
  PikpakSourceBinding(this._deps);
  final PikpakSourceBindingDeps _deps;

  Future<void> selectBoundSource(Map<String, dynamic> file) async {
    final id = file['id']?.toString() ?? '';
    final name = file['name']?.toString() ?? 'PikPak Source';
    final kind = file['kind']?.toString() ?? '';
    final isFolder = kind == 'drive#folder';
    final isVideo =
        (file['mime_type']?.toString().startsWith('video/') ?? false) ||
        FileUtils.isVideoFile(name);
    if (id.isEmpty || (!isFolder && !isVideo)) {
      _deps.showSnackBar('Choose a video file or folder', isError: true);
      return;
    }

    if (!_deps.mounted()) return;
    showDialog<void>(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Checking PikPak source...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
    var checkingDialogOpen = true;
    void closeCheckingDialog() {
      if (!checkingDialogOpen || !_deps.mounted()) return;
      checkingDialogOpen = false;
      Navigator.of(_deps.context(), rootNavigator: true).pop();
    }

    try {
      if (isFolder) {
        final folderDetails = await PikPakApiService.instance.getFileDetails(
          id,
        );
        if (folderDetails['phase'] != 'PHASE_TYPE_COMPLETE') {
          if (!_deps.mounted()) return;
          closeCheckingDialog();
          _deps.showSnackBar(
            'This PikPak folder is not ready to stream',
            isError: true,
          );
          return;
        }
        final files = await PikPakApiService.instance.listFilesRecursive(
          folderId: id,
          includePaths: true,
        );
        final videos = files.where((entry) {
          final entryName = entry['name']?.toString() ?? '';
          final mime = entry['mime_type']?.toString() ?? '';
          return mime.startsWith('video/') || FileUtils.isVideoFile(entryName);
        }).toList();
        if (!_deps.mounted()) return;
        if (videos.isEmpty) {
          closeCheckingDialog();
          _deps.showSnackBar(
            'This folder has no playable videos',
            isError: true,
          );
          return;
        }

        // A completed folder can still contain an incomplete or otherwise
        // unstreamable file. Confirm that at least one video resolves to a
        // fresh PikPak URL before persisting only the stable folder id.
        var hasPlayableVideo = false;
        for (final video in videos) {
          if (video['phase'] != 'PHASE_TYPE_COMPLETE') continue;
          final videoId = video['id']?.toString() ?? '';
          if (videoId.isEmpty) continue;
          try {
            final details = await PikPakApiService.instance.getFileDetails(
              videoId,
            );
            final url = PikPakApiService.instance.getStreamingUrl(details);
            if (details['phase'] == 'PHASE_TYPE_COMPLETE' &&
                url != null &&
                url.isNotEmpty) {
              hasPlayableVideo = true;
              break;
            }
          } catch (_) {
            // One stale child must not hide another playable video.
          }
        }
        if (!_deps.mounted()) return;
        closeCheckingDialog();
        if (!hasPlayableVideo) {
          _deps.showSnackBar(
            'This PikPak folder has no ready video streams',
            isError: true,
          );
          return;
        }
      } else {
        final details = await PikPakApiService.instance.getFileDetails(id);
        if (!_deps.mounted()) return;
        closeCheckingDialog();
        if (details['phase'] != 'PHASE_TYPE_COMPLETE' ||
            PikPakApiService.instance.getStreamingUrl(details) == null) {
          _deps.showSnackBar(
            'This PikPak file is not ready to stream',
            isError: true,
          );
          return;
        }
      }

      await _deps.onSourceSelected()?.call(
        SeriesSource(
          torrentHash: '',
          torrentName: name,
          debridService: 'pikpak',
          debridTorrentId: id,
          cloudSourceKind: isFolder
              ? SeriesSource.cloudKindFolder
              : SeriesSource.cloudKindFile,
          boundAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!_deps.mounted()) return;
      Navigator.of(_deps.context()).pop();
    } catch (e) {
      if (_deps.mounted()) {
        closeCheckingDialog();
        _deps.showSnackBar(
          'Could not bind this PikPak source: $e',
          isError: true,
        );
      }
    }
  }
}
