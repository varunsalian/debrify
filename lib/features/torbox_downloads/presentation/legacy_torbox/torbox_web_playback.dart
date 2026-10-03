import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxWebPlaybackDeps = ({
  TorboxCatalogState catalogState,
  void Function(String message, {bool isError}) showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxWebPlayback {
  TorboxWebPlayback(this._deps);
  final TorboxWebPlaybackDeps _deps;

  Future<void> handlePlayWebDownload(TorboxWebDownload webDownload) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    final videoFiles = webDownload.files.where((file) {
      if (file.zipped) return false;
      return torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _deps.showSnackBar('No playable video files found in this download.');
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: webDownload.id,
          fileId: file.id,
        );
        if (!_deps.mounted()) return;
        await VideoPlayerLauncher.push(
          _deps.context(),
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: webDownload.name,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!_deps.mounted()) return;
        _deps.showSnackBar('Failed to play file: ${formatTorboxError(e)}');
      }
      return;
    }

    // Multiple video files - show selection dialog
    await showDialog(
      context: _deps.context(),
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select a file to play'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: videoFiles.length,
              itemBuilder: (context, index) {
                final file = videoFiles[index];
                final fileName = file.shortName.isNotEmpty
                    ? file.shortName
                    : FileUtils.getFileName(file.name);
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(Formatters.formatFileSize(file.size)),
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      final streamUrl =
                          await TorboxService.requestWebDownloadFileLink(
                            apiKey: key,
                            webId: webDownload.id,
                            fileId: file.id,
                          );
                      if (!_deps.mounted()) return;
                      await VideoPlayerLauncher.push(
                        context,
                        VideoPlayerLaunchArgs(
                          videoUrl: streamUrl,
                          title: fileName,
                          subtitle: Formatters.formatFileSize(file.size),
                        ),
                      );
                    } catch (e) {
                      if (!_deps.mounted()) return;
                      _deps.showSnackBar(
                        'Failed to play file: ${formatTorboxError(e)}',
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
