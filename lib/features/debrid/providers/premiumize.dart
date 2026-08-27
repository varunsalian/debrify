import '../provider.dart';
import '../descriptor.dart';
import '../resolved_playback.dart';
import '../../../core/playback/playlist_entry.dart';
import '../../../models/premiumize_file.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/premiumize_service.dart';
import '../../../services/storage_service.dart';
import '../../../utils/debrid_media_files.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/stremio_episode_selector.dart';
import 'package:flutter/foundation.dart';

class PremiumizeProvider implements DebridProvider {
  /// No dependencies to take yet: this provider still calls a static
  /// service. It is non-const so it can take one the moment that service
  /// grows a port, without touching the registry again.
  PremiumizeProvider();

  @override
  DebridProviderDescriptor get descriptor => DebridProviders.premiumize;

  @override
  Future<bool> isConfigured() async =>
      (await StorageService.getPremiumizeApiKey())?.isNotEmpty ?? false;

  @override
  Future<bool> isEnabled() => StorageService.getPremiumizeIntegrationEnabled();

  @override
  Future<bool> isHiddenFromNav() => StorageService.getPremiumizeHiddenFromNav();

  @override
  Future<bool> isAvailable() async =>
      await isEnabled() && await StorageService.hasPremiumizeCredential();

  @override
  Future<String> postTorrentAction() =>
      StorageService.getPremiumizePostTorrentAction();

  @override
  Future<Set<String>> cachedHashes(List<String> infohashes) async {
    final key = (await StorageService.getPremiumizeApiKey()) ?? '';
    final res = await PremiumizeService.checkCache(key, infohashes);
    return {
      for (var i = 0; i < infohashes.length && i < res.length; i++)
        if (res[i]) infohashes[i],
    };
  }

