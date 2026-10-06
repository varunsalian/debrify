import 'dart:async';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';

import 'package:debrify/models/premiumize_file.dart';
import 'package:debrify/models/stremio_addon.dart';

import 'package:debrify/models/torrent.dart';

import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/pikpak_tv_service.dart';

import 'package:debrify/services/premiumize_service.dart';

import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/torbox_torrent_control_service.dart';

import 'package:debrify/utils/file_utils.dart';

import 'package:debrify/utils/stremio_episode_selector.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';

import 'package:flutter/material.dart';

class StremioTvCloudResolvers {
  StremioTvCloudResolvers(this._deps);
  final StremioTvDependencies _deps;

  StremioTvSections get _sections => _deps.sections;

  Future<String?> resolveViaTorbox(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
  }) async {
    int? createdTorrentId;
    var keepTorrent = false;
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final result = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnet,
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
      if (isCancelled?.call() ?? false) return null;

      final torrentInfo = await TorboxService.getTorrentById(
        apiKey,
        createdTorrentId,
      );

      if (torrentInfo == null || (isCancelled?.call() ?? false)) return null;

      final allFiles = torrentInfo.files;
      final videoFiles = allFiles
          .where((f) => FileUtils.isVideoFile(f.name))
          .toList();
      final files = videoFiles.isNotEmpty ? videoFiles : allFiles;
      if (files.isEmpty) return null;

      var targetFile = files.first;
      if (item.type.toLowerCase() == 'series' &&
          season != null &&
          episode != null) {
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
              sourceName: torrent.name,
              season: season,
              episode: episode,
            );
        if (targetIndex == null || targetIndex >= files.length) {
          debugPrint(
            'StremioTV: Torbox could not match S${season}E$episode in ${torrent.name}, '
            'rejecting source',
          );
          return null;
        } else {
          targetFile = files[targetIndex];
        }
      } else if (item.type.toLowerCase() == 'movie' && files.length > 1) {
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
      if (streamUrl.isEmpty || (isCancelled?.call() ?? false)) return null;

      keepTorrent = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: Torbox resolve error: $e');
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
            'StremioTV: Failed to delete rejected TorBox torrent '
            '$createdTorrentId: $e',
          );
        }
      }
    }
  }

  Future<String?> resolveViaPikPak(
    Torrent torrent,
    StremioMeta item, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
  }) async {
    Map<String, dynamic>? preparedForCleanup;
    var keepPreparedItem = false;
    try {
      final prepared = await PikPakTvService.instance.prepareTorrent(
        infohash: torrent.infohash.trim().toLowerCase(),
        torrentName: torrent.name,
      );

      if (prepared == null) return null;
      preparedForCleanup = prepared;
      if (isCancelled?.call() ?? false) return null;

      String? streamUrl = prepared['url'] as String?;

      final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;
      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries &&
          season != null &&
          episode != null &&
          (allVideoFiles == null || allVideoFiles.isEmpty)) {
        final directNames = <String>[
          if ((prepared['title'] as String?)?.trim().isNotEmpty == true)
            (prepared['title'] as String).trim(),
          torrent.name,
        ];
        final directMatch = StremioEpisodeSelector.namesContainEpisode(
          directNames,
          season: season,
          episode: episode,
        );
        if (!directMatch) {
          debugPrint(
            'StremioTV: PikPak single file could not verify '
            'S${season}E$episode in ${torrent.name}, rejecting source',
          );
          return null;
        }
      }
      if (allVideoFiles != null && allVideoFiles.isNotEmpty) {
        Map<String, dynamic>? targetFile;
        if (isSeries && season != null && episode != null) {
          final candidateNames = allVideoFiles.map((file) {
            if (file is! Map<String, dynamic>) return '';
            return (file['_fullPath'] as String?) ??
                (file['name'] as String?) ??
                '';
          }).toList();
          final targetIndex =
              StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
                candidateNames,
                sourceName: torrent.name,
                season: season,
                episode: episode,
              );
          if (targetIndex == null || targetIndex >= allVideoFiles.length) {
            debugPrint(
              'StremioTV: PikPak could not match S${season}E$episode in ${torrent.name}, '
              'rejecting source',
            );
            return null;
          } else {
            final file = allVideoFiles[targetIndex];
            if (file is Map<String, dynamic>) {
              targetFile = file;
            }
          }
        } else if (item.type.toLowerCase() == 'movie') {
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

          final api = PikPakApiService.instance;
          final fileData = await api.getFileDetails(targetFileId);
          final url = api.getStreamingUrl(fileData);
          if (url == null || url.isEmpty) return null;
          streamUrl = url;
        } else if (isSeries && season != null && episode != null) {
          return null;
        }
      }

      if (streamUrl == null ||
          streamUrl.isEmpty ||
          (isCancelled?.call() ?? false)) {
        return null;
      }

      keepPreparedItem = true;
      return streamUrl;
    } catch (e) {
      debugPrint('StremioTV: PikPak resolve error: $e');
      return null;
    } finally {
      if (preparedForCleanup != null && !keepPreparedItem) {
        await _sections.cloud._trashRejectedPikPakItem(preparedForCleanup);
      }
    }
  }

  Future<void> _trashRejectedPikPakItem(Map<String, dynamic> prepared) async {
    final rootId = StremioTvDebridFallback.pikPakCleanupRootId(prepared);
    if (rootId == null) return;

    try {
      await PikPakApiService.instance
          .batchTrashFiles(<String>[rootId])
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('StremioTV: Failed to trash rejected PikPak item $rootId: $e');
    }
  }

  Future<String?> resolveViaPremiumize(
    Torrent torrent,
    StremioMeta item,
    String apiKey, {
    int? season,
    int? episode,
  }) async {
    try {
      final magnet =
          'magnet:?xt=urn:btih:${torrent.infohash}&dn=${Uri.encodeComponent(torrent.name)}';
      final files = await PremiumizeService.directDownload(apiKey, magnet);

      if (files.isEmpty) return null;

      final videoFiles = files
          .where((f) => FileUtils.isVideoFile(f.fileName))
          .toList();
      final candidates = videoFiles.isNotEmpty ? videoFiles : files;

      PremiumizeFile? targetFile;
      final isSeries = item.type.toLowerCase() == 'series';
      if (isSeries && season != null && episode != null) {
        final candidateNames = candidates.map((f) => f.path).toList();
        final targetIndex =
            StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
              candidateNames,
              sourceName: torrent.name,
              season: season,
              episode: episode,
            );
        if (targetIndex != null && targetIndex < candidates.length) {
          targetFile = candidates[targetIndex];
        } else {
          debugPrint(
            'StremioTV: Premiumize could not match S${season}E$episode in '
            '${torrent.name}, rejecting source',
          );
          return null;
        }
      }
      targetFile ??= candidates.length > 1
          ? candidates.reduce((a, b) => a.size >= b.size ? a : b)
          : candidates.first;

      return targetFile.streamLink ?? targetFile.link;
    } catch (e) {
      debugPrint('StremioTV: Premiumize resolve error: $e');
      return null;
    }
  }
}
