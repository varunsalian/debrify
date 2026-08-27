import '../provider.dart';
import '../descriptor.dart';
import '../resolved_playback.dart';
import '../../../core/playback/playlist_entry.dart';
import '../../../models/rd_torrent.dart';
import '../../../services/debrid_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/storage_service.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/rd_folder_tree_builder.dart';
import '../../../utils/series_parser.dart';
import '../../../utils/stremio_episode_selector.dart';
import '../../../utils/rd_blocked_filter.dart';
import 'package:flutter/foundation.dart';

class RealDebridProvider implements DebridProvider {
  /// No dependencies to take yet: this provider still calls a static
  /// service. It is non-const so it can take one the moment that service
  /// grows a port, without touching the registry again.
  RealDebridProvider();

  @override
  DebridProviderDescriptor get descriptor => DebridProviders.realDebrid;

  @override
  Future<bool> isConfigured() async =>
      (await StorageService.getApiKey())?.isNotEmpty ?? false;

  @override
  Future<bool> isEnabled() => StorageService.getRealDebridIntegrationEnabled();

  @override
  Future<bool> isHiddenFromNav() => StorageService.getRealDebridHiddenFromNav();

  @override
  Future<bool> isAvailable() async =>
      await isEnabled() && await StorageService.hasRealDebridCredential();

  @override
  Future<String> postTorrentAction() => StorageService.getPostTorrentAction();

  @override
  Future<Set<String>> cachedHashes(List<String> infohashes) async => const {};

  /// RD's add already created the account entry, so "add anyway" has nothing
  /// left to queue.
  @override
  Future<void> queueDownload(String magnet) async {}

  @override
  Future<void> discardFailedAdd(Object marker) async {
    if (marker is! TorrentNotCachedException) return;
    try {
      await DebridService.deleteTorrent(marker.apiKey, marker.torrentId);
    } catch (_) {}
  }

  /// The blocked-hoster skip list is the user's call; when it's on, a torrent
  /// RD refuses is not worth an attempt.
  @override
  Future<bool> canServe(DebridStreamRequest request) async {
    if (!await isEnabled()) return false;
    return !await StorageService.getRdSkipBlockedTorrents() ||
        !isRdBlockedTorrent(request.name);
  }

  @override
  Future<String?> resolveStream(DebridStreamRequest request) async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;
    String? createdTorrentId;
    var keepTorrent = false;
    try {
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        request.magnet,
      );
      final torrentId = result['torrentId']?.toString();
      if (torrentId != null && torrentId.isNotEmpty) {
        createdTorrentId = torrentId;
      }

      final links = result['links'] as List<dynamic>? ?? [];
      final updatedInfo = result['updatedInfo'] as Map<String, dynamic>? ?? {};
      final files = updatedInfo['files'] as List<dynamic>? ?? [];

      if (links.isEmpty) return null;

      String linkToUnrestrict = links.first.toString();
      final selectedVideoFiles = <Map<String, dynamic>>[];
      final selectedVideoLinks = <String>[];
      int linkIndex = 0;
      for (final file in files) {
        if (file is! Map<String, dynamic>) continue;
        final selected = file['selected'] == 1 || file['selected'] == true;
        if (!selected) continue;
        final rawName =
            (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        if (FileUtils.isVideoFile(FileUtils.getFileName(rawName)) &&
            linkIndex < links.length) {
          selectedVideoFiles.add(file);
          selectedVideoLinks.add(links[linkIndex].toString());
        }
        linkIndex++;
      }

      final season = request.season;
      final episode = request.episode;
      if (request.isSeries && season != null && episode != null) {
        final candidateNames = selectedVideoFiles.map((file) {
          return (file['path'] as String?) ?? (file['name'] as String?) ?? '';
        }).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: request.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= selectedVideoLinks.length) {
          debugPrint(
            'RD could not match S${season}E$episode in ${request.name}, '
            'rejecting source',
          );
          return null;
        } else {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      } else if (request.isMovie && selectedVideoLinks.length > 1) {
        final targetIndex = StremioEpisodeSelector.findLargestFileIndex(
          selectedVideoFiles.map((file) => file['bytes'] as int?).toList(),
        );
        if (targetIndex < selectedVideoLinks.length) {
          linkToUnrestrict = selectedVideoLinks[targetIndex];
        }
      }

      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        linkToUnrestrict,
      );
      final url = unrestrictResult['download'] as String?;
      if (url == null || url.isEmpty) return null;