  @override
  Future<void> queueDownload(String magnet) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    await PremiumizeService.createTransfer(apiKey, magnet);
  }

  @override
  Future<void> discardFailedAdd(Object marker) async {}

  /// Collections re-resolve from torrent_hash; singles from the file path.
  @override
  Future<bool> canServe(DebridStreamRequest request) => isEnabled();

  @override
  Future<String?> resolveStream(DebridStreamRequest request) async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    try {
      final files = await PremiumizeService.directDownload(
        apiKey,
        request.magnet,
      );

      if (files.isEmpty) return null;

      final videoFiles = files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      final candidates = videoFiles.isNotEmpty ? videoFiles : files;

      PremiumizeFile? targetFile;
      final season = request.season;
      final episode = request.episode;
      if (request.isSeries && season != null && episode != null) {
        final candidateNames = candidates.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: request.name,
              season: season,
              episode: episode,
            );
        if (targetIndex != null && targetIndex < candidates.length) {
          targetFile = candidates[targetIndex];
        } else {
          debugPrint(
            'Premiumize could not match S${season}E$episode in '
            '${request.name}, rejecting source',
          );
          return null;
        }
      }
      targetFile ??= candidates.length > 1
          ? candidates.reduce((a, b) => a.size >= b.size ? a : b)
          : candidates.first;

      return targetFile.streamLink ?? targetFile.link;
    } catch (e) {
      debugPrint('Premiumize resolve error: $e');
      return null;
    }
  }

  @override
  Map<String, dynamic> playlistItemIds(
    ResolvedPlayback resolved, {
    required bool isPack,
  }) => {
    if (!isPack && resolved.premiumizePath != null)
      'premiumizePath': resolved.premiumizePath,
  };

  @override
  Future<void> discardAdded(ResolvedPlayback resolved) async {}

  @override
  Future<ResolvedPlayback?> resolveCloudBinding(
    DebridCloudBinding binding,
  ) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    if (apiKey.isEmpty) return null;
    if (binding.isFile) {
      final file = await PremiumizeService.resolveItemById(
        apiKey,
        binding.sourceId,
      );
      if (file == null || file.link.isEmpty) return null;
      return ResolvedPlayback(
        title: binding.name,
        playUrl: file.link,
        downloadUrls: [file.link],
        fileName: file.path.isNotEmpty ? file.path : binding.name,
      );
    }

    final all = await PremiumizeService.listFolderRecursive(
      apiKey,
      binding.sourceId,
    );
    final videos = all.where((f) => f.isVideo).toList();
    if (videos.isEmpty) return null;
    if (!binding.isSeries) {
      final video = videos.reduce((a, b) => a.size >= b.size ? a : b);
      var url = video.playableUrl ?? '';
      if (url.isEmpty) {
        final resolved = await PremiumizeService.resolveItemById(
          apiKey,
          video.id,
        );
        url = resolved?.link ?? '';
      }
      if (url.isEmpty) return null;
      return ResolvedPlayback(
        title: binding.name,
        playUrl: url,
        downloadUrls: [url],
        fileName: video.relativePath ?? video.name,
      );
    }
    final (sorted, startIndex) = debridOrderBySeries(
      videos,
      (f) => f.relativePath ?? f.name,
    );
    final entries = <PlaylistEntry>[
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? (sorted[i].playableUrl ?? '') : '',
          title: sorted[i].relativePath ?? sorted[i].name,
          relativePath: sorted[i].relativePath ?? sorted[i].name,
          provider: DebridProviderIds.premiumize,
          premiumizeItemId: sorted[i].id,
          sizeBytes: sorted[i].size > 0 ? sorted[i].size : null,
        ),
    ];
    var playUrl = entries[startIndex].url;
    if (playUrl.isEmpty) {
      final resolved = await PremiumizeService.resolveItemById(
        apiKey,
        entries[startIndex].premiumizeItemId!,
      );
      playUrl = resolved?.link ?? '';
    }
    if (playUrl.isEmpty) return null;
    return ResolvedPlayback(
      title: binding.name,
      playUrl: playUrl,
      downloadUrls: [playUrl],
      playlist: entries.length > 1 ? entries : null,
      startIndex: startIndex,
      fileName: entries.length == 1 ? entries.first.title : null,
    );
  }

  @override
  Future<ResolvedPlayback> add(String magnet, DebridAddRequest request) async {
    final title = request.title;
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    // Strict: a cache-check failure must not read as "not cached", which
    // would offer "add anyway" and report a transfer the API never created.
    if (!await PremiumizeService.isCachedStrict(apiKey, magnet)) {
      throw const DebridNotCached(DebridProviderIds.premiumize);
    }
    final files = await PremiumizeService.directDownload(apiKey, magnet);
    void open() => MainPageBridge.openPremiumizeFolder?.call();
    final videos = files.where((f) => FileUtils.isVideoFile(f.path)).toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty ? videos.first : _pickLargest(files);
      return ResolvedPlayback(
        title: title,
        playUrl: file?.link,
        downloadUrls: file?.link != null ? [file!.link] : const [],
        openInTab: open,
        fileName: file == null ? null : debridFileName(file.path),
        // File path so a saved playlist item re-resolves from the cloud.
        premiumizePath: file?.path,
      );
    }
    // Premiumize direct links are all ready — no lazy resolution needed.
    final (sorted, startIndex) = debridOrderBySeries(videos, (f) => f.path);
    final entries = [
      for (final f in sorted)
        PlaylistEntry(
          url: f.link,
          title: debridFileName(f.path),
          provider: DebridProviderIds.premiumize,
          premiumizeHash: request.infohash,
          premiumizePath: f.path,
          sizeBytes: f.size,
          torrentHash: request.infohash,
        ),
    ];
    return ResolvedPlayback(
      title: title,
      playUrl: sorted[startIndex].link,
      downloadUrls: [sorted[startIndex].link],
      openInTab: open,
      playlist: entries,
      startIndex: startIndex,
    );
  }

  static PremiumizeFile? _pickLargest(List<PremiumizeFile> files) {
    final pool = debridVideoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }
}
