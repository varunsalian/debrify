import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/screens/video_player_screen.dart'; // re-exports PlaylistEntry
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeFilePlaybackDeps = ({
  PremiumizeCatalogState catalogState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class PremiumizeFilePlayback {
  PremiumizeFilePlayback(this._deps);
  final PremiumizeFilePlaybackDeps _deps;

  Future<void> playFile(PremiumizeFolderItem file) async {
    String? url = file.playableUrl;
    // Search hits (folder/search) may omit the direct link — resolve by id.
    if ((url == null || url.isEmpty) &&
        _deps.catalogState.apiKey != null &&
        _deps.catalogState.apiKey!.isNotEmpty) {
      final resolved = await PremiumizeService.resolveItemById(
        _deps.catalogState.apiKey!,
        file.id,
      );
      url = resolved?.link;
    }
    if (url == null || url.isEmpty) {
      _deps.showSnackBar('No playable URL for this file', isError: true);
      return;
    }
    final sizeBytes = file.size > 0 ? file.size : null;
    if (!_deps.mounted()) return;
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: file.name,
        subtitle: sizeBytes != null
            ? Formatters.formatFileSize(sizeBytes)
            : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: file.name,
            relativePath: file.relativePath ?? file.name,
            provider: 'premiumize',
            premiumizeItemId: file.id,
            sizeBytes: sizeBytes,
          ),
        ],
        startIndex: 0,
      ),
    );
  }
}
