import '../provider.dart';
import '../descriptor.dart';
import '../resolved_playback.dart';
import '../../../core/playback/playlist_entry.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/storage_service.dart';
import '../../../utils/debrid_media_files.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/series_parser.dart';
import '../../../utils/stremio_tv_debrid_fallback.dart';
import '../../../utils/stremio_episode_selector.dart';
import '../../pikpak/data/tv_service.dart';
import 'package:flutter/foundation.dart';
import '../../pikpak/data/repository.dart';
import '../../pikpak/models/file.dart';

const _stillProcessing = DebridStillProcessing(
  DebridProviderIds.pikpak,
  'Files still processing on PikPak. Check the PikPak Files page later.',
);
const _failed = DebridAddFailed(
  DebridProviderIds.pikpak,
  'Download failed on PikPak.',
);

class PikPakProvider implements DebridProvider {
  final PikPakRepository _pikpak;

  /// The drive arrives through the constructor rather than off a global. That
  /// is what lets this be tested, and it is why the registry stopped being
  /// `const`.
  PikPakProvider({required PikPakRepository drive}) : _pikpak = drive;

  @override
  DebridProviderDescriptor get descriptor => DebridProviders.pikpak;

  /// PikPak signs in with an account rather than an API key, so the enable
  /// toggle is the configuration.
  @override
  Future<bool> isConfigured() => StorageService.getPikPakEnabled();

  @override
  Future<bool> isEnabled() => StorageService.getPikPakEnabled();

  @override
  Future<bool> isHiddenFromNav() => StorageService.getPikPakHiddenFromNav();

  /// PikPak holds a session rather than an API key, so availability is whether
  /// that session is signed in.
  @override
  Future<bool> isAvailable() => _pikpak.isAuthenticated();

  @override
  Future<String> postTorrentAction() =>
      StorageService.getPikPakPostTorrentAction();

  @override
  Future<Set<String>> cachedHashes(List<String> infohashes) async => const {};

  @override
  Future<void> queueDownload(String magnet) async {}

  @override
  Future<void> discardFailedAdd(Object marker) async {}

  /// PikPak's addOfflineDownload always makes a fresh drive entry, so a
  /// rejected result has to be deleted again.
  @override
  Future<void> discardAdded(ResolvedPlayback resolved) async {
    final id = resolved.pikpakFileId;
    if (id == null || id.isEmpty) return;
    try {
      await _pikpak.batchDeleteFiles([id]);
    } catch (_) {}
  }

  @override
  Future<bool> canServe(DebridStreamRequest request) async => true;

  @override
  Future<String?> resolveStream(DebridStreamRequest request) async {
    if (!await StorageService.getPikPakEnabled()) return null;
    Map<String, dynamic>? preparedForCleanup;
    var keepPreparedItem = false;
    try {
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: request.infohash.trim().toLowerCase(),
        torrentName: request.name,
      );

      if (prepared == null) return null;
      preparedForCleanup = prepared;
      if (request.cancelled) return null;

      String? streamUrl = prepared['url'] as String?;

      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
      final season = request.season;
      final episode = request.episode;
      if (request.isSeries &&
          season != null &&
          episode != null &&
          (allVideoFiles == null || allVideoFiles.isEmpty)) {
        final directNames = <String>[
          if ((prepared['title'] as String?)?.trim().isNotEmpty == true)
            (prepared['title'] as String).trim(),
          request.name,
        ];
        final directMatch = StremioEpisodeSelector.namesContainEpisode(
          directNames,
          season: season,
          episode: episode,
        );
        if (!directMatch) {
          debugPrint(
            'PikPak single file could not verify '
            'S${season}E$episode in ${request.name}, rejecting source',
          );
          return null;
        }
      }
      if (allVideoFiles != null && allVideoFiles.isNotEmpty) {
        Map<String, dynamic>? targetFile;
        if (request.isSeries && season != null && episode != null) {
          final candidateNames = allVideoFiles.map((file) {
            if (file is! Map<String, dynamic>) return '';
            return (file['_fullPath'] as String?) ??
                (file['name'] as String?) ??
                '';
          }).toList();
          final targetIndex =
              StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
                candidateNames,
                sourceName: request.name,
                season: season,
                episode: episode,
              );
          if (targetIndex == null || targetIndex >= allVideoFiles.length) {
            debugPrint(
              'PikPak could not match S${season}E$episode in ${request.name}, '
              'rejecting source',
            );
            return null;
          } else {
            final file = allVideoFiles[targetIndex];
            if (file is Map<String, dynamic>) {
              targetFile = file;
            }
          }
        } else if (request.isMovie) {
          final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
            allVideoFiles.map((file) {
              if (file is! Map<String, dynamic>) return null;
              return file['size'] as int?;
            }).toList(),
          );
          final file = allVideoFiles[targetIndex];
          if (file is Map<String, dynamic>) {
            targetFile = file;
          }
        }