      keepTorrent = true;
      return url;
    } catch (e) {
      debugPrint('RD resolve error: $e');
      return null;
    } finally {
      if (createdTorrentId != null && !keepTorrent) {
        try {
          await DebridService.deleteTorrent(apiKey, createdTorrentId);
        } catch (e) {
          debugPrint(
            'Failed to delete rejected RD torrent $createdTorrentId: $e',
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
    if (resolved.rdTorrentId != null) 'rdTorrentId': resolved.rdTorrentId,
    if (!isPack) ...{
      'url': '', // force re-resolution from restrictedLink
      if (resolved.restrictedLink != null)
        'restrictedLink': resolved.restrictedLink,
    },
  };

  @override
  Future<ResolvedPlayback?> resolveCloudBinding(
    DebridCloudBinding binding,
  ) async => null;

  /// RD's addMagnet always makes a fresh account entry, so a rejected result
  /// has to be deleted again.
  @override
  Future<void> discardAdded(ResolvedPlayback resolved) async {
    final id = resolved.rdTorrentId;
    if (id == null || id.isEmpty) return;
    try {
      final apiKey = (await StorageService.getApiKey()) ?? '';
      await DebridService.deleteTorrent(apiKey, id);
    } catch (_) {}
  }

  @override
  Future<ResolvedPlayback> add(String magnet, DebridAddRequest request) async {
    final title = request.title;
    final apiKey = (await StorageService.getApiKey()) ?? '';
    final result = await DebridService.addTorrentToDebrid(apiKey, magnet);
    final playUrl = result['downloadLink'] as String?;
    final linksRaw = (result['links'] as List?) ?? const [];
    final filesRaw = (result['files'] as List?) ?? const [];
    final links = linksRaw.map((e) => e.toString()).toList();
    // RD returns multiple selected files but a single link for an
    // unextracted RAR archive — the provider "open" view isn't useful then.
    final isRar = filesRaw.isNotEmpty
        ? RDFolderTreeBuilder.isRarArchive(
            filesRaw.map((f) => f as Map<String, dynamic>).toList(),
            linksRaw,
          )
        : false;
    final rd = RDTorrent(
      id: result['torrentId']?.toString() ?? '',
      filename: title,
      hash: request.infohash,
      bytes: request.sizeBytes,
      host: '',
      split: 0,
      progress: 100,
      status: 'downloaded',
      added: DateTime.now().toIso8601String(),
      links: links,
    );
    void open() => MainPageBridge.openDebridOptions?.call(rd);
    final playlist = await _buildPlaylist(linksRaw, filesRaw, apiKey);
    if (playlist != null && playlist.length > 1) {
      var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
      if (startIndex < 0) startIndex = 0;
      final start = playlist[startIndex].url.isNotEmpty
          ? playlist[startIndex].url
          : playUrl;
      return ResolvedPlayback(
        title: title,
        playUrl: start,
        downloadUrls: playUrl != null ? [playUrl] : const [],
        openInTab: open,
        playlist: playlist,
        startIndex: startIndex,
        isRarArchive: isRar,
        rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
      );
    }
    return ResolvedPlayback(
      title: title,
      playUrl: playUrl,
      downloadUrls: playUrl != null ? [playUrl] : const [],
      openInTab: open,
      // Single video file: expose its real name so the bound-source
      // episode check can judge it (RAR resolves keep playlist null AND
      // fileName null, staying deliberately lenient).
      fileName: (playlist != null && playlist.length == 1)
          ? playlist.first.title
          : null,
      isRarArchive: isRar,
      rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
      // Raw restricted link so a saved playlist item re-unrestricts later.
      restrictedLink: links.isNotEmpty ? links.first : null,
    );
  }

  /// Multi-file playlist — a verbatim port of Home's `_buildRdPlaylistEntries`
  /// (pure logic): video-file filtering aligned to the `links` array, archive
  /// guard, [SeriesParser] first-episode detection, start entry unrestricted,
  /// the rest carry `restrictedLink` for lazy resolution.
  static Future<List<PlaylistEntry>?> _buildPlaylist(
    List<dynamic> links,
    List<dynamic> files,
    String apiKey,
  ) async {
    final selectedFiles = files.where((file) => file['selected'] == 1).toList();
    final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

    final filesToUse = allFilesToUse.where((file) {
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      return filename != null && FileUtils.isVideoFile(filename);
    }).toList();

    // Archive check (multiple files but a single link) / no video.
    if (filesToUse.length > 1 && links.length == 1) return null;
    if (filesToUse.isEmpty) return null;

    final filenames = filesToUse.map((file) {
      String? name =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (name != null && name.startsWith('/')) name = name.split('/').last;
      return name ?? 'Unknown File';
    }).toList();

    final isSeries = SeriesParser.isSeriesPlaylist(filenames);
    final seriesInfos = isSeries ? SeriesParser.parsePlaylist(filenames) : null;

    int firstIndex = 0;
    if (isSeries && seriesInfos != null) {
      int lowestSeason = 999, lowestEpisode = 999;
      for (int i = 0; i < seriesInfos.length; i++) {
        final info = seriesInfos[i];
        if (info.isSeries && info.season != null && info.episode != null) {
          if (info.season! < lowestSeason ||
              (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
            lowestSeason = info.season!;
            lowestEpisode = info.episode!;
            firstIndex = i;
          }
        }
      }
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < filesToUse.length; i++) {
      final file = filesToUse[i];
      String? filename =
          file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      String? relativePath = filename;
      if (relativePath != null && relativePath.startsWith('/')) {
        relativePath = relativePath.substring(1);
      }
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      final finalFilename = filename ?? 'Unknown File';
      final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;
      if (i >= links.length) continue;

      String url = '';
      if (i == firstIndex) {
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[i].toString(),
          );
          url = unrestrictResult['download']?.toString() ?? '';
        } catch (_) {
          url = '';
        }
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: finalFilename,
          relativePath: relativePath,
          restrictedLink: url.isEmpty ? links[i].toString() : null,
          sizeBytes: sizeBytes,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }
}
