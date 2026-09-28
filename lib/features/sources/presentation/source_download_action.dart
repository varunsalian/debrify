import 'package:flutter/material.dart';

import '../../../models/torrent.dart';
import '../data/source_download.dart';

/// UI feedback for the existing explicit download action.
Future<void> downloadSource(
  BuildContext context,
  Torrent source,
  SourceDownload download,
) async {
  void show(SourceDownloadStatus status) {
    if (!context.mounted) return;
    final message = switch (status) {
      SourceDownloadStatus.findingEpisode => 'Finding this IPTV episode…',
      SourceDownloadStatus.resolving => 'Resolving download URL…',
      SourceDownloadStatus.unsupported =>
        'Jellyfin and Emby downloads are not supported yet.',
      SourceDownloadStatus.episodeMissing =>
        "${source.episodeIdentifier ?? 'This episode'} is not available in this IPTV series.",
      SourceDownloadStatus.episodeUnavailable =>
        'Could not check this IPTV series. Try again.',
      SourceDownloadStatus.connectionChanged =>
        'IPTV connection changed. Search sources again.',
      SourceDownloadStatus.noUrl => 'No stream URL available.',
      SourceDownloadStatus.queued => 'Download queued.',
      SourceDownloadStatus.failed => 'Failed to queue download.',
      SourceDownloadStatus.retired => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  show(
    await download.download(
      source,
      canContinue: () => context.mounted,
      onProgress: show,
    ),
  );
}