        if (targetFile != null) {
          final targetFileId = targetFile['id'] as String?;
          if (targetFileId == null || targetFileId.isEmpty) return null;

          final api = _pikpak;
          final fileData = await api.getFileDetails(targetFileId);
          final url = fileData.streamingUrl;
          if (url == null || url.isEmpty) return null;
          streamUrl = url;
        } else if (request.isSeries && season != null && episode != null) {
          return null;
        }
      }

      if (streamUrl == null || streamUrl.isEmpty || request.cancelled) {
        return null;
      }

      keepPreparedItem = true;
      return streamUrl;
    } catch (e) {
      debugPrint('PikPak resolve error: $e');
      return null;
    } finally {
      if (preparedForCleanup != null && !keepPreparedItem) {
        await _trashRejected(_pikpak, preparedForCleanup);
      }
    }
  }

  static Future<void> _trashRejected(
    PikPakRepository pikpak,
    Map<String, dynamic> prepared,
  ) async {
    final rootId = StremioTvDebridFallback.pikPakCleanupRootId(prepared);
    if (rootId == null) return;

    try {
      await pikpak
          .batchTrashFiles(<String>[rootId])
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Failed to trash rejected PikPak item $rootId: $e');
    }
  }

  @override
  Map<String, dynamic> playlistItemIds(
    ResolvedPlayback resolved, {
    required bool isPack,
  }) => isPack
      // Pack: folder id + per-file video ids (player collection path).
      ? {
          'pikpakFileId': resolved.pikpakFileId,
          'pikpakFileIds': [
            for (final e in resolved.playlist!)
              if (e.pikpakFileId != null) e.pikpakFileId,
          ],
        }
      // Single: the playable VIDEO-file id, NOT the folder id — else the
      // player can't get a streaming URL and the item won't play.
      : {'pikpakFileId': resolved.pikpakVideoFileId ?? resolved.pikpakFileId};

  @override
  Future<ResolvedPlayback?> resolveCloudBinding(
    DebridCloudBinding binding,
  ) async {
    final pikpak = _pikpak;
    final sourceId = binding.sourceId;
    if (binding.isFile) {
      final data = await pikpak.getFileDetails(sourceId);
      if (!data.isReady) return null;
      final url = data.streamingUrl;
      if (url == null || url.isEmpty) return null;
      final name = (data.name.isNotEmpty ? data.name : binding.name).toString();
      return ResolvedPlayback(
        title: binding.name,
        playUrl: url,
        downloadUrls: [url],
        fileName: name,
        pikpakFileId: sourceId,
        pikpakVideoFileId: sourceId,
      );
    }

    final all = await pikpak.listFilesRecursive(
      folderId: sourceId,
      includePaths: true,
    );
    final videos = all.where((file) {
      final name = file.name.toString();
      final mime = file.mimeType.toString();
      return mime.startsWith('video/') || FileUtils.isVideoFile(name);
    }).toList();
    if (videos.isEmpty) return null;
    if (!binding.isSeries) {
      final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
      final videoId = video.id.toString();
      if (videoId.isEmpty) return null;
      final data = await pikpak.getFileDetails(videoId);
      if (!data.isReady) return null;
      final url = data.streamingUrl;
      if (url == null || url.isEmpty) return null;
      return ResolvedPlayback(
        title: binding.name,
        playUrl: url,
        downloadUrls: [url],
        fileName:
            video.fullPath ??
            (video.name.isNotEmpty ? video.name : binding.name),
        pikpakFileId: sourceId,
        pikpakVideoFileId: videoId,
      );
    }
    final playlist = await _buildPlaylist(binding.name, videos, pikpak);
    if (playlist == null || playlist.isEmpty) return null;
    var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
    if (startIndex < 0) startIndex = 0;
    final playUrl = playlist[startIndex].url;
    if (playUrl.isEmpty) return null;
    return ResolvedPlayback(
      title: binding.name,
      playUrl: playUrl,
      downloadUrls: [playUrl],
      playlist: playlist.length > 1 ? playlist : null,
      startIndex: startIndex,
      fileName: playlist.length == 1 ? playlist.first.title : null,
      pikpakFileId: sourceId,
      pikpakVideoFileId: playlist.length == 1
          ? playlist.first.pikpakFileId
          : null,
    );
  }

  /// Adds the magnet to PikPak, polls task + file until complete, lists the
  /// folder (season packs) and builds a playlist. A port of Home's
  /// `_resolveSourceViaPikPak` + `_buildPikPakPlaylistEntries` (downloads to the
  /// PikPak root rather than a dedicated subfolder, for simplicity).
  @override
  Future<ResolvedPlayback> add(String magnet, DebridAddRequest request) async {
    final title = request.title;
    final pikpak = _pikpak;
    final add = await pikpak.addOfflineDownload(magnet);
    // PikPakTask folds PikPak's three add shapes into one, so the drive entry
    // and the task id are just fields now.
    final fileId = add.destinationId;
    final taskId = (add.id.isEmpty || add.id == fileId) ? null : add.id;
    if (fileId == null) throw Exception('PikPak: no file id returned');

    const pollInterval = Duration(seconds: 2);
    var phase1 = false;
    if (taskId != null) {
      for (var a = 0; a < 7; a++) {
        if (a > 0) await Future.delayed(pollInterval);
        try {
          final t = await pikpak.getTaskStatus(taskId);
          if (t.isComplete) {
            phase1 = true;
            break;
          }
          if (t.hasFailed) {
            throw _failed;
          }
          final rp = t.progress;
          final p = rp;
          if (p >= 90) {
            phase1 = true;
            break;
          }
        } on DebridAddFailed {
          rethrow; // surface "Download failed on PikPak"
        } catch (_) {
          break;
        }
      }
    }

    List<PikPakFile> videoFiles = const [];
    for (var a = 0; a < 5; a++) {
      if (a > 0 || !phase1) await Future.delayed(pollInterval);
      try {
        final fd = await pikpak.getFileDetails(fileId);
        if (fd.isReady) {
          if (fd.isFolder) {
            videoFiles = await _extractVideos(pikpak, fileId);
          } else {
            final mt = (fd.mimeType).toString();
            if (mt.startsWith('video/')) videoFiles = [fd];
          }
          break;
        }
        if (fd.hasFailed) {
          throw _failed;
        }
      } on DebridAddFailed {
        rethrow; // surface "Download failed on PikPak"
      } catch (e) {
        debugPrint('PikPak: file listing attempt ${a + 1} failed: $e');
      }
    }
    if (videoFiles.isEmpty) {
      throw _stillProcessing;
    }

    final playlist = await _buildPlaylist(request.name, videoFiles, pikpak);
    if (playlist == null || playlist.isEmpty) {
      throw Exception('PikPak: could not resolve a playable stream.');
    }
    var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
    if (startIndex < 0) startIndex = 0;
    final capturedFileId = fileId;
    return ResolvedPlayback(
      title: title,
      playUrl: playlist[startIndex].url,
      downloadUrls: playlist[startIndex].url.isNotEmpty
          ? [playlist[startIndex].url]
          : const [],
      openInTab: () =>
          MainPageBridge.openPikPakFolder?.call(capturedFileId, title),
      playlist: playlist.length > 1 ? playlist : null,
      startIndex: startIndex,
      // Single video file: expose its real name so the bound-source episode
      // check can judge it instead of passing vacuously.
      fileName: playlist.length == 1 ? playlist.first.title : null,
      pikpakFileId: capturedFileId,
      // The playable video-file id (folder id is capturedFileId) so a single
      // saved to a playlist re-resolves its stream instead of failing on the
      // folder.
      pikpakVideoFileId: playlist.length == 1
          ? playlist.first.pikpakFileId
          : null,
    );
  }

  static Future<List<PikPakFile>> _extractVideos(
    PikPakRepository pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
    String currentPath = '',
  }) async {
    if (currentDepth >= maxDepth) return [];
    final videos = <PikPakFile>[];
    // Deliberately unguarded: a failed listing must not read as a complete
    // pack. Propagating lets the caller retry rather than build a playlist
    // that is silently missing episodes.
    final result = await pikpak.listFiles(parentId: folderId);
    for (final file in result.files) {
      final itemName = file.name.isEmpty ? 'unknown' : file.name;
      final path = currentPath.isEmpty ? itemName : '$currentPath/$itemName';
      if (file.isFolder) {
        videos.addAll(
          await _extractVideos(
            pikpak,
            file.id,
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
            currentPath: path,
          ),
        );
      } else if (file.isVideo) {
        videos.add(currentPath.isEmpty ? file : file.at(path));
      }
    }
    videos.sort(
      (a, b) =>
          a.displayPath.toLowerCase().compareTo(b.displayPath.toLowerCase()),
    );
    return videos;
  }

  static Future<List<PlaylistEntry>?> _buildPlaylist(
    String torrentName,
    List<PikPakFile> videoFiles,
    PikPakRepository pikpak,
  ) async {
    if (videoFiles.isEmpty) return null;
    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final fullData = await pikpak.getFileDetails(file.id.toString());
        final url = fullData.streamingUrl;
        if (url == null) return null;
        return [
          PlaylistEntry(
            url: url,
            title: (file.name.isNotEmpty ? file.name : torrentName).toString(),
            relativePath: file.fullPath,
            provider: DebridProviderIds.pikpak,
            pikpakFileId: file.id.toString(),
            sizeBytes: int.tryParse(file.size.toString()) ?? 0,
          ),
        ];
      } catch (_) {
        return null;
      }
    }

    final items = <_PikPakItem>[
      for (final file in videoFiles)
        _PikPakItem(
          file: file,
          seriesInfo: SeriesParser.parseFilename(_displayName(file)),
          displayName: _displayName(file),
        ),
    ];
    final fnames = items.map((e) => e.displayName).toList();
    final isSeriesCollection =
        items.length > 1 && SeriesParser.isSeriesPlaylist(fnames);

    final sorted = [...items];
    if (isSeriesCollection) {
      sorted.sort((a, b) {
        final sc = (a.seriesInfo.season ?? 0).compareTo(
          b.seriesInfo.season ?? 0,
        );
        if (sc != 0) return sc;
        final ec = (a.seriesInfo.episode ?? 0).compareTo(
          b.seriesInfo.episode ?? 0,
        );
        if (ec != 0) return ec;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    } else {
      sorted.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }

    final seriesInfos = sorted.map((e) => e.seriesInfo).toList();
    var startIndex = isSeriesCollection
        ? debridFirstEpisodeIndex(seriesInfos)
        : 0;
    if (startIndex < 0 || startIndex >= sorted.length) startIndex = 0;

    String initialUrl = '';
    try {
      final fullData = await pikpak.getFileDetails(
        sorted[startIndex].file.id.toString(),
      );
      initialUrl = fullData.streamingUrl ?? '';
    } catch (_) {
      return null;
    }
    if (initialUrl.isEmpty) return null;

    final entries = <PlaylistEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final episodeLabel = _formatTitle(
        info: entry.seriesInfo,
        fallback: entry.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _combineTitle(
        seriesTitle: entry.seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: entry.displayName,
      );
      entries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: entry.file.fullPath,
          provider: DebridProviderIds.pikpak,
          pikpakFileId: entry.file.id.toString(),
          sizeBytes: int.tryParse(entry.file.size.toString()),
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  static String _displayName(PikPakFile file) {
    final name = file.displayPath;
    if (name.isNotEmpty) return FileUtils.getFileName(name);
    return 'File ${file.id}';
  }

  static String _formatTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      final desc = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : (info.title?.trim().isNotEmpty == true
                ? info.title!.trim()
                : fallback);
      return 'S${s}E$e · $desc';
    }
    return fallback;
  }

  static String _combineTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
    return fallback;
  }
}

class _PikPakItem {
  final PikPakFile file;
  final SeriesInfo seriesInfo;
  final String displayName;
  const _PikPakItem({
    required this.file,
    required this.seriesInfo,
    required this.displayName,
  });
}
