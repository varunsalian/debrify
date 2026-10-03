import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';

typedef PikpakFilePlaybackDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class PikpakFilePlayback {
  PikpakFilePlayback(this._deps);
  final PikpakFilePlaybackDeps _deps;

  Future<void> playFile(Map<String, dynamic> fileData) async {
    try {
      // Check if it's a folder
      final kind = fileData['kind'];
      if (kind == 'drive#folder') {
        _deps.showSnackBar(
          'Cannot play folders. Please select a video file.',
          isError: true,
        );
        return;
      }

      // Check if it's a video
      final mimeType = fileData['mime_type'] ?? '';
      if (!mimeType.startsWith('video/')) {
        _deps.showSnackBar('Only video files can be played', isError: true);
        return;
      }

      // CRITICAL FIX: Fetch fresh file details with download URLs
      // listFiles() returns empty web_content_link/medias, so we need to call
      // getFileDetails() with usage=FETCH to get populated download URLs
      final fileId = fileData['id'];

      // Show loading indicator
      if (!_deps.mounted()) return;
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } finally {
        // Close loading indicator
        if (_deps.mounted()) {
          Navigator.of(_deps.context(), rootNavigator: true).pop();
        }
      }

      // Extract streaming URL from fresh data
      final streamingUrl = PikPakApiService.instance.getStreamingUrl(
        freshFileData,
      );

      if (streamingUrl == null || streamingUrl.isEmpty) {
        _deps.showSnackBar(
          'No streaming URL available for this file',
          isError: true,
        );
        return;
      }

      // Links ready - play the video
      if (!_deps.mounted()) return;

      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: streamingUrl,
          title: freshFileData['name'] ?? 'Video',
        ),
      );
    } catch (e) {
      print('Error playing file: $e');
      _deps.showSnackBar('Failed to play video: $e', isError: true);
    }
  }
}
