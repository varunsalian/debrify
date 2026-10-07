import 'dart:async';

import 'package:debrify/features/premiumize_files/application/premiumize_playlist_titles.dart';
import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/screens/video_player_screen.dart'; // re-exports PlaylistEntry
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeFolderPlaybackDeps = ({
  PremiumizeCatalogState catalogState,
  void Function(String message) showLoadingDialog,
  void Function() dismissDialog,
  bool Function() mounted,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  BuildContext Function() context,
});

class PremiumizeFolderPlayback {
  PremiumizeFolderPlayback(this._deps);
  final PremiumizeFolderPlaybackDeps _deps;

  Future<void> playFolder(PremiumizeFolderItem folder) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _deps.showLoadingDialog('Scanning folder for videos...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
      _deps.dismissDialog();
      if (!_deps.mounted()) return;

      final videos = all.where((f) => f.isVideo).toList();
      if (videos.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }
      await playPremiumizeVideos(videos, folder.name);
    } catch (e) {
      _deps.dismissDialog();
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  Future<void> playPremiumizeVideos(
    List<PremiumizeFolderItem> videos,
    String collectionName,
  ) async {
    if (videos.isEmpty) return;

    // Single video.
    if (videos.length == 1) {
      final v = videos.first;
      final url = v.playableUrl;
      if (url == null || url.isEmpty) {
        _deps.showSnackBar('No playable URL for this file', isError: true);
        return;
      }
      final sizeBytes = v.size > 0 ? v.size : null;
      if (!_deps.mounted()) return;
      MainPageBridge.notifyPlayerLaunching();
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: url,
          title: v.name,
          subtitle: sizeBytes != null
              ? Formatters.formatFileSize(sizeBytes)
              : null,
          playlist: [
            PlaylistEntry(
              url: url,
              title: v.name,
              relativePath: v.relativePath ?? v.name,
              provider: 'premiumize',
              premiumizeItemId: v.id,
              sizeBytes: sizeBytes,
            ),
          ],
          startIndex: 0,
        ),
      );
      return;
    }

    // Collection.
    final infos = videos
        .map((v) => SeriesParser.parseFilename(v.name))
        .toList();
    final filenames = videos.map((v) => v.name).toList();
    final bool isSeries =
        videos.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final indexed = List.generate(videos.length, (i) => i);
    if (isSeries) {
      indexed.sort((a, b) {
        final sa = infos[a].season ?? 0, sb = infos[b].season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = infos[a].episode ?? 0, eb = infos[b].episode ?? 0;
        if (ea != eb) return ea.compareTo(eb);
        return videos[a].name.toLowerCase().compareTo(
          videos[b].name.toLowerCase(),
        );
      });
    } else {
      indexed.sort(
        (a, b) => videos[a].name.toLowerCase().compareTo(
          videos[b].name.toLowerCase(),
        ),
      );
    }

    final sortedVideos = [for (final i in indexed) videos[i]];
    final sortedInfos = [for (final i in indexed) infos[i]];

    int startIndex = isSeries ? findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      final info = sortedInfos[i];
      final episodeLabel = formatPlaylistTitle(
        info: info,
        fallback: v.name,
        isSeriesCollection: isSeries,
      );
      final title = composeEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeries,
        fallback: v.name,
      );
      entries.add(
        PlaylistEntry(
          // folder/list already returns direct links, so fill all up front.
          url: v.playableUrl ?? '',
          title: title,
          relativePath: v.relativePath ?? v.name,
          provider: 'premiumize',
          premiumizeItemId: v.id,
          sizeBytes: v.size > 0 ? v.size : null,
        ),
      );
    }

    final totalBytes = sortedVideos.fold<int>(0, (s, v) => s + v.size);
    final subtitle =
        '${entries.length} ${isSeries ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!_deps.mounted()) return;
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: entries[startIndex].url,
        title: collectionName,
        subtitle: subtitle,
        playlist: entries,
        startIndex: startIndex,
      ),
    );
  }
}
