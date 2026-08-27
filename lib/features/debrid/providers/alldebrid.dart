import '../provider.dart';
import '../descriptor.dart';
import '../resolved_playback.dart';
import '../../../core/playback/playlist_entry.dart';
import '../../../models/alldebrid_file.dart';
import '../../../services/alldebrid_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/storage_service.dart';
import '../../../utils/debrid_media_files.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/stremio_episode_selector.dart';
import 'package:flutter/foundation.dart';

class AllDebridProvider implements DebridProvider {
  /// No dependencies to take yet: this provider still calls a static
  /// service. It is non-const so it can take one the moment that service
  /// grows a port, without touching the registry again.
  AllDebridProvider();

  @override
  DebridProviderDescriptor get descriptor => DebridProviders.allDebrid;

  @override
  Future<bool> isConfigured() async =>
      (await StorageService.getAllDebridApiKey())?.isNotEmpty ?? false;

  @override
  Future<bool> isEnabled() => StorageService.getAllDebridIntegrationEnabled();

  @override
  Future<bool> isHiddenFromNav() => StorageService.getAllDebridHiddenFromNav();

  @override
  Future<bool> isAvailable() async =>
      await isEnabled() && await StorageService.hasAllDebridCredential();

  @override
  Future<String> postTorrentAction() =>
      StorageService.getAllDebridPostTorrentAction();

  @override
  Future<Set<String>> cachedHashes(List<String> infohashes) async => const {};

  /// AllDebrid's add already created the magnet, so "add anyway" has nothing
  /// left to queue.
  @override
  Future<void> queueDownload(String magnet) async {}

  @override
  Future<void> discardFailedAdd(Object marker) async {
    if (marker is! AllDebridTorrentNotReadyException) return;
    try {
      await AllDebridService.deleteMagnet(marker.apiKey, marker.magnetId);
    } catch (_) {}
  }

  /// Collections re-resolve from torrent_hash; singles from the locked link.
  @override
  Future<bool> canServe(DebridStreamRequest request) => isEnabled();

  @override
  Future<String?> resolveStream(DebridStreamRequest request) async {
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    String? createdMagnetId;
    var keepMagnet = false;
    try {
      AllDebridAddResult result;
      try {
        result = await AllDebridService.addMagnetAndResolveFiles(
          apiKey,
          request.magnet,
        );
      } on AllDebridTorrentNotReadyException catch (e) {
        // Not cached/ready — don't leave it downloading on the account.
        try {
          await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        } catch (err) {
          debugPrint(
            'Failed to delete not-ready AllDebrid magnet ${e.magnetId}: $err',
          );
        }
        return null;
      }
      createdMagnetId = result.magnetId;

      final videoFiles = result.files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      if (videoFiles.isEmpty) return null;

      String targetLink = videoFiles.first.link;

      final season = request.season;
      final episode = request.episode;
      if (request.isSeries && season != null && episode != null) {
        final candidateNames = videoFiles.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: request.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= videoFiles.length) {
          debugPrint(
            'AllDebrid could not match S${season}E$episode in '
            '${request.name}, rejecting source',
          );
          return null;
        } else {
          targetLink = videoFiles[targetIndex].link;
        }
      } else if (request.isMovie && videoFiles.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          videoFiles.map<int?>((f) => f.size).toList(),
        );
        if (targetIndex < videoFiles.length) {
          targetLink = videoFiles[targetIndex].link;
        }
      }

      if (targetLink.isEmpty) return null;
      final url = await AllDebridService.unlockLink(apiKey, targetLink);
      if (url.isEmpty) return null;

      keepMagnet = true;
      return url;
    } catch (e) {
      debugPrint('AllDebrid resolve error: $e');
      return null;
    } finally {
      if (createdMagnetId != null && !keepMagnet) {
        try {
          await AllDebridService.deleteMagnet(apiKey, createdMagnetId);
        } catch (e) {
          debugPrint(
            'Failed to delete rejected AllDebrid magnet $createdMagnetId: $e',
          );
        }
      }
    }
  }

  @override
  Map<String, dynamic> playlistItemIds(
    ResolvedPlayback resolved, {
    required bool isPack,
  }) => {
    if (!isPack && resolved.allDebridLink != null)
      'allDebridLink': resolved.allDebridLink,
  };

  @override
  Future<ResolvedPlayback?> resolveCloudBinding(
    DebridCloudBinding binding,
  ) async => null;

  @override
  Future<void> discardAdded(ResolvedPlayback resolved) async {}

  @override
  Future<ResolvedPlayback> add(String magnet, DebridAddRequest request) async {
    final title = request.title;
    final apiKey = (await StorageService.getAllDebridApiKey()) ?? '';
    final result = await AllDebridService.addMagnetAndResolveFiles(
      apiKey,
      magnet,
    );
    void open() => MainPageBridge.openAllDebridFolder?.call();
    final videos = result.files
        .where((f) => FileUtils.isVideoFile(f.path))
        .toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty
          ? videos.first
          : _pickLargest(result.files);
      final playUrl = file == null
          ? null
          : await AllDebridService.unlockLink(apiKey, file.link);
      return ResolvedPlayback(
        title: title,
        playUrl: playUrl,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        fileName: file == null ? null : debridFileName(file.path),
        // Locked link so a saved playlist item re-unlocks a fresh URL.
        allDebridLink: file?.link,
      );
    }
    final (sorted, startIndex) = debridOrderBySeries(videos, (f) => f.path);
    final startUrl = await AllDebridService.unlockLink(
      apiKey,
      sorted[startIndex].link,
    );
    final entries = [
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: debridFileName(sorted[i].path),
          provider: DebridProviderIds.allDebrid,
          allDebridLink: sorted[i].link,
          sizeBytes: sorted[i].size,
          torrentHash: request.infohash,
        ),
    ];
    return ResolvedPlayback(
      title: title,
      playUrl: startUrl,
      downloadUrls: [startUrl],
      openInTab: open,
      playlist: entries,
      startIndex: startIndex,
    );
  }

  static AllDebridFile? _pickLargest(List<AllDebridFile> files) {
    final pool = debridVideoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }
}
