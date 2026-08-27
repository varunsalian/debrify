import '../provider.dart';
import '../descriptor.dart';
import '../resolved_playback.dart';
import '../../../core/playback/playlist_entry.dart';
import '../../../models/torbox_file.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/storage_service.dart';
import '../../../services/torbox_service.dart';
import '../../../utils/debrid_media_files.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/stremio_episode_selector.dart';
import '../../../services/torbox_torrent_control_service.dart';
import 'package:flutter/foundation.dart';

class TorboxProvider implements DebridProvider {
  /// No dependencies to take yet: this provider still calls a static
  /// service. It is non-const so it can take one the moment that service
  /// grows a port, without touching the registry again.
  TorboxProvider();

  @override
  DebridProviderDescriptor get descriptor => DebridProviders.torbox;

  @override
  Future<bool> isConfigured() async =>
      (await StorageService.getTorboxApiKey())?.isNotEmpty ?? false;

  @override
  Future<bool> isEnabled() => StorageService.getTorboxIntegrationEnabled();

  @override
  Future<bool> isHiddenFromNav() => StorageService.getTorboxHiddenFromNav();

  @override
  Future<bool> isAvailable() async =>
      await isEnabled() && await StorageService.hasTorboxCredential();

  @override
  Future<String> postTorrentAction() =>
      StorageService.getTorboxPostTorrentAction();

  @override
  Future<Set<String>> cachedHashes(List<String> infohashes) async {
    final key = (await StorageService.getTorboxApiKey()) ?? '';
    return TorboxService.checkCachedTorrents(
      apiKey: key,
      infoHashes: infohashes,
    );
  }

  @override
  Future<void> queueDownload(String magnet) async {
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    await TorboxService.createTorrent(
      apiKey: apiKey,
      magnet: magnet,
      addOnlyIfCached: false,
    );
  }

  @override
  Future<void> discardFailedAdd(Object marker) async {}

  /// In Auto mode only instantly-cached torrents are worth an attempt, since a
  /// miss would leave a download running on the account.
  @override
  Future<bool> canServe(DebridStreamRequest request) async {
    if (!await isEnabled()) return false;
    if (!request.autoSelected) return true;
    final cached =
        await (request.cachedHashes?.call() ??
            cachedHashes([request.infohash]));
    return cached.contains(request.infohash.trim().toLowerCase());
  }

  @override
  Future<String?> resolveStream(DebridStreamRequest request) async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    int? createdTorrentId;
    var keepTorrent = false;
    try {
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: request.magnet,
      );
      final data = result['data'];
      final rawTorrentId = data is Map
          ? (data['torrent_id'] ?? data['id'])
          : (result['torrent_id'] ?? result['id']);

      createdTorrentId = rawTorrentId is int
          ? rawTorrentId
          : int.tryParse(rawTorrentId?.toString() ?? '');
      if (createdTorrentId == null) return null;

      await Future.delayed(const Duration(seconds: 3));
      if (request.cancelled) return null;

      final torrentInfo = await TorboxService.getTorrentById(
        apiKey,
        createdTorrentId,
      );

      if (torrentInfo == null || request.cancelled) return null;

      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) return null;

      final season = request.season;
      final episode = request.episode;
      var targetFile = files.first;
      if (request.isSeries && season != null && episode != null) {
        if (files.length > 1) {
          final fallbackIndex = StremioEpisodeSelector.findLargestFileIndex(
            files.map((f) => f.size).toList(),
          );
          targetFile = files[fallbackIndex];
        }
        final candidateNames = files
            .map((f) => f.absolutePath ?? f.name)
            .toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: request.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= files.length) {
          debugPrint(
            'TorBox could not match S${season}E$episode in ${request.name}, '
            'rejecting source',
          );
          return null;
        } else {
          targetFile = files[targetIndex];
        }
      } else if (request.isMovie && files.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          files.map((f) => f.size).toList(),
        );
        targetFile = files[targetIndex];
      } else if (files.length > 1) {
        for (final f in files) {
          if (f.size > targetFile.size) {
            targetFile = f;
          }
        }
      }

      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: createdTorrentId,
        fileId: targetFile.id,
      );
      if (streamUrl.isEmpty || request.cancelled) return null;

      keepTorrent = true;
      return streamUrl;
    } catch (e) {
      debugPrint('TorBox resolve error: $e');
      return null;
    } finally {
      if (createdTorrentId != null && !keepTorrent) {
        try {
          await TorboxTorrentControlService.deleteTorrent(
            apiKey: apiKey,
            torrentId: createdTorrentId,
          ).timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint(
            'Failed to delete rejected TorBox torrent $createdTorrentId: $e',
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
    'torboxTorrentId': resolved.torboxTorrentId,
    if (isPack)
      'torboxFileIds': [
        for (final e in resolved.playlist!)
          if (e.torboxFileId != null) e.torboxFileId,
      ]
    else if (resolved.torboxFileId != null)
      'torboxFileId': resolved.torboxFileId,
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
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    final resp = await TorboxService.createTorrent(
      apiKey: apiKey,
      magnet: magnet,
      addOnlyIfCached: true,
    );
    final ok =
        resp['success'] == true ||
        resp['error'].toString().contains('ALREADY_ADDED');
    if (!ok) {
      if (resp['error'].toString().contains('NOT_CACHED')) {
        throw const DebridNotCached(DebridProviderIds.torbox);
      }
      throw Exception(resp['error']?.toString() ?? 'TorBox add failed');
    }
    final data = resp['data'];
    final torrentId = data is Map
        ? (data['torrent_id'] as num?)?.toInt()
        : null;
    if (torrentId == null) throw Exception('TorBox: no torrent id');
    final tt = await TorboxService.getTorrentById(apiKey, torrentId);
    final open = tt == null
        ? null
        : () => MainPageBridge.openTorboxFolder?.call(tt);
    final videos = (tt?.files ?? const <TorboxFile>[])
        .where((f) => FileUtils.isVideoFile(f.name))
        .toList();
    if (videos.length <= 1) {
      final file = videos.isNotEmpty
          ? videos.first
          : _pickLargest(tt?.files ?? const []);
      final playUrl = file == null
          ? null
          : await TorboxService.requestFileDownloadLink(
              apiKey: apiKey,
              torrentId: torrentId,
              fileId: file.id,
            );
      return ResolvedPlayback(
        title: title,
        playUrl: playUrl,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        fileName: file == null ? null : debridFileName(file.name),
        torboxTorrentId: torrentId,
        // File id so a saved playlist item re-requests a fresh link later.
        torboxFileId: file?.id,
      );
    }
    final (sorted, startIndex) = debridOrderBySeries(videos, (f) => f.name);
    final startUrl = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrentId,
      fileId: sorted[startIndex].id,
    );
    final entries = [
      for (var i = 0; i < sorted.length; i++)
        PlaylistEntry(
          url: i == startIndex ? startUrl : '',
          title: debridFileName(sorted[i].name),
          provider: DebridProviderIds.torbox,
          torboxTorrentId: torrentId,
          torboxFileId: sorted[i].id,
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
      torboxTorrentId: torrentId,
    );
  }

  static TorboxFile? _pickLargest(List<TorboxFile> files) {
    final pool = debridVideoPool(files, (f) => f.name);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }
}
