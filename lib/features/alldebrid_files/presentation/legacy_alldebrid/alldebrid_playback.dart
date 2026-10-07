import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart'; // re-exports PlaylistEntry
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

typedef AllDebridPlaybackDeps = ({
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function() dismissLoading,
  int Function(List<SeriesInfo> infos) findFirstEpisodeIndex,
  bool Function(AllDebridFile f) looksLikeVideo,
  Future<void> Function(AllDebridFile file) playFile,
  Future<void> Function(List<AllDebridFile> files, String collectionName)
  playVideos,
  void Function(String message) showLoading,
  void Function(String message, {bool isError}) snack,
  Future<String> Function(String apiKey, String lockedLink) unlockStart,
});

class AllDebridPlayback {
  final AllDebridPlaybackDeps _deps;
  AllDebridPlayback(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  // ── Playback ─────────────────────────────────────────────────────────────

  bool looksLikeVideo(AllDebridFile f) => FileUtils.isVideoFile(f.fileName);

  Future<String> unlockStart(String apiKey, String lockedLink) async {
    try {
      return await AllDebridService.unlockLink(apiKey, lockedLink);
    } catch (e) {
      debugPrint('AllDebridFiles: unlock failed: $e');
      return '';
    }
  }

  Future<void> playFile(AllDebridFile file) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _deps.showLoading('Unlocking…');
    final url = await _deps.unlockStart(apiKey, file.link);
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (url.isEmpty) {
      _deps.snack('Failed to unlock this file.', isError: true);
      return;
    }
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: file.fileName,
        subtitle: file.size > 0 ? Formatters.formatFileSize(file.size) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: file.fileName,
            relativePath: file.fileName,
            provider: 'alldebrid',
            allDebridLink: file.link,
            sizeBytes: file.size > 0 ? file.size : null,
          ),
        ],
        startIndex: 0,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }

  Future<void> playMagnet(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _deps.snack('This magnet is not ready yet.', isError: true);
      return;
    }
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _deps.showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _deps.dismissLoading();
        _deps.snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _deps.dismissLoading();
    }
    await _deps.playVideos(files, magnet.name);
  }

  Future<void> playVideos(
    List<AllDebridFile> files,
    String collectionName,
  ) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    final videos = files.where(_deps.looksLikeVideo).toList();
    if (videos.isEmpty) {
      _deps.snack('No playable video files found.', isError: true);
      return;
    }

    if (videos.length == 1) {
      await _deps.playFile(videos.first);
      return;
    }

    // Multi-file: build a series-aware playlist, unlocking only the start file
    // up front. The rest carry their stable locked link and are unlocked on
    // demand by the player's lazy AllDebrid resolver.
    final infos = videos
        .map((v) => SeriesParser.parseFilename(v.fileName))
        .toList();
    final filenames = videos.map((v) => v.fileName).toList();
    final bool isSeries =
        videos.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final order = List<int>.generate(videos.length, (i) => i);
    if (isSeries) {
      order.sort((a, b) {
        final sa = infos[a].season ?? 0, sb = infos[b].season ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = infos[a].episode ?? 0, eb = infos[b].episode ?? 0;
        if (ea != eb) return ea.compareTo(eb);
        return videos[a].fileName.toLowerCase().compareTo(
          videos[b].fileName.toLowerCase(),
        );
      });
    } else {
      order.sort(
        (a, b) => videos[a].fileName.toLowerCase().compareTo(
          videos[b].fileName.toLowerCase(),
        ),
      );
    }

    final sortedVideos = [for (final i in order) videos[i]];
    final sortedInfos = [for (final i in order) infos[i]];
    int startIndex = isSeries ? _deps.findFirstEpisodeIndex(sortedInfos) : 0;
    if (startIndex < 0 || startIndex >= sortedVideos.length) startIndex = 0;

    _deps.showLoading('Unlocking…');
    String startUrl = await _deps.unlockStart(
      apiKey,
      sortedVideos[startIndex].link,
    );
    if (startUrl.isEmpty) {
      for (int i = 0; i < sortedVideos.length; i++) {
        if (i == startIndex) continue;
        final u = await _deps.unlockStart(apiKey, sortedVideos[i].link);
        if (u.isNotEmpty) {
          startUrl = u;
          startIndex = i;
          break;
        }
      }
    }
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (startUrl.isEmpty) {
      _deps.snack(
        'Failed to resolve playable links from AllDebrid.',
        isError: true,
      );
      return;
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < sortedVideos.length; i++) {
      final v = sortedVideos[i];
      String relativePath = v.path;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }
      entries.add(
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: v.fileName,
          relativePath: relativePath,
          provider: 'alldebrid',
          allDebridLink: v.link,
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
        videoUrl: startUrl,
        title: collectionName,
        subtitle: subtitle,
        playlist: entries,
        startIndex: startIndex,
        viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted,
      ),
    );
  }

  int findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final betterSeason = bestSeason == null || season < bestSeason;
      final betterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (betterSeason || betterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  // ── Web Downloads (saved links) ──────────────────────────────────────────

  Future<void> playLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _deps.showLoading('Unlocking…');
    final url = await _deps.unlockStart(apiKey, l.link);
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (url.isEmpty) {
      _deps.snack('Failed to unlock this link.', isError: true);
      return;
    }
    MainPageBridge.notifyPlayerLaunching();
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: l.fileName,
        subtitle: l.size > 0 ? Formatters.formatFileSize(l.size) : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: l.fileName,
            relativePath: l.fileName,
            provider: 'alldebrid',
            allDebridLink: l.link,
            sizeBytes: l.size > 0 ? l.size : null,
          ),
        ],
        startIndex: 0,
        viewMode: PlaylistViewMode.sorted,
      ),
    );
  }
}
